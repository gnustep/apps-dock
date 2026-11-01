#import "AppControllerPrivate.h"
#import "DockViewPrivate.h"
#import <objc/runtime.h>

@interface NSUserDefaults (IsolatedTestDatabase)

- (id) initWithContentsOfFile: (NSString *)path;

@end

static NSUserDefaults *testDefaults;

static id isolatedDefaults(id receiver, SEL selector)
{
  return testDefaults;
}

@interface KeepInDockController : AppController

- (NSMutableArray *) items;

@end

@implementation KeepInDockController

- (id) init
{
  self = [super init];
  if (self)
    {
      _items = [[NSMutableArray alloc] init];
    }
  return self;
}

- (NSMutableArray *) items
{
  return _items;
}

- (void) refreshDock
{
}

- (void) savePersistedApplications
{
}

@end

int main(void)
{
  NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
  NSUserDefaults *defaults;
  Method method;
  IMP original;
  NSString *name = [[NSProcessInfo processInfo] globallyUniqueString];
  NSString *path = [@"/tmp" stringByAppendingPathComponent:name];
  KeepInDockController *controller = [[KeepInDockController alloc] init];
  NSString *domain = [controller defaultsDomainForApplicationPath:path];
  DockView *view;
  DockItem *item;
  id<NSMenuItem> toggle;

  [NSApplication sharedApplication];
  testDefaults = [[NSUserDefaults alloc]
                   initWithContentsOfFile:[path stringByAppendingString:@"-defaults"]];
  defaults = testDefaults;
  [defaults synchronize];
  method = class_getClassMethod([NSUserDefaults class], @selector(standardUserDefaults));
  original = method_setImplementation(method, (IMP)isolatedDefaults);
  [defaults setPersistentDomain:[NSDictionary dictionaryWithObject:@"preserved"
                                forKey:@"Unrelated"] forName:domain];
  NSCAssert([controller applicationPathIsKeptInDock:path], @"Default is enabled");
  NSCAssert([controller applicationPathIsKeptInDock:nil], @"Unknown paths stay visible");
  item = [DockItem applicationItemWithPath:path];
  [[controller items] addObject:item];
  view = [[DockView alloc] initWithFrame:NSMakeRect(0, 0, 64, 64)];
  [view setDelegate:controller];
  toggle = [[view menuForDockItem:item] itemWithTitle:@"Keep In Dock"];
  NSCAssert(toggle != nil && [toggle state] == NSOnState, @"Menu is checked by default");
  [view performSelector:[toggle action] withObject:toggle];
  NSCAssert([[controller items] count] == 0, @"Toggling removes the item immediately");
  DESTROY(testDefaults);
  testDefaults = [[NSUserDefaults alloc]
                   initWithContentsOfFile:[path stringByAppendingString:@"-defaults"]];
  defaults = testDefaults;
  [defaults synchronize];
  NSCAssert(![controller applicationPathIsKeptInDock:path], @"Opt-out survives reload");
  NSCAssert([[[defaults persistentDomainForName:domain] objectForKey:@"Unrelated"]
              isEqual:@"preserved"], @"Other application defaults are preserved");
  NSCAssert([[[view menuForDockItem:item] itemWithTitle:@"Keep In Dock"] state]
              == NSOffState, @"Menu reflects opt-out");
  [controller x11DockManagerDidDiscoverWindowWithTitle:name window:123
               hidden:NO icon:nil path:path dockApp:NO];
  NSCAssert([[controller items] count] == 0, @"X11 discovery respects opt-out");
  [[NSFileManager defaultManager] createFileAtPath:path contents:[NSData data]
                                   attributes:nil];
  [(id<DockViewDelegate>)controller dockViewDidReceivePaths:[NSArray arrayWithObject:path] atIndex:0];
  NSCAssert([controller applicationPathIsKeptInDock:path] &&
            [[controller items] count] == 1, @"Dropping the app restores visibility");
  [defaults removePersistentDomainForName:domain];
  [defaults synchronize];
  [[NSFileManager defaultManager] removeItemAtPath:path error:NULL];
  RELEASE(view);
  RELEASE(controller);
  method_setImplementation(method, original);
  RELEASE(testDefaults);
  [[NSFileManager defaultManager]
    removeItemAtPath:[path stringByAppendingString:@"-defaults"] error:NULL];
  NSLog(@"Keep In Dock tests passed");
  RELEASE(pool);
  return 0;
}

