#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
if [ "${1:-}" = "--with-wm" ]; then
  build_dir=$2
  wmaker --static --no-dock --no-clip --no-autolaunch --no-drawer \
    --dont-restore >"$build_dir/wmaker.log" 2>&1 &
  wm_pid=$!
  trap 'kill "$wm_pid" 2>/dev/null || true; wait "$wm_pid" 2>/dev/null || true' EXIT
  ready=false
  for attempt in $(seq 1 50); do
    if xprop -root _NET_SUPPORTING_WM_CHECK | grep -q "window id"; then
      ready=true
      break
    fi
    sleep 0.1
  done
  if [ "$ready" != true ]; then cat "$build_dir/wmaker.log"; exit 1; fi
  "$build_dir/icon-windows"
  exit
fi

make
build_dir=$(mktemp -d /tmp/dock-icon-windows.XXXXXX)
trap 'rm -rf "$build_dir"' EXIT
clang $(gnustep-config --objc-flags) Tests/IconWindows.m \
  obj/DockWM.obj/DockView*.o obj/DockWM.obj/DockItem*.o \
  obj/DockWM.obj/X11DockManager*.o \
  -o "$build_dir/icon-windows" $(gnustep-config --gui-libs) -lX11 -lXext -lXtst
xvfb-run -a "$build_dir/icon-windows"
# Repeat with a reparenting window manager; bare Xvfb cannot cover WM restacks.
xvfb-run -a sh "$0" --with-wm "$build_dir"
