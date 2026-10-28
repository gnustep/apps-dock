#import <AppKit/AppKit.h>
#import <GNUstepBase/GNUstep.h>
#import <objc/runtime.h>
#import "DockPreferences.h"

@interface NSUserDefaults (IsolatedTestDatabase)

- (id) initWithContentsOfFile: (NSString *)path;

@end

static NSUserDefaults *testDefaults;

static id isolatedDefaults(id receiver, SEL selector)
{
  return testDefaults;
}

int main(void)
{
  CREATE_AUTORELEASE_POOL(pool);
  NSString *root = [NSTemporaryDirectory() stringByAppendingPathComponent:
    [[NSProcessInfo processInfo] globallyUniqueString]];
  NSString *path = [root stringByAppendingPathComponent:@"defaults"];
  NSFileManager *files = [NSFileManager defaultManager];
  [files createDirectoryAtPath:root withIntermediateDirectories:YES
                   attributes:nil error:NULL];
  testDefaults = [[NSUserDefaults alloc] initWithContentsOfFile:path];
  Method method = class_getClassMethod([NSUserDefaults class],
                                      @selector(standardUserDefaults));
  IMP original = method_setImplementation(method, (IMP)isolatedDefaults);
  DockPreferences *preferences = [[DockPreferences alloc] init];
  NSCAssert([preferences savedUsesIconManager], @"Default must be on");
  [testDefaults setPersistentDomain:
    [NSDictionary dictionaryWithObject:@"preserved" forKey:@"OtherSetting"]
    forName:NSGlobalDomain];
  [testDefaults setPersistentDomain:[NSDictionary dictionaryWithObjectsAndKeys:
    [NSNumber numberWithBool:YES], @"GSUseIconManager", @"kept", @"Other", nil]
    forName:@"ExampleApplication"];
  [preferences applyIconManagerPreference];
  NSCAssert([[testDefaults persistentDomainForName:@"ExampleApplication"]
    objectForKey:@"GSUseIconManager"] == nil, @"Per-app override removed");
  NSCAssert([[[testDefaults persistentDomainForName:@"ExampleApplication"]
    objectForKey:@"Other"] isEqual:@"kept"], @"Other app settings preserved");
  NSCAssert([[[testDefaults persistentDomainForName:NSGlobalDomain]
    objectForKey:@"GSUseIconManager"] boolValue], @"Startup writes global YES");
  [preferences saveUsesIconManager:NO];
  DESTROY(testDefaults);
  testDefaults = [[NSUserDefaults alloc] initWithContentsOfFile:path];
  [testDefaults synchronize];
  NSCAssert(![preferences savedUsesIconManager], @"Off survives reload");
  [preferences applyIconManagerPreference];
  NSCAssert(![preferences savedUsesIconManager], @"Startup preserves off");
  NSCAssert([[[testDefaults persistentDomainForName:NSGlobalDomain]
    objectForKey:@"OtherSetting"] isEqual:@"preserved"],
    @"Other global preferences are preserved");
  [preferences saveUsesIconManager:YES];
  NSCAssert([preferences savedUsesIconManager], @"Can enable again");
  method_setImplementation(method, original);
  RELEASE(preferences);
  DESTROY(testDefaults);
  [files removeItemAtPath:root error:NULL];
  NSLog(@"Icon manager preference tests passed");
  RELEASE(pool);
  return 0;
}
