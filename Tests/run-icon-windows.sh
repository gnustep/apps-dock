#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
make
build_dir=$(mktemp -d /tmp/dock-icon-windows.XXXXXX)
trap 'rm -rf "$build_dir"' EXIT
clang $(gnustep-config --objc-flags) Tests/IconWindows.m \
  obj/DockWM.obj/DockView*.o obj/DockWM.obj/DockItem*.o \
  -o "$build_dir/icon-windows" $(gnustep-config --gui-libs) -lX11 -lXext -lXtst
xvfb-run -a "$build_dir/icon-windows"
