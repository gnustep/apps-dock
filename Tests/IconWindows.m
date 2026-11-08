#import "DockViewPrivate.h"
#import "AppControllerPrivate.h"
#import "X11DockManagerPrivate.h"
#import <X11/Xlib.h>
#import <X11/Xutil.h>
#import <X11/extensions/shape.h>
#import <X11/extensions/XTest.h>
#include <assert.h>
#import <GNUstepGUI/GSDisplayServer.h>

/* Use the WM frame when the dock client has been reparented. */
static Window RootAncestor(Display *display, Window window)
{
  Window root, parent, *children;
  unsigned int count;

  for (;;)
    {
      NSCAssert(XQueryTree(display, window, &root, &parent, &children, &count),
                @"Read window ancestry");
      if (children) XFree(children);
      if (parent == root) return window;
      NSCAssert(parent != None, @"Client must belong to the root");
      window = parent;
    }
}

@interface StackingManager : X11DockManager
@end

@implementation StackingManager
- (void) registerIconManager {}

- (void) scanForDockApps {}

- (void) handlePossiblyNewWindow: (Window)window {}

- (void) scanClientWindow: (Window)window {}

@end

/* Exercise the production event timer without discovery or login launches. */
@interface ModalTestController : AppController

- (id) initWithManager: (X11DockManager *)manager;
- (void) stopTimers;

@end

@implementation ModalTestController

- (id) initWithManager: (X11DockManager *)manager
{
  self = [super init];
  if (self) _x11 = RETAIN(manager);
  return self;
}

- (void) scanRunningApplications
{
}

- (void) launchOpenAtLoginApplications
{
}

- (void) stopTimers
{
  [_x11EventTimer invalidate];
  _x11EventTimer = nil;
  [_scanTimer invalidate];
  _scanTimer = nil;
  [_processScanTimer invalidate];
  _processScanTimer = nil;
  [_applicationExitTimer invalidate];
  _applicationExitTimer = nil;
}

@end

/* XQueryTree returns siblings in bottom-to-top stacking order. isVisible
 * cannot detect a mapped icon that is completely covered by the dock. */
static BOOL IconAboveDock(Display *display, NSWindow *icon, NSWindow *dock)
{
  Window root, parent, *children = NULL;
  unsigned int count = 0;
  NSInteger iconIndex = -1, dockIndex = -1;
  Window dockAncestor = RootAncestor(display, (Window)[dock windowRef]);
  XSync((Display *)[GSCurrentServer() serverDevice], False);
  XSync(display, False);
  NSCAssert(XQueryTree(display, DefaultRootWindow(display), &root, &parent,
                      &children, &count), @"Read native window stacking");
  for (unsigned int i = 0; i < count; i++)
    {
      if (children[i] == (Window)[icon windowRef]) iconIndex = i;
      if (children[i] == dockAncestor) dockIndex = i;
    }
  if (children) XFree(children);
  NSCAssert(dockIndex >= 0 && iconIndex >= 0, @"Both native windows exist");
  return iconIndex > dockIndex;
}

static void AssertIconAboveDock(Display *display, NSWindow *icon, NSWindow *dock)
{
  NSCAssert(IconAboveDock(display, icon, dock),
            @"Icon must be above dock, not merely mapped");
}

static BOOL ShapeContains(Display *display, Window window, int kind, int x, int y)
{
  int count, ordering;
  BOOL contains = NO;
  XRectangle *rects = XShapeGetRectangles(display, window, kind, &count, &ordering);
  for (int i = 0; i < count; i++)
    if (x >= rects[i].x && x < rects[i].x + rects[i].width &&
        y >= rects[i].y && y < rects[i].y + rects[i].height) contains = YES;
  if (rects) XFree(rects);
  return contains;
}

@interface ClickRecorder : NSObject
{
@public
  DockItem *activatedItem;
}
@end
@implementation ClickRecorder
- (void) dockViewDidActivateItem: (DockItem *)item { activatedItem = item; }
@end

