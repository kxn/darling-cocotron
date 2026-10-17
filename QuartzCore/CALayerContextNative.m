/* Darling's CALayerContext extension for a native QuartzCore layer tree.
 * A real bitmap context is rendered by native CALayer's renderInContext:.
 * There is no window, CGL context, Metal device, texture allocation or fake
 * display. Those operations fail explicitly if a caller requires them. */
#define DARLING_NATIVE_LAYER_CONTEXT 1
#import <QuartzCore/CALayerContext.h>
#import <QuartzCore/CALayer.h>
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#include <math.h>
#include <stdint.h>
#include <limits.h>
#include <errno.h>
extern bool CGFloatIsValid(CGFloat);
@interface CALayer (DarlingNativeBitmapRender)
- (void)renderInContext:(CGContextRef)context;
@end
@implementation CALayerContext
- (id)initWithFrame:(CGRect)frame {
    self=[super init];
    if(self) {
        @try {[self setFrame:frame];}
        @catch(id error){[self release];@throw;}
    }
    return self;
}
- (void)dealloc {
    [self invalidate];[_layer release];[super dealloc];
}
- (void)_requireValid {
    if(_invalidated)[NSException raise:NSInternalInconsistencyException format:@"CALayerContext has been invalidated"];
}
- (void)setFrame:(CGRect)frame {
    [self _requireValid];
    if(!CGFloatIsValid(frame.origin.x)||!CGFloatIsValid(frame.origin.y)||!CGFloatIsValid(frame.size.width)||!CGFloatIsValid(frame.size.height)||frame.size.width<0||frame.size.height<0||frame.size.width>INT_MAX||frame.size.height>INT_MAX)
        [NSException raise:NSInvalidArgumentException format:@"CALayerContext requires finite, nonnegative bitmap dimensions"];
    size_t width=(size_t)ceil(frame.size.width),height=(size_t)ceil(frame.size.height);
    if(width && height && (width>SIZE_MAX/4 || height>SIZE_MAX/(width*4)))
        [NSException raise:NSInvalidArgumentException format:@"CALayerContext bitmap size overflows size_t"];
    if(_bitmapContext&&CGBitmapContextGetWidth(_bitmapContext)==width&&CGBitmapContextGetHeight(_bitmapContext)==height){_frame=frame;return;}
    CGContextRef replacement=NULL;
    if(width&&height){
        CGColorSpaceRef rgb=CGColorSpaceCreateDeviceRGB();
        if(rgb){replacement=CGBitmapContextCreate(NULL,width,height,8,width*4,rgb,kCGImageAlphaPremultipliedLast|kCGBitmapByteOrder32Big);CGColorSpaceRelease(rgb);}
        if(!replacement)[NSException raise:NSMallocException format:@"Unable to create CALayerContext bitmap"];
    }
    if(_bitmapContext)CGContextRelease(_bitmapContext);
    _bitmapContext=replacement;_frame=frame;
}
- (void)setLayer:(CALayer *)layer {
    [self _requireValid];layer=[layer retain];[_layer release];_layer=layer;
}
- (void)render {
    [self _requireValid];
    /* An empty frame has no destination pixels. A nil layer clears an actual
     * nonempty destination to transparent, rather than leaving stale content. */
    if(!_bitmapContext)return;
    CGContextClearRect(_bitmapContext,CGRectMake(0,0,CGBitmapContextGetWidth(_bitmapContext),CGBitmapContextGetHeight(_bitmapContext)));
    [_layer renderInContext:_bitmapContext];
}
- (void)flush {[self _requireValid];if(_bitmapContext)CGContextFlush(_bitmapContext);}
- (CGImageRef)copyRenderedImage {
    [self _requireValid];if(!_bitmapContext){errno=ENOENT;return NULL;}
    return CGBitmapContextCreateImage(_bitmapContext);
}
- (void)timer:(NSTimer *)timer {if(!_invalidated)[self render];}
- (void)startTimerIfNeeded {
    [self _requireValid];
    if(!_timer)_timer=[[NSTimer scheduledTimerWithTimeInterval:1.0/60.0 target:self selector:@selector(timer:) userInfo:nil repeats:YES] retain];
}
- (void)invalidate {
    if(_invalidated)return;
    _invalidated=YES;[_timer invalidate];[_timer release];_timer=nil;
    if(_bitmapContext){CGContextRelease(_bitmapContext);_bitmapContext=NULL;}
}
- (CGLContextObj)glContext {
    [NSException raise:NSInternalInconsistencyException format:@"Bitmap CALayerContext has no OpenGL context"];
    return NULL;
}
- (void)setSubwindow:(CGSubWindow *)window {
    [self _requireValid];
    if(window)[NSException raise:NSInvalidArgumentException format:@"Bitmap CALayerContext does not attach to native windows"];
}
- (void)deleteTextureId:(NSNumber *)texture {
    [self _requireValid];
    if(texture)[NSException raise:NSInvalidArgumentException format:@"Bitmap CALayerContext does not own OpenGL textures"];
}
@end
