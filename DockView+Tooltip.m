/*
 * DockWM
 *
 * Copyright (C) 2026 Gregory Casamento <greg.casamento@gmail.com>
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 */

#import "DockViewPrivate.h"

@implementation DockView (Tooltip)

- (NSString *) tooltipTitleForHoverIndex: (NSInteger)index
{
  if (index == DockHoverTopIcon)
    {
      return @"DockWM";
    }

  if (index == DockHoverRecycler)
    {
      return @"Recycler";
    }

  if (index >= 0 && index < (NSInteger)[_items count])
    {
      DockItem *item = [_items objectAtIndex: (NSUInteger)index];
      if ([item isMissing])
        {
          return [NSString stringWithFormat:@"%@ (Missing)", [item title]];
        }
      return [[item title] length] ? [item title] : [[item path] lastPathComponent];
    }

  return nil;
}


- (void) hideTooltip
{
  [_tooltipTimer invalidate];
  DESTROY(_tooltipTimer);
  if (_tooltipItemIndex != DockHoverNone)
    {
      _tooltipItemIndex = DockHoverNone;
      [self setNeedsDisplay:YES];
    }
}


- (void) scheduleTooltipForHoverIndex: (NSInteger)index
{
  [_tooltipTimer invalidate];
  DESTROY(_tooltipTimer);
  _tooltipItemIndex = DockHoverNone;

  if (index == DockHoverNone)
    {
      [self setNeedsDisplay:YES];
      return;
    }

  if (_tooltipDelay == 0.0)
    {
      [self showTooltip:nil];
      return;
    }

  _tooltipTimer = [NSTimer scheduledTimerWithTimeInterval:_tooltipDelay
                                                   target:self
                                                 selector:@selector(showTooltip:)
                                                 userInfo:nil
						  repeats:NO];
  _tooltipTimer = RETAIN(_tooltipTimer);
  [self setNeedsDisplay:YES];
}


- (NSDictionary *) tooltipTextAttributes
{
  NSMutableParagraphStyle *style = AUTORELEASE([[NSMutableParagraphStyle alloc] init]);
  [style setLineBreakMode:NSLineBreakByTruncatingTail];
  return [NSDictionary dictionaryWithObjectsAndKeys:
    [NSFont systemFontOfSize:11.0], NSFontAttributeName,
    [NSColor whiteColor], NSForegroundColorAttributeName,
    style, NSParagraphStyleAttributeName, nil];
}


- (NSRect) tooltipWindowFrame
{
  NSString *title = [self tooltipTitleForHoverIndex:_tooltipItemIndex];
  NSRect cell = [self cellRectForHoverIndex:_tooltipItemIndex];
  if (![title length] || NSIsEmptyRect(cell) || ![self window]) return NSZeroRect;

  NSSize textSize = [title sizeWithAttributes:[self tooltipTextAttributes]];
  NSScreen *screen = [[self window] screen];
  if (!screen) screen = [NSScreen mainScreen];
  NSRect screenFrame = NSInsetRect([screen frame], 4.0, 4.0);
  NSRect frame = NSMakeRect(0.0, 0.0,
    MIN(ceil(textSize.width) + 14.0, NSWidth(screenFrame)),
    ceil(textSize.height) + 8.0);
  /* Reserve a transparent strip for the pointer on the icon-facing edge. */
  if (_horizontal) frame.size.height += 6.0;
  else frame.size.width = MIN(NSWidth(frame) + 6.0, NSWidth(screenFrame));
  cell.origin = [[self window] convertBaseToScreen:
    [self convertPoint:cell.origin toView:nil]];

  /* Place the label beside the dock, toward the interior of the screen. */
  if (_horizontal)
    {
      frame.origin.x = NSMidX(cell) - NSWidth(frame) / 2.0;
      frame.origin.y = NSMidY([[self window] frame]) > NSMidY(screenFrame)
        ? NSMinY(cell) - NSHeight(frame) - 6.0 : NSMaxY(cell) + 6.0;
    }
  else
    {
      frame.origin.x = NSMidX([[self window] frame]) > NSMidX(screenFrame)
        ? NSMinX(cell) - NSWidth(frame) - 6.0 : NSMaxX(cell) + 6.0;
      frame.origin.y = NSMidY(cell) - NSHeight(frame) / 2.0;
    }
  frame.origin.x = floor(MAX(NSMinX(screenFrame),
    MIN(frame.origin.x, NSMaxX(screenFrame) - NSWidth(frame))));
  frame.origin.y = floor(MAX(NSMinY(screenFrame),
    MIN(frame.origin.y, NSMaxY(screenFrame) - NSHeight(frame))));
  return frame;
}


