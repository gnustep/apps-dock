#import "AppControllerPrivate.h"
#import "DockViewPrivate.h"
#import "X11DockManagerPrivate.h"

@interface RestoreManager : X11DockManager

- (id) initWithDisplay: (Display *)display;

@end

@implementation RestoreManager

- (id) initWithDisplay: (Display *)display
{
  self = [super initWithDockView:nil];
  if (self) _display = display;
  return self;
}

@end

@interface RestoreController : AppController
{
  BOOL _forceApplicationRestore;
  BOOL _requestedWindow;
}

- (void) setForceApplicationRestore: (BOOL)force;
- (BOOL) requestedWindow;
- (NSArray *) minimizedItems;

- (id) initWithManager: (X11DockManager *)manager;

@end

@implementation RestoreController

- (id) initWithManager: (X11DockManager *)manager
{
  self = [super init];
  if (self)
    {
      ASSIGN(_x11, manager);
      _applicationScanner = [[RunningApplicationScanner alloc] init];
    }
  return self;
}

- (NSArray *) runningProcessIdentifiersForApplicationItem: (DockItem *)item
{
  if (![[item path] isEqualToString:@"/tmp/RestoreTest.app"])
    return [super runningProcessIdentifiersForApplicationItem:item];
  if ([item state] == DockItemNotRunning) return [NSArray array];
  return [NSArray arrayWithObject:[NSNumber numberWithInt:12345]];
}

- (void) setForceApplicationRestore: (BOOL)force
{
  _forceApplicationRestore = force;
}

- (NSArray *) dockView: (id)view minimizedWindowsForItem: (DockItem *)item
{
  if (_forceApplicationRestore) return [NSArray array];
  return [super dockView:view minimizedWindowsForItem:item];
}

- (BOOL) launchApplicationItem: (DockItem *)item useIconManager: (BOOL)useIconManager
{
  _requestedWindow = YES;
  return YES;
}

- (NSArray *) minimizedItems
{
  return _minimizedItems;
}

- (BOOL) requestedWindow
{
  return _requestedWindow;
}

- (void) refreshDock
{
}

@end

static Window makeWindow(Display *display, long state, unsigned long style)
{
  Window window = XCreateSimpleWindow(display, DefaultRootWindow(display),
                                       0, 0, 300, 200, 0, 0, 0);
  Atom atom = XInternAtom(display, "WM_STATE", False);
  unsigned long values[] = {state, None};
  unsigned long pid = 12345;
  unsigned long attrs[] = {1, style};
  XChangeProperty(display, window, atom, atom, 32, PropModeReplace,
                  (unsigned char *)values, 2);
  XChangeProperty(display, window, XInternAtom(display, "_NET_WM_PID", False),
                  XA_CARDINAL, 32, PropModeReplace, (unsigned char *)&pid, 1);
  atom = XInternAtom(display, "_GNUSTEP_WM_ATTR", False);
  XChangeProperty(display, window, atom, atom, 32, PropModeReplace,
                  (unsigned char *)attrs, 2);
  XStoreName(display, window, "Test Document");
  XSync(display, False);
  return window;
}

