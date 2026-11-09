#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
if [ "${1:-}" = "--application" ]; then
  export DOCK_DRAG_TEST_APPLICATION=1
fi
if [ "${1:-}" != "--inside-xvfb" ]; then
  make
  exec xvfb-run -a sh Tests/run-recycler-drag.sh --inside-xvfb
fi
build_dir=$(mktemp -d /tmp/dock-recycler-drag.XXXXXX)
wm_pid=
target_pid=
source_pid=
cleanup()
{
  for pid in "$source_pid" "$target_pid" "$wm_pid"; do
    if [ -n "$pid" ]; then kill "$pid" 2>/dev/null || true; fi
  done
  wait 2>/dev/null || true
  rm -rf "$build_dir"
}
trap cleanup EXIT
objects=$(find obj/DockWM.obj -name '*.o' ! -name main.m.o)
clang $(gnustep-config --objc-flags) Tests/RecyclerDrag.m $objects \
  -o "$build_dir/recycler-drag" $(gnustep-config --gui-libs) -lX11 -lXext
wmaker --static --no-dock --no-clip --no-autolaunch --no-drawer \
  --dont-restore >"$build_dir/wmaker.log" 2>&1 &
wm_pid=$!
for attempt in $(seq 1 50); do
  if wmctrl -m >/dev/null 2>&1; then break; fi
  sleep .1
done
"$build_dir/recycler-drag" "$build_dir" >"$build_dir/target.log" 2>&1 &
target_pid=$!
"$build_dir/recycler-drag" "$build_dir" source >"$build_dir/source.log" 2>&1 &
source_pid=$!
for attempt in $(seq 1 100); do
  if [ -f "$build_dir/coordinates" ]; then break; fi
  sleep .1
done
read target_x target_y <"$build_dir/coordinates"
source_window=$(xdotool search --name 'Recycler Test Source' | head -1)
# Show the tooltip before beginning the drag, as in a normal desktop session.
xdotool mousemove $((target_x - 66)) "$target_y"
sleep .3
xdotool mousemove --window "$source_window" 50 50 mousedown 1
sleep .2
xdotool mousemove 170 580
sleep .2
# Keep the button held while repeatedly entering/leaving app and Recycler
# overlays. Native event processing, tooltips and hover magnification stay live.
for pass in 1 2 3 4 5; do
  xdotool mousemove $((target_x - 66)) "$target_y"
  sleep .15
  xdotool mousemove "$target_x" "$target_y"
  sleep .15
  xdotool mousemove "$target_x" $((target_y - 100))
  sleep .15
  kill -0 "$target_pid"
  if [ -n "${DOCK_DRAG_TEST_APPLICATION:-}" ]; then
    test -d "$build_dir/Ink.app"
  else
    test -d "$build_dir/Untitled Folder"
  fi
done
if [ -n "${DOCK_DRAG_TEST_APPLICATION:-}" ]; then
  target_x=$((target_x - 66))
fi
xdotool mousemove "$target_x" "$target_y"
sleep .3
xdotool mouseup 1
if [ -n "${DOCK_DRAG_TEST_APPLICATION:-}" ]; then
  for attempt in $(seq 1 50); do
    if [ -f "$build_dir/pinned" ]; then break; fi
    sleep .1
  done
  if ! kill -0 "$target_pid" 2>/dev/null || [ ! -f "$build_dir/pinned" ]; then
    cat "$build_dir/target.log" "$build_dir/source.log"
    echo 'FAIL: application drag did not pin the bundle safely' >&2
    exit 1
  fi
  sleep 1
  kill -0 "$target_pid"
  test -d "$build_dir/Ink.app"
  echo 'PASS: cross-process application drag pins the bundle without exiting'
  exit
fi
for attempt in $(seq 1 50); do
  if [ -d "$build_dir/Trash/Untitled Folder" ]; then break; fi
  sleep .1
done
if ! kill -0 "$target_pid" 2>/dev/null ||
   [ ! -d "$build_dir/Trash/Untitled Folder" ] ||
   [ -e "$build_dir/Untitled Folder" ]; then
  cat "$build_dir/target.log" "$build_dir/source.log"
  echo 'FAIL: Recycler drag did not complete safely' >&2
  exit 1
fi
# Allow drag completion callbacks and the Recycler bounce to finish.
sleep 1
kill -0 "$target_pid"
echo 'PASS: cross-process folder drag to Recycler completes without exiting'