- (NSRectEdge) tooltipArrowEdge
{
  NSScreen *screen = [[self window] screen];
  if (!screen) screen = [NSScreen mainScreen];
  if (_horizontal)
    return NSMidY([[self window] frame]) > NSMidY([screen frame])
      ? NSMaxYEdge : NSMinYEdge;
  return NSMidX([[self window] frame]) > NSMidX([screen frame])
    ? NSMaxXEdge : NSMinXEdge;
}


- (NSPoint) tooltipArrowTip
{
  NSRect frame = [self tooltipWindowFrame];
  NSRect cell = [self cellRectForHoverIndex:_tooltipItemIndex];
  NSPoint center = [[self window] convertBaseToScreen:
    [self convertPoint:NSMakePoint(NSMidX(cell), NSMidY(cell)) toView:nil]];
  NSRectEdge edge = [self tooltipArrowEdge];

  /* Keep the pointer aligned with the icon when the label hits a screen edge. */
  if (edge == NSMinYEdge || edge == NSMaxYEdge)
    return NSMakePoint(MAX(10.0, MIN(center.x - NSMinX(frame), NSWidth(frame) - 10.0)),
                       edge == NSMinYEdge ? 0.0 : NSHeight(frame));
  return NSMakePoint(edge == NSMinXEdge ? 0.0 : NSWidth(frame),
    MAX(10.0, MIN(center.y - NSMinY(frame), NSHeight(frame) - 10.0)));
}


- (void) drawTooltip
{
  NSString *title = [self tooltipTitleForHoverIndex:_tooltipItemIndex];
  NSRect rect = [[_tooltipWindow contentView] bounds];
  NSRectEdge edge = [self tooltipArrowEdge];
  NSPoint tip = [self tooltipArrowTip];
  NSPoint a = tip, b = tip;
  NSBezierPath *arrow = [NSBezierPath bezierPath];

  if (![title length]) return;
  if (edge == NSMinYEdge || edge == NSMaxYEdge)
    {
      rect.size.height -= 6.0;
      if (edge == NSMinYEdge) rect.origin.y += 6.0;
      a.x -= 5.0;
      b.x += 5.0;
      a.y = b.y = tip.y + (edge == NSMinYEdge ? 6.0 : -6.0);
    }
  else
    {
      rect.size.width -= 6.0;
      if (edge == NSMinXEdge) rect.origin.x += 6.0;
      a.y -= 5.0;
      b.y += 5.0;
      a.x = b.x = tip.x + (edge == NSMinXEdge ? 6.0 : -6.0);
    }
  [[NSColor colorWithCalibratedWhite:0.22 alpha:1.0] set];
  [[NSBezierPath bezierPathWithRoundedRect:rect xRadius:4.0 yRadius:4.0] fill];
  [arrow moveToPoint:a];
  [arrow lineToPoint:tip];
  [arrow lineToPoint:b];
  [arrow closePath];
  [arrow fill];
  [title drawInRect:NSInsetRect(rect, 7.0, 4.0)
    withAttributes:[self tooltipTextAttributes]];
}


- (void) showTooltip: (NSTimer *)timer
{
  DESTROY(_tooltipTimer);

  if (_hoveredItemIndex != DockHoverNone)
    {
      _tooltipItemIndex = _hoveredItemIndex;
      [self setNeedsDisplay:YES];
    }
}


@end
