/*
 * DockWM
 *
 * Copyright (C) 2026 Gregory Casamento <greg.casamento@gmail.com>
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 */

#import "ApplicationIconManager.h"
#import "DockItem.h"
#import "RunningApplicationScanner.h"
#import <GNUstepBase/GNUstep.h>

@implementation ApplicationIconManager

- (id) initWithScanner: (RunningApplicationScanner *)scanner
{
  self = [super init];
  if (self)
    {
      _scanner = RETAIN(scanner);
      _applicationIconWindowItems = [NSMutableDictionary new];
      _applicationIconUpdatesByProcessID = [NSMutableDictionary new];
    }
  return self;
}

- (void) dealloc
{
  DESTROY(_applicationIconUpdatesByProcessID);
  DESTROY(_applicationIconWindowItems);
  DESTROY(_scanner);
  DEALLOC;
}

- (DockItem *) itemForApplicationIconWindow: (unsigned long)xWindow
{
  return [_applicationIconWindowItems objectForKey:
				       [NSNumber numberWithUnsignedLong:xWindow]];
}

- (void) setApplicationIconWindow: (unsigned long)xWindow forItem: (DockItem *)item
{
  if (!item || !xWindow)
    {
      return;
    }

  [_applicationIconWindowItems setObject:item
				  forKey:[NSNumber numberWithUnsignedLong:xWindow]];
}

- (void) removeApplicationIconWindowsForItem: (DockItem *)item
{
  NSArray *keys = [_applicationIconWindowItems allKeysForObject:item];
  NSUInteger i;

  for (i = 0; i < [keys count]; i++)
    {
      [_applicationIconWindowItems removeObjectForKey:[keys objectAtIndex:i]];
    }
}

- (BOOL) item: (DockItem *)item iconMatchesImage: (NSImage *)image
{
  return [item icon] == image;
}

- (NSString *) x11IconCacheDirectory
{
  return [DockItem x11IconCacheDirectory];
}

- (NSString *) x11IconCacheFileNameForIdentifier: (NSString *)identifier
{
  return [DockItem x11IconCacheFileNameForIdentifier:identifier];
}

- (NSString *) storeX11Icon: (NSImage *)icon identifier: (NSString *)identifier
{
  NSString *directory;
  NSString *fileName;
  NSString *path;
  NSData *data;

  if (!icon)
    {
      return nil;
    }

  data = [icon TIFFRepresentation];
  if (![data length])
    {
      return nil;
    }

  directory = [self x11IconCacheDirectory];
  if (![directory length])
    {
      return nil;
    }

  fileName = [self x11IconCacheFileNameForIdentifier:identifier];
  path = [directory stringByAppendingPathComponent:fileName];
  if ([data writeToFile:path atomically:YES])
    {
      return path;
    }

  return nil;
}

- (NSString *) x11IconIdentifierForTitle: (NSString *)title
				    path: (NSString *)path
				  window: (unsigned long)xWindow
{
  if ([path length])
    {
      return path;
    }
  if ([title length])
    {
      return title;
    }
  return [NSString stringWithFormat:@"0x%lx", xWindow];
}

- (BOOL) shouldApplyX11Icon: (NSImage *)icon toItem: (DockItem *)item
{
  NSString *bundlePath;

  if (!icon || !item)
    {
      return NO;
    }
  if ([item kind] != DockItemApplication)
    {
      return YES;
    }

  bundlePath = [DockItem applicationBundlePathForPath:[item path]];
  return ![bundlePath length];
}

- (BOOL) imageHasVisiblePixels: (NSImage *)image
{
  NSArray *representations = [image representations];
  NSUInteger remainingPixels = 1024 * 1024;
  NSSize size = [image size];
  BOOL visible = NO;

  /* Inspect the existing bitmap, never a TIFF encode/decode round trip.
   * Reject oversized representations before scanning or caching the image.
   * Bound the total work as well as each dimension for multi-rep images. */
  if (!image || !(size.width > 0 && size.width <= 1024 &&
                  size.height > 0 && size.height <= 1024) ||
      ![representations count] || [representations count] > 16)
    return NO;

  for (NSImageRep *representation in representations)
    {
      NSInteger width = [representation pixelsWide];
      NSInteger height = [representation pixelsHigh];
      if (width <= 0 || height <= 0 || width > 1024 || height > 1024 ||
          (NSUInteger)(width * height) > remainingPixels)
        return NO;
      remainingPixels -= width * height;
    }

  for (NSImageRep *representation in representations)
    {
      if (![representation isKindOfClass:[NSBitmapImageRep class]])
        {
          /* Non-bitmap images cannot be inspected without rendering. */
          visible = YES;
          continue;
        }

      NSBitmapImageRep *rep = (NSBitmapImageRep *)representation;
      NSInteger samples = [rep samplesPerPixel];
      NSInteger bits = [rep bitsPerSample];
      NSBitmapFormat format = [rep bitmapFormat];
      if (![rep hasAlpha])
        return YES;
      /* getPixel: supplies integer samples. Preserve unusual representations
       * rather than interpreting floating-point samples as integer alpha. */
      if (samples < 1 || samples > 5 || bits < 1 || bits > 16 ||
          (format & NSFloatingPointSamplesBitmapFormat))
        {
          visible = YES;
          continue;
        }

      NSInteger width = [rep pixelsWide];
      NSInteger height = [rep pixelsHigh];
      NSInteger alphaIndex = (format & NSAlphaFirstBitmapFormat) ? 0 : samples - 1;
      NSUInteger threshold = ((1UL << bits) - 1) / 100;
      for (NSInteger y = 0; y < height; y++)
        for (NSInteger x = 0; x < width; x++)
          {
            NSUInteger pixel[5] = {0};
            [rep getPixel:pixel atX:x y:y];
            if (pixel[alphaIndex] > threshold)
              return YES;
          }
    }

  return visible;
}

