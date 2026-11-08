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

@implementation DockView (Menus)

- (NSMenuItem *) menuItemWithTitle: (NSString *)title
                            action: (SEL)action
                              item: (DockItem *)item
{
  NSMenuItem *menuItem;

  menuItem = AUTORELEASE([[NSMenuItem alloc] initWithTitle:title
						    action:action
					     keyEquivalent:@""]);
  [menuItem setTarget:self];
  [menuItem setRepresentedObject:item];
  return menuItem;
}


- (NSMenu *) menuForDockItem: (DockItem *)item
{
  NSMenu *menu = AUTORELEASE([[NSMenu alloc] initWithTitle:@"Application"]);
  NSMenuItem *menuItem;
  BOOL hasPath = [[item path] length] > 0;
  BOOL openAtLogin = NO;
  BOOL canShowSettings = NO;

  if ([_delegate respondsToSelector:
		 @selector(dockView:itemIsOpenAtLogin:)])
    {
      openAtLogin = [_delegate dockView:self itemIsOpenAtLogin:item];
    }
  if ([_delegate respondsToSelector:
		 @selector(dockView:canShowSettingsForItem:)])
    {
      canShowSettings = [_delegate dockView:self canShowSettingsForItem:item];
    }

  if ([item kind] == DockItemApplication && canShowSettings)
    {
      menuItem = [self menuItemWithTitle:@"Settings..."
				  action:@selector(showItemSettings:)
				    item:item];
      [menu addItem:menuItem];
      [menu addItem:[NSMenuItem separatorItem]];
    }

  menuItem = [self menuItemWithTitle:@"Keep In Dock"
                              action:@selector(toggleKeepInDock:)
                                item:item];
  [menuItem setState:([_delegate respondsToSelector:
                                @selector(dockView:itemIsKeptInDock:)] &&
                      ![_delegate dockView:self itemIsKeptInDock:item])
                     ? NSOffState : NSOnState];
  [menuItem setEnabled:hasPath];
  [menu addItem:menuItem];

  menuItem = [self menuItemWithTitle:@"Open At Login"
                              action:@selector(toggleOpenAtLogin:)
                                item:item];
  [menuItem setState: (openAtLogin ? NSOnState : NSOffState)];
  [menuItem setEnabled:hasPath];
  [menu addItem:menuItem];

  menuItem = [self menuItemWithTitle:@"Show In File Viewer"
                              action:@selector(showItemInFileViewer:)
                                item:item];
  [menuItem setEnabled:hasPath];
  [menu addItem:menuItem];

  {
    NSArray *windows = nil;
    NSMutableArray *identifiers = [NSMutableArray array];
    NSUInteger i;
    NSMenu *restoreMenu = AUTORELEASE([[NSMenu alloc] initWithTitle:@"Restore"]);

    [restoreMenu setAutoenablesItems:NO];
    if ([_delegate respondsToSelector:@selector(dockView:minimizedWindowsForItem:)])
      windows = [_delegate dockView:self minimizedWindowsForItem:item];
    for (i = 0; i < [windows count]; i++)
      {
        NSDictionary *window = [windows objectAtIndex:i];
        NSNumber *identifier = [window objectForKey:@"window"];
        [identifiers addObject:identifier];
        menuItem = [self menuItemWithTitle:[window objectForKey:@"title"]
                                  action:@selector(restoreItem:) item:item];
        [menuItem setRepresentedObject:[NSDictionary dictionaryWithObjectsAndKeys:
          item, @"item", [NSArray arrayWithObject:identifier], @"windows", nil]];
        [restoreMenu addItem:menuItem];
      }
    menuItem = [self menuItemWithTitle:@"Restore" action:@selector(restoreItem:) item:item];
    [menuItem setRepresentedObject:[NSDictionary dictionaryWithObjectsAndKeys:
      item, @"item", identifiers, @"windows", nil]];
    [menuItem setEnabled:([identifiers count] > 0 ||
      ([_delegate respondsToSelector:@selector(dockView:canRestoreItem:)] &&
       [_delegate dockView:self canRestoreItem:item]))];
    if ([identifiers count] > 1)
      {
        NSMenuItem *restoreAll = [self menuItemWithTitle:@"Restore All"
                                            action:@selector(restoreItem:) item:item];
        [restoreAll setRepresentedObject:[menuItem representedObject]];
        [restoreMenu addItem:[NSMenuItem separatorItem]];
        [restoreMenu addItem:restoreAll];
        [menuItem setSubmenu:restoreMenu];
      }
    [menu addItem:menuItem];
  }

  menuItem = [self menuItemWithTitle:@"Quit"
                              action:@selector(quitItem:)
                                item:item];
  [menu addItem:menuItem];

  return menu;
}


- (NSMenu *) menuForRecycler
{
  NSMenu *menu = AUTORELEASE([[NSMenu alloc] initWithTitle:@"Recycler"]);
  NSMenuItem *menuItem;

  menuItem = AUTORELEASE([[NSMenuItem alloc] initWithTitle:@"Empty Recycler"
                                                    action:@selector(emptyRecycler:)
                                             keyEquivalent:@""]);
  [menuItem setTarget:self];
  [menu addItem:menuItem];
  return menu;
}


- (void) toggleKeepInDock: (id)sender
{
  if ([_delegate respondsToSelector:
                 @selector(dockView:didToggleKeepInDockForItem:)])
    {
      [_delegate dockView:self
          didToggleKeepInDockForItem:[sender representedObject]];
    }
}

- (void) toggleOpenAtLogin: (id)sender
{
  DockItem *item = [sender representedObject];

  if ([_delegate respondsToSelector:
		 @selector(dockView:didToggleOpenAtLoginForItem:)])
    {
      [_delegate dockView:self didToggleOpenAtLoginForItem:item];
    }
}


- (void) showItemInFileViewer: (id)sender
{
  DockItem *item = [sender representedObject];

  if ([_delegate respondsToSelector:
		 @selector(dockView:didShowItemInFileViewer:)])
    {
      [_delegate dockView:self didShowItemInFileViewer:item];
    }
}


- (void) showItemSettings: (id)sender
{
  DockItem *item = [sender representedObject];

  if ([_delegate respondsToSelector:
		 @selector(dockView:didShowSettingsForItem:)])
    {
      [_delegate dockView:self didShowSettingsForItem:item];
    }
}


- (BOOL) validateMenuItem: (id<NSMenuItem>)menuItem
{
  if ([menuItem action] == @selector(restoreItem:))
    {
      NSDictionary *selection = [menuItem representedObject];
      return [[selection objectForKey:@"windows"] count] > 0 ||
        ([_delegate respondsToSelector:@selector(dockView:canRestoreItem:)] &&
         [_delegate dockView:self canRestoreItem:[selection objectForKey:@"item"]]);
    }
  return [menuItem isEnabled];
}


- (void) restoreItem: (id)sender
{
  NSDictionary *selection = [sender representedObject];

  if ([_delegate respondsToSelector:@selector(dockView:restoreWindows:forItem:)])
    {
      [_delegate dockView:self restoreWindows:[selection objectForKey:@"windows"]
                 forItem:[selection objectForKey:@"item"]];
    }
}


- (void) quitItem: (id)sender
{
  DockItem *item = [sender representedObject];

  if ([_delegate respondsToSelector:@selector(dockView:didQuitItem:)])
    {
      [_delegate dockView:self didQuitItem:item];
    }
}


- (void) emptyRecycler: (id)sender
{
  if ([_delegate respondsToSelector:@selector(dockViewDidEmptyRecycler:)])
    {
      [_delegate dockViewDidEmptyRecycler:self];
    }
}


@end
