#!/bin/bash
# Dizzy v1.2.0+30 full release build: 3 ABI-split APKs + Universal APK + Windows EXE
# Log: build-all.log | Outputs copied to release-artifacts/
set -u
cd C:/Users/opcha/Downloads/Dizzy-v3
FLUTTER=C:/Users/opcha/flutter/bin/flutter
LOG=build-all.log
ART=release-artifacts
: > "$LOG"

step() { echo "===== [$1] $(date '+%H:%M:%S') =====" | tee -a "$LOG"; }

fail() { echo "BUILD FAILED at: $1 -- see $LOG" | tee -a "$LOG"; exit 1; }

step "1/4 split-per-abi APKs"
"$FLUTTER" build apk --release --split-per-abi --dart-define-from-file=.env >> "$LOG" 2>&1 || fail "split APKs"

step "2/4 universal APK"
"$FLUTTER" build apk --release --dart-define-from-file=.env >> "$LOG" 2>&1 || fail "universal APK"

step "3/4 windows EXE"
"$FLUTTER" build windows --release --dart-define-from-file=.env >> "$LOG" 2>&1 || fail "windows"

step "4/4 copy artifacts"
mkdir -p "$ART/windows-x64"
cp -f build/app/outputs/flutter-apk/app-arm64-v8a-release.apk "$ART/Dizzy-arm64-v8a.apk" >> "$LOG" 2>&1
cp -f build/app/outputs/flutter-apk/app-armeabi-v7a-release.apk "$ART/Dizzy-armeabi-v7a.apk" >> "$LOG" 2>&1
cp -f build/app/outputs/flutter-apk/app-x86_64-release.apk "$ART/Dizzy-x86_64.apk" >> "$LOG" 2>&1
cp -f build/app/outputs/flutter-apk/app-release.apk "$ART/Dizzy-Universal.apk" >> "$LOG" 2>&1
cp -rf build/windows/x64/runner/Release/. "$ART/windows-x64/" >> "$LOG" 2>&1
ls -la "$ART/" >> "$LOG" 2>&1
ls -la "$ART/windows-x64/" | head -n 20 >> "$LOG" 2>&1

step "DONE all builds OK"
