#import <AppKit/AppKit.h>
#import "ApplicationIconManager.h"
#import "DockApplicationStore.h"
#import "DockItem.h"
#import "RunningApplicationScanner.h"

int main(void)
{
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  NSFileManager *files = [NSFileManager defaultManager];
  NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:
    [[NSProcessInfo processInfo] globallyUniqueString]];
  RunningApplicationScanner *scanner = [[RunningApplicationScanner alloc] init];
  ApplicationIconManager *manager = [[ApplicationIconManager alloc] initWithScanner:scanner];
  DockApplicationStore *store = [[DockApplicationStore alloc] initWithScanner:scanner];
  NSMutableArray *items = [NSMutableArray array];
  NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
  NSImage *icon;
  NSString *cachedPath;
  DockItem *item;
  id record;

  [NSApplication sharedApplication];
  [files createFileAtPath:path contents:[NSData data] attributes:nil];
  icon = AUTORELEASE([[NSImage alloc] initWithSize:NSMakeSize(23, 19)]);
  [icon lockFocus];
  [[NSColor redColor] set];
  NSRectFill(NSMakeRect(0, 0, 23, 19));
  [icon unlockFocus];
  item = [DockItem applicationItemWithPath:path];
  [manager applyX11Icon:icon toItem:item identifier:path];
  cachedPath = [item iconPath];
  NSCAssert(![cachedPath isEqual:path] && [files fileExistsAtPath:cachedPath],
            @"Live X11 icon is cached");
  record = [store persistedApplicationRecordForItem:item];
  NSCAssert([record isKindOfClass:[NSString class]], @"Exercise legacy path-only record");
  [defaults removeVolatileDomainForName:NSArgumentDomain];
  [defaults setVolatileDomain:[NSDictionary dictionaryWithObject:
    [NSArray arrayWithObject:record] forKey:@"DockApplications"] forName:NSArgumentDomain];
  RELEASE(manager);
  [store loadPersistedApplicationsIntoItems:items];
  item = [items objectAtIndex:0];
  NSCAssert([[item iconPath] isEqual:cachedPath] &&
            NSEqualSizes([[item icon] size], NSMakeSize(23, 19)),
            @"Restart restores the cached X11 icon without a running window");
  NSCAssert([item state] == DockItemNotRunning, @"Cache does not restore running state");
  [item setIcon:nil];
  [item restoreOriginalIcon];
  NSCAssert(NSEqualSizes([[item icon] size], NSMakeSize(23, 19)),
            @"Exit restoration retains the cached icon");
  [files removeItemAtPath:path error:NULL];
  NSCAssert([item refreshMissingState] && [item isMissing], @"Missing app stays a placeholder");
  [files createFileAtPath:path contents:[NSData data] attributes:nil];
  NSCAssert([item refreshMissingState] &&
            NSEqualSizes([[item icon] size], NSMakeSize(23, 19)),
            @"Reappearing app restores its cached icon");
  [@"invalid image" writeToFile:cachedPath atomically:YES
                     encoding:NSUTF8StringEncoding error:NULL];
  item = [DockItem applicationItemWithPath:path];
  NSCAssert([item icon] && [[item iconPath] isEqual:path], @"Corrupt cache falls back");
  [files removeItemAtPath:cachedPath error:NULL];
  item = [DockItem applicationItemWithPath:path];
  NSCAssert([item icon] && [[item iconPath] isEqual:path], @"Absent cache falls back");
  [files removeItemAtPath:path error:NULL];
  [defaults removeVolatileDomainForName:NSArgumentDomain];
  RELEASE(store);
  RELEASE(scanner);
  NSLog(@"X11 icon persistence tests passed");
  RELEASE(pool);
  return 0;
}

