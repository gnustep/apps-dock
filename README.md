# DockWM

DockWM is a small GNUstep/AppKit dock-style window manager shell inspired by
WindowMaker.

It supports two inputs:

- Dropping application bundles or executable paths from GNUstep tools such as
  apps-gworkspace onto the dock.
- Discovering small X11 top-level windows, including common WindowMaker
  dockapps, and reparenting them into an X11 dock host.

## Build

```sh
make
```

## Run

```sh
./DockWM.app/DockWM
```

The AppKit dock accepts filesystem drops. A companion X11 override-redirect host
window is created next to it for dockapps and other small X11 clients.

The dock remains visible on every workspace. Run the workspace regression
check with `sh Tests/run-all-workspaces.sh` (requires Xvfb, Window Maker,
`wmctrl`, `xprop`, and `xwininfo`). It switches among three workspaces on an
isolated display and checks that the dock stays visible.

Pinned applications that are moved or removed leave a question-mark placeholder
in their saved position by default. The tooltip identifies the missing app, and
its launch arguments and behavior settings are retained. The Dock checks for
changes every 15 seconds and restores the icon if the original path becomes
available again.

Disable **Keep placeholders for missing applications** in **Settings → Behavior**
to remove missing entries instead.

The missing-application regression checks can be run with:

```sh
sh Tests/run-missing-applications.sh
```

These checks require `clang`, GNUstep, and `xvfb-run`.

Window discovery runs in small batches so that full X11 sweeps yield to clicks
and icon-manager requests. Each batch handles at most eight windows and checks
an 8 ms budget between windows; a single slow X server reply can exceed that
budget. Newly mapped windows still use the event-driven discovery path.

Run the X11 regression tests with an installed GNUstep GUI backend and Xvfb:

```sh
sh Tests/run-window-scan.sh
sh Tests/run-x11-efficiency.sh
sh Tests/run-miniwindow-suppression.sh
```

The window-scan test creates 128 clients and verifies main-loop responsiveness,
complete discovery without duplicate classification, coalesced refreshes,
known-window updates, destruction during a scan, and discovery of new clients
while a sweep is active.

Icon suppression uses the `_GNUSTEP_WM_ATTR` application-icon and miniwindow
style bits, regardless of window dimensions. Miniwindow unmapping respects the
miniwindow preference. Window Maker application tiles are identified by the
`_WINDOWMAKER_APP_ICON` property (type `WINDOW`, one owning client window ID),
published by the companion gs-wmaker change. When that property is absent,
DockWM falls back to a validated Window Maker noticeboard plus an anonymous
override-redirect root window with the icon event mask and XDND support.
Named clients, transient windows, and containers of ordinary windows are
excluded from both fallback paths. If both attribute matches fail, exact
48×48 or 64×64 dimensions are used as the final fallback. The explicit marker
and legacy attribute matches do not require those dimensions. Both fallback
paths are heuristic.
Dockapp discovery uses explicit `DockApp` class and
`WM_HINTS` icon-window metadata instead of size heuristics.

Run `sh Tests/run-overlay-preservation.sh` to check preservation of unmarked
overlay windows, including windows with XDND support and icon-like event masks.
Run `sh Tests/run-windowmaker-icons.sh /path/to/gs-wmaker/src/wmaker` to verify
that Window Maker publishes the marker and DockWM unmaps the resulting tile,
then removes the marker and verifies the legacy fallback on the same tile.
This test uses an isolated display and requires `xdotool`.

Before launching an application, DockWM saves `GSSuppressAppIcon = YES` in that
application’s defaults domain, preserving its other preferences. This applies
to app bundles, executables, and applications launched through desktop files;
no suppression argument is added to the command line. DockWM also sets this
default for itself before creating its application object.

At startup, DockWM writes `GSUseIconManager` to the GNUstep global defaults
domain. It defaults to enabled. Turn off **Settings → Behavior → Use icon
manager for all applications** to disable it; the global choice is saved
immediately and retained across restarts. Applications read this setting when
starting, so restart running applications to pick up a change. DockWM no longer
writes this setting into individual application domains. At startup it removes
saved per-application `GSUseIconManager` overrides so applications inherit the
global choice, preserving their other preferences.

Run `sh Tests/run-icon-manager-preferences.sh` to check the default, persistence,
and migration of per-application overrides using an isolated defaults database.
