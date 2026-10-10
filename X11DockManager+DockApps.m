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

@implementation X11DockManager (DockApps)

- (id) iconIdentifierForProcessIdentifier: (int)processIdentifier
                                    title: (NSString *)title
{
  if (processIdentifier > 0)
    {
      return [NSNumber numberWithInt:processIdentifier];
    }
  if ([title length])
    {
      return [title lowercaseString];
    }
  return nil;
}


- (BOOL) windowIsDockAppIconChild: (Window)window
{
  Display *display = (Display *)_display;
  Window root;
  Window parent;
  Window *children = NULL;
  unsigned int childCount = 0;
  BOOL result = NO;

  if (!display || window == (Window)_hostWindow)
    {
      return NO;
    }

  [self clearX11Error];
  if (XQueryTree(display, window, &root, &parent, &children, &childCount) &&
      ![self x11ErrorOccurred])
    {
      result = parent != None && parent != root &&
	[self windowHasDockAppClass:parent];
    }
  if (children)
    {
      XFree(children);
    }

  return result;
}


- (BOOL) windowLooksLikeWindowMakerDockApp: (Window)window
{
  Display *display = (Display *)_display;
  XWindowAttributes attr;
  Window dockWindow;
  NSString *title;

  dockWindow = [self dockAppIconWindowForWindow:window];
  if (dockWindow == None)
    {
      return NO;
    }
  if (![self windowHasDockAppClass:window] &&
      ![self windowIsDockAppIconChild:window])
    {
      return NO;
    }

  [self clearX11Error];
  if (!XGetWindowAttributes(display, dockWindow, &attr) ||
      [self x11ErrorOccurred])
    {
      return NO;
    }

  if (attr.map_state != IsViewable &&
      ![self windowHasDockAppClass:window] &&
      ![self windowIsDockAppIconChild:window])
    {
      return NO;
    }
  if ([self windowHasTransientForHint:window])
    {
      return NO;
    }
  if ([self windowHasIgnoredWindowType:window])
    {
      return NO;
    }

  title = [self titleForWindow:window];
  if ([title length] || [self processIdentifierForWindow:window] > 0)
    {
      return YES;
    }

  return NO;
}


- (void) unmapIconWindow: (Window)window
{
  Display *display = (Display *)_display;
  XWindowAttributes attr;

  /* Suppress only windows explicitly marked as icons by their producer. */
  if (!display || window == (Window)_hostWindow ||
      (![self windowIsGNUstepIconOrMiniWindow:window] &&
       ![self windowIsWindowMakerApplicationIcon:window]) ||
      ([self windowHasGNUstepMiniWindowStyle:window] && !_hidesMiniwindows))
    {
      return;
    }

  [self clearX11Error];
  if (!XGetWindowAttributes(display, window, &attr) ||
      [self x11ErrorOccurred] || attr.map_state == IsUnmapped)
    {
      return;
    }

  /* A parent frame is not the icon and may contain other clients. */
  XUnmapWindow(display, window);
  XFlush(display);
}


- (void) suppressMiniwindowsUnderWindow: (Window)parent
{
  Display *display = (Display *)_display;
  Window root, ancestor, *children = NULL;
  unsigned int count = 0, i;

  /* Miniwindows can live inside WM frames and be absent from the client list. */
  if (XQueryTree(display, parent, &root, &ancestor, &children, &count))
    {
      for (i = 0; i < count; i++)
        {
          if ([self windowHasGNUstepMiniWindowStyle:children[i]])
            {
              [self unmapIconWindow:children[i]];
            }
          else if (children[i] != (Window)_hostWindow)
            {
              [self suppressMiniwindowsUnderWindow:children[i]];
            }
        }
    }
  if (children) XFree(children);
}

/* Find the owning document, including withdrawn clients outside _NET_CLIENT_LIST.
 * Do not resurrect a miniwindow whose document has since been restored/closed. */
