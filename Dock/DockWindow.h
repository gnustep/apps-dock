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

#ifndef _DOCKWINDOW_H_
#define _DOCKWINDOW_H_

#import <Foundation/Foundation.h>
#import <AppKit/NSWindow.h>

@interface DockWindow : NSWindow
{
  NSRect _dockRect;
}

- (instancetype) init
{
  return [super initWothContentRect: _dockRect
                          styleMask: NSWindowStyleMaskBorderless 
                            backing: NSBackintStoreBuffered
                              defer: NO
                             screen: [NSScreen mainScreen]];
}

@end

#endif // _DOCKWINDOW_H_

