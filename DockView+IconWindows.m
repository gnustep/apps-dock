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

/* Visible icon windows forward interaction to the shared dock view. */
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
  NSInteger _kind;
  NSTrackingRectTag _trackingTag;
  NSData *_shapeData;
  NSSize _shapeSize;
  NSImage *_renderedImage;
  NSArray *_renderState;
}

- (id) initWithDock: (DockView *)dock item: (DockItem *)item kind: (NSInteger)kind;
- (void) refreshRendering;

@end
@implementation DockIconContentView

- (id) initWithDock: (DockView *)dock item: (DockItem *)item kind: (NSInteger)kind
{
  self = [super initWithFrame:NSZeroRect];
  if (self)
    {
      _dock = dock;
      _item = RETAIN(item);
      _kind = kind;
      if (kind == 0 || kind == 3)
        [self registerForDraggedTypes:[dock registeredDraggedTypes]];
    }
  return self;
}

- (void) dealloc
{
  RELEASE(_item);
  RELEASE(_shapeData);
  RELEASE(_renderedImage);
  RELEASE(_renderState);
  DEALLOC;
}

- (BOOL) isOpaque { return NO; }

- (void) setFrame: (NSRect)frame
{
  if (NSEqualRects(frame, [self frame])) return;
  [super setFrame:frame];
  if (_trackingTag) [self removeTrackingRect:_trackingTag];
  _trackingTag = 0;
  if (_kind == 0 || _kind == 3)
    _trackingTag = [self addTrackingRect:[self bounds] owner:self
                               userData:NULL assumeInside:NO];
}

- (BOOL) acceptsFirstMouse: (NSEvent *)event
{
  return YES;
}

- (NSEvent *) dockEvent: (NSEvent *)event
{
  /* Use the resting cell even when this icon is bouncing. */
  NSPoint location = [event locationInWindow];
  NSRect cell = _kind == 3 ? [_dock topTileRect] :
    [_dock restingCellForItem:_item];
  location.x += cell.origin.x;
  location.y += cell.origin.y;
  location = [_dock convertPoint:location toView:nil];
  return [NSEvent mouseEventWithType:[event type] location:location
    modifierFlags:[event modifierFlags] timestamp:[event timestamp]
    windowNumber:[[_dock window] windowNumber] context:[event context]
    eventNumber:[event eventNumber] clickCount:[event clickCount] pressure:[event pressure]];
}

- (void) mouseDown: (NSEvent *)event
{
  [_dock mouseDown:[self dockEvent:event]];
}

- (void) rightMouseDown: (NSEvent *)event
{
  [_dock rightMouseDown:[self dockEvent:event]];
}

- (void) mouseDragged: (NSEvent *)event
{
  [_dock mouseDragged:[self dockEvent:event]];
}

- (void) mouseMoved: (NSEvent *)event
{
  [_dock mouseMoved:[self dockEvent:event]];
}

- (void) mouseExited: (NSEvent *)event
{
  [_dock mouseExited:event];
}

- (NSDragOperation) draggingEntered: (id <NSDraggingInfo>)sender
{
  return [_dock draggingEntered:sender];
}

- (NSDragOperation) draggingUpdated: (id <NSDraggingInfo>)sender
{
  return [_dock draggingUpdated:sender];
}

- (void) draggingExited: (id <NSDraggingInfo>)sender
{
  [_dock draggingExited:sender];
}

- (BOOL) prepareForDragOperation: (id <NSDraggingInfo>)sender
{
  return [_dock prepareForDragOperation:sender];
}

- (BOOL) performDragOperation: (id <NSDraggingInfo>)sender
{
  return [_dock performDragOperation:sender];
}

- (void) concludeDragOperation: (id <NSDraggingInfo>)sender
{
  [_dock concludeDragOperation:sender];
}

- (void) refreshRendering
{
  NSArray *state = [_dock renderStateForItem:_item kind:_kind];
  if (![_renderState isEqual:state])
    {
      ASSIGNCOPY(_renderState, state);
      DESTROY(_renderedImage);
      [self setNeedsDisplay:YES];
    }
}

