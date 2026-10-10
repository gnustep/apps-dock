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

static Window WindowProperty(Display *display, Window window, Atom property)
{
  Atom type;
  int format;
  unsigned long count, remaining;
  unsigned char *data = NULL;
  Window value = None;

  if (XGetWindowProperty(display, window, property, 0, 1, False, XA_WINDOW,
        &type, &format, &count, &remaining, &data) == Success && data &&
      type == XA_WINDOW && format == 32 && count == 1 && remaining == 0)
    value = ((Window *)data)[0];
  if (data) XFree(data);
  return value;
}

@implementation X11DockManager (WindowFiltering)

- (BOOL) windowIsRegisteredIconWindow: (Window)window
{
  return [[_iconWindowsByProcessID allValues]
	   containsObject:[NSNumber numberWithUnsignedLong:(unsigned long)window]];
}


- (BOOL) windowHasGNUstepStyleMask: (unsigned long)styleMask
                             window: (Window)window
{
  Display *display = (Display *)_display;
  Atom property = XInternAtom(display, "_GNUSTEP_WM_ATTR", False);
  Atom actualType;
  int actualFormat;
  unsigned long itemCount;
  unsigned long bytesAfter;
  unsigned char *data = NULL;
  BOOL result = NO;

  [self clearX11Error];
  if (XGetWindowProperty(display, window, property, 0,
                         2,
                         False, property, &actualType, &actualFormat,
                         &itemCount, &bytesAfter, &data) == Success && data)
    {
      if (![self x11ErrorOccurred] &&
	  actualFormat == 32 &&
	  itemCount >= 2)
	{
	  unsigned long *attrs = (unsigned long *)data;

	  if ((attrs[0] & DockGSWindowStyleAttr) &&
	      (attrs[1] & styleMask))
	    {
	      result = YES;
	    }
	}
      XFree(data);
    }

  return result;
}


- (BOOL) windowHasGNUstepIconStyle: (Window)window
{
  return [self windowHasGNUstepStyleMask:DockNSIconWindowMask
                                  window:window];
}


- (BOOL) windowHasGNUstepMiniWindowStyle: (Window)window
{
  return [self windowHasGNUstepStyleMask:DockNSMiniWindowMask
                                  window:window];
}


- (BOOL) windowIsGNUstepMainMenu: (Window)window
{
  Display *display = (Display *)_display;
  Atom property = XInternAtom(display, "_GNUSTEP_WM_ATTR", False);
  Atom dockType = XInternAtom(display, "_NET_WM_WINDOW_TYPE_DOCK", False);
  Atom windowType = XInternAtom(display, "_NET_WM_WINDOW_TYPE", False);
  Atom actualType;
  int actualFormat;
  unsigned long itemCount;
  unsigned long bytesAfter;
  unsigned char *data = NULL;
  BOOL isMenu = NO;

  [self clearX11Error];
  if (XGetWindowProperty(display, window, property, 0, 2, False, property,
                         &actualType, &actualFormat, &itemCount, &bytesAfter,
                         &data) == Success && data)
    {
      if (![self x11ErrorOccurred] && actualFormat == 32 && itemCount >= 2)
        {
          unsigned long *attrs = (unsigned long *)data;
          isMenu = (attrs[0] & DockGSWindowStyleAttr) && attrs[1] == 0;
        }
      XFree(data);
    }
  if (!isMenu)
    {
      return NO;
    }

  data = NULL;
  [self clearX11Error];
  if (XGetWindowProperty(display, window, windowType, 0, 8, False, XA_ATOM,
                         &actualType, &actualFormat, &itemCount, &bytesAfter,
                         &data) == Success && data)
    {
      unsigned long i;
      isMenu = NO;
      if (![self x11ErrorOccurred] && actualFormat == 32)
        {
          Atom *types = (Atom *)data;
          for (i = 0; i < itemCount; i++)
            {
              if (types[i] == dockType)
                {
                  isMenu = YES;
                  break;
                }
            }
        }
      XFree(data);
    }
  else
    {
      isMenu = NO;
    }

  return isMenu;
}


