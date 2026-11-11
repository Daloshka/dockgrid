#!/bin/zsh
# Сборка релизного архива build/DockGrid.zip (универсальный Apps.app: Apple Silicon + Intel).
# Архив прикладывается к релизу на GitHub, его скачивает install.sh.
set -e
cd "${0:A:h}"
rm -rf build/release && mkdir -p build/release
DOCKGRID_APP="$PWD/build/release/Apps.app" DOCKGRID_ARCHS="arm64 x86_64" DOCKGRID_PACKAGE=1 ./build.sh
rm -f build/DockGrid.zip
ditto -c -k --keepParent build/release/Apps.app build/DockGrid.zip
echo "готово: build/DockGrid.zip ($(lipo -archs build/release/Apps.app/Contents/MacOS/Apps))"
