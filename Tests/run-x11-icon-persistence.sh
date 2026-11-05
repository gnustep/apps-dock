#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
make
build_dir=$(mktemp -d /tmp/dock-x11-icon-tests.XXXXXX)
trap 'rm -rf "$build_dir"' EXIT
clang $(gnustep-config --objc-flags) Tests/X11IconPersistence.m \
  obj/DockWM.obj/ApplicationIconManager.m.o \
  obj/DockWM.obj/DockApplicationStore.m.o \
  obj/DockWM.obj/DockPreferences.m.o \
  obj/DockWM.obj/RunningApplicationScanner.m.o \
  obj/DockWM.obj/DockItem*.o \
  -o "$build_dir/icon-tests" $(gnustep-config --gui-libs)
xvfb-run -a "$build_dir/icon-tests"