- (BOOL) windowIsWindowMakerApplicationIcon: (Window)window
{
  Display *display = (Display *)_display;
  Atom type = None;
  int format;
  unsigned long count, remaining;
  unsigned char *data = NULL;
  BOOL result = NO;
  XWindowAttributes attr;
  Window root, parent, noticeboard, *children = NULL;
  unsigned int childCount = 0;
  long iconEvents = SubstructureRedirectMask | ButtonPressMask |
    ButtonReleaseMask | ButtonMotionMask | ExposureMask |
    EnterWindowMask | LeaveWindowMask;

  if (!display || window == (Window)_hostWindow)
    return NO;

  [self clearX11Error];
  if (XGetWindowProperty(display, window,
        XInternAtom(display, "_WINDOWMAKER_APP_ICON", False), 0, 1,
        False, XA_WINDOW, &type, &format, &count, &remaining, &data)
      == Success && data)
    {
      result = ![self x11ErrorOccurred] && type == XA_WINDOW &&
        format == 32 && count == 1 && remaining == 0 &&
        ((Window *)data)[0] != None;
    }
  if (data) XFree(data);
  /* First prefer the producer's explicit application-icon marker. */
  if (result)
    return YES;

  /* Shared exclusions apply to both fallback paths. Never classify a named
   * client or a container of ordinary windows merely from its dimensions. */
  if (!XGetWindowAttributes(display, window, &attr) ||
      !attr.override_redirect || attr.class != InputOutput ||
      [[self classNameForWindow:window] length] ||
      [self windowHasTransientForHint:window] ||
      [self windowHasIgnoredWindowType:window] ||
      [self windowIsGNUstepIconOrMiniWindow:window])
    return NO;

  if (!XQueryTree(display, window, &root, &parent, &children, &childCount))
    return NO;
  result = parent == root;
  for (unsigned int i = 0; i < childCount && result; i++)
    result = [self windowHasGNUstepIconStyle:children[i]] &&
      ![self windowHasGNUstepMiniWindowStyle:children[i]];
  if (children) XFree(children);
  if (!result) return NO;

  /* Second try the legacy attribute signature, independent of size. */
  Atom boardAtom = XInternAtom(display, "_WINDOWMAKER_NOTICEBOARD", False);
  noticeboard = WindowProperty(display, root, boardAtom);
  if (noticeboard != None &&
      WindowProperty(display, noticeboard, boardAtom) == noticeboard &&
      (attr.all_event_masks & iconEvents) == iconEvents)
    {
      data = NULL;
      result = NO;
      if (XGetWindowProperty(display, window,
            XInternAtom(display, "XdndAware", False), 0, 1, False, XA_ATOM,
            &type, &format, &count, &remaining, &data) == Success && data)
        result = type == XA_ATOM && format == 32 && count == 1 && remaining == 0 &&
          ((unsigned long *)data)[0] >= 3 && ((unsigned long *)data)[0] <= 5;
      if (data) XFree(data);
      if (result) return YES;
    }

  /* Only after both attribute matches fail, use the original exact sizes. */
  return (attr.width == 48 && attr.height == 48) ||
    (attr.width == 64 && attr.height == 64);
}


- (BOOL) windowIsGNUstepIconOrMiniWindow: (Window)window
{
  return [self windowHasGNUstepIconStyle:window] ||
    [self windowHasGNUstepMiniWindowStyle:window];
}


- (BOOL) windowHasTransientForHint: (Window)window
{
  Display *display = (Display *)_display;
  Window transientFor = None;

  if (!display)
    {
      return NO;
    }

  [self clearX11Error];
  if (XGetTransientForHint(display, window, &transientFor) &&
      ![self x11ErrorOccurred] &&
      transientFor != None)
    {
      return YES;
    }

  return NO;
}


- (BOOL) windowLooksLikeDockApp: (Window)window
{
  return [self windowIsRegisteredIconWindow:window] ||
    [self windowIsKnownDockAppWindow:window] ||
    [self windowLooksLikeWindowMakerDockApp:window];
}


