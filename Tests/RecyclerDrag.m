/* Recycler drag regression test. Copyright (C) 2026 Gregory Casamento
 * <greg.casamento@gmail.com>. Licensed under GPLv3 or later. */

#import "AppControllerPrivate.h"
#import "DockViewPrivate.h"
#import "X11DockManagerPrivate.h"

static NSString *testDirectory;
static BOOL applicationDrop;

static NSString *draggedPath(void)
{
  return [testDirectory stringByAppendingPathComponent:
    applicationDrop ? @"Ink.app" : @"Untitled Folder"];
}


@interface RecyclerDragManager : X11DockManager

@end

@implementation RecyclerDragManager

- (void) registerIconManager
{
  /* Do not register the user's shared icon-update service from a test. */
}

@end

@interface RecyclerDragController : AppController

- (id) initWithView: (DockView *)view;

@end

@implementation RecyclerDragController

- (id) initWithView: (DockView *)view
{
  self = [super init];
  if (self)
    {
      _items = [[NSMutableArray alloc] init];
      _dockView = RETAIN(view);
      _recyclerController = [[RecyclerController alloc] init];
      _applicationScanner = [[RunningApplicationScanner alloc] init];
    }
  return self;
}

- (NSString *) recyclerPathForDropping
{
  return [testDirectory stringByAppendingPathComponent:@"Trash"];
}

- (BOOL) recyclerHasContents
{
  return [_recyclerController directoryHasVisibleContentsAtPath:
    [self recyclerPathForDropping]];
}

- (void) setApplicationPath: (NSString *)path keptInDock: (BOOL)keep
{
  /* Do not alter application defaults from this isolated drag test. */
}

- (void) savePersistedApplications
{
  if (applicationDrop)
    {
      NSCAssert([_items count] == 1, @"Drop adds exactly one application");
      DockItem *item = [_items objectAtIndex:0];
      NSCAssert([[item path] isEqual:draggedPath()] && [item isPinned],
        @"Application is pinned at the dropped path");
      [@"pinned" writeToFile:[testDirectory stringByAppendingPathComponent:@"pinned"]
        atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    }
}

- (void) refreshDock
{
  if (applicationDrop)
    {
      [_dockView setItems:_items];
      [_dockView setPinnedItemCount:[self pinnedApplicationCount]];
    }
  [_dockView setNeedsDisplay:YES];
}

@end

@interface FolderDragSource : NSView

@end

@implementation FolderDragSource

- (BOOL) acceptsFirstMouse: (NSEvent *)event
{
  return YES;
}

- (void) drawRect: (NSRect)rect
{
  [[NSColor blueColor] set];
  NSRectFill([self bounds]);
}

- (void) mouseDown: (NSEvent *)event
{
  NSString *path = draggedPath();
  NSPasteboard *pasteboard = [NSPasteboard pasteboardWithName:NSDragPboard];
  NSImage *image = [[NSWorkspace sharedWorkspace] iconForFile:path];

  [pasteboard declareTypes:[NSArray arrayWithObject:NSFilenamesPboardType] owner:nil];
  [pasteboard setPropertyList:[NSArray arrayWithObject:path] forType:NSFilenamesPboardType];
  [self dragImage:image at:NSMakePoint(20, 20) offset:NSZeroSize event:event
      pasteboard:pasteboard source:self slideBack:YES];
}

- (NSDragOperation) draggingSourceOperationMaskForLocal: (BOOL)local
{
  return NSDragOperationMove;
}

@end

int main(int argc, char **argv)
{
  CREATE_AUTORELEASE_POOL(pool);
  NSWindow *window;
  NSDate *deadline;

  NSCAssert(argc >= 2, @"Temporary directory required");
  testDirectory = [NSString stringWithUTF8String:argv[1]];
  applicationDrop = [[[NSProcessInfo processInfo] environment]
    objectForKey:@"DOCK_DRAG_TEST_APPLICATION"] != nil;
  [NSApplication sharedApplication];
  NSSetUncaughtExceptionHandler(NULL);
  if (argc > 2)
    {
      window = [[NSWindow alloc] initWithContentRect:NSMakeRect(100, 400, 100, 100)
        styleMask:NSBorderlessWindowMask backing:NSBackingStoreBuffered defer:NO];
      [window setTitle:@"Recycler Test Source"];
      [window setContentView:AUTORELEASE([[FolderDragSource alloc]
        initWithFrame:NSMakeRect(0, 0, 100, 100)])];
      [window orderFront:nil];
      [window display];
    }
  else
    {
      NSFileManager *manager = [NSFileManager defaultManager];
      DockView *view;
      RecyclerDragController *controller;
      NSWindow *recycler = nil;
      RecyclerDragManager *x11;
      NSTimer *timer;
      NSWindow *child;
      NSString *coordinates;

      [manager createDirectoryAtPath:[testDirectory stringByAppendingPathComponent:@"Trash"]
        withIntermediateDirectories:YES attributes:nil error:NULL];
      [manager createDirectoryAtPath:draggedPath()
        withIntermediateDirectories:YES attributes:nil error:NULL];
      window = [[DockWindow alloc] initWithContentRect:NSMakeRect(100, 100, 280, 64)
        styleMask:NSBorderlessWindowMask backing:NSBackingStoreBuffered defer:NO];
      view = AUTORELEASE([[DockView alloc] initWithFrame:NSMakeRect(0, 0, 280, 64)]);
      [view setHorizontal:YES];
      [view setMagnifiesHoveredIcons:YES];
      [view setTooltipDelay:0.0];
      [view setItems:[NSArray arrayWithObject:[DockItem applicationItemWithPath:@"/bin/sh"]]];
      [window setContentView:view];
      controller = AUTORELEASE([[RecyclerDragController alloc] initWithView:view]);
      [view setDelegate:controller];
      [window orderFront:nil];
      [window display];
      x11 = AUTORELEASE([[RecyclerDragManager alloc] initWithDockView:view]);
      NSCAssert([x11 start], @"Native event manager starts");
      timer = [NSTimer scheduledTimerWithTimeInterval:0.05 target:x11
        selector:@selector(processPendingEvents) userInfo:nil repeats:YES];
      [[NSRunLoop currentRunLoop] addTimer:timer forMode:NSEventTrackingRunLoopMode];
      for (child in [window childWindows])
        if ([[child title] isEqualToString:@"Recycler"]) recycler = child;
      NSCAssert(recycler != nil, @"Recycler overlay exists");
      coordinates = [NSString stringWithFormat:@"%.0f %.0f\n",
        NSMidX([recycler frame]), NSHeight([[NSScreen mainScreen] frame]) - NSMidY([recycler frame])];
      [coordinates writeToFile:[testDirectory stringByAppendingPathComponent:@"coordinates"]
        atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    }
  /* Process real Xdnd events without launching a full application session or
   * contacting the user's workspace/icon manager on another display. */
  deadline = [NSDate dateWithTimeIntervalSinceNow:20.0];
  while ([deadline timeIntervalSinceNow] > 0)
    {
      CREATE_AUTORELEASE_POOL(eventPool);
      NSEvent *event = [NSApp nextEventMatchingMask:NSAnyEventMask
        untilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]
        inMode:NSDefaultRunLoopMode dequeue:YES];
      if (event) [NSApp sendEvent:event];
      [NSApp updateWindows];
      RELEASE(eventPool);
    }
  RELEASE(pool);
  return 0;
}

