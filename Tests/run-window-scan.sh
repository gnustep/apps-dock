#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
make
build_dir=$(mktemp -d /tmp/dock-scan-tests.XXXXXX)
trap 'rm -rf "$build_dir"' EXIT
clang $(gnustep-config --objc-flags) Tests/WindowScan.m \
  obj/DockWM.obj/X11DockManager*.o \
  -o "$build_dir/scan-tests" $(gnustep-config --gui-libs) -lX11 -lXext
xvfb-run -a "$build_dir/scan-tests"
