#import <AppKit/AppKit.h>
#import <GNUstepBase/GNUstep.h>
#import <objc/runtime.h>
#import "DockPreferences.h"
#import "AppControllerPrivate.h"
#import "SettingsControllerPrivate.h"

@interface NSUserDefaults (IsolatedTestDatabase)

- (id) initWithContentsOfFile: (NSString *)path;

@end

static NSUserDefaults *testDefaults;

static id isolatedDefaults(id receiver, SEL selector)
{
  return testDefaults;
}

@interface IconPreferenceController : AppController
{
  NSUInteger _receivedUpdates;
}

- (NSUInteger) receivedUpdates;

@end

@implementation IconPreferenceController

- (id) init
{
  self = [super init];
  if (self)
    {
      _preferences = [[DockPreferences alloc] init];
      _items = [[NSMutableArray alloc] init];
    }
  return self;
}

- (NSString *) executablePathForProcessIdentifier: (NSNumber *)identifier
{
  return @"/tmp/ExampleApplication.app";
}

- (void) rememberApplicationIcon: (NSImage *)icon
                     badgeLabel: (NSString *)badgeLabel
              processIdentifier: (NSNumber *)identifier
{
  _receivedUpdates++;
}

- (DockItem *) applicationItemMatchingProcessIdentifier: (NSNumber *)identifier
{
  return nil;
}

- (DockItem *) transientApplicationItemForProcessIdentifier: (NSNumber *)identifier
{
  return nil;
}

- (NSUInteger) receivedUpdates
{
  return _receivedUpdates;
}

@end

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
    objectForKey:@"GSUseIconManager"] != nil, @"Startup preserves per-app override");
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
  [preferences setIconManagerOverride:[NSNumber numberWithBool:NO]
                            forDomain:@"ExampleApplication"];
  DESTROY(testDefaults);
  testDefaults = [[NSUserDefaults alloc] initWithContentsOfFile:path];
  [preferences applyIconManagerPreference];
  NSCAssert(![[preferences iconManagerOverrideForDomain:@"ExampleApplication"] boolValue],
    @"App opt-out survives reload and startup");
  [preferences saveUsesIconManager:NO];
  [preferences setIconManagerOverride:[NSNumber numberWithBool:YES]
                            forDomain:@"ExampleApplication"];
  NSCAssert([[preferences iconManagerOverrideForDomain:@"ExampleApplication"] boolValue],
    @"App can opt in while global default is off");
  [preferences setIconManagerOverride:nil forDomain:@"ExampleApplication"];
  NSCAssert([preferences iconManagerOverrideForDomain:@"ExampleApplication"] == nil,
    @"Use global setting removes the override");
  NSCAssert([[[testDefaults persistentDomainForName:@"ExampleApplication"]
    objectForKey:@"Other"] isEqual:@"kept"], @"Changing overrides preserves other preferences");
  {
    IconPreferenceController *controller = [[IconPreferenceController alloc] init];
    SettingsController *settings;
    DockItem *item;
    NSPopUpButton *popup;
    NSButton *globalButton;

    [controller x11DockManagerDidUpdateApplicationIcon:nil badgeLabel:@"1"
                                    processIdentifier:123];
    NSCAssert([controller receivedUpdates] == 0,
      @"Direct icon-manager messages cannot bypass global off");
    [preferences saveUsesIconManager:YES];
    [preferences setIconManagerOverride:[NSNumber numberWithBool:NO]
                              forDomain:@"ExampleApplication"];
    [controller x11DockManagerDidUpdateApplicationIcon:nil badgeLabel:@"2"
                                    processIdentifier:123];
    NSCAssert([controller receivedUpdates] == 0,
      @"Direct messages cannot bypass app off");
    [preferences saveUsesIconManager:NO];
    [preferences setIconManagerOverride:[NSNumber numberWithBool:YES]
                              forDomain:@"ExampleApplication"];
    [controller x11DockManagerDidUpdateApplicationIcon:nil badgeLabel:@"3"
                                    processIdentifier:123];
    NSCAssert([controller receivedUpdates] == 1,
      @"Explicit app on takes precedence over global off");
    [NSApplication sharedApplication];
    item = [DockItem applicationItemWithPath:@"/tmp/ExampleApplication.app"];
    [item setPinned:YES];
    [[controller valueForKey:@"items"] addObject:item];
    settings = [[SettingsController alloc] initWithDelegate:controller];
    [settings showWindowForItem:item];
    popup = [settings valueForKey:@"applicationIconManagerPopup"];
    NSCAssert([popup isEnabled] && [popup indexOfSelectedItem] == 1,
      @"Application settings display stored override");
    [popup selectItemAtIndex:2];
    [settings applicationIconManagerChanged:popup];
    NSCAssert(![[preferences iconManagerOverrideForDomain:@"ExampleApplication"] boolValue],
      @"Application control saves off");
    [popup selectItemAtIndex:0];
    [settings applicationIconManagerChanged:popup];
    NSCAssert([preferences iconManagerOverrideForDomain:@"ExampleApplication"] == nil,
      @"Application control restores inheritance");
    globalButton = [settings valueForKey:@"useIconManagerButton"];
    [globalButton setState:NSOnState];
    [settings useIconManagerChanged:globalButton];
    NSCAssert([preferences savedUsesIconManager], @"Global control saves on");
    [settings closePanel:nil];
    RELEASE(settings);
    RELEASE(controller);
  }
  method_setImplementation(method, original);
  RELEASE(preferences);
  DESTROY(testDefaults);
  [files removeItemAtPath:root error:NULL];
  NSLog(@"Icon manager preference tests passed");
  RELEASE(pool);
  return 0;
}