- (BOOL) windowLooksManageable: (Window)window
{
  Display *display = (Display *)_display;
  XWindowAttributes attr;
  long state = NormalState;
  BOOL dockApp;

  if (window == (Window)_hostWindow)
    {
      return NO;
    }
  if ([self windowIsWindowMakerApplicationIcon:window])
    {
      [self unmapIconWindow:window];
      return NO;
    }
  if ([self windowHasGNUstepMiniWindowStyle:window])
    {
      if (_hidesMiniwindows)
        {
          [self unmapIconWindow:window];
        }
      return NO;
    }
  if ([self windowIsRegisteredIconWindow:window])
    {
      [self unmapIconWindow:window];
      return NO;
    }
  if ([self windowIsGNUstepIconOrMiniWindow:window])
    {
      [self rememberApplicationIconWindow:window
                       processIdentifier:[self processIdentifierForWindow:window]
                                   title:[self classNameForWindow:window]];
      [self unmapIconWindow:window];
      return NO;
    }
  [self clearX11Error];
  if (!XGetWindowAttributes(display, window, &attr))
    {
      return NO;
    }
  if ([self x11ErrorOccurred])
    {
      return NO;
    }
  dockApp = [self windowLooksLikeDockApp:window];
  if ([self wmStateForWindow:window state:&state] && state == WithdrawnState)
    {
      return dockApp;
    }
  if (attr.override_redirect && !dockApp)
    {
      return NO;
    }
  if (attr.map_state != IsViewable &&
      (![self wmStateForWindow:window state:&state] || state != IconicState))
    {
      return NO;
    }
  return YES;
}


- (BOOL) windowHasIgnoredWindowType: (Window)window
{
  Display *display = (Display *)_display;
  Atom property = XInternAtom(display, "_NET_WM_WINDOW_TYPE", False);
  Atom ignoredTypes[8];
  Atom actualType;
  int actualFormat;
  unsigned long itemCount;
  unsigned long bytesAfter;
  unsigned char *data = NULL;
  BOOL ignored = NO;
  unsigned long i;
  unsigned int j;

  ignoredTypes[0] = XInternAtom(display, "_NET_WM_WINDOW_TYPE_DESKTOP", False);
  ignoredTypes[1] = XInternAtom(display, "_NET_WM_WINDOW_TYPE_DOCK", False);
  ignoredTypes[2] = XInternAtom(display, "_NET_WM_WINDOW_TYPE_TOOLBAR", False);
  ignoredTypes[3] = XInternAtom(display, "_NET_WM_WINDOW_TYPE_MENU", False);
  ignoredTypes[4] = XInternAtom(display, "_NET_WM_WINDOW_TYPE_UTILITY", False);
  ignoredTypes[5] = XInternAtom(display, "_NET_WM_WINDOW_TYPE_SPLASH", False);
  ignoredTypes[6] = XInternAtom(display, "_NET_WM_WINDOW_TYPE_DROPDOWN_MENU", False);
  ignoredTypes[7] = XInternAtom(display, "_NET_WM_WINDOW_TYPE_TOOLTIP", False);

  [self clearX11Error];
  if (XGetWindowProperty(display, window, property, 0, 16, False, XA_ATOM,
                         &actualType, &actualFormat, &itemCount, &bytesAfter,
                         &data) == Success && data)
    {
      if (![self x11ErrorOccurred] && actualFormat == 32)
	{
	  unsigned long *types = (unsigned long *)data;

	  for (i = 0; i < itemCount && !ignored; i++)
	    {
	      for (j = 0; j < 8; j++)
		{
		  if (types[i] == ignoredTypes[j])
		    {
		      ignored = YES;
		      break;
		    }
		}
	    }
	}
      XFree(data);
    }

  return ignored;
}


