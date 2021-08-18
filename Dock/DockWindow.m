/*
   Project: Dock

   Copyright (C) 2021 Free Software Foundation

   Author: Gregory John Casamento,,,

   Created: 2021-08-18 00:01:18 -0400 by heron

   This application is free software; you can redistribute it and/or
   modify it under the terms of the GNU General Public
   License as published by the Free Software Foundation; either
   version 2 of the License, or (at your option) any later version.

   This application is distributed in the hope that it will be useful,
   but WITHOUT ANY WARRANTY; without even the implied warranty of
   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
   Library General Public License for more details.

   You should have received a copy of the GNU General Public
   License along with this library; if not, write to the Free
   Software Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA 02111 USA.
*/

#import "DockWindow.h"
#import <AppKit/NSScreen.h>
#import <AppKit/NSWindow.h>

@implementation DockWindow

- (instancetype) initWithContentRect: (NSRect)r
                           styleMask: (NSUInteger)styleMask
                             backing: (NSBackingStoreType)b
                               defer: (BOOL)flag
{
  NSScreen *s = [NSScreen mainScreen];
  NSRect f = [s frame];
  CGFloat screen_height = f.size.height;
  CGFloat screen_width = f.size.width;
  CGFloat w = 64.0, h = screen_height;
  CGFloat x = screen_width - 64.0;
  CGFloat y = screen_height;

  _dockRect = NSMakeRect(x,y,w,h);
  
  NSLog(@"_dockRect = %@", NSStringFromRect(_dockRect));
  id d = [super initWithContentRect: _dockRect
                          styleMask: NSWindowStyleMaskBorderless 
                            backing: b
                              defer: flag];
  NSLog(@"d = %@", d);
  return d;
}

@end