static void checkWindowPreviews(Display *display, RestoreManager *manager,
                                RestoreController *controller)
{
  Window window = makeWindow(display, NormalState, 0);
  Atom active = XInternAtom(display, "_NET_ACTIVE_WINDOW", False);
  Atom stateAtom = XInternAtom(display, "WM_STATE", False);
  unsigned long states[] = {IconicState, None};
  NSImage *preview;
  NSBitmapImageRep *rep;
  NSUInteger pixel[4];

  XSetWindowBackground(display, window, WhitePixel(display, DefaultScreen(display)));
  XMapRaised(display, window);
  XClearWindow(display, window);
  XChangeProperty(display, DefaultRootWindow(display), active, XA_WINDOW, 32,
                  PropModeReplace, (unsigned char *)&window, 1);
  XSync(display, False);
  [manager processPendingEvents];
  preview = [manager previewForWindow:window];
  NSCAssert(preview && NSEqualSizes([preview size], NSMakeSize(48, 48)),
            @"Active window is captured in a 48x48 image");
  rep = [[preview representations] objectAtIndex:0];
  [rep getPixel:pixel atX:24 y:0];
  NSCAssert(pixel[3] == 0, @"Landscape preview has transparent padding");
  [rep getPixel:pixel atX:24 y:8];
  NSCAssert(pixel[0] == 255 && pixel[3] == 255,
            @"Window content is fitted proportionally, not replaced by an app icon");

  XUnmapWindow(display, window);
  XChangeProperty(display, window, stateAtom, stateAtom, 32, PropModeReplace,
                  (unsigned char *)states, 2);
  XSync(display, False);
  NSCAssert(![manager capturePreviewForWindow:window],
            @"Unmapped windows cannot overwrite the cached preview");
  [controller updateMinimizedItems];
  NSCAssert([[[controller minimizedItems] objectAtIndex:0] icon] == preview,
            @"Minimized dock entry uses its captured window preview");

  states[0] = NormalState;
  XChangeProperty(display, window, stateAtom, stateAtom, 32, PropModeReplace,
                  (unsigned char *)states, 2);
  XResizeWindow(display, window, 200, 300);
  XSetWindowBackground(display, window, BlackPixel(display, DefaultScreen(display)));
  XMapRaised(display, window);
  XClearWindow(display, window);
  XSync(display, False);
  [controller updateMinimizedItems];
  [manager captureActiveWindowPreview];
  preview = [manager previewForWindow:window];
  rep = [[preview representations] objectAtIndex:0];
  [rep getPixel:pixel atX:0 y:24];
  NSCAssert(pixel[3] == 0, @"Portrait preview has transparent side padding");
  [rep getPixel:pixel atX:8 y:24];
  NSCAssert(pixel[0] == 0 && pixel[3] == 255,
            @"Restored windows refresh their preview, including black content");
  XDestroyWindow(display, window);
  XDeleteProperty(display, DefaultRootWindow(display), active);
  XSync(display, False);
  [manager processPendingEvents];
  NSCAssert(![manager previewForWindow:window], @"Destroyed window preview removed");
}

static BOOL mapped(Display *display, Window window)
{
  XWindowAttributes attr;
  XSync(display, False);
  NSCAssert(XGetWindowAttributes(display, window, &attr), @"Window exists");
  return attr.map_state == IsViewable;
}

static void invoke(DockView *view, id<NSMenuItem> entry)
{
  [view performSelector:[entry action] withObject:entry];
}

static void doubleClick(DockView *view, DockItem *item)
{
  NSPoint point;
  NSEvent *event;

  [view setFrame:NSMakeRect(0, 0, 280, 84)];
  [view setHorizontal:YES];
  [view setItems:[NSArray arrayWithObject:item]];
  point = [view cellOriginAtIndex:0];
  point.x += 20.0;
  point.y += 20.0;
  point = [view convertPoint:point toView:nil];
  event = [NSEvent mouseEventWithType:NSLeftMouseDown location:point
    modifierFlags:0 timestamp:[NSDate timeIntervalSinceReferenceDate]
    windowNumber:0 context:nil eventNumber:1 clickCount:2 pressure:1.0];
  [view mouseDown:event];
}

