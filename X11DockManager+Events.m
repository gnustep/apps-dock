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

#import "X11DockManagerPrivate.h"

@implementation X11DockManager (Events)

- (void) processPendingEvents
{
  Display *display = (Display *)_display;
  NSMutableSet *eventWindows = nil;
  NSMutableSet *iconEventWindows = nil;
  BOOL sawRelevantEvent = NO;
  unsigned int processedEvents = 0;
  const unsigned int maxEventsPerTick = 256;
  const NSUInteger maxWindowsPerTick = 32;
  NSTimeInterval now;

  if (!display)
    {
      return;
    }

  /* A continuation may have been queued by the preceding batch. The regular
   * timer or transient-icon drain can get here first; keep only one pending. */
  [NSObject cancelPreviousPerformRequestsWithTarget:self
    selector:@selector(processPendingEvents) object:nil];

  while (processedEvents < maxEventsPerTick &&
         [eventWindows count] + [iconEventWindows count] < maxWindowsPerTick &&
         XPending(display) > 0)
    {
      XEvent event;

      XNextEvent(display, &event);
      processedEvents++;
      switch (event.type)
	{
	case CreateNotify:
	    {
	      if (!iconEventWindows)
		{
		  iconEventWindows = [NSMutableSet set];
		}
	      [iconEventWindows addObject:
				  [NSNumber numberWithUnsignedLong:
					      (unsigned long)event.xcreatewindow.window]];
	    }
	  sawRelevantEvent = YES;
	  break;
	case MapNotify:
	  if (!eventWindows)
	    {
	      eventWindows = [NSMutableSet set];
	    }
	  [eventWindows addObject:
			  [NSNumber numberWithUnsignedLong:
				      (unsigned long)event.xmap.window]];
	  sawRelevantEvent = YES;
	  break;
	case MapRequest:
	  if (!eventWindows)
	    {
	      eventWindows = [NSMutableSet set];
	    }
	  [eventWindows addObject:
			  [NSNumber numberWithUnsignedLong:
				      (unsigned long)event.xmaprequest.window]];
	  sawRelevantEvent = YES;
	  break;
        case DestroyNotify:
          {
            NSNumber *key = [NSNumber numberWithUnsignedLong:event.xdestroywindow.window];
            [_knownWindows removeObject:key];
            [_dockAppWindows removeObject:key];
            [self removeWindow:(unsigned int)event.xdestroywindow.window];
            if ([_dockedWindowFrames objectForKey:key])
              {
                [_dockedWindowFrames removeObjectForKey:key];
                [self updateHostWindowShape];
              }
            _scanPending = YES;
          }
          break;
        case ReparentNotify:
          if (event.xreparent.parent != (Window)_hostWindow)
            {
              NSNumber *key = [NSNumber numberWithUnsignedLong:event.xreparent.window];
              if ([_dockedWindowFrames objectForKey:key])
                {
                  [_dockedWindowFrames removeObjectForKey:key];
                  [self updateHostWindowShape];
                }
            }
          break;
        case ConfigureNotify:
          {
            NSNumber *key = [NSNumber numberWithUnsignedLong:event.xconfigure.window];
            NSValue *frame = [_dockedWindowFrames objectForKey:key];
            if (frame && !NSEqualRects([frame rectValue],
                NSMakeRect(event.xconfigure.x, event.xconfigure.y,
                           event.xconfigure.width, event.xconfigure.height)))
              {
                /* Earlier configure events may precede our latest resize. */
                XWindowAttributes attr;
                if (!XGetWindowAttributes(display, event.xconfigure.window, &attr) ||
                    !NSEqualRects([frame rectValue],
                                  NSMakeRect(attr.x, attr.y, attr.width, attr.height)))
                  {
                    [_dockedWindowFrames removeObjectForKey:key];
                    [self updateHostWindowShape];
                  }
              }
          }
          break;
        case UnmapNotify:
          {
            NSNumber *key = [NSNumber numberWithUnsignedLong:event.xunmap.window];
            if ([_dockedWindowFrames objectForKey:key])
              {
                XWindowAttributes attr;
                /* Reparenting emits a temporary unmap followed by a map. */
                if (!XGetWindowAttributes(display, event.xunmap.window, &attr) ||
                    attr.map_state == IsUnmapped)
                  {
                    [_dockedWindowFrames removeObjectForKey:key];
                    [self updateHostWindowShape];
                  }
              }
            _scanPending = YES;
          }
          break;
        case PropertyNotify:
          if (event.xproperty.window == DefaultRootWindow(display) &&
              event.xproperty.atom == XInternAtom(display, "_NET_CLIENT_LIST", False))
            _scanPending = YES;
          break;
	default:
	  break;
	}
    }

  if ([eventWindows count] > 0)
    {
      NSArray *windows = [eventWindows allObjects];
      NSUInteger i;

      for (i = 0; i < [windows count]; i++)
	{
	  Window window =
	    (Window)[[windows objectAtIndex:i] unsignedLongValue];

	  [self handlePossiblyNewWindow:window];
	  [self scanClientWindow:window];
	}
    }

  if ([iconEventWindows count] > 0)
    {
      NSArray *windows = [iconEventWindows allObjects];
      NSUInteger i;

      for (i = 0; i < [windows count]; i++)
	{
	  Window window =
	    (Window)[[windows objectAtIndex:i] unsignedLongValue];

	  [self handlePossiblyNewWindow:window];
	}
    }

  now = [NSDate timeIntervalSinceReferenceDate];
  if (_scanPending && XPending(display) == 0 &&
      now - _lastEventScanTime >= X11DockManagerEventScanInterval)
    {
      _scanPending = NO;
      _lastEventScanTime = now;
      [self scanForDockApps];
    }

  if (sawRelevantEvent)
    {
      XFlush(display);
    }

  /* Drain bursts promptly in bounded batches, yielding to the UI between
   * batches. Queue pressure alone is not a reason to scan every window. */
  if (XPending(display) > 0)
    [self performSelector:@selector(processPendingEvents)
               withObject:nil afterDelay:0.001];
}


- (void) drainTransientIconEvents
{
  Display *display = (Display *)_display;
  unsigned int i;

  if (!display)
    {
      return;
    }

  for (i = 0; i < 12; i++)
    {
      [self processPendingEvents];
      XSync(display, False);
      usleep(1000);
    }
}


- (void) handlePossiblyNewWindow: (Window)window
{
  Display *display = (Display *)_display;
  int processIdentifier;
  NSString *title;

  if (!display || window == (Window)_hostWindow)
    {
      return;
    }

  if ([self windowIsWindowMakerApplicationIcon:window])
    {
      [self unmapIconWindow:window];
      return;
    }
  if ([self windowHasGNUstepMiniWindowStyle:window])
    {
      if (_hidesMiniwindows)
        {
          [self unmapIconWindow:window];
        }
      return;
    }
  if ([self windowIsGNUstepIconOrMiniWindow:window])
    {
      processIdentifier = [self processIdentifierForWindow:window];
      title = [self classNameForWindow:window];
      [self rememberApplicationIconWindow:window
                       processIdentifier:processIdentifier
                                   title:title];
      [self unmapIconWindow:window];
      return;
    }
}


@end
