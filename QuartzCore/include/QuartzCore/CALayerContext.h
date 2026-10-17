#import <CoreGraphics/CGGeometry.h>
#ifdef DARLING_NATIVE_LAYER_CONTEXT
#import <CoreGraphics/CGContext.h>
#endif
#import <Foundation/NSObject.h>
#import <OpenGL/OpenGL.h>
#import <CoreGraphics/CGSubWindow.h>

@class CARenderer, CALayer, CGLPixelSurface, NSTimer, NSMutableArray, NSNumber;

@interface CALayerContext : NSObject {
    CGRect _frame;
    CGLPixelFormatObj _pixelFormat;
    CGLContextObj _glContext;
    CALayer *_layer;
    CARenderer *_renderer;

    NSMutableArray *_deleteTextureIds;

    NSTimer *_timer;
    CGSubWindow* _subwindow;
    void* _cglWindow;
#ifdef DARLING_NATIVE_LAYER_CONTEXT
    CGContextRef _bitmapContext;
    BOOL _invalidated;
#endif
}

@property(readonly) CGLContextObj glContext;

- initWithFrame: (CGRect) rect;

- (void) setFrame: (CGRect) value;
- (void) setLayer: (CALayer *) layer;
- (void) setSubwindow: (CGSubWindow*) subwindow;

- (void) invalidate;

- (void) render;

- (void) startTimerIfNeeded;

- (void) deleteTextureId: (NSNumber *) textureId;

- (void) flush;
#ifdef DARLING_NATIVE_LAYER_CONTEXT
/* Owned snapshot of the actual offscreen pixels, also used for validation. */
- (CGImageRef) copyRenderedImage CF_RETURNS_RETAINED;
#endif

@end