- (void) drawRect: (NSRect)rect
{
  /* Expose events reuse the pixels and shape until appearance changes. */
  if (_renderedImage && NSEqualSizes([_renderedImage size], [self bounds].size))
    {
      NSRectFillUsingOperation(rect, NSCompositeClear);
      [_renderedImage drawInRect:[self bounds] fromRect:NSZeroRect
                      operation:NSCompositeSourceOver fraction:1.0];
      return;
    }
  /* Render on a surface with alpha, then explicitly shape the native window.
   * Clear pixels in an ordinary X11 window are not transparent without a
   * compositor. The shape exposes the desktop around each icon or dot. */
  NSImage *image = [[NSImage alloc] initWithSize:[self bounds].size];
  [image setBackgroundColor:[NSColor clearColor]];
  [image lockFocus];
  NSRectFillUsingOperation([self bounds], NSCompositeClear);
  if (_kind == 1) [_dock drawTooltip];
  else if (_kind == 2) [_dock drawIndicatorWindowForItem:_item];
  else if (_kind == 3)
    {
      NSRect cell = [_dock topTileRect];
      NSAffineTransform *transform = [NSAffineTransform transform];
      [transform translateXBy:-cell.origin.x yBy:-cell.origin.y];
      [transform concat];
      [_dock drawTopTile];
    }
  else if (_kind == 4) [_dock drawDropIndicator];
  else if (_kind == 5)
    {
      [[NSColor colorWithCalibratedWhite:1.0 alpha:0.55] set];
      NSRectFill([self bounds]);
    }
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
      NSSize shapeSize = NSMakeSize(width, height);
      /* Exposure and color-only updates need not send another shape to X11. */
      if (!NSEqualSizes(_shapeSize, shapeSize) || ![_shapeData isEqualToData:maskData])
        {
          Pixmap mask = XCreateBitmapFromData(display, native,
            (const char *)bits, (unsigned int)width, (unsigned int)height);
          XShapeCombineMask(display, native, ShapeBounding, 0, 0, mask, ShapeSet);
          XFreePixmap(display, mask);
          ASSIGNCOPY(_shapeData, maskData);
          _shapeSize = shapeSize;
        }
    }
  XFlush(display);
  ASSIGN(_renderedImage, image);
  RELEASE(image);
}

@end

