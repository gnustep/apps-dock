#import "../X11DockManagerPrivate.h"
#include <assert.h>

@interface ScanManager : X11DockManager
{
@public
  NSUInteger discoveries;
  NSUInteger classifications;
  NSUInteger updates;
  BOOL yielded;
  NSMutableSet *classified;
}
- (BOOL)scanning;
- (void)heartbeat;
- (Display *)display;
@end
@implementation ScanManager
- (void)registerIconManager {}
- (Display *)display { return _display; }
- (BOOL)scanning { return _scanWindows != nil; }
- (void)heartbeat { yielded = [self scanning]; }
- (void)discoverApplicationIconWindows:(Window *)windows count:(unsigned int)count
{
  discoveries += count;
  [super discoverApplicationIconWindows:windows count:count];
}
- (void)scanClientWindow:(Window)window
{
  classifications++;
  if (!classified) classified = [NSMutableSet new];
  [classified addObject:[NSNumber numberWithUnsignedLong:window]];
  [super scanClientWindow:window];
}
- (void)scanKnownWindow:(Window)window
{
  updates++;
  [super scanKnownWindow:window];
}
- (void)dealloc { [classified release]; [super dealloc]; }
@end

static void finishScan(ScanManager *manager)
{
  NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:10];
  while ([manager scanning] && [deadline timeIntervalSinceNow] > 0)
    [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode
      beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
  assert(![manager scanning]);
}

int main(void)
{
  NSAutoreleasePool *pool = [NSAutoreleasePool new];
  /* start needs nonzero host geometry. Use a plain NSView, with no NSApp. */
  NSView *view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 64, 512)];
  ScanManager *manager = [[ScanManager alloc] initWithDockView:(id)view];
  assert([manager start]);
  Display *d = [manager display];
  Window root = DefaultRootWindow(d), windows[128];
  for (unsigned int i = 0; i < 128; i++)
    {
      windows[i] = XCreateSimpleWindow(d, root, 0, 0, 300, 200, 0, 0, 0);
      XStoreName(d, windows[i], "Scan regression window");
      XMapWindow(d, windows[i]);
    }
  /* EWMH clients also appear among root children; classify each only once. */
  XChangeProperty(d, root, XInternAtom(d, "_NET_CLIENT_LIST", False),
    XA_WINDOW, 32, PropModeReplace, (unsigned char *)windows, 128);
  XSync(d, False);
  [manager performSelector:@selector(heartbeat) withObject:nil afterDelay:0];
  [manager scanForDockApps];
  assert(manager->discoveries <= 8);
  assert([manager scanning]);
  NSUInteger count = manager->discoveries;
  [manager scanForDockApps];
  assert(manager->discoveries == count); /* Refresh does not restart the scan. */

  /* A snapshotted window may disappear before its batch is reached. */
  XDestroyWindow(d, windows[127]);
  XSync(d, False);
  finishScan(manager);
  assert(manager->yielded); /* Main-loop work ran before the sweep finished. */
  assert(manager->discoveries == 129); /* Includes the host. */
  assert(manager->classifications == 129);
  assert([manager->classified count] == 129);

  /* Known windows continue to receive updates on subsequent sweeps. */
  [manager scanForDockApps];
  finishScan(manager);
  assert(manager->updates == 127);

  /* Event discovery remains immediate while a background sweep is active. */
  XSync(d, False);
  while (XPending(d)) { XEvent event; XNextEvent(d, &event); }
  [manager scanForDockApps];
  Window late = XCreateSimpleWindow(d, root, 0, 0, 300, 200, 0, 0, 0);
  XStoreName(d, late, "New client during scan");
  XMapWindow(d, late);
  XSync(d, False);
  [manager processPendingEvents];
  assert([manager->classified containsObject:[NSNumber numberWithUnsignedLong:late]]);
  assert([manager scanning]);
  finishScan(manager);
  [NSObject cancelPreviousPerformRequestsWithTarget:manager];
  [manager release];
  [view release];
  [pool drain];
  puts("Incremental window scan tests passed");
  return 0;
}
