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

#import "X11DockManagerPrivate.h"

@implementation X11DockManager (Images)

/* XGetImage cannot read an unmapped client. Retain a small snapshot while the
 * active window is visible, independently of the application's icon cache. */
- (void) captureActiveWindowPreview
{
  Display *display = (Display *)_display;
  Window window = None;
  Atom type;
  int format, revert;
  unsigned long count, remaining;
  unsigned char *data = NULL;
  long state;

  if (!display) return;
  if (XGetWindowProperty(display, DefaultRootWindow(display),
        XInternAtom(display, "_NET_ACTIVE_WINDOW", False), 0, 1, False,
        XA_WINDOW, &type, &format, &count, &remaining, &data) == Success &&
      type == XA_WINDOW && format == 32 && count == 1)
    window = *(Window *)data;
  if (data) XFree(data);
  if (window == None)
    XGetInputFocus(display, &window, &revert);

  /* Focus can belong to a child widget rather than the managed client. */
  while (window != None && window != PointerRoot &&
         window != DefaultRootWindow(display))
    {
      Window root, parent, *children = NULL;
      unsigned int childCount;
      if ([self wmStateForWindow:window state:&state])
        {
          [self cachePreviewForWindow:window];
          return;
        }
      if (!XQueryTree(display, window, &root, &parent, &children, &childCount))
        return;
      if (children) XFree(children);
      window = parent;
    }
}

/* Discovery also seeds inactive clients, which may be minimized without ever
 * becoming the active window (for example, another Prompt terminal). */
- (void) cachePreviewForWindow: (Window)window
{
  Display *display = (Display *)_display;
  long state;
  NSImage *preview;

  if (!display || ![self wmStateForWindow:window state:&state] ||
      state != NormalState ||
      [self windowIsGNUstepIconOrMiniWindow:window] ||
      [self windowIsRegisteredIconWindow:window]) return;
  preview = [self capturePreviewForWindow:window];
  if (preview)
    {
      XWindowAttributes attr;
      [_windowPreviews setObject:preview forKey:
        [NSNumber numberWithUnsignedLong:window]];
      /* Reparented clients no longer report destruction at root. */
      if (XGetWindowAttributes(display, window, &attr))
        XSelectInput(display, window, attr.your_event_mask | StructureNotifyMask);
    }
}

- (NSImage *) capturePreviewForWindow: (Window)window
{
  Display *display = (Display *)_display;
  XWindowAttributes attr;
  XImage *source;
  NSMutableData *data;
  unsigned char *pixels;
  int width, height, left, top, x, y;

  if (!display || !window) return nil;
  [self clearX11Error];
  if (!XGetWindowAttributes(display, window, &attr) ||
      [self x11ErrorOccurred] || attr.map_state != IsViewable ||
      attr.class != InputOutput || attr.width <= 0 || attr.height <= 0 ||
      (unsigned long)attr.width * attr.height > 16777216UL ||
      attr.visual->class != TrueColor)
    return nil;

  [self clearX11Error];
  source = XGetImage(display, window, 0, 0, attr.width, attr.height,
                     AllPlanes, ZPixmap);
  if (!source || [self x11ErrorOccurred])
    {
      if (source) XDestroyImage(source);
      return nil;
    }

  width = attr.width >= attr.height ? 48 : MAX(1, 48 * attr.width / attr.height);
  height = attr.height >= attr.width ? 48 : MAX(1, 48 * attr.height / attr.width);
  left = (48 - width) / 2;
  top = (48 - height) / 2;
  data = [NSMutableData dataWithLength:48 * 48 * 4];
  pixels = [data mutableBytes];
  for (y = 0; y < height; y++)
    for (x = 0; x < width; x++)
      {
        unsigned int red = 0, green = 0, blue = 0;
        int sx, sy;
        unsigned char *dst = pixels + ((top + y) * 48 + left + x) * 4;
        /* Average sixteen samples per output pixel without converting a
         * full-size window into an AppKit bitmap. */
        for (sy = 0; sy < 4; sy++)
          for (sx = 0; sx < 4; sx++)
            {
              unsigned long pixel = XGetPixel(source,
                ((x * 8 + sx * 2 + 1) * attr.width) / (width * 8),
                ((y * 8 + sy * 2 + 1) * attr.height) / (height * 8));
              red += [self componentFromPixel:pixel mask:source->red_mask];
              green += [self componentFromPixel:pixel mask:source->green_mask];
              blue += [self componentFromPixel:pixel mask:source->blue_mask];
            }
        dst[0] = red / 16;
        dst[1] = green / 16;
        dst[2] = blue / 16;
        dst[3] = 255;
      }
  XDestroyImage(source);
  return [self imageFromData:data width:48 height:48];
}

