#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
make
clang $(gnustep-config --objc-flags) Tests/IconManagerPreferences.m \
  obj/DockWM.obj/DockPreferences.m.o \
  -o /tmp/dock-icon-manager-preferences $(gnustep-config --gui-libs)
/tmp/dock-icon-manager-preferences
