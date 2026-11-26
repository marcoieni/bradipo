#!/bin/sh
# Packs .build/bradipo.app from scripts/build-app.sh into .build/bradipo.tar.gz
# for the Terminal command in README.md and Check for Updates. The name has no
# version, so the command's URL always points to the latest release.
set -eu
cd "$(dirname "$0")/.."

# Leave out extended attributes, which would describe the build machine's files.
tar --no-mac-metadata --no-xattrs -czf .build/bradipo.tar.gz -C .build bradipo.app
echo "Packaged .build/bradipo.tar.gz"