- (NSImage *) previewForWindow: (unsigned long)window
{
  return [_windowPreviews objectForKey:[NSNumber numberWithUnsignedLong:window]];
}

- (unsigned char) componentFromPixel: (unsigned long)pixel mask: (unsigned long)mask
{
  unsigned long value;
  unsigned int shift = 0;
  unsigned int bits = 0;

  if (!mask)
    {
      return 0;
    }

  while (((mask >> shift) & 1UL) == 0)
    {
      shift++;
    }

  value = (pixel & mask) >> shift;
  while (((mask >> (shift + bits)) & 1UL) != 0)
    {
      bits++;
    }

  if (bits >= 8)
    {
      return (unsigned char)(value >> (bits - 8));
    }

  return (unsigned char)((value * 255UL) / ((1UL << bits) - 1UL));
}


- (NSData *) imageDataFromDrawable: (Drawable)drawable
                              mask: (Pixmap)mask
                             width: (unsigned int)width
                            height: (unsigned int)height
{
  Display *display = (Display *)_display;
  XImage *ximage;
  XImage *maskImage = NULL;
  NSMutableData *imageData;
  unsigned char *bitmapData;
  NSInteger bytesPerRow;
  NSInteger x;
  NSInteger y;
  BOOL sawVisiblePixel = NO;

  if (!display || !drawable || width == 0 || height == 0 ||
      width > 128 || height > 128)
    {
      return nil;
    }

  [self clearX11Error];
  ximage = XGetImage(display, drawable, 0, 0, width, height,
                     AllPlanes, ZPixmap);
  if (!ximage || [self x11ErrorOccurred])
    {
      if (ximage)
	{
	  XDestroyImage(ximage);
	}
      return nil;
    }

  if (mask)
    {
      [self clearX11Error];
      maskImage = XGetImage(display, mask, 0, 0, width, height,
			    AllPlanes, ZPixmap);
      if ([self x11ErrorOccurred])
	{
	  if (maskImage)
	    {
	      XDestroyImage(maskImage);
	    }
	  maskImage = NULL;
	}
    }

  bytesPerRow = (NSInteger)width * 4;
  imageData = [NSMutableData dataWithLength:bytesPerRow * (NSInteger)height];
  if (!imageData)
    {
      XDestroyImage(ximage);
      if (maskImage)
	{
	  XDestroyImage(maskImage);
	}
      return nil;
    }

  bitmapData = [imageData mutableBytes];
  for (y = 0; y < (NSInteger)height; y++)
    {
      for (x = 0; x < (NSInteger)width; x++)
	{
	  unsigned long pixel = XGetPixel(ximage, (int)x, (int)y);
	  unsigned char alpha = 255;
	  unsigned char *dst = bitmapData + y * bytesPerRow + x * 4;

	  if (maskImage && XGetPixel(maskImage, (int)x, (int)y) == 0)
	    {
	      alpha = 0;
	    }

	  dst[0] = [self componentFromPixel:pixel mask:ximage->red_mask];
	  dst[1] = [self componentFromPixel:pixel mask:ximage->green_mask];
	  dst[2] = [self componentFromPixel:pixel mask:ximage->blue_mask];
	  dst[3] = alpha;
	  if (alpha && (dst[0] || dst[1] || dst[2]))
	    {
	      sawVisiblePixel = YES;
	    }
	}
    }

  XDestroyImage(ximage);
  if (maskImage)
    {
      XDestroyImage(maskImage);
    }

  if (!sawVisiblePixel)
    {
      return nil;
    }

  return imageData;
}