- (BOOL) miniwindowHasMinimizedOwner: (Window)miniwindow under: (Window)parent
{
  Display *display = (Display *)_display;
  Window root, ancestor, *children = NULL;
  unsigned int count = 0, i;
  BOOL found = NO;

  [self clearX11Error];
  if (!XQueryTree(display, parent, &root, &ancestor, &children, &count) ||
      [self x11ErrorOccurred])
    {
      if (children) XFree(children);
      return NO;
    }
  for (i = 0; i < count && !found; i++)
    {
      XWMHints *hints = XGetWMHints(display, children[i]);
      if (hints)
        {
          if ((hints->flags & IconWindowHint) &&
              hints->icon_window == miniwindow && children[i] != miniwindow)
            {
              XWindowAttributes attr;
              long state = WithdrawnState;
              [self wmStateForWindow:children[i] state:&state];
              found = XGetWindowAttributes(display, children[i], &attr) &&
                attr.map_state != IsViewable && state != NormalState;
            }
          XFree(hints);
        }
      if (!found)
        {
          found = [self miniwindowHasMinimizedOwner:miniwindow under:children[i]];
        }
    }
  if (children) XFree(children);
  return found;
}

- (BOOL) restoreMiniwindowsUnderWindow: (Window)window
{
  Display *display = (Display *)_display;
  Window root, parent, *children = NULL;
  unsigned int count = 0, i;
  BOOL restored = NO;

  if (window == (Window)_hostWindow)
    return NO;

  if ([self windowHasGNUstepMiniWindowStyle:window])
    {
      restored = [self miniwindowHasMinimizedOwner:window
                                             under:DefaultRootWindow(display)];
    }
  else if (XQueryTree(display, window, &root, &parent, &children, &count))
    {
      for (i = 0; i < count; i++)
        {
          if ([self restoreMiniwindowsUnderWindow:children[i]])
            restored = YES;
        }
    }
  if (children) XFree(children);

  /* Map the icon and its current ancestors, not a possibly obsolete WM frame.
   * Walking the tree also recovers icons hidden by an earlier DockWM session. */
  if (restored && window != DefaultRootWindow(display))
    XMapWindow(display, window);
  return restored;
}

- (void) restoreSuppressedMiniwindows
{
  Display *display = (Display *)_display;
  [self restoreMiniwindowsUnderWindow:DefaultRootWindow(display)];
  XFlush(display);
}

- (void) hideApplicationIconWindow: (Window)window
{
  [self unmapIconWindow:window];
}


- (BOOL) windowIsKnownDockAppWindow: (Window)window
{
  return [_dockAppWindows containsObject:
			    [NSNumber numberWithUnsignedLong:(unsigned long)window]];
}


- (BOOL) windowHasDockAppClass: (Window)window
{
  Display *display = (Display *)_display;
  XClassHint hint;
  BOOL dockApp = NO;

  [self clearX11Error];
  if (XGetClassHint(display, window, &hint) && ![self x11ErrorOccurred])
    {
      if ((hint.res_class && strcasecmp(hint.res_class, "DockApp") == 0) ||
	  (hint.res_name && strcasecmp(hint.res_name, "DockApp") == 0))
	{
	  dockApp = YES;
	}
      if (hint.res_name)
	{
	  XFree(hint.res_name);
	}
      if (hint.res_class)
	{
	  XFree(hint.res_class);
	}
    }

  return dockApp;
}


- (Window) dockAppIconWindowForWindow: (Window)window
{
  Display *display = (Display *)_display;
  XWMHints *hints;
  Window iconWindow = None;

  if (!display || window == (Window)_hostWindow)
    {
      return None;
    }

  [self clearX11Error];
  hints = XGetWMHints(display, window);
  if (![self x11ErrorOccurred] && hints)
    {
      if ((hints->flags & IconWindowHint) && hints->icon_window != None)
	{
	  iconWindow = hints->icon_window;
	}
      XFree(hints);
    }
  else if (hints)
    {
      XFree(hints);
    }

  if (iconWindow != None)
    {
      return iconWindow;
    }

  if ([self windowHasDockAppClass:window] ||
      [self windowIsDockAppIconChild:window])
    {
      return window;
    }

  return None;
}


