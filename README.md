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

Application exits are checked every half second, independently of the slower
application discovery and missing-file scans. Closing a window keeps its app
running in the dock if the process is still alive. Run the exit regression
checks with `sh Tests/run-application-exits.sh`.

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
starting, so restart running applications to pick up a change. Per-app choices are available in **Settings → Applications → Icon manager**:
**Use global setting** (the default), **On**, or **Off**. An explicit app choice
takes priority over the global switch and survives DockWM restarts. Choose
**Use global setting** to remove an override. Other app preferences are preserved.
DockWM also rejects incoming application icon-manager updates when disabled,
including direct messages from apps that bypass GNUstep's preference check.
This does not pause an embedded X11 dockapp's own drawing or disable process
tracking. Restart applications after changing the setting to update their own
icon-manager connections.

Run `sh Tests/run-icon-manager-preferences.sh` to check defaults, persistence,
and per-application overrides using an isolated defaults database.

Each application's menu includes **Keep In Dock**, enabled by default. Turning
it off immediately removes the app from the dock, even while it is running,
and prevents process scans and icon updates from adding it again. The choice
is saved as `GSDockKeepInDock` in the application's defaults domain. Drag the
application back onto the dock to enable it again. This is separate from
**Open At Login** and does not quit the application.

Run `sh Tests/run-keep-in-dock.sh` to check the menu, saved visibility, X11
rediscovery, and restoring an app by dropping it back into the dock.

### Icon windows and bounce animation

Application icons, the GNUstep tile, the Recycler, and application state dots use
separate shaped, non-focusable windows. There is no visible dock background
or border. Two thin separator windows bracket the unpinned application section
when it contains apps. State dots remain stationary while icons bounce and are
removed when their state no longer matches the selected indicator mode.
Icon windows move through a large vertical hop and a smaller settling hop;
a top-edge dock bounces downward into the screen. Attention requests repeat
until acknowledged. Bounce frames move the existing buffered windows without
redrawing icons or rebuilding their shapes. The drop marker window exists only
during a drag. Rendered overlays are cached: unchanged refreshes and exposure
events reuse their images, while icon, badge, label, and size changes refresh
the affected surfaces. Existing animation preferences remain compatible.

App names appear in compact tooltip windows beside the hovered icon, toward the
interior of the screen. Labels stay within the screen edges.

Icons receive clicks, context menus, hover, and drag input directly. Dots,
tooltips, separators, and the drag insertion marker pass pointer input through. On X11,
alpha-derived bounding shapes expose the desktop without requiring a compositor.
The invisible layout owner remains for placement and screen-space reservation.

Run `sh Tests/run-icon-windows.sh` with an available Xvfb server to check native
window creation, desktop visibility, dot lifecycle, pointer activation (using XTest), bounce movement,
reordering, and window cleanup. The test requires the XTest development library, Window Maker, and `xprop`.
It runs both on bare Xvfb and under Window Maker, checking recovery after native
restacking hides mapped icons behind the dock and ensuring repairs do not
generate a repeating configure-event loop.
Native event processing also continues during modal alerts and menu tracking,
so window-manager restacks cannot leave icons covered while those loops run.
The icon-window test checks recovery with a modal alert open.

Gaps can be enabled with **Settings → Dock → Allow gaps (NeXT style)**
(off by default). In **Applications**, select a pinned app and enable
**Gap before app** to leave one empty tile-sized slot before it. Gap positions
are saved with pinned apps; turning gaps off compacts the dock without erasing
them. The option works in horizontal and vertical docks.

**Appearance → Use common_Tile** draws a tile behind each icon while keeping
the surrounding dock transparent. The tile itself retains its image opacity.