- (NSArray *) clientListWindows
{
  Display *display = (Display *)_display;
  Window root;
  Atom property;
  Atom actualType;
  int actualFormat;
  unsigned long itemCount;
  unsigned long bytesAfter;
  unsigned char *data = NULL;
  NSMutableArray *windows = [NSMutableArray array];
  unsigned long i;

  if (!display)
    {
      return windows;
    }

  root = RootWindow(display, DefaultScreen(display));
  property = XInternAtom(display, "_NET_CLIENT_LIST", False);

  [self clearX11Error];
  if (XGetWindowProperty(display, root, property, 0, 4096, False, XA_WINDOW,
                         &actualType, &actualFormat, &itemCount, &bytesAfter,
                         &data) == Success && data)
    {
      if (![self x11ErrorOccurred] && actualFormat == 32)
	{
	  unsigned long *clientWindows = (unsigned long *)data;

	  for (i = 0; i < itemCount; i++)
	    {
	      [windows addObject:[NSNumber numberWithUnsignedLong:clientWindows[i]]];
	    }
	}
      XFree(data);
    }

  return windows;
}


- (BOOL) knownWindowStillExists: (Window)window
{
  Display *display = (Display *)_display;
  XWindowAttributes attr;
  long state = NormalState;

  if (window == (Window)_hostWindow)
    {
      return NO;
    }
  if ([self windowIsRegisteredIconWindow:window])
    {
      return NO;
    }

  [self clearX11Error];
  if (!XGetWindowAttributes(display, window, &attr))
    {
      return NO;
    }
  if ([self x11ErrorOccurred])
    {
      return NO;
    }
  if ([self wmStateForWindow:window state:&state] && state == WithdrawnState)
    {
      return NO;
    }
  if (attr.override_redirect && ![self windowLooksLikeDockApp:window])
    {
      return NO;
    }
  if (attr.map_state != IsViewable &&
      (![self wmStateForWindow:window state:&state] || state != IconicState))
    {
      return NO;
    }

  return YES;
}


- (BOOL) windowExists: (unsigned long)xWindow
{
  BOOL exists = [self knownWindowStillExists:(Window)xWindow];

  if (!exists &&
      [_dockedWindowFrames objectForKey:
			     [NSNumber numberWithUnsignedLong:xWindow]])
    {
      [_dockedWindowFrames removeObjectForKey:
			     [NSNumber numberWithUnsignedLong:xWindow]];
      [_dockAppWindows removeObject:
			 [NSNumber numberWithUnsignedLong:xWindow]];
      [self updateHostWindowShape];
    }

  return exists;
}


- (BOOL) windowShouldBeIgnoredWithTitle: (NSString *)title path: (NSString *)path
{
  NSString *lowerTitle = [title lowercaseString];
  NSString *lowerName = [[path lastPathComponent] lowercaseString];
  NSArray *pathComponents = [[path lowercaseString] pathComponents];

  if ([lowerTitle isEqualToString:@"gworkspace"] ||
      [lowerTitle isEqualToString:@"dockwm"] ||
      [lowerName isEqualToString:@"gworkspace"] ||
      [lowerName isEqualToString:@"dockwm"] ||
      [pathComponents containsObject:@"gworkspace.app"] ||
      [pathComponents containsObject:@"dockwm.app"])
    {
      return YES;
    }

  if ([lowerTitle rangeOfString:@"drag"].location != NSNotFound &&
      [lowerName isEqualToString:@"gworkspace"])
    {
      return YES;
    }

  return NO;
}


- (void) scanKnownWindow: (Window)window
{
  NSNumber *key = [NSNumber numberWithUnsignedLong:window];

  if (![self knownWindowStillExists:window])
    {
      [_knownWindows removeObject:key];
      return;
    }
  if ([_delegate respondsToSelector:
                   @selector(x11DockManagerDidUpdateWindow:hidden:icon:)])
    {
      [_delegate x11DockManagerDidUpdateWindow:(unsigned long)window
                                      hidden:[self windowIsHidden:window]
                                        icon:nil];
    }
}

- (void) scanKnownWindows
{
  NSArray *windows = [_knownWindows allObjects];
  NSUInteger i;

  for (i = 0; i < [windows count]; i++)
    [self scanKnownWindow:(Window)[[windows objectAtIndex:i] unsignedLongValue]];
}


@end
