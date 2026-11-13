#import <AppKit/AppKit.h>
#import "ApplicationIconManager.h"
#import "RunningApplicationScanner.h"
#import "DockItem.h"

static NSString *cacheDirectory;

@interface RestartIconManager : ApplicationIconManager

@end

@implementation RestartIconManager

- (NSString *) x11IconCacheDirectory
{
  return cacheDirectory;
}

@end

@interface RestartScanner : RunningApplicationScanner

@end

@implementation RestartScanner

- (NSArray *) runningProcessIdentifiersForApplicationItem: (DockItem *)item
{
  return [NSArray arrayWithObject:[NSNumber numberWithInt:
    [[NSProcessInfo processInfo] processIdentifier]]];
}

@end

int main(void)
{
  CREATE_AUTORELEASE_POOL(pool);
  NSFileManager *files = [NSFileManager defaultManager];
  RestartScanner *scanner = [[RestartScanner alloc] init];
  RestartIconManager *manager;
  NSNumber *pid = [NSNumber numberWithInt:[[NSProcessInfo processInfo] processIdentifier]];
  NSBitmapImageRep *rep = AUTORELEASE([[NSBitmapImageRep alloc]
    initWithBitmapDataPlanes:NULL pixelsWide:23 pixelsHigh:19
    bitsPerSample:8 samplesPerPixel:4 hasAlpha:YES isPlanar:NO
    colorSpaceName:NSDeviceRGBColorSpace bytesPerRow:0 bitsPerPixel:0]);
  NSImage *image = AUTORELEASE([[NSImage alloc] initWithSize:NSMakeSize(23, 19)]);
  DockItem *item = AUTORELEASE([[DockItem alloc] init]);
  NSString *statePath;
  NSString *iconPath;
  NSMutableDictionary *record;

  cacheDirectory = [NSTemporaryDirectory() stringByAppendingPathComponent:
    [[NSProcessInfo processInfo] globallyUniqueString]];
  [files createDirectoryAtPath:cacheDirectory withIntermediateDirectories:YES
    attributes:nil error:NULL];
  memset([rep bitmapData], 255, [rep bytesPerPlane]);
  [image addRepresentation:rep];
  manager = [[RestartIconManager alloc] initWithScanner:scanner];
  [manager rememberApplicationIcon:image badgeLabel:nil processIdentifier:pid];
  statePath = [cacheDirectory stringByAppendingPathComponent:
    [NSString stringWithFormat:@"icon-manager-%@.plist", pid]];
  record = [NSMutableDictionary dictionaryWithContentsOfFile:statePath];
  NSCAssert(record != nil, @"State persisted for a live process");
  iconPath = [record objectForKey:@"iconPath"];
  RELEASE(manager);

  manager = [[RestartIconManager alloc] initWithScanner:scanner];
  NSCAssert([manager applyStoredApplicationIconUpdateForItem:item],
    @"A fresh manager restores state without another client update");
  NSCAssert(NSEqualSizes([[item icon] size], NSMakeSize(23, 19)),
    @"Restored application uses the transmitted image");
  [manager rememberApplicationIcon:nil badgeLabel:@"7" processIdentifier:pid];
  RELEASE(manager);
  manager = [[RestartIconManager alloc] initWithScanner:scanner];
  [manager applyStoredApplicationIconUpdateForItem:item];
  NSCAssert([[item badgeLabel] isEqual:@"7"], @"Badge survives restart");
  [manager rememberApplicationIcon:image badgeLabel:nil processIdentifier:pid];
  RELEASE(manager);

  [@"invalid image" writeToFile:iconPath atomically:YES
    encoding:NSUTF8StringEncoding error:NULL];
  manager = [[RestartIconManager alloc] initWithScanner:scanner];
  NSCAssert(![[manager applicationIconUpdateForProcessIdentifier:pid] objectForKey:@"icon"],
    @"Corrupt image is ignored");
  RELEASE(manager);
  [files removeItemAtPath:iconPath error:NULL];
  manager = [[RestartIconManager alloc] initWithScanner:scanner];
  NSCAssert(![[manager applicationIconUpdateForProcessIdentifier:pid] objectForKey:@"icon"],
    @"Missing cached image is ignored");
  [manager rememberApplicationIcon:image badgeLabel:nil processIdentifier:pid];
  NSCAssert([[manager applicationIconUpdateForProcessIdentifier:pid] objectForKey:@"icon"] == image,
    @"A new client update replaces restored state");
  RELEASE(manager);

  for (NSString *key in [NSArray arrayWithObjects:@"startTime", @"boot", @"executable", nil])
    {
      NSMutableDictionary *stale = [NSMutableDictionary dictionaryWithDictionary:record];
      [stale setObject:@"different" forKey:key];
      [stale writeToFile:statePath atomically:YES];
      manager = [[RestartIconManager alloc] initWithScanner:scanner];
      NSCAssert([manager applicationIconUpdateForProcessIdentifier:pid] == nil,
        @"Never restore an icon from another process incarnation");
      RELEASE(manager);
    }
  [files removeItemAtPath:cacheDirectory error:NULL];
  RELEASE(scanner);
  NSLog(@"Icon manager restart tests passed");
  RELEASE(pool);
  return 0;
}

