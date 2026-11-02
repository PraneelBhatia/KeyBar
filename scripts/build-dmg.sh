#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"

./scripts/build-app.sh
app="$PWD/dist/KeyBar.app"
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app/Contents/Info.plist")
architecture=$(uname -m)
image="$PWD/dist/KeyBar-${version}-${architecture}.dmg"
staging=$(mktemp -d "$PWD/dist/dmg-stage.XXXXXX")
trap 'rm -rf "$staging"' EXIT

ditto "$app" "$staging/KeyBar.app"
ln -s /Applications "$staging/Applications"
hdiutil create -volname KeyBar -srcfolder "$staging" -format UDZO -ov "$image"
hdiutil verify "$image"
(cd dist && shasum -a 256 "${image:t}" > "${image:t}.sha256")
printf 'Packaged %s\n' "$image"
