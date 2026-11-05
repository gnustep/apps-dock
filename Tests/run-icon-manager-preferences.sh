#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
make
build_dir=$(mktemp -d /tmp/dock-icon-manager-preferences.XXXXXX)
trap 'rm -rf "$build_dir"' EXIT
objects=$(find obj/DockWM.obj -name '*.o' ! -name main.m.o)
clang $(gnustep-config --objc-flags) Tests/IconManagerPreferences.m $objects \
  -o "$build_dir/preferences" $(gnustep-config --gui-libs) -lX11 -lXext
xvfb-run -a "$build_dir/preferences"
