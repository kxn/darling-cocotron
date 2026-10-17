/* Floating geometry validation. Classify bits without floating arithmetic so
 * signaling NaNs do not raise FE_INVALID. Native x86_64 CoreGraphics uses this
 * same absolute-bit comparison against the infinity encoding. */
#include <CoreGraphics/CGBase.h>
#include <stdbool.h>
#include <stdint.h>
#include <string.h>
bool CGFloatIsValid(CGFloat value)
{
#if __LP64__
    uint64_t bits;_Static_assert(sizeof(value)==sizeof(bits),"CGFloat width");
    memcpy(&bits,&value,sizeof(bits));return (bits&UINT64_C(0x7fffffffffffffff))<UINT64_C(0x7ff0000000000000);
#else
    uint32_t bits;_Static_assert(sizeof(value)==sizeof(bits),"CGFloat width");
    memcpy(&bits,&value,sizeof(bits));return (bits&UINT32_C(0x7fffffff))<UINT32_C(0x7f800000);
#endif
}