static void PumpEvents(void)
{
  NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:0.25];
  while ([deadline timeIntervalSinceNow] > 0)
    {
      NSEvent *event = [NSApp nextEventMatchingMask:NSAnyEventMask untilDate:deadline
        inMode:NSDefaultRunLoopMode dequeue:YES];
      if (event) [NSApp sendEvent:event];
      [NSApp updateWindows];
    }
}

@interface TestDockView : DockView
{
  NSUInteger _iconRenderCount;
}

- (void) setTileFixture: (NSImage *)image;
- (NSUInteger) iconRenderCount;
- (NSWindow *) showNameForIndex: (NSInteger)index;
- (NSWindow *) iconWindowForItem: (DockItem *)item;
- (NSWindow *) indicatorWindowForItem: (DockItem *)item;
- (NSWindow *) separatorWindowAtEnd: (BOOL)atEnd;
- (void) advanceBounce: (NSTimeInterval)elapsed;
@end
@implementation TestDockView
- (void) setTileFixture: (NSImage *)image
{ ASSIGN(_cellBackgroundImage, image); }
- (NSWindow *) iconWindowForItem: (DockItem *)item
{ return [_iconWindows objectForKey:[NSValue valueWithPointer:item]]; }
- (NSWindow *) indicatorWindowForItem: (DockItem *)item
{
  return [_iconWindows objectForKey:[NSString stringWithFormat:@"indicator-%p", item]];
}

- (NSWindow *) separatorWindowAtEnd: (BOOL)atEnd
{
  return [_iconWindows objectForKey:atEnd ? @"separator-end" : @"separator-start"];
}

- (void) advanceBounce: (NSTimeInterval)elapsed
{
  _wiggleStartTime = [NSDate timeIntervalSinceReferenceDate] - elapsed;
  [self stepWiggle:nil];
}

- (NSWindow *) showNameForIndex: (NSInteger)index
{
  _hoveredItemIndex = index;
  [self showTooltip:nil];
  return _tooltipWindow;
}

- (NSUInteger) iconRenderCount
{
  return _iconRenderCount;
}

- (void) drawIconWindowForItem: (DockItem *)item
{
  _iconRenderCount++;
  [super drawIconWindowForItem:item];
}
@end