- (void) applyX11Icon: (NSImage *)icon
	       toItem: (DockItem *)item
	   identifier: (NSString *)identifier
{
  NSString *iconPath;
  NSString *bundlePath;

  if (![self shouldApplyX11Icon:icon toItem:item])
    {
      return;
    }

  iconPath = [self storeX11Icon:icon identifier:identifier];
  [item setIcon:icon];
  if ([iconPath length])
    {
      [item setIconPath:iconPath];
    }

  bundlePath = [DockItem applicationBundlePathForPath:[item path]];
  if ([item kind] == DockItemApplication && ![bundlePath length])
    {
      [item setOriginalIcon:icon];
    }
}

/* A PID alone can be reused after exit or reboot. Bind persisted updates to
 * the executable and Linux process start time within the current boot. */
- (NSDictionary *) identityForProcessIdentifier: (NSNumber *)identifier
{
  NSString *root = [_scanner procFilesystemPath];
  NSString *path = [_scanner procPathForProcessIdentifierString:
    [identifier stringValue]];
  NSString *executable = [_scanner executablePathForProcessIdentifier:identifier];
  NSString *boot;
  NSString *stat;
  NSRange end;
  NSArray *fields;

  if (![root length] || ![path length] || ![executable length])
    return nil;
  boot = [NSString stringWithContentsOfFile:
    [root stringByAppendingPathComponent:@"sys/kernel/random/boot_id"]];
  stat = [NSString stringWithContentsOfFile:
    [path stringByAppendingPathComponent:@"stat"]];
  end = [stat rangeOfString:@") " options:NSBackwardsSearch];
  if (![executable length] || ![boot length] || ![stat length] ||
      end.location == NSNotFound)
    return nil;
  /* The command in parentheses may itself contain spaces or parentheses.
   * Fields after it begin at field 3; starttime is field 22. */
  fields = [[stat substringFromIndex:NSMaxRange(end)]
    componentsSeparatedByString:@" "];
  if ([fields count] <= 19)
    return nil;
  return [NSDictionary dictionaryWithObjectsAndKeys:
    executable, @"executable", boot, @"boot",
    [fields objectAtIndex:19], @"startTime", nil];
}

- (NSString *) applicationIconStatePathForProcessIdentifier: (NSNumber *)identifier
{
  return [[self x11IconCacheDirectory] stringByAppendingPathComponent:
    [NSString stringWithFormat:@"icon-manager-%@.plist", identifier]];
}

- (void) rememberApplicationIcon: (NSImage *)icon
		      badgeLabel: (NSString *)badgeLabel
	       processIdentifier: (NSNumber *)processIdentifier
{
  NSMutableDictionary *update;
  NSDictionary *identity;
  BOOL updateHasBadge = [badgeLabel length] > 0;

  if (![processIdentifier isKindOfClass:[NSNumber class]])
    {
      return;
    }

  update = [NSMutableDictionary dictionary];
  if (icon && !updateHasBadge && [self imageHasVisiblePixels:icon])
    {
      NSString *iconPath = [self storeX11Icon:icon
				   identifier:[NSString stringWithFormat:@"pid-%@",
							    processIdentifier]];
      [update setObject:icon forKey:@"icon"];
      if ([iconPath length])
	{
	  [update setObject:iconPath forKey:@"iconPath"];
	}
    }
  [update setObject:([badgeLabel length] ? badgeLabel : (id)[NSNull null])
	     forKey:@"badgeLabel"];
  [_applicationIconUpdatesByProcessID setObject:update
					 forKey:processIdentifier];

  identity = [self identityForProcessIdentifier:processIdentifier];
  if (identity)
    {
      NSMutableDictionary *record = [NSMutableDictionary dictionaryWithDictionary:identity];
      NSString *iconPath = [update objectForKey:@"iconPath"];
      if (iconPath) [record setObject:iconPath forKey:@"iconPath"];
      if (badgeLabel) [record setObject:badgeLabel forKey:@"badgeLabel"];
      [record writeToFile:[self applicationIconStatePathForProcessIdentifier:
        processIdentifier] atomically:YES];
    }
}

