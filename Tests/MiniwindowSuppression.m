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

  /* Every miniwindow size, including mixed styles, honors the preference. */
  Window large = makeWindow(d, root, DockNSMiniWindowMask, 96);
  Window mixed = makeWindow(d, root, DockNSMiniWindowMask | DockNSIconWindowMask, 64);
  [manager handlePossiblyNewWindow:large];
  [manager handlePossiblyNewWindow:mixed];
  assert(![manager windowLooksManageable:large]);
  assert(![manager windowLooksManageable:mixed]);
  assert(mapped(d, large) && mapped(d, mixed));

  /* Style attributes, never dimensions, determine suppression on every path. */
  [manager setHidesMiniwindows:YES];
  assert(!mapped(d, large));
  unsigned long styles[] = {0, DockNSIconWindowMask, DockNSMiniWindowMask};
  int sizes[][2] = {{5, 5}, {47, 47}, {48, 48}, {49, 49}, {63, 63},
                    {64, 64}, {65, 65}, {96, 96}, {48, 64}, {64, 48},
                    {256, 256}, {400, 5}, {5, 400}};
  unsigned int i, j;
  for (i = 0; i < sizeof(styles) / sizeof(styles[0]); i++)
    for (j = 0; j < sizeof(sizes) / sizeof(sizes[0]); j++)
      {
        Window w = makeWindow(d, root, styles[i], sizes[j][0]);
        XResizeWindow(d, w, sizes[j][0], sizes[j][1]);
        BOOL shouldHide = styles[i] != 0;
        [manager handlePossiblyNewWindow:w];
        assert(mapped(d, w) == !shouldHide);
        XMapWindow(d, w);
        [manager windowLooksManageable:w];
        assert(mapped(d, w) == !shouldHide);
        XMapWindow(d, w);
        [manager unmapIconWindow:w];
        assert(mapped(d, w) == !shouldHide);
        XDestroyWindow(d, w);
      }

  /* Registered application icons are unmapped without changing their size. */
  [manager setHidesMiniwindows:NO];
  Window appIcon = makeWindow(d, root, DockNSIconWindowMask, 48);
  assert([manager rememberApplicationIconWindow:appIcon
                             processIdentifier:12345 title:nil]);
  assert(!mapped(d, appIcon));
  XWindowAttributes appAttr;
  assert(XGetWindowAttributes(d, appIcon, &appAttr));
  assert(appAttr.width == 48 && appAttr.height == 48);
  XMapWindow(d, appIcon);
  assert(![manager windowLooksManageable:appIcon]);
  assert(!mapped(d, appIcon));
  Window largeIcon = makeWindow(d, root, DockNSIconWindowMask, 256);
  assert([manager rememberApplicationIconWindow:largeIcon
                              processIdentifier:12346 title:nil]);
  assert(![manager windowLooksManageable:largeIcon]);
  assert(!mapped(d, largeIcon));

  /* Creation events, discovery, and icon-manager registration also ignore size. */
  XSelectInput(d, root, SubstructureNotifyMask);
  Window eventIcon = makeWindow(d, root, DockNSIconWindowMask, 256);
  [manager processPendingEvents];
  assert(!mapped(d, eventIcon));
  Window discoveredIcon = makeWindow(d, root, DockNSIconWindowMask, 256);
  XClassHint classHint = {"LargeIcon", "LargeIcon"};
  XSetClassHint(d, discoveredIcon, &classHint);
  [manager discoverApplicationIconWindows:&discoveredIcon count:1];
  assert(!mapped(d, discoveredIcon));
  Window registeredIcon = makeWindow(d, root, DockNSIconWindowMask, 256);
  [manager setWindow:(unsigned int)registeredIcon appProcessId:12347];
  assert(!mapped(d, registeredIcon));

  /* Re-enabling suppression still works, including reparented miniwindows. */
  [manager setHidesMiniwindows:YES];
  [manager handlePossiblyNewWindow:mini];
  assert(!mapped(d, mini));
  Window frame = makeWindow(d, root, 0, 100);
  Window child = makeWindow(d, frame, DockNSMiniWindowMask, 64);
  owner(d, child);
  Window sibling = makeWindow(d, frame, 0, 64);
  [manager handlePossiblyNewWindow:child];
  assert(mapped(d, frame) && !mapped(d, child));
  XWindowAttributes siblingAttr;
  assert(XGetWindowAttributes(d, sibling, &siblingAttr));
  assert(siblingAttr.map_state == IsViewable);
  [manager setHidesMiniwindows:NO];
  assert(mapped(d, mini) && mapped(d, frame) && mapped(d, child));

  /* The preference itself must find existing icons inside WM frames. */
  [manager setHidesMiniwindows:YES];
  assert(!mapped(d, mini) && mapped(d, frame) && !mapped(d, child));
  [manager setHidesMiniwindows:NO];
  assert(mapped(d, mini) && mapped(d, frame) && mapped(d, child));

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
