# DockWM Changelog

Changes from the first commit, `a83384c` (August 26, 2026), through
`1976526` (November 15, 2026), newest first. Dates are Git author dates.
The repository has no release tags; these entries describe development history,
not numbered releases. Related commits on the same day are consolidated.

## 2026-11-15

- Added a separate minimized-window section between undocked applications and
  the Recycler for both X11 and GNUstep clients.
- Each minimized entry restores its own window and disappears when the window
  is restored or closed. Pinned application icons remain in place.
- Added section dividers for horizontal and vertical docks and regression
  coverage for minimized-window discovery and lifecycle.

## 2026-11-13

- Addressed dock flashing and restored the latest GSIconManager icons and badges
  for still-running applications after a dock restart.
- Validated cached updates against process start time, executable, and boot ID
  to prevent stale state from being applied to a reused process ID.
- Added restart tests covering stale and corrupt icon-manager caches.

## 2026-11-08

- Fixed Recycler drag handling and application drag-and-drop across icon windows.
- Retained the shared drag pasteboard for the dock view's lifetime to prevent
  crashes as drags cross windows.
- Added integration tests for folder recycling and application pinning with
  normal autorelease-pool turnover.

## 2026-11-07

- Added **Restore** for GNUstep and X11 applications, including application
  activation when no minimized-window list is available.
- Added individual window restoration and **Restore All** for applications with
  multiple minimized windows, while excluding miniwindow icons.
- Made double-click activation use the same restoration behavior; the single-click
  preference also follows this behavior.
- Added restoration regression tests and a real Chrome/Window Maker test.
- Added a pointer arrow to application-name tooltips.

## 2026-11-04

- Added global and per-application icon-manager controls, including **Use global
  setting**, **On**, and **Off** overrides that survive restarts.
- Rejected incoming icon-manager updates when disabled without disabling process
  tracking or embedded X11 dockapp drawing.
- Improved X11 icon caching and reloading by application path, including older
  pinned entries and fallback when cached images are unavailable.
- Added preference and X11 icon-persistence regression tests.

## 2026-11-02

- Extended the separate-window design to the GNUstep tile, Recycler, and state
  indicators, with transparent desktop space around icons.
- Enabled direct click, context-menu, hover, and drag input on icon windows.
- Restored section separators as thin windows that pass pointer input through.
- Fixed disappearing icons during window-manager restacking, modal alerts, and
  menu tracking.
- Cached rendered overlays and moved existing buffered windows during bounce
  animation to avoid unnecessary redraws and shape rebuilding.
- Improved tooltip placement and kept labels within screen edges.
- Added optional NeXT-style gaps before pinned apps, preserving gap positions
  when the option is disabled.
- Restored **common_Tile** backgrounds behind individual icons.

## 2026-11-01

- Reduced application-exit detection to half-second checks, separate from slower
  discovery scans. Closing a window no longer implies that its app has exited.
- Added persistent **Keep In Dock** visibility control, including suppression of
  rediscovery until the application is dragged back into the dock.
- Moved application icons and the Recycler into separate transparent windows
  and introduced a two-stage bounce animation.
- Fixed icon disappearance after native restacking and added tests on both bare
  Xvfb and Window Maker.
- Added application-exit and Keep In Dock regression coverage.

## 2026-10-28

- Applied `GSUseIconManager` through GNUstep global defaults so applications
  inherit the setting, with migration of earlier per-app settings.
- Improved the settings panel's appearance and added icon-manager preference tests.

## 2026-10-15

- Added `.ycode.plist` development configuration.

## 2026-10-10

- Refined icon and miniwindow suppression to avoid hiding ordinary windows,
  including Gorm windows and small overlays.
- Used GNUstep window-style attributes and Window Maker's application-icon
  marker, with legacy attribute and size fallbacks when needed.
- Changed dockapp detection to use explicit class and icon-window metadata.
- Saved `GSSuppressAppIcon` in application defaults before launch without adding
  suppression arguments to the application's command line.
- Added overlay-preservation and Window Maker icon regression tests.

## 2026-10-08

- Batched X11 window discovery so large scans yield to clicks and icon-manager
  requests, while newly mapped windows retain event-driven discovery.
- Improved scan efficiency, icon handling, and visibility across workspaces.
- Added tests for window scanning, X11 efficiency, miniwindow suppression, and
  visibility across multiple workspaces.

## 2026-10-01

- Added an **App Name Delay** setting for tooltips, including immediate display
  when the delay is zero.