- (NSDictionary *) applicationIconUpdateForProcessIdentifier: (NSNumber *)processIdentifier
{
  NSDictionary *update = [_applicationIconUpdatesByProcessID objectForKey:processIdentifier];
  if (!update)
    {
      NSDictionary *identity = [self identityForProcessIdentifier:processIdentifier];
      NSDictionary *record = [NSDictionary dictionaryWithContentsOfFile:
        [self applicationIconStatePathForProcessIdentifier:processIdentifier]];
      if (identity &&
          [[record objectForKey:@"executable"] isEqual:[identity objectForKey:@"executable"]] &&
          [[record objectForKey:@"boot"] isEqual:[identity objectForKey:@"boot"]] &&
          [[record objectForKey:@"startTime"] isEqual:[identity objectForKey:@"startTime"]])
        {
          NSMutableDictionary *restored = [NSMutableDictionary dictionary];
          id badge = [record objectForKey:@"badgeLabel"];
          id path = [record objectForKey:@"iconPath"];
          if ([path isKindOfClass:[NSString class]])
            {
              NSImage *icon = AUTORELEASE([[NSImage alloc] initWithContentsOfFile:path]);
              if ([self imageHasVisiblePixels:icon])
                {
                  [restored setObject:icon forKey:@"icon"];
                  [restored setObject:path forKey:@"iconPath"];
                }
            }
          [restored setObject:([badge isKindOfClass:[NSString class]]
            ? badge : (id)[NSNull null]) forKey:@"badgeLabel"];
          [_applicationIconUpdatesByProcessID setObject:restored forKey:processIdentifier];
          update = restored;
        }
    }
  return update;
}

- (BOOL) applyApplicationIconUpdate: (NSDictionary *)update toItem: (DockItem *)item
{
  id icon = [update objectForKey:@"icon"];
  id iconPath = [update objectForKey:@"iconPath"];
  id badgeObject = [update objectForKey:@"badgeLabel"];
  NSString *badgeLabel = badgeObject == [NSNull null] ? nil : badgeObject;
  BOOL updateHasBadge = [badgeLabel length] > 0;
  BOOL updateClearsBadge = !updateHasBadge && [[item badgeLabel] length] > 0;
  BOOL changed = NO;

  if (updateHasBadge || updateClearsBadge)
    {
      NSImage *currentIcon = [item icon];

      [item restoreOriginalIcon];
      if ([item icon] != currentIcon)
	{
	  changed = YES;
	}
    }

  if (!updateHasBadge &&
      !updateClearsBadge &&
      [icon isKindOfClass:[NSImage class]] &&
      ![self item:item iconMatchesImage:icon] &&
      [self imageHasVisiblePixels:icon])
    {
      [item setIcon:icon];
      changed = YES;
    }
  if (!updateHasBadge &&
      !updateClearsBadge &&
      [iconPath isKindOfClass:[NSString class]] && [iconPath length] &&
      !([[item iconPath] isEqualToString:iconPath]))
    {
      [item setIconPath:iconPath];
      changed = YES;
    }

  if (([badgeLabel length] || [[item badgeLabel] length]) &&
      !(([item badgeLabel] == badgeLabel) ||
	([item badgeLabel] && badgeLabel &&
	 [[item badgeLabel] isEqualToString:badgeLabel])))
    {
      [item setBadgeLabel:badgeLabel];
      changed = YES;
    }

  return changed;
}

- (BOOL) applyStoredApplicationIconUpdateForItem: (DockItem *)item
{
  NSArray *processIdentifiers = [_scanner runningProcessIdentifiersForApplicationItem:item];
  BOOL changed = NO;
  NSUInteger i;

  for (i = 0; i < [processIdentifiers count]; i++)
    {
      NSDictionary *update = [self applicationIconUpdateForProcessIdentifier:
        [processIdentifiers objectAtIndex:i]];

      if (update)
	{
	  changed = [self applyApplicationIconUpdate:update toItem:item] || changed;
	}
    }

  return changed;
}

- (void) pruneApplicationIconUpdatesForExitedProcesses
{
  NSArray *processIdentifiers = [_applicationIconUpdatesByProcessID allKeys];
  NSUInteger i;

  for (i = 0; i < [processIdentifiers count]; i++)
    {
      NSNumber *processIdentifier = [processIdentifiers objectAtIndex:i];
      NSString *processPath = [_scanner procPathForProcessIdentifierString:
					  [processIdentifier stringValue]];

      if (![processPath length] ||
	  ![[NSFileManager defaultManager] fileExistsAtPath:processPath])
	{
	  [_applicationIconUpdatesByProcessID removeObjectForKey:processIdentifier];
	}
    }
}

@end
