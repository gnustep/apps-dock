#import <AppKit/AppKit.h>
#import "ApplicationIconManager.h"
#import "DockItem.h"

@interface ApplicationIconManager (Testing)
- (BOOL) imageHasVisiblePixels:(NSImage *)image;
@end

@interface TestIconManager : ApplicationIconManager
@end
@implementation TestIconManager
- (NSString *) storeX11Icon:(NSImage *)icon identifier:(NSString *)identifier
{
  return nil; // Keep tests out of the user's icon cache.
}
@end

@interface NoEncodingImage : NSImage
@end
@implementation NoEncodingImage
- (NSData *) TIFFRepresentation
{
  [NSException raise:@"UnexpectedEncoding" format:@"Visibility must not encode TIFF"];
  return nil;
}
@end

@interface OversizedRep : NSBitmapImageRep
@end
@implementation OversizedRep
- (NSInteger) pixelsWide { return 65537; }
- (NSInteger) pixelsHigh { return 642; }
- (void) getPixel:(NSUInteger *)pixel atX:(NSInteger)x y:(NSInteger)y
{
  [NSException raise:@"UnexpectedScan" format:@"Oversized icons must not be scanned"];
}
@end

static NSBitmapImageRep *bitmap(Class cls, NSInteger bits, BOOL planar, NSBitmapFormat format)
{
  NSBitmapImageRep *rep = [[cls alloc] initWithBitmapDataPlanes:NULL
    pixelsWide:64 pixelsHigh:64 bitsPerSample:bits samplesPerPixel:4
    hasAlpha:YES isPlanar:planar colorSpaceName:NSDeviceRGBColorSpace
    bitmapFormat:format bytesPerRow:0 bitsPerPixel:0];
  unsigned char *planes[5] = {0};
  [rep getBitmapDataPlanes:planes];
  for (NSInteger i = 0; i < (planar ? 4 : 1); i++)
    memset(planes[i], 0, [rep bytesPerPlane]);
  return [rep autorelease];
}

int main(void)
{
  NSAutoreleasePool *pool = [NSAutoreleasePool new];
  TestIconManager *manager = [[TestIconManager alloc] initWithScanner:nil];
  for (NSUInteger variant = 0; variant < 4; variant++)
    {
      BOOL first = variant == 1;
      NSInteger bits = variant == 3 ? 16 : 8;
      NSBitmapImageRep *rep = bitmap([NSBitmapImageRep class], bits,
        variant == 2, first ? NSAlphaFirstBitmapFormat : 0);
      NSImage *image = [[[NoEncodingImage alloc] initWithSize:NSMakeSize(64,64)] autorelease];
      [image addRepresentation:rep];
      NSCAssert(![manager imageHasVisiblePixels:image], @"Transparent image rejected");
      NSUInteger pixel[4] = {0};
      pixel[first ? 0 : 3] = ((1UL << bits) - 1) / 100;
      [rep setPixel:pixel atX:63 y:63];
      NSCAssert(![manager imageHasVisiblePixels:image], @"Alpha threshold preserved");
      pixel[first ? 0 : 3]++;
      [rep setPixel:pixel atX:63 y:63];
      NSCAssert([manager imageHasVisiblePixels:image], @"Last visible pixel found");
      [manager rememberApplicationIcon:image badgeLabel:nil processIdentifier:@123];
      NSCAssert([[manager applicationIconUpdateForProcessIdentifier:@123] objectForKey:@"icon"] == image,
        @"Normal icon update retained");
      [manager rememberApplicationIcon:image badgeLabel:@"7" processIdentifier:@123];
      NSCAssert([[[manager applicationIconUpdateForProcessIdentifier:@123] objectForKey:@"badgeLabel"] isEqual:@"7"],
        @"Badge update retained");
      [image addRepresentation:bitmap([OversizedRep class], 8, NO, 0)];
      NSCAssert(![manager imageHasVisiblePixels:image], @"All representations checked before accepting visible pixels");
      [manager rememberApplicationIcon:image badgeLabel:nil processIdentifier:@123];
      NSCAssert(![[manager applicationIconUpdateForProcessIdentifier:@123] objectForKey:@"icon"],
        @"Oversized icon never cached");
    }
  NSImage *large = [[[NoEncodingImage alloc] initWithSize:NSMakeSize(64,64)] autorelease];
  [large addRepresentation:bitmap([OversizedRep class], 8, NO, 0)];
  NSTimeInterval start = [NSDate timeIntervalSinceReferenceDate];
  for (NSUInteger i = 0; i < 1000; i++)
    NSCAssert(![manager imageHasVisiblePixels:large], @"Reject pathological dimensions");
  NSLog(@"Icon processing tests passed; 1000 oversized rejections took %.4fs",
    [NSDate timeIntervalSinceReferenceDate] - start);
  [manager release];
  [pool drain];
  return 0;
}