int main(void)
{
  NSAutoreleasePool *pool = [NSAutoreleasePool new];
  [NSApplication sharedApplication];
  NSSetUncaughtExceptionHandler(NULL);
  NSWindow *dock = [[DockWindow alloc] initWithContentRect:NSMakeRect(100, 100, 280, 84)
    styleMask:NSBorderlessWindowMask backing:NSBackingStoreBuffered defer:NO];
  [dock setReleasedWhenClosed:NO];
  TestDockView *view = [[TestDockView alloc] initWithFrame:NSMakeRect(0, 0, 280, 84)];
  [view setHorizontal:YES];
  DockItem *a = [DockItem applicationItemWithPath:@"/bin/sh"];
  [a setState:DockItemRunning];
  NSImage *fixture = [[[NSImage alloc] initWithSize:NSMakeSize(46, 46)] autorelease];
  [fixture lockFocus];
  [[NSColor redColor] set];
  NSRectFill(NSMakeRect(0, 0, 46, 46));
  [fixture unlockFocus];
  [a setIcon:fixture];
  DockItem *b = [DockItem x11ItemWithTitle:@"Second" window:0 icon:nil hidden:NO];
  [view setItems:[NSArray arrayWithObjects:a, b, nil]];
  [dock setContentView:view];
  StackingManager *manager = [[StackingManager alloc] initWithDockView:view];
  NSCAssert([manager start], @"Start native event observation");
  [dock orderFront:nil];
  [dock display];
  NSWindow *first = [view iconWindowForItem:a];
  NSWindow *second = [view iconWindowForItem:b];
  NSCAssert(first && second && first != second, @"Each app has a distinct window");
  NSCAssert([first parentWindow] == dock, @"Icon belongs to the dock");
  NSCAssert([first isVisible], @"Icon window is visible");
  Display *display = XOpenDisplay(NULL);
  XSetWindowBackground(display, DefaultRootWindow(display), 0x123456);
  XClearWindow(display, DefaultRootWindow(display));
  XSync(display, False);
  XWindowAttributes attributes;
  XSync(display, False);
  NSCAssert(XGetWindowAttributes(display, (Window)[first windowRef], &attributes), @"Native icon window exists");
  NSCAssert(attributes.map_state == IsViewable, @"Native icon window is mapped");
  /* Reproduce the actual startup sequence, which raises the dock twice. */
  [dock makeKeyAndOrderFront:nil];
  [dock orderFrontRegardless];
  PumpEvents();
  [manager processPendingEvents];
  AssertIconAboveDock(display, first, dock);
  AssertIconAboveDock(display, second, dock);
  [dock orderFront:nil];
  AssertIconAboveDock(display, first, dock);
  [first display];
  [second display];
  PumpEvents();
  XSync((Display *)[GSCurrentServer() serverDevice], False);
  XGetWindowAttributes(display, (Window)[first windowRef], &attributes);
  NSCAssert(attributes.override_redirect, @"No WM frame can swallow clicks");
  NSCAssert(ShapeContains(display, (Window)[first windowRef], ShapeBounding, 32, 32),
            @"Icon pixels remain visible");
  NSCAssert(!ShapeContains(display, (Window)[first windowRef], ShapeBounding, 32, 60),
            @"Icon window does not cover the running dot");
  NSCAssert(!ShapeContains(display, (Window)[dock windowRef], ShapeBounding, 10, 10),
            @"Layout owner has no visible backing surface");
  int shapeCount, shapeOrdering;
  XRectangle *input = XShapeGetRectangles(display, (Window)[first windowRef],
                                        ShapeInput, &shapeCount, &shapeOrdering);
  NSCAssert(shapeCount > 0, @"Icon window receives pointer input");
  if (input) XFree(input);
  NSPoint iconCenter = NSMakePoint(NSMidX([first frame]), NSMidY([first frame]));
  int screenX = (int)iconCenter.x;
  int screenY = DisplayHeight(display, DefaultScreen(display)) - (int)iconCenter.y;
  XImage *dot = XGetImage(display, DefaultRootWindow(display), screenX, screenY + 28,
                         1, 1, AllPlanes, ZPixmap);
  XImage *background = XGetImage(display, DefaultRootWindow(display), screenX - 12,
                                screenY + 28, 1, 1, AllPlanes, ZPixmap);
  NSCAssert(dot && background && XGetPixel(dot, 0, 0) != XGetPixel(background, 0, 0),
            @"Running dot is visible on screen below the icon");
  XImage *desktop = XGetImage(display, DefaultRootWindow(display), 5, 5,
                             1, 1, AllPlanes, ZPixmap);
  NSCAssert(desktop && XGetPixel(background, 0, 0) == XGetPixel(desktop, 0, 0),
            @"Desktop is visible through the former dock background");
  XDestroyImage(desktop);
  NSWindow *indicator = [view indicatorWindowForItem:a];
  NSCAssert(indicator && indicator != first && [indicator isVisible],
            @"Running indicator has its own visible window");
  NSRect indicatorRest = [indicator frame];
  XDestroyImage(dot);
  XDestroyImage(background);
  ClickRecorder *recorder = [[[ClickRecorder alloc] init] autorelease];
  [view setDelegate:recorder];
  [view setSingleClickLaunchesApplications:YES];
  XTestFakeMotionEvent(display, DefaultScreen(display), screenX, screenY, CurrentTime);
  XTestFakeButtonEvent(display, 1, True, CurrentTime);
  XTestFakeButtonEvent(display, 1, False, CurrentTime);
  XFlush(display);
  PumpEvents();
  NSCAssert(recorder->activatedItem == a, @"Real pointer click reaches app activation");
  /* A native restack bypasses DockWindow's orderWindow: override. Check
   * recovery through the real event consumer, including under Window Maker. */
  XLowerWindow(display, (Window)[first windowRef]);
  XLowerWindow(display, (Window)[second windowRef]);
  XRaiseWindow(display, RootAncestor(display, (Window)[dock windowRef]));
  XSync(display, False);
  NSCAssert([first isVisible], @"Covered icons still report visible");
  NSCAssert(!IconAboveDock(display, first, dock), @"Reproduce a covered icon");
  [manager processPendingEvents];
  AssertIconAboveDock(display, first, dock);
  AssertIconAboveDock(display, second, dock);
  /* Once repaired, another check must not produce configure events. */
  XSync(display, False);
  XSelectInput(display, DefaultRootWindow(display), SubstructureNotifyMask);
  [view repairIconWindowStacking];
  XSync((Display *)[GSCurrentServer() serverDevice], False);
  XSync(display, False);
  XEvent event;
  NSCAssert(!XCheckTypedEvent(display, ConfigureNotify, &event),
            @"Correct stacking must not trigger a configure loop");
  XSelectInput(display, DefaultRootWindow(display), 0);
  /* Keep the production timer responsible for recovery during an alert;
   * manually calling processPendingEvents would hide a run-loop mode bug. */
  ModalTestController *controller = [[ModalTestController alloc] initWithManager:manager];
  [controller performInitialApplicationScans];
  NSAlert *alert = [[NSAlert alloc] init];
  [alert setMessageText:@"Icon visibility regression"];
  NSModalSession session = [NSApp beginModalSessionForWindow:[alert window]];
  XLowerWindow(display, (Window)[first windowRef]);
  XLowerWindow(display, (Window)[second windowRef]);
  XSync(display, False);
  NSCAssert(!IconAboveDock(display, first, dock), @"Reproduce covered icons during alert");
  NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:1.5];
  while ([deadline timeIntervalSinceNow] > 0)
    {
      [NSApp runModalSession:session];
      [[NSRunLoop currentRunLoop] runMode:NSModalPanelRunLoopMode
                              beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.02]];
      [NSApp updateWindows];
    }
  AssertIconAboveDock(display, first, dock);
  AssertIconAboveDock(display, second, dock);
  [NSApp endModalSession:session];
  [[alert window] orderOut:nil];
  RELEASE(alert);
  [controller stopTimers];
  RELEASE(controller);
  [NSObject cancelPreviousPerformRequestsWithTarget:manager];
  RELEASE(manager);

  NSRect rest = [first frame];
  NSRect other = [second frame];
  for (NSWindow *child in [dock childWindows]) [child displayIfNeeded];
  NSUInteger rendersBeforeBounce = [view iconRenderCount];
  [view startWiggleForItem:a];
  for (NSUInteger tick = 1; tick <= 8; tick++)
    {
      [view advanceBounce:0.02 * tick];
      for (NSWindow *child in [dock childWindows]) [child displayIfNeeded];
    }
  NSCAssert([view iconRenderCount] == rendersBeforeBounce,
            @"Animation moves buffered windows without repainting icons");
  [view advanceBounce:0.275];
  NSCAssert(NSMinY([first frame]) > NSMinY(rest) + 30, @"Icon physically rises");
  NSCAssert(NSEqualRects(indicatorRest, [indicator frame]),
            @"Running indicator stays stationary during bounce");
  NSCAssert(NSMinX([first frame]) == NSMinX(rest), @"No horizontal wiggle");
  NSCAssert(NSEqualRects(other, [second frame]), @"Other app stays still");
  [view stopWiggle];
  NSCAssert(NSEqualRects(rest, [first frame]), @"Icon lands exactly at rest");
  for (NSUInteger refresh = 0; refresh < 10; refresh++)
    {
      [view setNeedsDisplay:YES];
      for (NSWindow *child in [dock childWindows]) [child displayIfNeeded];
    }
  [first display];
  NSCAssert([view iconRenderCount] == rendersBeforeBounce,
            @"Unchanged refreshes and exposures reuse rendered icons");
  [a setBadgeLabel:@"2"];
  [view setNeedsDisplay:YES];
  for (NSWindow *child in [dock childWindows]) [child displayIfNeeded];
  NSCAssert([view iconRenderCount] == rendersBeforeBounce + 1,
            @"Badge changes repaint only the affected icon");
  [a setBadgeLabel:nil];
  [view setItems:[NSArray arrayWithObjects:b, a, nil]];
  NSCAssert([view iconWindowForItem:a] == first, @"Reorder preserves window identity");
  NSCAssert(NSMinX([first frame]) > NSMinX(rest), @"Reorder moves window");
  [view startAttentionWiggleForItem:a];
  [view acknowledgeWiggleForItem:a];
  NSRect landed = [first frame];
  [view syncIconWindows];
  NSCAssert(NSEqualRects(landed, [first frame]), @"Acknowledgement stops attention bounce");
  [a setState:DockItemNotRunning];
  [view setNeedsDisplay:YES];
  NSCAssert(![view indicatorWindowForItem:a], @"Exit removes running indicator window");
  [a setState:DockItemRunning];
  [view setNeedsDisplay:YES];
  NSCAssert([view indicatorWindowForItem:a], @"Restart restores running indicator window");
  [view setItems:[NSArray arrayWithObject:b]];
  NSCAssert(![view indicatorWindowForItem:a], @"Removal closes running indicator window");
  NSCAssert(![view iconWindowForItem:a], @"Removed app releases window");
  NSWindow *nameWindow = [view showNameForIndex:0];
  NSCAssert(nameWindow && nameWindow != second && [nameWindow isVisible],
            @"App name has a separate visible window");
  NSCAssert(NSWidth([nameWindow frame]) < NSWidth([dock frame]) &&
            NSHeight([nameWindow frame]) < NSHeight([second frame]),
            @"Name window fits the label rather than the whole dock");
  NSCAssert(!NSIntersectsRect([nameWindow frame], [second frame]),
            @"Name appears beside the icon rather than over it");
  [nameWindow display];
  XSync((Display *)[GSCurrentServer() serverDevice], False);
  NSCAssert(!ShapeContains(display, (Window)[nameWindow windowRef], ShapeInput, 8, 8),
            @"Name window does not intercept pointer input");
  NSPoint tip = [view tooltipArrowTip];
  int arrowY = (int)NSHeight([nameWindow frame]) - 3;
  NSCAssert(ShapeContains(display, (Window)[nameWindow windowRef], ShapeBounding,
                          (int)tip.x, arrowY), @"Tooltip has a downward pointer");
  NSCAssert(!ShapeContains(display, (Window)[nameWindow windowRef], ShapeBounding,
                           2, arrowY), @"Space beside the pointer is transparent");
  [view hideTooltip];
  NSCAssert(![nameWindow isVisible], @"Name window hides when hover ends");
  /* Section dividers follow pinning and orientation, with no backing panel. */
  [view setItems:[NSArray arrayWithObjects:a, b, nil]];
  [view setPinnedItemCount:1];
  NSWindow *startSeparator = [view separatorWindowAtEnd:NO];
  NSWindow *endSeparator = [view separatorWindowAtEnd:YES];
  NSCAssert(startSeparator && endSeparator && startSeparator != endSeparator,
            @"Unpinned section has two separate divider windows");
  NSCAssert([startSeparator isVisible] && [endSeparator isVisible],
            @"Both section dividers are visible");
  NSCAssert(NSWidth([startSeparator frame]) == 1.0 &&
            NSHeight([startSeparator frame]) > 1.0,
            @"Horizontal dock uses a thin vertical divider");
  NSCAssert(NSMinX([startSeparator frame]) > NSMaxX([[view iconWindowForItem:a] frame]) &&
            NSMaxX([startSeparator frame]) <= NSMinX([second frame]) &&
            NSMinX([endSeparator frame]) >= NSMaxX([second frame]),
            @"Dividers bracket only the unpinned section");
  [startSeparator display];
  XSync((Display *)[GSCurrentServer() serverDevice], False);
  NSCAssert(ShapeContains(display, (Window)[startSeparator windowRef], ShapeBounding, 0, 1) &&
            !ShapeContains(display, (Window)[startSeparator windowRef], ShapeInput, 0, 1),
            @"Divider is visible and passes pointer input through");
  /* Tile toggles must invalidate cached pixels and native shapes. */
  first = [view iconWindowForItem:a];
  [view setTileFixture:fixture];
  [view setUsesCellBackgroundTile:YES];
  for (NSWindow *child in [dock childWindows]) [child displayIfNeeded];
  XSync((Display *)[GSCurrentServer() serverDevice], False);
  NSCAssert(ShapeContains(display, (Window)[first windowRef], ShapeBounding, 1, 1),
            @"Enabled tile fills the icon cell");
  NSCAssert(!ShapeContains(display, (Window)[dock windowRef], ShapeBounding, 10, 10),
            @"Tiles leave the dock backing transparent");
  [view setUsesCellBackgroundTile:NO];
  for (NSWindow *child in [dock childWindows]) [child displayIfNeeded];
  XSync((Display *)[GSCurrentServer() serverDevice], False);
  NSCAssert(!ShapeContains(display, (Window)[first windowRef], ShapeBounding, 1, 1),
            @"Disabling tiles restores the icon-only shape");
  [view setHorizontal:NO];
  NSCAssert([view separatorWindowAtEnd:NO] == startSeparator &&
            NSHeight([startSeparator frame]) == 1.0 && NSWidth([startSeparator frame]) > 1.0,
            @"Vertical dock reuses the divider as a thin horizontal window");
  [view setPinnedItemCount:2];
  NSCAssert(![view separatorWindowAtEnd:NO] && ![view separatorWindowAtEnd:YES],
            @"No divider windows remain when every application is pinned");
  [view setPinnedItemCount:0];
  NSCAssert([view separatorWindowAtEnd:NO] && [view separatorWindowAtEnd:YES],
            @"Entirely unpinned section has both dividers");
  /* Empty slots change geometry, but never become clickable dock items. */
  [view setFrame:NSMakeRect(0, 0, 420, 420)];
  [a setPinned:YES];
  [a setGapBefore:YES];
  [view setHorizontal:YES];
  NSPoint compact = [view cellOriginAtIndex:0];
  [view setAllowsGaps:YES];
  NSPoint spaced = [view cellOriginAtIndex:0];
  NSCAssert(spaced.x - compact.x == [view cellSize].width + 2,
            @"Horizontal gap occupies one full slot");
  NSPoint emptyCenter = NSMakePoint(compact.x + 32, compact.y + 32);
  NSCAssert([view indexAtPoint:emptyCenter] == NSNotFound &&
            [view insertionIndexAtPoint:emptyCenter] == 0,
            @"Gap has no item and preserves insertion order");
  [view setHorizontal:NO];
  spaced = [view cellOriginAtIndex:0];
  [view setAllowsGaps:NO];
  compact = [view cellOriginAtIndex:0];
  NSCAssert(compact.y - spaced.y == [view cellSize].height + 2 && [a gapBefore],
            @"Disabling gaps compacts vertical layout without losing saved gaps");
  [dock orderOut:nil];
  NSCAssert(![second isVisible], @"Hiding dock hides icons");
  [dock setContentView:nil];
  NSCAssert([[dock childWindows] count] == 0, @"Detaching view removes icon windows");
  [view release];
  [dock close];
  [dock release];
  XCloseDisplay(display);
  NSLog(@"Icon window tests passed");
  [pool drain];
  return 0;
}
