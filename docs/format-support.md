# Format-support matrix (player, v1.2.0 — backend: media_kit/MPV)

| Format | Support | Notes |
|---|---|---|
| HLS VOD master (`...m3u8`) | ✅ Full | Ladder parsed (`HlsRenditionParser`); quality menu = Auto + every rung; live `hls-bitrate-max` cap, no reopen |
| HLS live/event (`/hls/live`) | ✅ Plays | No duration bar promises; quality capped live |
| Progressive MP4 (http direct) | ✅ Full | Badge-gated switching across ranked files (first match wins) |
| Other progressive (mkv/webm via http) | ⚠️ Best-effort | MPV core usually plays; no badge → Auto only |
| Magnet / torrent (p2p) | ✅ Via resolver | Torrent streaming service; needs swarm/seeds |
| Debrid links (Real-Debrid/Torbox-style) | ✅ Full | Treated as premium direct; Hindi dub gate applies |
| DASH (`...mpd`) | ❌ Not advertised | MPV may play if offered, but no menu/detection support |
| DRM (Widevine/FairPlay) | ❌ No | License flow not implemented |
| External subs (srt/vtt url) | ✅ Full | Words-on-screen styles + live preview |
| Embedded subs | ✅ Best-effort | Depends on MPV track detection |

Audio: language tags drive the Hindi dub gate (`hasAudioLanguage`);
AV1 on weak/straining devices is dodged first (H264 preferred), with AV1
fallback when nothing else matches. Data Saver caps auto quality at 720p.
