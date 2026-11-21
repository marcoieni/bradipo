#!/bin/sh
set -eu
cd "$(dirname "$0")/.."

swift build -c release --product bradipo
bin_dir=$(swift build -c release --show-bin-path)
contents=".build/bradipo.app/Contents"
mkdir -p "$contents/MacOS" "$contents/Resources"
cp "$bin_dir/bradipo" "$contents/MacOS/bradipo"
cp Resources/Info.plist "$contents/"
cp Resources/Sloth.png Resources/bradipo.icns "$contents/Resources/"
codesign --force --sign - .build/bradipo.app
echo "Built .build/bradipo.app"
