#!/bin/sh
# Pass a Window Maker build that publishes _WINDOWMAKER_APP_ICON.
set -eu
cd "$(dirname "$0")/.."
if [ "${1:-}" != "--inside-xvfb" ]; then
  make
  exec xvfb-run -a sh Tests/run-windowmaker-icons.sh --inside-xvfb "${1:-wmaker}"
fi
wm_binary=${2:-wmaker}
test_dir=$(mktemp -d /tmp/dock-wmaker-icons.XXXXXX)
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
"$wm_binary" --static --no-dock --no-clip --no-autolaunch --no-drawer \
  --dont-restore >"$test_dir/wmaker.log" 2>&1 &
wm_pid=$!
for attempt in $(seq 1 50); do
  if xprop -root _NET_SUPPORTING_WM_CHECK | grep -q 'window id'; then break; fi
  sleep 0.1
done
wmctrl -m >/dev/null
./DockWM.app/DockWM >"$test_dir/dock.log" 2>&1 &
dock_pid=$!
for attempt in $(seq 1 50); do
  kill -0 "$dock_pid"
  windows=$(xwininfo -root -children | awk '/^     0x/ { print $1 }')
  for window in $windows; do
    if xprop -id "$window" _WINDOWMAKER_APP_ICON 2>/dev/null |
       grep -q '_WINDOWMAKER_APP_ICON(WINDOW): window id # 0x'; then
      if xwininfo -id "$window" | grep -q 'Map State: IsUnMapped'; then
        echo 'PASS: Window Maker publishes application-icon metadata and DockWM unmaps its tile'
        exit 0
      fi
    fi
  done
  sleep 0.1
done
cat "$test_dir/wmaker.log" "$test_dir/dock.log"
echo 'FAIL: no explicitly marked, unmapped application tile found' >&2
exit 1