## 2026-09-29

- Added question-mark placeholders for pinned applications that have been moved
  or removed, retaining their positions, launch arguments, and behavior settings.
- Restored icons when application paths become available again and added a
  preference to remove missing entries instead of keeping placeholders.
- Added missing-application regression tests.

## 2026-09-26

- Added filesystem unmounting when a mounted filesystem is dropped on the Recycler.

## 2026-09-20

- Added dock scaling with a size control in Settings.
- Added a **Hide Miniwindows** preference and applied it to window filtering.

## 2026-09-19

- Changed application launching to set `GSUseIconManager` in defaults.
- Launched applications with the user's home directory as the working directory.

## 2026-09-17

- Improved window filtering and activation for applications that initially open
  only a menu.

## 2026-09-16

- Fixed launching behavior that closed the initial Terminal window.

## 2026-09-15

- Enabled icon-manager use by default for applications launched manually or at login.
- Refactored AppController and other large classes into smaller implementation units.
- Updated Recycler behavior and prevented drag removal of running applications.

## 2026-09-11

- Added an application path field to Settings.
- Added single-click application launching as a preference.

## 2026-09-10

- Added per-application settings.

## 2026-09-09

- Improved running-application matching to avoid identifying an app launched from
  a different path as the docked application.
- Fixed dock loading before initialization was complete.
- Fixed GCC build issues.

## 2026-09-06

- Displayed opacity and magnification settings as percentages.

## 2026-09-05

- Added animation for application attention requests and sticky dock-window behavior.
- Added an application-removal sound and related settings.

## 2026-09-03

- Improved interaction between launch/activation animation and hover magnification.
- Restored minimized windows when activating applications.
- Fixed badge rendering and icons disappearing when badges were shown.

## 2026-09-02

- Added icon magnification on hover.

## 2026-09-01

- Improved support for Window Maker dockapps and GSIconManager icon updates.
- Replaced color sliders with a color well and the standard color panel.
- Expanded application settings with launch arguments and ordering controls,
  including movement of dockapps.
- Preserved X11 item paths so those applications could be started automatically.
- Introduced a separate Settings controller and extracted responsibilities from
  AppController into supporting classes.

## 2026-08-31

- Fixed Recycler behavior and badge display.
- Corrected GCC builds and added and repaired the GitHub Actions build workflow.
- Updated development workspace settings.

## 2026-08-29

- Improved X11 and GNUstep icon discovery and activation from rendered icons.
- Reduced polling, avoided rescanning static X11 icons, and improved X11 event
  processing and process-table scanning to reduce lag and icon churn.
- Suppressed repeated appearances of native application icons and miniwindows.
- Filtered unnamed X11 applications and persisted X11 icons.
- Removed hardcoded paths and the earlier transparency feature.
- Added dock borders, **common_Tile** backgrounds, and NeXT-style appearance and
  running-state indicator options.

## 2026-08-28

- Expanded support for displaying X11 applications in the dock.
- Reset application icons when apps exited and rendered application-provided badges.
- Fixed initial Terminal-window closure and icon churn.
- Revised miniwindow suppression, temporarily disabling it before restoring it
  with further fixes.

## 2026-08-27

- Improved drag-and-drop insertion indicators and GWorkspace interaction.
- Added file drops onto the Recycler, moving dropped items to the trash and
  extending support across file types.
- Improved application-provided icon updates and application activation.
- Added a preferences panel, color selection, and relative icon paths.
- Refined the early simulated-transparency rendering and X11 application handling.
- Revised application naming and updated the README to use DockWM.

## 2026-08-26 — Initial implementation

- Introduced the GNUstep/AppKit dock, initially named AppsDockWM, with filesystem
  drops and an X11 host for small clients and Window Maker dockapps.
- Added application launching, persistence, running-process detection, state
  indicators, and duplicate-entry prevention.
- Added NSDockTile-based icons and support for application icon updates.
- Added drag reordering, insertion at the drop position, and removal by dragging
  applications out of the dock.
- Added the Recycler, emptying confirmation, application-name tooltips, and
  launch/activation animation.
- Added a separator between pinned and running applications and initial
  miniwindow suppression.
- Fixed visibility, orientation, icon rendering, transparency, and GWorkspace
  drag interoperability during the initial implementation.
- Added graceful quitting, GNU-style formatting, copyright headers, and the
  GNU General Public License.
- Cleaned generated files from the repository and updated build and ignore rules.
