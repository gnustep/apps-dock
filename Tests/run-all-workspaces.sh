#!/bin/sh
# Exercise the real AppKit window and native X11 ID under a window manager.
set -eu
cd "$(dirname "$0")/.."

if [ "${1:-}" != "--inside-xvfb" ]; then
  make
  exec xvfb-run -a sh Tests/run-all-workspaces.sh --inside-xvfb
fi

test_dir=$(mktemp -d /tmp/dock-workspace-tests.XXXXXX)
wm_pid=
dock_pid=
cleanup()
{
  if [ -n "$dock_pid" ]; then kill "$dock_pid" 2>/dev/null || true; fi
  if [ -n "$wm_pid" ]; then kill "$wm_pid" 2>/dev/null || true; fi
  wait 2>/dev/null || true
  rm -rf "$test_dir"
}
trap cleanup EXIT

wmaker --static --no-dock --no-clip --no-autolaunch --no-drawer \
  --dont-restore >"$test_dir/wmaker.log" 2>&1 &
wm_pid=$!
for attempt in $(seq 1 50); do
  if xprop -root _NET_SUPPORTING_WM_CHECK | grep -q 'window id'; then break; fi
  sleep 0.1
done
wmctrl -m >/dev/null
wmctrl -n 3
./DockWM.app/DockWM >"$test_dir/dock.log" 2>&1 &
dock_pid=$!

dock_id=
for attempt in $(seq 1 100); do
  # Startup helper windows may disappear while xwininfo walks the tree.
  dock_id=$(xwininfo -root -tree 2>/dev/null |
    awk '/"AppsDockWM"/ { print $1; exit }')
  if [ -n "$dock_id" ] &&
     xprop -id "$dock_id" _NET_WM_DESKTOP | grep -q '= 4294967295'; then
    break
  fi
  sleep 0.1
done
if [ -z "$dock_id" ]; then
  cat "$test_dir/dock.log"
  echo 'FAIL: dock window did not appear' >&2
  exit 1
fi
xprop -id "$dock_id" _NET_WM_DESKTOP | grep -q '= 4294967295'

for desktop in 1 2 0; do
  wmctrl -s "$desktop"
  sleep 0.3
  xprop -root _NET_CURRENT_DESKTOP | grep -q "= $desktop$"
  xwininfo -id "$dock_id" | grep -q 'Map State: IsViewable'
  xprop -id "$dock_id" _NET_WM_DESKTOP | grep -q '= 4294967295'
done
echo 'PASS: dock remains visible across all three workspaces'