- (BOOL) rememberApplicationIconWindow: (Window)window
                     processIdentifier: (int)processIdentifier
                                 title: (NSString *)title
{
  id identifier;
  NSNumber *windowKey;
  XWindowAttributes attr;

  if (window == (Window)_hostWindow)
    {
      return NO;
    }
  identifier = [self iconIdentifierForProcessIdentifier:processIdentifier
                                                  title:title];
  if (!identifier)
    {
      return NO;
    }
  if ([self windowHasGNUstepMiniWindowStyle:window] ||
      ![self windowHasGNUstepIconStyle:window])
    {
      return NO;
    }

  [self clearX11Error];
  if (!XGetWindowAttributes((Display *)_display, window, &attr) ||
      [self x11ErrorOccurred])
    {
      return NO;
    }

  windowKey = [NSNumber numberWithUnsignedLong:(unsigned long)window];
  if (!attr.override_redirect &&
      [[self clientListWindows] containsObject:windowKey])
    {
      return NO;
    }

  if ([_iconWindowsByProcessID objectForKey:identifier] &&
      ![[_iconWindowsByProcessID objectForKey:identifier] isEqual:windowKey])
    {
      return NO;
    }
  [_iconWindowsByProcessID setObject:windowKey forKey:identifier];
  [_knownWindows removeObject:windowKey];

  [self hideApplicationIconWindow:window];

  return YES;
}


- (void) discoverApplicationIconWindows: (Window *)children
                                  count: (unsigned int)count
{
  unsigned int i;

  for (i = 0; i < count; i++)
    {
      int pid;
      NSString *title;

      if ([self windowIsRegisteredIconWindow:children[i]])
	{
	  continue;
	}
      if (![self windowHasGNUstepIconStyle:children[i]])
	{
	  continue;
	}

      pid = [self processIdentifierForWindow:children[i]];
      title = [self classNameForWindow:children[i]];

      [self rememberApplicationIconWindow:children[i]
			processIdentifier:pid
				    title:title];
    }

  for (i = 0; i < count; i++)
    {
      XWMHints *hints;

      [self clearX11Error];
      hints = XGetWMHints((Display *)_display, children[i]);
      if ([self x11ErrorOccurred])
	{
	  if (hints)
	    {
	      XFree(hints);
	    }
	  continue;
	}
      if (hints)
	{
	  if ((hints->flags & IconWindowHint) && hints->icon_window != None)
	    {
	      int pid = [self processIdentifierForWindow:children[i]];
	      NSString *title = [self classNameForWindow:children[i]];

	      [self rememberApplicationIconWindow:hints->icon_window
				processIdentifier:pid
					    title:title];
	    }
	  XFree(hints);
	}
    }
}


- (void) scanApplicationIconWindows
{
  NSArray *iconKeys = [_iconWindowsByProcessID allKeys];
  NSUInteger i;

  for (i = 0; i < [iconKeys count]; i++)
    {
      id iconKey = [iconKeys objectAtIndex:i];
      NSNumber *windowKey = [_iconWindowsByProcessID objectForKey:iconKey];
      Window window = (Window)[windowKey unsignedLongValue];
      XWindowAttributes attr;
      [self clearX11Error];
      if (!XGetWindowAttributes((Display *)_display, window, &attr) ||
	  [self x11ErrorOccurred])
	{
	  [_iconWindowsByProcessID removeObjectForKey:iconKey];
	  [_iconImageDataByProcessID removeObjectForKey:iconKey];
	  continue;
	}
    }
}


- (void) scanClientWindow: (Window)window
{
  NSNumber *key = [NSNumber numberWithUnsignedLong:(unsigned long)window];
  Window reportedWindow = window;
  BOOL dockApp;
  BOOL hidden;
  NSString *title;
  NSString *path;

  if ([_knownWindows containsObject:key])
    {
      return;
    }
  if (![self windowLooksManageable:window])
    {
      return;
    }
  if ([self windowHasIgnoredWindowType:window])
    {
      return;
    }

  dockApp = [self windowLooksLikeDockApp:window];
  if (dockApp)
    {
      Window iconWindow = [self dockAppIconWindowForWindow:window];

      if (iconWindow != None)
	{
	  reportedWindow = iconWindow;
	  [_dockAppWindows addObject:
			     [NSNumber numberWithUnsignedLong:
					       (unsigned long)reportedWindow]];
	}
  }
  hidden = [self windowIsHidden:window];
  title = [self titleForWindow:window];
  path = [self executablePathForWindow:window];

  if (!dockApp && ![title length] && ![path length])
    {
      return;
    }

  if ([self windowShouldBeIgnoredWithTitle:title path:path])
    {
      if (dockApp)
	{
	  [_knownWindows addObject:key];
	  if ([_delegate respondsToSelector:
			   @selector(x11DockManagerDidDiscoverWindowWithTitle:window:hidden:icon:path:dockApp:)])
	    {
	      [_delegate x11DockManagerDidDiscoverWindowWithTitle:title
							   window:(unsigned long)reportedWindow
							   hidden:YES
							     icon:[self iconForWindow:reportedWindow]
							     path:path
							  dockApp:dockApp];
	    }
	}
      return;
    }

  [_knownWindows addObject:key];
  if ([_delegate respondsToSelector:
		   @selector(x11DockManagerDidDiscoverWindowWithTitle:window:hidden:icon:path:dockApp:)])
    {
      [_delegate x11DockManagerDidDiscoverWindowWithTitle:title
						   window:(unsigned long)reportedWindow
						   hidden:hidden
						     icon:[self iconForWindow:reportedWindow]
						     path:path
						  dockApp:dockApp];
    }
}