int main(int argc, char **argv)
{
  CREATE_AUTORELEASE_POOL(pool);
  Display *display = XOpenDisplay(NULL);
  RestoreManager *manager;
  RestoreController *controller;
  DockView *view;
  DockItem *app, *x11;
  NSMenu *menu;
  id<NSMenuItem> restore;
  Window first, second, normal, mini, frame;

  NSCAssert(display != NULL, @"Display available");
  [NSApplication sharedApplication];
  manager = [[RestoreManager alloc] initWithDisplay:display];
  controller = [[RestoreController alloc] initWithManager:manager];
  view = [[DockView alloc] initWithFrame:NSMakeRect(0, 0, 64, 64)];
  [view setDelegate:controller];
  app = [DockItem applicationItemWithPath:@"/tmp/RestoreTest.app"];
  if (argc >= 2)
    {
      unsigned long target = strtoul(argv[1], NULL, 0);
      NSUInteger attempt;
      long state = IconicState;
      /* Exercise a pinned application through the real process scanner,
       * without injecting its client window ID into the dock item. */
      [app setPath:[manager executablePathForWindow:target]];
      [app setPinned:YES];
      if (argc >= 3) [controller setForceApplicationRestore:YES];
      menu = [view menuForDockItem:app];
      [menu update];
      restore = [menu itemWithTitle:@"Restore"];
      NSCAssert([restore isEnabled], @"Real minimized X11 client is restorable");
      if (argc >= 4) doubleClick(view, app);
      else invoke(view, restore);
      for (attempt = 0; attempt < 100; attempt++)
        {
          [manager wmStateForWindow:target state:&state];
          if (state == NormalState && mapped(display, target)) break;
          [NSThread sleepForTimeInterval:0.05];
        }
      NSCAssert(state == NormalState && mapped(display, target),
                @"Window manager restores the real client");
      RELEASE(view);
      RELEASE(controller);
      RELEASE(manager);
      RELEASE(pool);
      return 0;
    }
  checkWindowPreviews(display, manager, controller);
  doubleClick(view, app);
  NSCAssert([controller requestedWindow] && [app state] == DockItemRunning,
            @"Double-click still launches an app that is not running");
  [app setState:DockItemNotRunning];
  normal = makeWindow(display, NormalState, 0);
  mini = makeWindow(display, IconicState, DockNSMiniWindowMask);
  menu = [view menuForDockItem:app];
  [menu update];
  NSCAssert(![[menu itemWithTitle:@"Restore"] isEnabled],
            @"Unmapped normal windows and GNUstep miniwindow icons are excluded");

  /* Reparenting WMs use override-redirect frames around ordinary clients. */
  frame = makeWindow(display, NormalState, 0);
  {
    XSetWindowAttributes attrs;
    attrs.override_redirect = True;
    XChangeWindowAttributes(display, frame, CWOverrideRedirect, &attrs);
    XMapWindow(display, frame);
  }
  first = makeWindow(display, IconicState, 0);
  XReparentWindow(display, first, frame, 0, 0);
  XSync(display, False);
  x11 = [DockItem x11ItemWithTitle:@"X11" window:first icon:nil hidden:YES];
  restore = [[view menuForDockItem:x11] itemWithTitle:@"Restore"];
  NSCAssert([restore isEnabled] && ![restore submenu], @"Single-window Restore");
  invoke(view, restore);
  NSCAssert(mapped(display, first), @"X11 restore maps the client");
  XUnmapWindow(display, first);

  doubleClick(view, x11);
  NSCAssert(mapped(display, first), @"Double-click restores an X11 entry");
  XUnmapWindow(display, first);

  [app setState:DockItemRunning];
  second = makeWindow(display, IconicState, NSTitledWindowMask);
  XDeleteProperty(display, first, XInternAtom(display, "_GNUSTEP_WM_ATTR", False));
  XSync(display, False);
  NSCAssert([[manager minimizedWindows] count] == 2,
            @"Global scan includes X11 and GNUstep clients, excluding mini icons");
  NSCAssert([controller updateMinimizedItems], @"New minimized entries detected");
  NSArray *entries = [controller minimizedItems];
  NSCAssert([entries count] == 2, @"One entry per minimized window");
  NSCAssert(![controller updateMinimizedItems], @"Unchanged entries retain identity");
  NSMutableArray *displayItems = [NSMutableArray arrayWithObjects:app, x11, nil];
  [displayItems addObjectsFromArray:entries];
  [view setItems:displayItems];
  [view setPinnedItemCount:1];
  [view setMinimizedItemCount:2];
  for (NSUInteger orientation = 0; orientation < 2; orientation++)
    {
      [view setHorizontal:orientation == 1];
      NSRect separator = [view minimizedSectionSeparatorRect];
      NSCAssert(!NSIsEmptyRect(separator), @"Minimized section has a separator");
      NSCAssert(!NSEqualRects(separator, [view sectionSeparatorRectAtEnd:NO]),
                @"Minimized and undocked sections have separate boundaries");
      NSCAssert([view reorderInsertionIndexAtPoint:NSMakePoint(10000, -10000)
                                         fromIndex:1] == 2,
                @"Application reordering stops before minimized entries");
    }
  [view setMinimizedItemCount:0];
  {
    Atom atom = XInternAtom(display, "WM_STATE", False);
    unsigned long values[] = {NormalState, None};
    XChangeProperty(display, second, atom, atom, 32, PropModeReplace,
                    (unsigned char *)values, 2);
    XSync(display, False);
    NSCAssert([controller updateMinimizedItems] &&
              [[controller minimizedItems] count] == 1,
              @"Restored clients leave the minimized section");
    values[0] = IconicState;
    XChangeProperty(display, second, atom, atom, 32, PropModeReplace,
                    (unsigned char *)values, 2);
    XSync(display, False);
    NSCAssert([controller updateMinimizedItems] &&
              [[controller minimizedItems] count] == 2,
              @"Minimizing again recreates the window entry");
  }
  restore = [[view menuForDockItem:app] itemWithTitle:@"Restore"];
  NSCAssert([[restore submenu] numberOfItems] == 4,
            @"Application Restore lists two windows and Restore All");
  invoke(view, [[restore submenu] itemAtIndex:0]);
  NSCAssert(mapped(display, first) != mapped(display, second),
            @"Selecting a title restores only one window");
  invoke(view, [[restore submenu] itemWithTitle:@"Restore All"]);
  NSCAssert(mapped(display, first) && mapped(display, second),
            @"Restore All restores all application clients");
  NSCAssert(!mapped(display, normal) && !mapped(display, mini),
            @"Unrelated windows and miniwindow icons stay untouched");
  XUnmapWindow(display, first);
  XUnmapWindow(display, second);
  doubleClick(view, app);
  NSCAssert(mapped(display, first) && mapped(display, second),
            @"Double-click restores all application windows");
  [controller setForceApplicationRestore:YES];
  menu = [view menuForDockItem:app];
  [menu update];
  restore = [menu itemWithTitle:@"Restore"];
  NSCAssert([restore isEnabled], @"Running apps restore without a miniwindow list");
  XUnmapWindow(display, first);
  doubleClick(view, app);
  NSCAssert(mapped(display, first), @"Application activation reaches framed clients");
  NSCAssert(!mapped(display, mini), @"Application restore never reveals miniwindow icons");
  [controller setForceApplicationRestore:NO];
  restore = [[view menuForDockItem:app] itemWithTitle:@"Restore"];
  XDestroyWindow(display, first);
  XDestroyWindow(display, second);
  XSync(display, False);
  invoke(view, [[restore submenu] itemWithTitle:@"Restore All"]);
  NSCAssert([[manager minimizedWindowsForProcessIdentifiers:
    [NSArray arrayWithObject:[NSNumber numberWithInt:12345]] window:0] count] == 0,
    @"Closed menu targets are safely ignored");
  NSCAssert([controller updateMinimizedItems] &&
            [[controller minimizedItems] count] == 0,
            @"Closed clients disappear from the minimized section");
  [view setItems:[NSArray arrayWithObject:app]];
  [view setPinnedItemCount:1];
  [view setMinimizedItemCount:0];
  NSCAssert(NSIsEmptyRect([view minimizedSectionSeparatorRect]),
            @"Empty minimized section has no separator");
  [app setPath:@"/tmp/RestoreTest-executable"];
  XDestroyWindow(display, normal);
  XDestroyWindow(display, frame);
  [controller setForceApplicationRestore:YES];
  /* No document clients remain; only an intentionally suppressed miniwindow. */
  invoke(view, [[view menuForDockItem:app] itemWithTitle:@"Restore"]);
  NSCAssert([controller requestedWindow], @"Windowless app receives a reopen request");
  NSCAssert(!mapped(display, mini), @"Reopen never maps the suppressed icon");
  RELEASE(view);
  RELEASE(controller);
  RELEASE(manager);
  RELEASE(pool);
  return 0;
}
