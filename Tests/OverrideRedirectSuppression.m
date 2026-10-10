#import "../X11DockManagerPrivate.h"
#include <assert.h>

@interface OverlayTestManager : X11DockManager
- (id)initWithDisplay:(Display *)display;
@end
@implementation OverlayTestManager
- (id)initWithDisplay:(Display *)display
{
  self = [super initWithDockView:nil];
  _display = display;
  return self;
}
@end

static BOOL viewable(Display *display, Window window)
{
  XWindowAttributes attributes;
  XSync(display, False);
  assert(XGetWindowAttributes(display, window, &attributes));
  return attributes.map_state == IsViewable;
}

int main(void)
{
  NSAutoreleasePool *pool = [NSAutoreleasePool new];
  Display *display = XOpenDisplay(NULL);
  assert(display);
  OverlayTestManager *manager = [[OverlayTestManager alloc] initWithDisplay:display];
  Window root = DefaultRootWindow(display);
  XSelectInput(display, root, SubstructureNotifyMask);
  XSetWindowAttributes attributes;
  attributes.override_redirect = True;
  Window frame = XCreateWindow(display, root, 10, 10, 5, 5, 0,
    CopyFromParent, InputOutput, CopyFromParent, CWOverrideRedirect, &attributes);
  XMapWindow(display, frame);
  XSync(display, False);

  /* A newly created WM frame may not have a client or metadata yet. */
  [manager handlePossiblyNewWindow:frame];
  assert(viewable(display, frame));
  assert(![manager windowLooksManageable:frame]);
  assert(viewable(display, frame));

  Window client = XCreateSimpleWindow(display, frame, 0, 0, 5, 5, 0, 0, 0);
  XMapWindow(display, client);
  XSync(display, False);
  [manager handlePossiblyNewWindow:frame];
  assert(![manager windowLooksManageable:frame]);
  assert(viewable(display, client));

  /* Both connection orientations grow from the same initially tiny frame. */
  XResizeWindow(display, frame, 400, 5);
  XResizeWindow(display, client, 400, 5);
  [manager handlePossiblyNewWindow:frame];
  assert(viewable(display, client));
  XResizeWindow(display, frame, 5, 400);
  XResizeWindow(display, client, 5, 400);
  [manager handlePossiblyNewWindow:frame];
  assert(viewable(display, client));

  /* Window Maker paints its own application tile when the application has
   * suppressed its GNUstep icon. XDND and event flags alone are not proof
   * that a window is an icon, so this unmarked window must remain mapped. */
  Window tile = XCreateWindow(display, root, 100, 100, 96, 96, 0,
    CopyFromParent, InputOutput, CopyFromParent, CWOverrideRedirect, &attributes);
  XSelectInput(display, tile, SubstructureRedirectMask | ButtonPressMask |
    ButtonReleaseMask | ButtonMotionMask | ExposureMask |
    EnterWindowMask | LeaveWindowMask);
  XMapWindow(display, tile);
  [manager handlePossiblyNewWindow:tile];
  assert(viewable(display, tile));
  Atom xdnd = XInternAtom(display, "XdndAware", False);
  unsigned long version = 3;
  XChangeProperty(display, tile, xdnd, XA_ATOM, 32, PropModeReplace,
    (unsigned char *)&version, 1);
  [manager handlePossiblyNewWindow:tile];
  assert(viewable(display, tile));
  XMapWindow(display, tile);
  [manager processPendingEvents];
  assert(viewable(display, tile));
  XMapWindow(display, tile);
  assert(![manager windowLooksManageable:tile]);
  assert(viewable(display, tile));

  /* The producer's explicit application-icon property is sufficient at any
   * dimensions. Malformed properties and XDND alone must not hide windows. */
  Atom marker = XInternAtom(display, "_WINDOWMAKER_APP_ICON", False);
  unsigned long owner = client;
  XChangeProperty(display, tile, marker, XA_CARDINAL, 32, PropModeReplace,
    (unsigned char *)&owner, 1);
  [manager handlePossiblyNewWindow:tile];
  assert(viewable(display, tile));
  XChangeProperty(display, tile, marker, XA_WINDOW, 32, PropModeReplace,
    (unsigned char *)&owner, 1);
  int sizes[][2] = {{5, 5}, {48, 48}, {64, 64}, {256, 256}, {400, 5}};
  for (unsigned int i = 0; i < sizeof(sizes) / sizeof(sizes[0]); i++)
    {
      XResizeWindow(display, tile, sizes[i][0], sizes[i][1]);
      XMapWindow(display, tile);
      [manager handlePossiblyNewWindow:tile];
      assert(!viewable(display, tile));
      XMapWindow(display, tile);
      XSync(display, False);
      [manager processPendingEvents];
      assert(!viewable(display, tile));
      XMapWindow(display, tile);
      assert(![manager windowLooksManageable:tile]);
      assert(!viewable(display, tile));
    }
  XDeleteProperty(display, tile, marker);
  XMapWindow(display, tile);
  [manager handlePossiblyNewWindow:tile];
  assert(viewable(display, tile));
  /* Simulate legacy Window Maker's self-referencing noticeboard. */
  Atom boardAtom = XInternAtom(display, "_WINDOWMAKER_NOTICEBOARD", False);
  Window board = XCreateSimpleWindow(display, root, 0, 0, 1, 1, 0, 0, 0);
  XChangeProperty(display, root, boardAtom, XA_WINDOW, 32, PropModeReplace,
    (unsigned char *)&board, 1);
  [manager handlePossiblyNewWindow:tile];
  assert(viewable(display, tile));
  XChangeProperty(display, board, boardAtom, XA_WINDOW, 32, PropModeReplace,
    (unsigned char *)&board, 1);
  for (unsigned int i = 0; i < sizeof(sizes) / sizeof(sizes[0]); i++)
    {
      XResizeWindow(display, tile, sizes[i][0], sizes[i][1]);
      XMapWindow(display, tile);
      [manager handlePossiblyNewWindow:tile];
      assert(!viewable(display, tile));
      XMapWindow(display, tile);
      XSync(display, False);
      [manager processPendingEvents];
      assert(!viewable(display, tile));
    }
  /* Shared exclusions protect clients even at the last-resort icon size. */
  XResizeWindow(display, tile, 64, 64);
  XClassHint hint = {"Gorm", "Gorm"};
  XSetClassHint(display, tile, &hint);
  XMapWindow(display, tile);
  [manager handlePossiblyNewWindow:tile];
  assert(viewable(display, tile));
  XDeleteProperty(display, tile, XA_WM_CLASS);
  Window overlay = XCreateSimpleWindow(display, tile, 0, 0, 5, 5, 0, 0, 0);
  [manager handlePossiblyNewWindow:tile];
  assert(viewable(display, tile));
  XDestroyWindow(display, overlay);
  /* Without the attribute signature, non-icon dimensions remain mapped. */
  XResizeWindow(display, tile, 96, 96);
  XDeleteProperty(display, tile, xdnd);
  [manager handlePossiblyNewWindow:tile];
  assert(viewable(display, tile));
  XChangeProperty(display, tile, xdnd, XA_ATOM, 32, PropModeReplace,
    (unsigned char *)&version, 1);
  XSelectInput(display, tile, ExposureMask);
  [manager handlePossiblyNewWindow:tile];
  assert(viewable(display, tile));
  XDeleteProperty(display, root, boardAtom);
  XDestroyWindow(display, board);
  XDeleteProperty(display, tile, xdnd);
  /* Third and last: exact 48x48 or 64x64, with no marker or signature. */
  int fallbackSizes[][2] = {{47, 47}, {48, 48}, {49, 49}, {63, 63},
    {64, 64}, {65, 65}, {48, 64}, {64, 48}, {400, 5}};
  for (unsigned int i = 0; i < sizeof(fallbackSizes) / sizeof(fallbackSizes[0]); i++)
    {
      int width = fallbackSizes[i][0], height = fallbackSizes[i][1];
      BOOL shouldHide = (width == 48 && height == 48) ||
        (width == 64 && height == 64);
      XResizeWindow(display, tile, width, height);
      XMapWindow(display, tile);
      [manager handlePossiblyNewWindow:tile];
      assert(viewable(display, tile) == !shouldHide);
      XMapWindow(display, tile);
      XSync(display, False);
      [manager processPendingEvents];
      assert(viewable(display, tile) == !shouldHide);
      XMapWindow(display, tile);
      [manager windowLooksManageable:tile];
      assert(viewable(display, tile) == !shouldHide);
    }
  XDestroyWindow(display, tile);

  XDestroyWindow(display, frame);
  [manager release];
  [pool drain];
  puts("PASS: unclassified override-redirect windows and their clients remain viewable");
  return 0;
}