- (NSImage *) imageFromData: (NSData *)imageData
                      width: (unsigned int)width
                     height: (unsigned int)height
{
  NSBitmapImageRep *rep;
  NSImage *image;
  unsigned char *bitmapData;
  NSInteger bytesPerRow;

  if (![imageData length] || width == 0 || height == 0)
    {
      return nil;
    }

  bytesPerRow = (NSInteger)width * 4;
  if ([imageData length] < bytesPerRow * (NSInteger)height)
    {
      return nil;
    }

  rep = [[NSBitmapImageRep alloc]
	  initWithBitmapDataPlanes:NULL
			pixelsWide: (NSInteger)width
			pixelsHigh: (NSInteger)height
		     bitsPerSample:8
		   samplesPerPixel:4
			  hasAlpha:YES
			  isPlanar:NO
		    colorSpaceName:NSDeviceRGBColorSpace
		       bytesPerRow:bytesPerRow
		      bitsPerPixel:32];
  rep = AUTORELEASE(rep);
  if (!rep)
    {
      return nil;
    }

  bitmapData = [rep bitmapData];
  memcpy(bitmapData, [imageData bytes], bytesPerRow * (NSInteger)height);

  image = AUTORELEASE([[NSImage alloc]
			initWithSize:NSMakeSize(width, height)]);
  [image addRepresentation:rep];
  return image;
}


- (NSImage *) imageFromDrawable: (Drawable)drawable
                           mask: (Pixmap)mask
                          width: (unsigned int)width
                         height: (unsigned int)height
{
  NSData *imageData = [self imageDataFromDrawable:drawable
					     mask:mask
					    width:width
					   height:height];

  return [self imageFromData:imageData width:width height:height];
}


- (NSImage *) imageFromPixmap: (Pixmap)pixmap mask: (Pixmap)mask
{
  Display *display = (Display *)_display;
  Window root;
  int x;
  int y;
  unsigned int width;
  unsigned int height;
  unsigned int borderWidth;
  unsigned int depth;

  if (!display || !pixmap)
    {
      return nil;
    }

  [self clearX11Error];
  if (!XGetGeometry(display, pixmap, &root, &x, &y,
                    &width, &height, &borderWidth, &depth) ||
      [self x11ErrorOccurred])
    {
      return nil;
    }

  return [self imageFromDrawable:pixmap mask:mask width:width height:height];
}


- (NSImage *) imageFromWindowContents: (Window)window
{
  Display *display = (Display *)_display;
  XWindowAttributes attr;

  [self clearX11Error];
  if (!XGetWindowAttributes(display, window, &attr) ||
      [self x11ErrorOccurred])
    {
      return nil;
    }
  if (attr.width <= 0 || attr.height <= 0 ||
      attr.width > 128 || attr.height > 128)
    {
      return nil;
    }

  return [self imageFromDrawable:window
                            mask:None
                           width:(unsigned int)attr.width
                          height:(unsigned int)attr.height];
}