/* Snapshot once, then yield between small batches of synchronous X queries.
 * Keep icon discovery ahead of client classification, as in the full scan. */
- (void) scanForDockApps
{
  Display *display = (Display *)_display;
  Window root, parent, *children = NULL;
  unsigned int count = 0, i;
  NSMutableArray *windows;
  NSMutableSet *seen;
  NSArray *additionalWindows;

  if (!display) return;
  if (_scanWindows != nil)
    {
      /* Coalesce a refresh requested during a scan; never restart its cursor. */
      _scanPending = YES;
      return;
    }
  _scanPending = NO;
  _lastEventScanTime = [NSDate timeIntervalSinceReferenceDate];
  [self scanApplicationIconWindows];
  windows = [NSMutableArray array];
  seen = [NSMutableSet set];
  root = RootWindow(display, DefaultScreen(display));
  if (XQueryTree(display, root, &root, &parent, &children, &count))
    {
      for (i = 0; i < count; i++)
        {
          NSNumber *key = [NSNumber numberWithUnsignedLong:children[i]];
          [windows addObject:key];
          [seen addObject:key];
        }
    }
  if (children) XFree(children);
  _scanIconWindowCount = [windows count];
  additionalWindows = [[self clientListWindows]
    arrayByAddingObjectsFromArray:[_knownWindows allObjects]];
  for (i = 0; i < [additionalWindows count]; i++)
    {
      id key = [additionalWindows objectAtIndex:i];
      if (![seen containsObject:key])
        {
          [windows addObject:key];
          [seen addObject:key];
        }
    }
  _scanWindows = [windows copy];
  _scanWindowIndex = 0;
  _scanDiscoveringIcons = YES;
  [self continueWindowScan];
}

- (void) continueWindowScan
{
  NSUInteger processed = 0;
  NSTimeInterval deadline = [NSDate timeIntervalSinceReferenceDate] + 0.008;

  [NSObject cancelPreviousPerformRequestsWithTarget:self
    selector:@selector(continueWindowScan) object:nil];
  if (_scanWindows == nil) return;

  /* The time limit is checked between windows: an individual X server reply
   * can still take longer. The count limit also bounds work on fast servers. */
  while (processed < 8)
    {
      NSUInteger count = _scanDiscoveringIcons
        ? _scanIconWindowCount : [_scanWindows count];
      if (_scanWindowIndex >= count)
        {
          if (_scanDiscoveringIcons)
            {
              _scanDiscoveringIcons = NO;
              _scanWindowIndex = 0;
              continue;
            }
          DESTROY(_scanWindows);
          _lastEventScanTime = [NSDate timeIntervalSinceReferenceDate];
          return;
        }
      NSNumber *key = [_scanWindows objectAtIndex:_scanWindowIndex++];
      Window window = (Window)[key unsignedLongValue];
      if (_scanDiscoveringIcons)
        [self discoverApplicationIconWindows:&window count:1];
      else
        {
          if ([_knownWindows containsObject:key])
            [self scanKnownWindow:window];
          if (![_knownWindows containsObject:key])
            [self scanClientWindow:window];
        }
      processed++;
      if ([NSDate timeIntervalSinceReferenceDate] >= deadline) break;
    }
  [self performSelector:@selector(continueWindowScan)
             withObject:nil afterDelay:0.001];
}

@end
