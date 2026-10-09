#import "../X11DockManagerPrivate.h"
#include <assert.h>

/* A geometry-only view keeps these tests independent of the GUI backend. */
@interface GeometryView : NSObject
@end
@implementation GeometryView
- (NSRect)bounds { return NSMakeRect(0, 0, 64, 512); }
- (NSPoint)cellOriginAtIndex:(NSUInteger)i { return NSMakePoint(0, i * 64); }
- (NSSize)cellSize { return NSMakeSize(64, 64); }
@end

@interface EfficiencyManager : X11DockManager
{
@public
  NSUInteger scans;
}
- (Display *)display;
- (Window)host;
- (void)allowDockApp:(Window)window;
- (BOOL)hasFrame:(Window)window;
@end
@implementation EfficiencyManager
- (void)registerIconManager {}
- (Display *)display { return _display; }
- (Window)host { return _hostWindow; }
- (void)allowDockApp:(Window)w
{ [_dockAppWindows addObject:[NSNumber numberWithUnsignedLong:w]]; }
- (BOOL)hasFrame:(Window)w
{ return [_dockedWindowFrames objectForKey:[NSNumber numberWithUnsignedLong:w]] != nil; }
- (void)scanForDockApps { scans++; _scanPending = NO; }
@end

static void checkGeometry(Display *d, Window w, Window parent, int y)
{
  Window root, actualParent, *children = NULL;
  unsigned int count;
  XWindowAttributes attr;
  assert(XQueryTree(d, w, &root, &actualParent, &children, &count));
  if (children) XFree(children);
  assert(actualParent == parent);
  assert(XGetWindowAttributes(d, w, &attr));
  assert(attr.x == 0 && attr.y == y && attr.width == 64 && attr.height == 64);
  assert(attr.map_state == IsViewable);
}

int main(void)
{
  NSAutoreleasePool *pool = [NSAutoreleasePool new];
  GeometryView *view = [GeometryView new];
  EfficiencyManager *manager = [[EfficiencyManager alloc] initWithDockView:(id)view];
  assert([manager start]);
  Display *d = [manager display];
  Window root = DefaultRootWindow(d);
  Window w = XCreateSimpleWindow(d, root, 0, 0, 32, 32, 0, 0, 0);
  [manager allowDockApp:w];
  [manager dockWindow:w atIndex:1];
  checkGeometry(d, w, [manager host], 384);

  /* Unchanged refreshes issue no requests, including host placement. */
  [manager setDockPlacement:DockPlacementLeftTop];
  unsigned long serial = NextRequest(d);
  for (int i = 0; i < 100; i++)
    {
      [manager dockWindow:w atIndex:1];
      [manager setDockPlacement:DockPlacementLeftTop];
    }
  assert(NextRequest(d) == serial);
  [manager dockWindow:w atIndex:2];
  checkGeometry(d, w, [manager host], 320);
  XSync(d, False);
  [manager processPendingEvents];
  serial = NextRequest(d);
  [manager dockWindow:w atIndex:2];
  assert(NextRequest(d) == serial);

  /* External geometry/parent changes invalidate the cache and can be repaired. */
  XResizeWindow(d, w, 40, 40);
  XSync(d, False);
  [manager processPendingEvents];
  assert(![manager hasFrame:w]);
  [manager dockWindow:w atIndex:2];
  checkGeometry(d, w, [manager host], 320);
  XReparentWindow(d, w, root, 0, 0);
  XSync(d, False);
  [manager processPendingEvents];
  assert(![manager hasFrame:w]);
  [manager dockWindow:w atIndex:2];
  checkGeometry(d, w, [manager host], 320);

  XUnmapWindow(d, w);
  XSync(d, False);
  [manager processPendingEvents];
  assert(![manager hasFrame:w]);
  [manager dockWindow:w atIndex:2];
  checkGeometry(d, w, [manager host], 320);

  /* Query error checks must not issue another server round trip. Errors from
   * older asynchronous writes must not poison the next successful query. */
  Window dead = XCreateSimpleWindow(d, root, 0, 0, 1, 1, 0, 0, 0);
  XDestroyWindow(d, dead);
  XDestroyWindow(d, dead);
  [manager clearX11Error];
  Window geometryRoot;
  int x, y;
  unsigned int width, height, border, depth;
  serial = NextRequest(d);
  assert(XGetGeometry(d, w, &geometryRoot, &x, &y, &width, &height, &border, &depth));
  assert(![manager x11ErrorOccurred]);
  assert(NextRequest(d) == serial + 1);
  [manager clearX11Error];
  assert(!XGetGeometry(d, dead, &geometryRoot, &x, &y, &width, &height, &border, &depth));
  assert([manager x11ErrorOccurred]);

  XDestroyWindow(d, w);
  XSync(d, False);
  [manager processPendingEvents];
  assert(![manager hasFrame:w]);
  /* Clear any state-change scan before testing unrelated event pressure. */
  [manager scanForDockApps];
  NSUInteger scans = manager->scans;
  XEvent event = {0};
  event.type = Expose;
  for (int i = 0; i < 2048; i++) XPutBackEvent(d, &event);
  [manager processPendingEvents];
  assert(XQLength(d) > 0); /* One callback stays bounded. */
  NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:0.25];
  while (XQLength(d) > 0 && [deadline timeIntervalSinceNow] > 0)
    [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:deadline];
  assert(XQLength(d) == 0); /* Continuations beat the half-second timer. */
  assert(manager->scans == scans); /* Queue pressure did not trigger scans. */

  [NSObject cancelPreviousPerformRequestsWithTarget:manager];
  [manager release];
  [view release];
  [pool drain];
  puts("X11 efficiency tests passed");
  return 0;
}
