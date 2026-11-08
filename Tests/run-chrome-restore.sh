#!/bin/sh
# Restore a real Chrome client under Window Maker in an isolated display/profile.
set -eu
cd "$(dirname "$0")/.."
if [ "${1:-}" != "--inside-xvfb" ]; then
  make
  exec xvfb-run -a sh Tests/run-chrome-restore.sh --inside-xvfb
fi
build_dir=$(mktemp -d /tmp/dock-chrome-restore.XXXXXX)
wm_pid=
chrome_pid=
cleanup()
{
  if [ -n "$chrome_pid" ]; then kill "$chrome_pid" 2>/dev/null || true; fi
  if [ -n "$wm_pid" ]; then kill "$wm_pid" 2>/dev/null || true; fi
  wait 2>/dev/null || true
  # Chrome's helper processes can finish writing after the parent exits.
  for attempt in $(seq 1 30); do
    if rm -rf "$build_dir" 2>/dev/null; then return; fi
    sleep 0.1
  done
  rm -rf "$build_dir"
}
trap cleanup EXIT
objects=$(find obj/DockWM.obj -name '*.o' ! -name main.m.o)
clang $(gnustep-config --objc-flags) Tests/RestoreMenu.m $objects \
  -o "$build_dir/restore-tests" $(gnustep-config --gui-libs) -lX11 -lXext
wmaker --static --no-dock --no-clip --no-autolaunch --no-drawer \
  --dont-restore >"$build_dir/wmaker.log" 2>&1 &
wm_pid=$!
for attempt in $(seq 1 50); do
  if wmctrl -m >/dev/null 2>&1; then break; fi
  sleep 0.1
done
google-chrome --user-data-dir="$build_dir/profile" --no-first-run \
  --no-default-browser-check --disable-gpu about:blank >"$build_dir/chrome.log" 2>&1 &
chrome_pid=$!
window=
for attempt in $(seq 1 100); do
  window=$(wmctrl -lx | awk '/Google-chrome/ { print $1; exit }')
  if [ -n "$window" ]; then break; fi
  sleep 0.1
done
test -n "$window"
xdotool windowminimize "$window"
for attempt in $(seq 1 50); do
  if xprop -id "$window" WM_STATE | grep -q Iconic; then break; fi
  sleep 0.1
done
xprop -id "$window" WM_STATE | grep -q Iconic
timeout -k 2 15 "$build_dir/restore-tests" "$window"
xdotool windowminimize "$window"
for attempt in $(seq 1 50); do
  if xprop -id "$window" WM_STATE | grep -q Iconic; then break; fi
  sleep 0.1
done
xprop -id "$window" WM_STATE | grep -q Iconic
timeout -k 2 15 "$build_dir/restore-tests" "$window" --application
xdotool windowminimize "$window"
for attempt in $(seq 1 50); do
  if xprop -id "$window" WM_STATE | grep -q Iconic; then break; fi
  sleep 0.1
done
xprop -id "$window" WM_STATE | grep -q Iconic
timeout -k 2 15 "$build_dir/restore-tests" "$window" --application --double-click
echo 'PASS: Restore menu and double-click restore Chrome under Window Maker'
