#import "DockViewPrivate.h"
#import <X11/Xlib.h>
#import <X11/Xutil.h>
#import <X11/extensions/shape.h>
#import <X11/extensions/XTest.h>
#include <assert.h>
#import <GNUstepGUI/GSDisplayServer.h>

/* XQueryTree returns siblings in bottom-to-top stacking order. isVisible
 * cannot detect a mapped icon that is completely covered by the dock. */
static void AssertIconAboveDock(Display *display, NSWindow *icon, NSWindow *dock)
{
  Window root, parent, *children = NULL;
  unsigned int count = 0;
  NSInteger iconIndex = -1, dockIndex = -1;
  XSync((Display *)[GSCurrentServer() serverDevice], False);
  XSync(display, False);
  NSCAssert(XQueryTree(display, DefaultRootWindow(display), &root, &parent,
                      &children, &count), @"Read native window stacking");
  for (unsigned int i = 0; i < count; i++)
    {
      if (children[i] == (Window)[icon windowRef]) iconIndex = i;
      if (children[i] == (Window)[dock windowRef]) dockIndex = i;
    }
  if (children) XFree(children);
  NSCAssert(dockIndex >= 0 && iconIndex > dockIndex,
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
- (NSWindow *) iconWindowForItem: (DockItem *)item;
- (void) advanceBounce: (NSTimeInterval)elapsed;
@end
@implementation TestDockView
- (NSWindow *) iconWindowForItem: (DockItem *)item
{ return [_iconWindows objectForKey:[NSValue valueWithPointer:item]]; }
- (void) advanceBounce: (NSTimeInterval)elapsed
{ _wiggleStartTime = [NSDate timeIntervalSinceReferenceDate] - elapsed; [self syncIconWindows]; }
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
  [dock orderFront:nil];
  [dock display];
  NSWindow *first = [view iconWindowForItem:a];
  NSWindow *second = [view iconWindowForItem:b];
  NSCAssert(first && second && first != second, @"Each app has a distinct window");
  NSCAssert([first parentWindow] == dock, @"Icon belongs to the dock");
  NSCAssert([first isVisible], @"Icon window is visible");
  Display *display = XOpenDisplay(NULL);
  XWindowAttributes attributes;
  XSync(display, False);
  NSCAssert(XGetWindowAttributes(display, (Window)[first windowRef], &attributes), @"Native icon window exists");
  NSCAssert(attributes.map_state == IsViewable, @"Native icon window is mapped");
  /* Reproduce the actual startup sequence, which raises the dock twice. */
  [dock makeKeyAndOrderFront:nil];
  [dock orderFrontRegardless];
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
  int shapeCount, shapeOrdering;
  XRectangle *input = XShapeGetRectangles(display, (Window)[first windowRef],
                                        ShapeInput, &shapeCount, &shapeOrdering);
  NSCAssert(shapeCount == 0, @"Entire icon window passes through pointer input");
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
  NSRect rest = [first frame];
  NSRect other = [second frame];
  [view startWiggleForItem:a];
  [view advanceBounce:0.275];
  NSCAssert(NSMinY([first frame]) > NSMinY(rest) + 30, @"Icon physically rises");
  NSCAssert(NSMinX([first frame]) == NSMinX(rest), @"No horizontal wiggle");
  NSCAssert(NSEqualRects(other, [second frame]), @"Other app stays still");
  [view stopWiggle];
  NSCAssert(NSEqualRects(rest, [first frame]), @"Icon lands exactly at rest");
  [view setItems:[NSArray arrayWithObjects:b, a, nil]];
  NSCAssert([view iconWindowForItem:a] == first, @"Reorder preserves window identity");
  NSCAssert(NSMinX([first frame]) > NSMinX(rest), @"Reorder moves window");
  [view startAttentionWiggleForItem:a];
  [view acknowledgeWiggleForItem:a];
  NSRect landed = [first frame];
  [view syncIconWindows];
  NSCAssert(NSEqualRects(landed, [first frame]), @"Acknowledgement stops attention bounce");
  [view setItems:[NSArray arrayWithObject:b]];
  NSCAssert(![view iconWindowForItem:a], @"Removed app releases window");
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
