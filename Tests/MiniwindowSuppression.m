#import "../X11DockManagerPrivate.h"
#include <assert.h>

@interface TestManager : X11DockManager
- (id)initWithDisplay:(Display *)display;
@end
@implementation TestManager
- (id)initWithDisplay:(Display *)display
{
  self = [super initWithDockView:nil];
  _display = display;
  return self;
}
@end

static int ignoreError(Display *display, XErrorEvent *event) { return 0; }
static Window makeWindow(Display *d, Window parent, unsigned long style, int size)
{
  Window w = XCreateSimpleWindow(d, parent, 0, 0, size, size, 0, 0, 0);
  Atom atom = XInternAtom(d, "_GNUSTEP_WM_ATTR", False);
  unsigned long attrs[] = {1, style};
  XChangeProperty(d, w, atom, atom, 32, PropModeReplace, (unsigned char *)attrs, 2);
  XMapWindow(d, w);
  XSync(d, False);
  return w;
}
static BOOL mapped(Display *d, Window w)
{
  XWindowAttributes attr;
  XSync(d, False);
  assert(XGetWindowAttributes(d, w, &attr));
  return attr.map_state != IsUnmapped;
}
static Window owner(Display *d, Window mini)
{
  Window w = XCreateSimpleWindow(d, DefaultRootWindow(d), 0, 0, 400, 300, 0, 0, 0);
  XWMHints hints = {0};
  hints.flags = IconWindowHint;
  hints.icon_window = mini;
  XSetWMHints(d, w, &hints);
  Atom atom = XInternAtom(d, "WM_STATE", False);
  unsigned long state[] = {IconicState, mini};
  XChangeProperty(d, w, atom, atom, 32, PropModeReplace, (unsigned char *)state, 2);
  return w;
}
int main(void)
{
  NSAutoreleasePool *pool = [NSAutoreleasePool new];
  Display *d = XOpenDisplay(NULL);
  assert(d);
  XSetErrorHandler(ignoreError);
  TestManager *manager = [[TestManager alloc] initWithDisplay:d];
  Window root = DefaultRootWindow(d);
  Window mini = makeWindow(d, root, DockNSMiniWindowMask, 64);
  Window document = owner(d, mini);
  [manager handlePossiblyNewWindow:mini];
  assert(!mapped(d, mini));
  [manager setHidesMiniwindows:NO];
  assert(mapped(d, mini));
  [manager handlePossiblyNewWindow:mini];
  assert(![manager windowLooksManageable:mini]);
  [manager unmapIconWindow:mini];
  assert(mapped(d, mini));

  /* Oversized and mixed-style miniwindows must bypass all icon hiding paths. */
  Window large = makeWindow(d, root, DockNSMiniWindowMask, 96);
  Window mixed = makeWindow(d, root, DockNSMiniWindowMask | DockNSIconWindowMask, 64);
  [manager handlePossiblyNewWindow:large];
  [manager handlePossiblyNewWindow:mixed];
  assert(![manager windowLooksManageable:large]);
  assert(![manager windowLooksManageable:mixed]);
  assert(mapped(d, large) && mapped(d, mixed));

  /* Re-enabling suppression still works, including reparented miniwindows. */
  [manager setHidesMiniwindows:YES];
  [manager handlePossiblyNewWindow:mini];
  assert(!mapped(d, mini));
  Window frame = makeWindow(d, root, 0, 100);
  Window child = makeWindow(d, frame, DockNSMiniWindowMask, 64);
  owner(d, child);
  [manager handlePossiblyNewWindow:child];
  assert(!mapped(d, frame));
  [manager setHidesMiniwindows:NO];
  assert(mapped(d, mini) && mapped(d, frame));

  /* The preference itself must find existing icons inside WM frames. */
  [manager setHidesMiniwindows:YES];
  assert(!mapped(d, mini) && !mapped(d, frame));
  [manager setHidesMiniwindows:NO];
  assert(mapped(d, mini) && mapped(d, frame));

  /* Some WMs minimize by unmapping the frame, leaving its client mapped. */
  Window ownerFrame = makeWindow(d, root, 0, 400);
  Window framedMini = makeWindow(d, root, DockNSMiniWindowMask, 64);
  Window framedOwner = owner(d, framedMini);
  XReparentWindow(d, framedOwner, ownerFrame, 0, 0);
  XMapWindow(d, framedOwner);
  XUnmapWindow(d, ownerFrame);
  [manager setHidesMiniwindows:YES];
  assert(!mapped(d, framedMini));
  [manager setHidesMiniwindows:NO];
  assert(mapped(d, framedMini));

  /* Recover icons hidden before this manager started tracking suppression. */
  [manager setHidesMiniwindows:YES];
  Window oldFrame = makeWindow(d, root, 0, 100);
  Window oldMini = makeWindow(d, oldFrame, DockNSMiniWindowMask, 64);
  owner(d, oldMini);
  XUnmapWindow(d, oldMini);
  XUnmapWindow(d, oldFrame);
  [manager setHidesMiniwindows:NO];
  assert(mapped(d, oldMini) && mapped(d, oldFrame));

  /* Reparenting while hidden must not leave restoration using a stale frame. */
  [manager setHidesMiniwindows:YES];
  Window newFrame = makeWindow(d, root, 0, 100);
  XReparentWindow(d, oldMini, newFrame, 0, 0);
  XUnmapWindow(d, oldMini);
  XUnmapWindow(d, newFrame);
  [manager setHidesMiniwindows:NO];
  assert(mapped(d, oldMini) && mapped(d, newFrame));

  /* Do not resurrect a miniwindow after its document was restored or closed. */
  [manager setHidesMiniwindows:YES];
  [manager handlePossiblyNewWindow:mini];
  XMapWindow(d, document);
  [manager setHidesMiniwindows:NO];
  assert(!mapped(d, mini));
  XUnmapWindow(d, document);
  XMapWindow(d, mini);
  [manager setHidesMiniwindows:YES];
  [manager handlePossiblyNewWindow:mini];
  XDestroyWindow(d, document);
  [manager setHidesMiniwindows:NO];
  assert(!mapped(d, mini));

  /* A destroyed suppressed icon must be harmless when the preference changes. */
  [manager setHidesMiniwindows:YES];
  [manager handlePossiblyNewWindow:child];
  XDestroyWindow(d, frame);
  [manager setHidesMiniwindows:NO];
  [manager release];
  [pool drain];
  puts("Miniwindow suppression tests passed");
  return 0;
}
