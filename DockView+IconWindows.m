#import "DockViewPrivate.h"
#import <X11/Xlib.h>
#import <X11/Xatom.h>
#import <X11/extensions/shape.h>
#import <GNUstepGUI/GSDisplayServer.h>

@implementation DockWindow
- (void) orderWindow: (NSWindowOrderingMode)place relativeTo: (NSInteger)number
{
  [super orderWindow:place relativeTo:number];
  if ([[self contentView] isKindOfClass:[DockView class]])
    {
      [(DockView *)[self contentView] syncIconWindows];
      /* GNUstep does not raise child windows when their parent is raised.
       * isVisible only means mapped: an icon can still be behind the dock.
       * Restore stacking after EVERY parent order, including the startup
       * orderFrontRegardless that follows makeKeyAndOrderFront. */
      if (place != NSWindowOut)
        {
          NSInteger sibling = [self windowNumber];
          for (NSWindow *child in [self childWindows])
            if ([child isVisible])
              {
                [child orderWindow:NSWindowAbove relativeTo:sibling];
                sibling = [child windowNumber];
              }
        }
    }
}
@end

/* Input stays on the stationary dock so clicks, hover and drag destinations
 * do not move out from under the pointer during a bounce. */
@interface DockIconWindow : NSWindow
@end
@implementation DockIconWindow
- (BOOL) canBecomeKeyWindow { return NO; }
- (BOOL) canBecomeMainWindow { return NO; }
- (void) orderWindow: (NSWindowOrderingMode)place relativeTo: (NSInteger)number
{
  [super orderWindow:place relativeTo:number];
  /* These unmanaged overlays have no WM frame. A relative restack against
   * a reparented dock client is not necessarily a sibling restack in X11. */
  if (place == NSWindowAbove)
    XRaiseWindow((Display *)[GSServerForWindow(self) serverDevice], (Window)[self windowRef]);
}
@end

@interface DockIconContentView : NSView
{
  DockView *_dock;
  DockItem *_item;
  BOOL _tooltip;
}
- (id) initWithDock: (DockView *)dock item: (DockItem *)item tooltip: (BOOL)tooltip;
@end
@implementation DockIconContentView
- (id) initWithDock: (DockView *)dock item: (DockItem *)item tooltip: (BOOL)tooltip
{
  self = [super initWithFrame:NSZeroRect];
  if (self) { _dock = dock; _item = RETAIN(item); _tooltip = tooltip; }
  return self;
}
- (void) dealloc { RELEASE(_item); [super dealloc]; }
- (BOOL) isOpaque { return NO; }
- (void) drawRect: (NSRect)rect
{
  /* Render on a surface with alpha, then explicitly shape the native window.
   * Clear pixels in an ordinary X11 window are not transparent without a
   * compositor; a full-cell window otherwise covers the running indicator. */
  NSImage *image = [[NSImage alloc] initWithSize:[self bounds].size];
  [image setBackgroundColor:[NSColor clearColor]];
  [image lockFocus];
  NSRectFillUsingOperation([self bounds], NSCompositeClear);
  if (_tooltip) [_dock drawTooltip];
  else [_dock drawIconWindowForItem:_item];
  [image unlockFocus];
  NSRectFillUsingOperation(rect, NSCompositeClear);
  [image drawInRect:[self bounds] fromRect:NSZeroRect
         operation:NSCompositeSourceOver fraction:1.0];

  Display *display = (Display *)[GSServerForWindow([self window]) serverDevice];
  Window native = (Window)[[self window] windowRef];
  NSBitmapImageRep *bitmap = [NSBitmapImageRep imageRepWithData:[image TIFFRepresentation]];
  if (bitmap)
    {
      NSUInteger width = [bitmap pixelsWide], height = [bitmap pixelsHigh];
      NSUInteger stride = (width + 7) / 8;
      NSMutableData *maskData = [NSMutableData dataWithLength:stride * height];
      unsigned char *bits = [maskData mutableBytes];
      for (NSUInteger y = 0; y < height; y++)
        for (NSUInteger x = 0; x < width; x++)
          if ([[bitmap colorAtX:x y:y] alphaComponent] > 0.0)
            bits[y * stride + x / 8] |= 1 << (x % 8);
      Pixmap mask = XCreateBitmapFromData(display, native,
        (const char *)bits, (unsigned int)width, (unsigned int)height);
      XShapeCombineMask(display, native, ShapeBounding, 0, 0, mask, ShapeSet);
      XFreePixmap(display, mask);
    }
  /* Do not depend on GNUstep's optional XFixes implementation of
   * setIgnoresMouseEvents:. This also covers the tooltip overlay. */
  XShapeCombineRectangles(display, native, ShapeInput, 0, 0, NULL, 0, ShapeSet, Unsorted);
  XFlush(display);
  [image release];
}
@end

