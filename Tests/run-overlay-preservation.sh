#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
make
build_dir=$(mktemp -d /tmp/dock-overlay-tests.XXXXXX)
trap 'rm -rf "$build_dir"' EXIT
clang $(gnustep-config --objc-flags) Tests/OverrideRedirectSuppression.m \
  obj/DockWM.obj/X11DockManager*.o \
  -o "$build_dir/overlay-tests" $(gnustep-config --gui-libs) -lX11 -lXext
xvfb-run -a "$build_dir/overlay-tests"