- (NSImage *) iconForWindow: (Window)window
{
  Display *display = (Display *)_display;
  Atom property = XInternAtom(display, "_NET_WM_ICON", False);
  Atom actualType;
  int actualFormat;
  unsigned long itemCount, bytesAfter;
  unsigned char *data = NULL;
  NSImage *netWmIcon = nil;
  NSImage *hintIcon = nil;
  NSImage *icon = nil;
  XWMHints *hints;
  NSImage *managedIcon;
  int pid;
  NSString *className;

  pid = [self processIdentifierForWindow:window];
  className = [self classNameForWindow:window];
  managedIcon = [self iconForIdentifier:
			[self iconIdentifierForProcessIdentifier:pid title:className]];
  if (managedIcon)
    {
      return managedIcon;
    }

  [self clearX11Error];
  hints = XGetWMHints(display, window);
  if (![self x11ErrorOccurred] && hints)
    {
      if ((hints->flags & IconWindowHint) && hints->icon_window != None)
	{
	  hintIcon = [self imageFromWindowContents:hints->icon_window];
	}

      if (!hintIcon &&
	  (hints->flags & IconPixmapHint) &&
	  hints->icon_pixmap != None)
	{
	  Pixmap mask = None;

	  if ((hints->flags & IconMaskHint) && hints->icon_mask != None)
	    {
	      mask = hints->icon_mask;
	    }
	  hintIcon = [self imageFromPixmap:hints->icon_pixmap mask:mask];
	}

      XFree(hints);
    }
  else if (hints)
    {
      XFree(hints);
    }

  [self clearX11Error];
  if (XGetWindowProperty(display, window, property, 0, 65536, False, XA_CARDINAL,
                         &actualType, &actualFormat, &itemCount, &bytesAfter,
                         &data) == Success && data)
    {
      if ([self x11ErrorOccurred])
	{
	  if (data) XFree(data);
	  return icon;
	}
      if (actualFormat == 32 && itemCount >= 3)
	{
	  unsigned long *values = (unsigned long *)data;
	  unsigned long offset = 0;
	  unsigned long bestOffset = 0;
	  unsigned long bestWidth = 0;
	  unsigned long bestHeight = 0;
	  unsigned long bestScore = ~0UL;

	  while (offset + 2 < itemCount)
	    {
	      unsigned long width = values[offset];
	      unsigned long height = values[offset + 1];
	      unsigned long pixelCount = width * height;
	      unsigned long score;

	      if (!width || !height || pixelCount > itemCount - offset - 2)
		{
		  break;
		}

	      score = labs((long)width - 48) + labs((long)height - 48);
	      if (score < bestScore)
		{
		  bestScore = score;
		  bestOffset = offset + 2;
		  bestWidth = width;
		  bestHeight = height;
		}

	      offset += 2 + pixelCount;
	    }

	  if (bestWidth && bestHeight)
	    {
	      NSBitmapImageRep *rep = [[NSBitmapImageRep alloc]
					       initWithBitmapDataPlanes:NULL
							     pixelsWide: (NSInteger)bestWidth
							     pixelsHigh: (NSInteger)bestHeight
							  bitsPerSample:8
							samplesPerPixel:4
							       hasAlpha:YES
							       isPlanar:NO
							 colorSpaceName:NSCalibratedRGBColorSpace
							    bytesPerRow: (NSInteger)bestWidth * 4
							   bitsPerPixel:32];
	      rep = AUTORELEASE(rep);
	      unsigned char *bitmap = [rep bitmapData];
	      unsigned long i;

	      for (i = 0; i < bestWidth * bestHeight; i++)
		{
		  unsigned long argb = values[bestOffset + i];
		  bitmap[i * 4 + 0] = (argb >> 16) & 0xff;
		  bitmap[i * 4 + 1] = (argb >> 8) & 0xff;
		  bitmap[i * 4 + 2] = argb & 0xff;
		  bitmap[i * 4 + 3] = (argb >> 24) & 0xff;
		}

	      netWmIcon = AUTORELEASE([[NSImage alloc]
					initWithSize:NSMakeSize(bestWidth, bestHeight)]);
	      [netWmIcon addRepresentation:rep];
	    }
	}
      XFree(data);
    }

  if (netWmIcon)
    {
      return netWmIcon;
    }
  if (hintIcon)
    {
      return hintIcon;
    }
  return icon;
}


- (NSImage *) iconForIdentifier: (id)identifier
{
  if (!identifier)
    {
      return nil;
    }

  return nil;
}


@end
