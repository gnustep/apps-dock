#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
make
build_dir=$(mktemp -d /tmp/dock-exit-tests.XXXXXX)
trap 'rm -rf "$build_dir"' EXIT
objects=$(find obj/DockWM.obj -name '*.o' ! -name main.m.o)
clang $(gnustep-config --objc-flags) Tests/ApplicationExits.m $objects \
  -o "$build_dir/exit-tests" $(gnustep-config --gui-libs) -lX11 -lXext
"$build_dir/exit-tests"
