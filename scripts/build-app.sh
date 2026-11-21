#!/bin/sh
# Usage: scripts/build-app.sh [MAJOR.MINOR.PATCH]
# A version argument replaces the one in Resources/Info.plist, so a release
# reports the version of its tag.
set -eu
cd "$(dirname "$0")/.."

version=${1-}
if [ -n "$version" ] && ! printf '%s\n' "$version" | grep -Eqx '[0-9]+\.[0-9]+\.[0-9]+'; then
    echo "usage: $0 [MAJOR.MINOR.PATCH]" >&2
    exit 64
fi

swift build -c release --product bradipo
bin_dir=$(swift build -c release --show-bin-path)
contents=".build/bradipo.app/Contents"
mkdir -p "$contents/MacOS" "$contents/Resources"
cp "$bin_dir/bradipo" "$contents/MacOS/bradipo"
cp Resources/Info.plist "$contents/"
if [ -n "$version" ]; then
    plutil -replace CFBundleShortVersionString -string "$version" "$contents/Info.plist"
    plutil -replace CFBundleVersion -string "$version" "$contents/Info.plist"
fi
cp Resources/Sloth.png Resources/bradipo.icns "$contents/Resources/"
codesign --force --sign - .build/bradipo.app
echo "Built .build/bradipo.app"
