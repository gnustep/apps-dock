#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
make
build_dir=$(mktemp -d /tmp/dock-restore-tests.XXXXXX)
trap 'rm -rf "$build_dir"' EXIT
objects=$(find obj/DockWM.obj -name '*.o' ! -name main.m.o)
clang $(gnustep-config --objc-flags) Tests/RestoreMenu.m $objects \
  -o "$build_dir/restore-tests" $(gnustep-config --gui-libs) -lX11 -lXext
xvfb-run -a "$build_dir/restore-tests"
