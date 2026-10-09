#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
make
build_dir=$(mktemp -d /tmp/dock-icon-tests.XXXXXX)
trap 'rm -rf "$build_dir"' EXIT
clang $(gnustep-config --objc-flags) Tests/IconProcessing.m \
  obj/DockWM.obj/ApplicationIconManager.m.o \
  obj/DockWM.obj/RunningApplicationScanner.m.o \
  obj/DockWM.obj/DockItem*.o \
  -o "$build_dir/icon-tests" $(gnustep-config --gui-libs)
"$build_dir/icon-tests"