static NSWindow *NewIconWindow(DockView *dock, DockItem *item, BOOL tooltip)
{
  NSWindow *window = [[DockIconWindow alloc] initWithContentRect:NSMakeRect(0, 0, 1, 1)
    styleMask:NSBorderlessWindowMask backing:NSBackingStoreBuffered defer:NO];
  [window setReleasedWhenClosed:NO];
  [window setOpaque:NO];
  [window setBackgroundColor:[NSColor clearColor]];
  [window setHasShadow:NO];
  [window setLevel:NSDockWindowLevel];
  [window setIgnoresMouseEvents:YES];
  [window setExcludedFromWindowsMenu:YES];
  [window setCollectionBehavior:NSWindowCollectionBehaviorCanJoinAllSpaces |
                                NSWindowCollectionBehaviorStationary];
  [window setTitle:tooltip ? @"Dock tooltip" : (item ? [item title] : @"Recycler")];
  DockIconContentView *content = [[DockIconContentView alloc] initWithDock:dock
    item:item tooltip:tooltip];
  [window setContentView:content];
  RELEASE(content);
  /* GNUstep's collection behavior is a stub. Set native dock/workspace
   * hints before mapping so these windows stay out of task switchers. */
  Display *display = (Display *)[GSServerForWindow(window) serverDevice];
  if (display)
    {
      Window native = (Window)[window windowRef];
      /* A WM frame would intercept input even with an empty client input
       * shape. Keep the overlay unmanaged and let DockWindow order it. */
      XSetWindowAttributes attributes;
      attributes.override_redirect = True;
      XChangeWindowAttributes(display, native, CWOverrideRedirect, &attributes);
      XShapeCombineRectangles(display, native, ShapeBounding, 0, 0, NULL, 0, ShapeSet, Unsorted);
      XShapeCombineRectangles(display, native, ShapeInput, 0, 0, NULL, 0, ShapeSet, Unsorted);
      unsigned long desktop = 0xffffffffUL;
      Atom type = XInternAtom(display, "_NET_WM_WINDOW_TYPE_DOCK", False);
      XChangeProperty(display, native, XInternAtom(display, "_NET_WM_WINDOW_TYPE", False),
        XA_ATOM, 32, PropModeReplace, (unsigned char *)&type, 1);
      XChangeProperty(display, native, XInternAtom(display, "_NET_WM_DESKTOP", False),
        XA_CARDINAL, 32, PropModeReplace, (unsigned char *)&desktop, 1);
      XFlush(display);
    }
  [[dock window] addChildWindow:window ordered:NSWindowAbove];
  return window;
}

@implementation DockView (IconWindows)

- (void) repairIconWindowStacking
{
  NSWindow *dock = [self window];
  Display *display;
  Window ancestor, root, parent, *children = NULL;
  unsigned int count, i;
  NSInteger dockIndex = -1;
  BOOL changed = NO;

  if (!dock || ![dock isVisible] || ![_iconWindows count]) return;
  display = (Display *)[GSServerForWindow(dock) serverDevice];
  if (!display) return;
  ancestor = (Window)[dock windowRef];
  /* The managed client and our unmanaged overlays are not siblings.
   * Compare against the WM's outermost frame, including after reparenting. */
  for (;;)
    {
      if (!XQueryTree(display, ancestor, &root, &parent, &children, &count)) return;
      if (children) XFree(children);
      children = NULL;
      if (parent == root) break;
      if (parent == None) return;
      ancestor = parent;
    }
  if (!XQueryTree(display, root, &root, &parent, &children, &count)) return;
  for (i = 0; i < count; i++)
    if (children[i] == ancestor) dockIndex = i;
  if (dockIndex >= 0)
    {
      NSWindow *overlay;

      for (overlay in [dock childWindows])
        {
          if (![overlay isKindOfClass:[DockIconWindow class]] ||
              ![overlay isVisible]) continue;
          for (i = 0; i < (unsigned int)dockIndex; i++)
            if (children[i] == (Window)[overlay windowRef])
              {
                XWindowChanges changes;

                changes.sibling = ancestor;
                changes.stack_mode = Above;
                XConfigureWindow(display, children[i], CWSibling | CWStackMode,
                                 &changes);
                changed = YES;
                break;
              }
        }
    }
  if (children) XFree(children);
  /* Do not raise already-correct overlays: that would generate an endless
   * ConfigureNotify loop and could cover menus above the dock. */
  if (changed) XFlush(display);
}

