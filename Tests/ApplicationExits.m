#import "AppControllerPrivate.h"
#import <signal.h>

@interface ExitTestController : AppController

- (NSMutableArray *) items;
- (void) stopTimers;

@end

@implementation ExitTestController

- (id) init
{
  self = [super init];
  if (self)
    {
      _items = [[NSMutableArray alloc] init];
      _applicationScanner = [[RunningApplicationScanner alloc] init];
    }
  return self;
}

- (NSMutableArray *) items
{
  return _items;
}

- (void) scanRunningApplications
{
  /* Isolate the fast exit check from the full discovery pass. */
}

- (void) launchOpenAtLoginApplications
{
}

- (void) refreshDock
{
}

- (void) stopTimers
{
  [_processScanTimer invalidate];
  _processScanTimer = nil;
  [_applicationExitTimer invalidate];
  _applicationExitTimer = nil;
}

@end

int main(void)
{
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:
    [[NSProcessInfo processInfo] globallyUniqueString]];
  NSFileManager *files = [NSFileManager defaultManager];
  ExitTestController *controller;
  int attempt;

  NSCAssert([files copyItemAtPath:@"/bin/sleep" toPath:path error:NULL],
            @"Create isolated executable");
  controller = [[ExitTestController alloc] init];
  [controller performInitialApplicationScans];
  for (attempt = 0; attempt < 2; attempt++)
    {
      NSTask *task = [[NSTask alloc] init];
      DockItem *pinned = AUTORELEASE([[DockItem alloc] init]);
      DockItem *transient = AUTORELEASE([[DockItem alloc] init]);
      NSDate *deadline;

      [task setLaunchPath:path];
      [task setArguments:[NSArray arrayWithObject:@"30"]];
      [task launch];
      [pinned setPath:path];
      [transient setPath:path];
      [pinned setPinned:YES];
      [pinned setState:DockItemHidden];
      [pinned setBadgeLabel:@"1"];
      [transient setPinned:NO];
      [transient setState:DockItemRunning];
      [[controller items] addObject:pinned];
      [[controller items] addObject:transient];
      [controller scanForExitedApplications];
      NSCAssert([[controller items] count] == 2 &&
                [pinned state] == DockItemHidden,
                @"A live process without a window remains running");
      if (attempt == 0)
        [task terminate];
      else
        NSCAssert(kill([task processIdentifier], SIGKILL) == 0, @"Crash fixture");
      [task waitUntilExit];
      deadline = [NSDate dateWithTimeIntervalSinceNow:1.5];
      while ([pinned state] != DockItemNotRunning &&
             [deadline timeIntervalSinceNow] > 0)
        {
          [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode
            beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
        }
      NSCAssert([pinned state] == DockItemNotRunning &&
                [[pinned badgeLabel] length] == 0 && [pinned xWindow] == 0,
                @"Exit clears running state and badge within 1.5 seconds");
      NSCAssert([[controller items] count] == 1 &&
                [[controller items] objectAtIndex:0] == pinned,
                @"Exit removes transient item and preserves pinned item");
      [[controller items] removeAllObjects];
      RELEASE(task);
    }
  [controller stopTimers];
  RELEASE(controller);
  [files removeItemAtPath:path error:NULL];
  NSLog(@"Application exit checks passed");
  RELEASE(pool);
  return 0;
}

