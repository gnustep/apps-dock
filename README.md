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
published by the companion gs-wmaker change. Parent frames, ordinary windows,
and unmarked tiles are not unmapped. Size, XDND support, and event masks are not used
to infer icon identity. Dockapp discovery uses explicit `DockApp` class and
`WM_HINTS` icon-window metadata instead of size heuristics.

Run `sh Tests/run-overlay-preservation.sh` to check preservation of unmarked
overlay windows, including windows with XDND support and icon-like event masks.
Run `sh Tests/run-windowmaker-icons.sh /path/to/gs-wmaker/src/wmaker` to verify
that Window Maker publishes the marker and DockWM unmaps the resulting tile
on an isolated display.

Before launching an application, DockWM saves `GSSuppressAppIcon = YES` in that
application’s defaults domain, preserving its other preferences. This applies
to app bundles, executables, and applications launched through desktop files;
no suppression argument is added to the command line. DockWM also sets this
default for itself before creating its application object.
