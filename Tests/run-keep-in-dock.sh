#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
make
build_dir=$(mktemp -d /tmp/dock-keep-tests.XXXXXX)
trap 'rm -rf "$build_dir"' EXIT
objects=$(find obj/DockWM.obj -name '*.o' ! -name main.m.o)
clang $(gnustep-config --objc-flags) Tests/KeepInDock.m $objects \
  -o "$build_dir/keep-tests" $(gnustep-config --gui-libs) -lX11 -lXext
xvfb-run -a "$build_dir/keep-tests"