static NSWindow *NewIconWindow(DockView *dock, DockItem *item, NSInteger kind)
{
  NSWindow *window = [[DockIconWindow alloc] initWithContentRect:NSMakeRect(0, 0, 1, 1)
    styleMask:NSBorderlessWindowMask backing:NSBackingStoreBuffered defer:NO];
  [window setReleasedWhenClosed:NO];
  [window setOpaque:NO];
  [window setBackgroundColor:[NSColor clearColor]];
  [window setHasShadow:NO];
  [window setLevel:NSDockWindowLevel];
  [window setIgnoresMouseEvents:kind != 0 && kind != 3];
  [window setAcceptsMouseMovedEvents:YES];
  [window setExcludedFromWindowsMenu:YES];
  [window setCollectionBehavior:NSWindowCollectionBehaviorCanJoinAllSpaces |
                                NSWindowCollectionBehaviorStationary];
  [window setTitle:kind == 1 ? @"Dock tooltip" :
    (kind == 3 ? @"DockWM tile" : (kind == 4 ? @"Dock insertion marker" :
    (kind == 2 ? [NSString stringWithFormat:@"%@ state", [item title]] :
    (item ? [item title] : @"Recycler"))))];
  if (kind == 5) [window setTitle:@"Dock section separator"];
  DockIconContentView *content = [[DockIconContentView alloc] initWithDock:dock
    item:item kind:kind];
  [window setContentView:content];
  RELEASE(content);
  /* GNUstep's collection behavior is a stub. Set native dock/workspace
   * hints before mapping so these windows stay out of task switchers. */
  Display *display = (Display *)[GSServerForWindow(window) serverDevice];
  if (display)
    {
      Window native = (Window)[window windowRef];
      /* Keep the shaped windows free of window-manager frames. */
      XSetWindowAttributes attributes;
      attributes.override_redirect = True;
      XChangeWindowAttributes(display, native, CWOverrideRedirect, &attributes);
      XShapeCombineRectangles(display, native, ShapeBounding, 0, 0, NULL, 0, ShapeSet, Unsorted);
      if (kind != 0 && kind != 3)
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

/* Animation changes only position. Repainting here would regenerate every
 * icon's bitmap and native shape sixty times a second. */
- (void) positionIconWindow: (NSWindow *)window
                    inCell: (NSRect)cell
               bounceStart: (NSTimeInterval)start
                      time: (NSTimeInterval)now
{
  NSPoint origin = [[self window] convertBaseToScreen:
    [self convertPoint:cell.origin toView:nil]];
  CGFloat offset = start ? [self bounceOffsetAtTime:now - start] : 0.0;
  NSRect screen = [[[self window] screen] frame];
  BOOL atTop = _horizontal && NSMaxY([[self window] frame]) >= NSMaxY(screen) - 1.0;
  NSRect frame;

  origin.y += atTop ? -offset : offset;
  origin.x = round(origin.x);
  origin.y = round(origin.y);
  frame = NSMakeRect(origin.x, origin.y, cell.size.width, cell.size.height);
  if (!NSEqualRects([window frame], frame)) [window setFrame:frame display:NO];
}

- (void) updateIconWindowPositions
{
  NSTimeInterval now = [NSDate timeIntervalSinceReferenceDate];
  if (![self window]) return;
  for (NSUInteger i = 0; i <= [_items count]; i++)
    {
      DockItem *item = i < [_items count] ? [_items objectAtIndex:i] : nil;
      id key = item ? (id)[NSValue valueWithPointer:item] : (id)@"recycler";
      NSWindow *window = [_iconWindows objectForKey:key];
      if (!window) continue;
      NSRect cell = item ? [self cellRectForHoverIndex:i] : [self recyclerTileRect];
      NSTimeInterval start = item ? (item == _wiggleItem ? _wiggleStartTime : 0.0)
                                 : _recyclerWiggleStartTime;
      [self positionIconWindow:window inCell:cell bounceStart:start time:now];
    }
}

- (void) syncIconWindows
{
  if (_syncingIconWindows || !_items) return;
  if (![self window]) { [self closeIconWindows]; return; }
  _syncingIconWindows = YES;
  /* Retain only the layout/strut owner. It has no visible or input region;
   * interaction belongs to the individual icon windows. */
  if (!_iconWindows)
    {
      Display *display = (Display *)[GSServerForWindow([self window]) serverDevice];
      XShapeCombineRectangles(display, (Window)[[self window] windowRef],
                             ShapeBounding, 0, 0, NULL, 0, ShapeSet, Unsorted);
      [[self window] setHasShadow:NO];
      _iconWindows = [[NSMutableDictionary alloc] init];
    }
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
      NSTimeInterval start = item ? (item == _wiggleItem ? _wiggleStartTime : 0.0)
                                 : _recyclerWiggleStartTime;
      [self positionIconWindow:window inCell:cell bounceStart:start time:now];
      if ([[self window] isVisible])
        {
          if (![window isVisible])
            [window orderWindow:NSWindowAbove relativeTo:[[self window] windowNumber]];
        }
      else if ([window isVisible]) [window orderOut:nil];
      [(DockIconContentView *)[window contentView] refreshRendering];
    }
  /* Indicators stay at rest while their icons bounce. The top tile and
   * drag insertion marker also need their own visible surfaces. */
  for (NSInteger i = -2; i < (NSInteger)[_items count]; i++)
    {
      if (i == -1 && ((!_draggingPaths && _draggedItemIndex == NSNotFound) ||
                       _dropIndex == NSNotFound || _dropIndex > [_items count])) continue;
      DockItem *item = i >= 0 ? [_items objectAtIndex:i] : nil;
      NSInteger kind = i == -2 ? 3 : (i == -1 ? 4 : 2);
      id key = i == -2 ? @"top" : (i == -1 ? @"drop" :
        [NSString stringWithFormat:@"indicator-%p", item]);
      if (item && ([item kind] != DockItemApplication ||
          (_runningIndicatorMode == DockRunningIndicatorModeNotRunningDots
           ? [item state] != DockItemNotRunning
           : [item state] == DockItemNotRunning))) continue;
      [liveKeys addObject:key];
      NSWindow *window = [_iconWindows objectForKey:key];
      if (!window)
        {
          window = NewIconWindow(self, item, kind);
          [_iconWindows setObject:window forKey:key];
          RELEASE(window);
        }
      NSRect cell = i == -2 ? [self topTileRect] :
        (i == -1 ? [self bounds] : [self cellRectForHoverIndex:i]);
      NSPoint origin = [[self window] convertBaseToScreen:
        [self convertPoint:cell.origin toView:nil]];
      NSRect frame = NSMakeRect(origin.x, origin.y, cell.size.width, cell.size.height);
      if (!NSEqualRects([window frame], frame)) [window setFrame:frame display:NO];
      if ([[self window] isVisible])
        {
          if (![window isVisible])
            [window orderWindow:NSWindowAbove relativeTo:[[self window] windowNumber]];
        }
      else if ([window isVisible]) [window orderOut:nil];
      [(DockIconContentView *)[window contentView] refreshRendering];
    }
  /* Bound the unpinned section with two narrow, stationary windows. */
  for (NSUInteger edge = 0; edge < 2; edge++)
    {
      NSRect rect = [self sectionSeparatorRectAtEnd:edge == 1];
      if (NSIsEmptyRect(rect)) continue;
      NSString *key = edge == 0 ? @"separator-start" : @"separator-end";
      [liveKeys addObject:key];
      NSWindow *window = [_iconWindows objectForKey:key];
      if (!window)
        {
          window = NewIconWindow(self, nil, 5);
          [_iconWindows setObject:window forKey:key];
          RELEASE(window);
        }
      rect.origin = [[self window] convertBaseToScreen:
        [self convertPoint:rect.origin toView:nil]];
      if (!NSEqualRects([window frame], rect)) [window setFrame:rect display:NO];
      if ([[self window] isVisible])
        {
          if (![window isVisible])
            [window orderWindow:NSWindowAbove relativeTo:[[self window] windowNumber]];
        }
      else if ([window isVisible]) [window orderOut:nil];
      [(DockIconContentView *)[window contentView] refreshRendering];
    }
  for (id key in AUTORELEASE([[_iconWindows allKeys] copy]))
    if (![liveKeys containsObject:key])
      {
        NSWindow *window = [_iconWindows objectForKey:key];
        [[window parentWindow] removeChildWindow:window];
        [window close];
        [_iconWindows removeObjectForKey:key];
      }
  if (_wiggleItem && ![_items containsObject:_wiggleItem]) [self stopWiggle];
  NSRect tooltipFrame = [self tooltipWindowFrame];
  if (!NSIsEmptyRect(tooltipFrame) && [[self window] isVisible])
    {
      if (!_tooltipWindow) _tooltipWindow = NewIconWindow(self, nil, YES);
      if (!NSEqualRects([_tooltipWindow frame], tooltipFrame))
        [_tooltipWindow setFrame:tooltipFrame display:NO];
      if (![_tooltipWindow isVisible]) [_tooltipWindow orderFront:nil];
      [(DockIconContentView *)[_tooltipWindow contentView] refreshRendering];
    }
  else if ([_tooltipWindow isVisible]) [_tooltipWindow orderOut:nil];
  _syncingIconWindows = NO;
  [self repairIconWindowStacking];
}

/* Describe only inputs used to draw each surface. Position-only changes and
 * unrelated application updates must not invalidate every overlay. */
- (NSArray *) renderStateForItem: (DockItem *)item kind: (NSInteger)kind
{
  NSMutableArray *state = [NSMutableArray array];
  NSNull *empty = [NSNull null];
  [state addObject:[NSNumber numberWithDouble:_cellSize]];
  if (kind == 0 || kind == 3)
    {
      [state addObject:[NSNumber numberWithBool:_usesCellBackgroundTile]];
      [state addObject:_cellBackgroundImage ? (id)_cellBackgroundImage : empty];
    }
  if (kind == 0 && item)
    {
      NSUInteger index = [_items indexOfObjectIdenticalTo:item];
      NSRect cell = [self restingCellForItem:item];
      CGFloat size = [self iconSizeForItemAtIndex:index];
      NSRect iconRect = [self iconRectInCell:cell size:size];
      iconRect.origin.x -= cell.origin.x;
      iconRect.origin.y -= cell.origin.y;
      [state addObject:[item icon] ? (id)[item icon] : empty];
      [state addObject:[item title] ? (id)[item title] : empty];
      [state addObject:[item badgeLabel] ? (id)[item badgeLabel] : empty];
      [state addObject:[NSNumber numberWithBool:[item isMissing]]];
      [state addObject:[NSNumber numberWithDouble:size]];
      [state addObject:[NSValue valueWithRect:iconRect]];
    }
  else if (kind == 0)
    {
      NSImage *image = [self standardRecyclerIcon];
      if (!image) image = _recyclerIcon;
      [state addObject:image ? (id)image : empty];
      [state addObject:[NSNumber numberWithBool:_recyclerHasContents]];
    }
  else if (kind == 1)
    {
      NSString *title = [self tooltipTitleForHoverIndex:_tooltipItemIndex];
      [state addObject:title ? (id)title : empty];
      [state addObject:[NSValue valueWithSize:[_tooltipWindow frame].size]];
    }
  else if (kind == 2)
    {
      [state addObject:[NSNumber numberWithInteger:_runningIndicatorMode]];
    }
  else if (kind == 3)
    {
      [state addObject:_gnustepIcon ? (id)_gnustepIcon : empty];
    }
  else if (kind == 4)
    {
      [state addObject:[NSNumber numberWithUnsignedInteger:_dropIndex]];
      [state addObject:[NSNumber numberWithBool:_horizontal]];
      [state addObject:[NSNumber numberWithDouble:_dockGap]];
      [state addObject:[NSNumber numberWithDouble:_dockPad]];
      [state addObject:[NSValue valueWithSize:[self bounds].size]];
    }
  if ((kind == 0 && !item) || kind == 3)
    {
      NSRect cell = kind == 3 ? [self topTileRect] : [self recyclerTileRect];
      NSRect iconRect = [self iconRectInCell:cell
        size:(kind == 3 ? 50.0 : 46.0) * (_cellSize / DockCell)];
      iconRect.origin.x -= cell.origin.x;
      iconRect.origin.y -= cell.origin.y;
      [state addObject:[NSValue valueWithRect:iconRect]];
    }
  if (kind == 5) [state addObject:[NSNumber numberWithBool:_horizontal]];
  return state;
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

- (NSRect) restingCellForItem: (DockItem *)item
{
  NSUInteger index = item ? [_items indexOfObjectIdenticalTo:item] : NSNotFound;
  return index == NSNotFound ? [self recyclerTileRect] : [self cellRectForHoverIndex:index];
}

- (void) drawIndicatorWindowForItem: (DockItem *)item
{
  NSUInteger index = [_items indexOfObjectIdenticalTo:item];
  if (index == NSNotFound) return;
  NSRect cell = [self cellRectForHoverIndex:index];
  NSAffineTransform *transform = [NSAffineTransform transform];
  [NSGraphicsContext saveGraphicsState];
  [transform translateXBy:-cell.origin.x yBy:-cell.origin.y];
  [transform concat];
  [self drawStateForItem:item inCell:cell];
  [NSGraphicsContext restoreGraphicsState];
}


@end