- (CGFloat) bounceOffsetAtTime: (NSTimeInterval)elapsed
{
  /* Two ballistic arcs: a large hop and a smaller settling hop. */
  if (elapsed <= 0.0 || elapsed >= DockWiggleDuration) return 0.0;
  CGFloat split = 0.55;
  CGFloat t = elapsed < split ? elapsed / split :
    (elapsed - split) / (DockWiggleDuration - split);
  CGFloat height = _cellSize * (elapsed < split ? 0.55 : 0.20);
  return height * 4.0 * t * (1.0 - t);
}

- (void) closeIconWindows
{
  for (NSWindow *window in [_iconWindows allValues])
    {
      [[window parentWindow] removeChildWindow:window];
      [window close];
    }
  DESTROY(_iconWindows);
  if (_tooltipWindow)
    {
      [[_tooltipWindow parentWindow] removeChildWindow:_tooltipWindow];
      [_tooltipWindow close];
      DESTROY(_tooltipWindow);
    }
}

- (void) syncIconWindows
{
  if (_syncingIconWindows || !_items) return;
  if (![self window]) { [self closeIconWindows]; return; }
  _syncingIconWindows = YES;
  if (!_iconWindows) _iconWindows = [NSMutableDictionary new];
  NSMutableSet *liveKeys = [NSMutableSet set];
  NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
  for (NSUInteger i = 0; i <= [_items count]; i++)
    {
      DockItem *item = i < [_items count] ? [_items objectAtIndex:i] : nil;
      id key = item ? (id)[NSValue valueWithPointer:item] : (id)@"recycler";
      [liveKeys addObject:key];
      NSWindow *window = [_iconWindows objectForKey:key];
      if (!window)
        {
          window = NewIconWindow(self, item, NO);
          [_iconWindows setObject:window forKey:key];
          RELEASE(window);
        }
      NSRect cell = item ? [self cellRectForHoverIndex:i] : [self recyclerTileRect];
      NSPoint origin = [[self window] convertBaseToScreen:
        [self convertPoint:cell.origin toView:nil]];
      NSTimeInterval start = item ? (item == _wiggleItem ? _wiggleStartTime : 0.0)
                                 : _recyclerWiggleStartTime;
      CGFloat offset = start ? [self bounceOffsetAtTime:now - start] : 0.0;
      /* A top dock bounces downward into the screen. Other docks rise. */
      NSRect screen = [[[self window] screen] frame];
      BOOL atTop = _horizontal && NSMaxY([[self window] frame]) >= NSMaxY(screen) - 1.0;
      origin.y += atTop ? -offset : offset;
      [window setFrame:NSMakeRect(origin.x, origin.y, cell.size.width, cell.size.height)
              display:NO];
      if ([[self window] isVisible])
        {
          if (![window isVisible])
            [window orderWindow:NSWindowAbove relativeTo:[[self window] windowNumber]];
        }
      else [window orderOut:nil];
      [[window contentView] setNeedsDisplay:YES];
    }
  for (id key in [[[_iconWindows allKeys] copy] autorelease])
    if (![liveKeys containsObject:key])
      {
        NSWindow *window = [_iconWindows objectForKey:key];
        [[window parentWindow] removeChildWindow:window];
        [window close];
        [_iconWindows removeObjectForKey:key];
      }
  if (_wiggleItem && ![_items containsObject:_wiggleItem]) [self stopWiggle];
  if (_tooltipItemIndex != DockHoverNone && [[self window] isVisible])
    {
      if (!_tooltipWindow) _tooltipWindow = NewIconWindow(self, nil, YES);
      NSPoint origin = [[self window] convertBaseToScreen:
        [self convertPoint:[self bounds].origin toView:nil]];
      [_tooltipWindow setFrame:NSMakeRect(origin.x, origin.y,
        NSWidth([self bounds]), NSHeight([self bounds])) display:NO];
      [_tooltipWindow orderFront:nil];
      [[_tooltipWindow contentView] setNeedsDisplay:YES];
    }
  else if (_tooltipWindow) [_tooltipWindow orderOut:nil];
  _syncingIconWindows = NO;
  [self repairIconWindowStacking];
}

- (void) drawIconWindowForItem: (DockItem *)item
{
  NSUInteger index = item ? [_items indexOfObjectIdenticalTo:item] : NSNotFound;
  if (item && index == NSNotFound) return;
  NSRect cell = item ? [self cellRectForHoverIndex:index] : [self recyclerTileRect];
  NSAffineTransform *transform = [NSAffineTransform transform];
  [NSGraphicsContext saveGraphicsState];
  [transform translateXBy:-cell.origin.x yBy:-cell.origin.y];
  [transform concat];
  if (item) [self drawDockTileForItem:item inCell:cell size:[self iconSizeForItemAtIndex:index]];
  else [self drawRecyclerTile];
  [NSGraphicsContext restoreGraphicsState];
}
@end
