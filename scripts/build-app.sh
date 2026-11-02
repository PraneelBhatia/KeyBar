#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
export CLANG_MODULE_CACHE_PATH="$PWD/.build/clang-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$PWD/.build/module-cache"
swift build -c release --disable-sandbox --cache-path .build/cache --config-path .build/config --security-path .build/security
app="$PWD/dist/KeyBar.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources"
cp .build/release/KeyBar "$app/Contents/MacOS/KeyBar"
cp Resources/Info.plist "$app/Contents/Info.plist"
swift scripts/make-icon.swift "$app/Contents/Resources"
# Local development signature only. Use an Apple Developer ID for distribution.
codesign --force --sign "${KEYBAR_SIGN_IDENTITY:--}" --identifier app.keybar.mac "$app"
printf 'Built %s\n' "$app"
