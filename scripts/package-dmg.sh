#!/bin/sh
# Packs .build/bradipo.app from scripts/build-app.sh into
# .build/bradipo-<version>.dmg. The disk image shows the app next to a
# shortcut to Applications, so installing is a single drag.
set -eu
cd "$(dirname "$0")/.."

app=.build/bradipo.app
version=$(plutil -extract CFBundleShortVersionString raw -o - "$app/Contents/Info.plist")
dmg=.build/bradipo-$version.dmg

stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT
ditto "$app" "$stage/bradipo.app"
ln -s /Applications "$stage/Applications"

# hdiutil sometimes fails with "Resource busy" on GitHub's macOS runners
# (actions/runner-images#7522), so give it a few tries.
attempt=1
until hdiutil create -volname bradipo -srcfolder "$stage" -format UDZO -ov "$dmg"; do
    [ "$attempt" -lt 3 ] || exit 1
    attempt=$((attempt + 1))
    sleep 5
done
echo "Packaged $dmg"
