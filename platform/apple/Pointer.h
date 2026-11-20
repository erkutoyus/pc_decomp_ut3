#ifndef UT3_APPLE_POINTER_H
#define UT3_APPLE_POINTER_H
#include <math.h>
#include <stdint.h>
#include <limits.h>

/* UIKit points (top-left origin) -> guest pixels. Match the integer
 * letterbox rectangle used by the native D3D9 Present bridge exactly. */
static inline int ut3_apple_pointer_position(double x,double y,double viewWidth,double viewHeight,
    uint32_t drawableWidth,uint32_t drawableHeight,uint32_t guestWidth,uint32_t guestHeight,
    int captured,int *guestX,int *guestY)
{
    if(!isfinite(x)||!isfinite(y)||!isfinite(viewWidth)||!isfinite(viewHeight)||
       viewWidth<=0||viewHeight<=0||!drawableWidth||!drawableHeight||!guestWidth||!guestHeight||
       drawableWidth>INT_MAX||drawableHeight>INT_MAX||guestWidth>INT_MAX||guestHeight>INT_MAX) return 0;
    double scale=fmin((double)drawableWidth/guestWidth,(double)drawableHeight/guestHeight);
    long width=lround(guestWidth*scale),height=lround(guestHeight*scale);
    if(width<=0||height<=0) return 0;
    long left=((long)drawableWidth-width)/2,top=((long)drawableHeight-height)/2;
    double px=x*drawableWidth/viewWidth-left,py=y*drawableHeight/viewHeight-top;
    if(!captured && (px<0||py<0||px>=width||py>=height))return 0;
    *guestX=(int)fmax(0,fmin(guestWidth-1,floor(px*guestWidth/width)));
    *guestY=(int)fmax(0,fmin(guestHeight-1,floor(py*guestHeight/height)));
    return 1;
}
#endif
