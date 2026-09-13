"""P12 codemod: cap every uncapped CachedNetworkImage in listed files.

Inserts (after the `fit:` line, else after `imageUrl:`):
    // P12: decode-capped (was full-res).
    memCacheWidth: <cap>,
    maxWidthDiskCache: <cap>,

Cap choice: explicit `width:` in block wins (<=150 -> 220 thumb,
<=700 -> 500 card, else 960 backdrop); else imageUrl hints
(logo -> 400, backdrop -> 960, else 500 card).
Skips blocks already containing memCacheWidth. Adds the
utils/perf/image_caps.dart import when missing.
DRY-RUN default: prints plan, writes only with --apply.
"""
import re
import sys

FILES = [
    "lib/pages/audiobooks/audiobook_detail_page.dart",
    "lib/pages/audiobooks/audiobook_player_screen.dart",
    "lib/pages/books/book_detail_sheet.dart",
    "lib/pages/books/widgets/continue_reading_slider.dart",
    "lib/pages/details/details_page.dart",
    "lib/pages/downloads/downloads_page.dart",
    "lib/pages/music/music_page.dart",
    "lib/pages/player/watch_screen.dart",
    "lib/pages/settings/addons_settings_page.dart",
]

CAP_EXPR = {
    220: "ImageCaps.kThumb",
    400: "ImageCaps.kLogo",
    500: "ImageCaps.kCardW",
    960: "ImageCaps.kBackdrop",
}


def pick_cap(block: str) -> int:
    m = re.search(r"width:\s*([\d.]+)", block)
    if m:
        w = float(m.group(1))
        if w <= 150:
            return 220
        if w <= 700:
            return 500
        return 960
    low = block.lower()
    if "logo" in low:
        return 400
    if "backdrop" in low:
        return 960
    return 500


def process(path: str) -> tuple[list[str], list[str]]:
    with open(path, encoding="utf-8") as f:
        lines = f.readlines()
    notes: list[str] = []
    out: list[str] = []
    i = 0
    changed = False
    while i < len(lines):
        if "CachedNetworkImage(" in lines[i] and "Provider(" not in lines[i]:
            # single-line constructor: manual fix only (auto-split risks
            # breaking ternaries) — report it.
            head = lines[i].split("CachedNetworkImage(", 1)[1]
            if ")" in head:
                notes.append(f"{path}:{i + 1} SINGLE-LINE (fix by hand)")
                out.append(lines[i])
                i += 1
                continue
            window = "".join(lines[i : i + 16])
            if "memCacheWidth" in window:
                out.append(lines[i])
                i += 1
                continue
            cap = pick_cap(window)
            expr = CAP_EXPR[cap]
            # insertion anchor: `fit:` line within window, else imageUrl line
            anchor = None
            for j in range(i, min(i + 16, len(lines))):
                if re.search(r"\bfit\s*:", lines[j]):
                    anchor = j
                    break
            if anchor is None:
                for j in range(i, min(i + 16, len(lines))):
                    if "imageUrl:" in lines[j]:
                        anchor = j
                        break
            if anchor is None:
                notes.append(f"{path}:{i + 1} SKIP (no anchor)")
                out.append(lines[i])
                i += 1
                continue
            # copy verbatim through the anchor, then insert caps
            for j in range(i, anchor + 1):
                out.append(lines[j])
            indent = re.match(r"\s*", lines[anchor]).group(0)
            out.append(f"{indent}// P12: decode-capped (was full-res).\n")
            out.append(f"{indent}memCacheWidth: {expr},\n")
            out.append(f"{indent}maxWidthDiskCache: {expr},\n")
            notes.append(f"{path}:{i + 1} cap={cap}")
            changed = True
            i = anchor + 1
            continue
        out.append(lines[i])
        i += 1
    if changed and not any("utils/perf/image_caps.dart" in l for l in out):
        for k, l in enumerate(out):
            if "package:cached_network_image/cached_network_image.dart" in l:
                rel = path.split("lib/", 1)[1]
                depth = len(rel.split("/")) - 1
                imp = "../" * depth + "utils/perf/image_caps.dart"
                out.insert(k + 1, "\n")
                out.insert(k + 2, f"import '{imp}';\n")
                notes.append(f"{path}: import added ({imp})")
                break
    return out, notes


def main() -> None:
    apply = "--apply" in sys.argv
    all_notes: list[str] = []
    for path in FILES:
        out, notes = process(path)
        all_notes += notes
        if apply and notes:
            with open(path, "w", encoding="utf-8") as f:
                f.writelines(out)
    print(f"{'APPLIED' if apply else 'DRY-RUN'}: {len(all_notes)} insertions")
    for n in all_notes:
        print(" ", n)


if __name__ == "__main__":
    main()
