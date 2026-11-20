#include "../platform/apple/Pointer.h"
#include <assert.h>
#include <stdio.h>
int main(void)
{
    int x=-1,y=-1;
    // Physical iPhone screen, UIKit points, 4:3 guest: horizontal bars ignored.
    assert(ut3_apple_pointer_position(478,220,956,440,2868,1320,640,480,0,&x,&y));
    assert(x==320&&y==240);
    assert(!ut3_apple_pointer_position(10,220,956,440,2868,1320,640,480,0,&x,&y));
    assert(ut3_apple_pointer_position(10,220,956,440,2868,1320,640,480,1,&x,&y)&&x==0);
    assert(ut3_apple_pointer_position(950,220,956,440,2868,1320,640,480,1,&x,&y)&&x==639);
    assert(ut3_apple_pointer_position(478,1,956,440,2868,1320,640,480,0,&x,&y)&&y==1);
    assert(ut3_apple_pointer_position(478,439,956,440,2868,1320,640,480,0,&x,&y)&&y==478);
    // Downward UIKit movement remains downward in the guest (no Mac Y flip).
    int before=y;
    assert(ut3_apple_pointer_position(478,440,956,440,2868,1320,640,480,1,&x,&y)&&y>before&&y==479);
    // Portrait-shaped surface, full HD guest, and variable drawable scaling.
    assert(ut3_apple_pointer_position(300,500,600,1000,1200,2000,1920,1080,0,&x,&y)&&x==960&&y==540);
    assert(!ut3_apple_pointer_position(300,1,600,1000,1200,2000,1920,1080,0,&x,&y));
    assert(ut3_apple_pointer_position(300,1,600,1000,1200,2000,1920,1080,1,&x,&y)&&y==0);
    assert(!ut3_apple_pointer_position(NAN,1,600,1000,1200,2000,640,480,0,&x,&y));
    assert(!ut3_apple_pointer_position(1,1,0,1000,1200,2000,640,480,0,&x,&y));
    assert(!ut3_apple_pointer_position(1,1,600,1000,1200,2000,0,480,0,&x,&y));
    assert(!ut3_apple_pointer_position(1,1,600,1000,1200,2000,UINT32_MAX,480,0,&x,&y));
    puts("PASS iOS touch-to-mouse letterboxing, point/pixel scaling, Y direction, captured drag clamping and invalid extents");
    return 0;
}
