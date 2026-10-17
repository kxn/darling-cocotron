/* CoreGraphics private state access needed by native layer rendering. Onyx2D
 * already retains the immutable initial device transform separately from the
 * user CTM; read that actual state, not a guessed identity or current CTM. */
#import <CoreGraphics/CGContext.h>
#import <Onyx2D/O2Context.h>
#import <Foundation/NSData.h>
#import <objc/runtime.h>
#include <string.h>
static char darling_base_ctm_key;
@interface O2Context (DarlingNativeLayer)
- (O2AffineTransform) _darlingNativeLayerBaseCTM;
@end
@implementation O2Context (DarlingNativeLayer)
- (O2AffineTransform) _darlingNativeLayerBaseCTM { return _userToDeviceTransform; }
@end
CGAffineTransform CGContextGetBaseCTM(CGContextRef context)
{
    if (!context) return (CGAffineTransform){1,0,0,1,0,0};
    NSData *stored=objc_getAssociatedObject((id)context,&darling_base_ctm_key);
    if(stored){CGAffineTransform transform;memcpy(&transform,[stored bytes],sizeof(transform));return transform;}
    O2AffineTransform value=[(O2Context *)context _darlingNativeLayerBaseCTM];
    return (CGAffineTransform){value.a,value.b,value.c,value.d,value.tx,value.ty};
}

/* Native SetBaseCTM only replaces the render-state base matrix; it does not
 * alter the current graphics-state CTM and SaveGState does not save it. Keep
 * this metadata separate from Onyx2D's physical initial device transform,
 * which its ordinary SetCTM implementation still needs for rasterization. */
void CGContextSetBaseCTM(CGContextRef context,CGAffineTransform transform)
{
    if(!context)return;
    NSData *stored=[[NSData alloc] initWithBytes:&transform length:sizeof(transform)];
    objc_setAssociatedObject((id)context,&darling_base_ctm_key,stored,OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [stored release];
}
