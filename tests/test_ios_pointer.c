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
    // Native 4:3 iPad window and the owner's 5:4 guest mode: side bars
    // do not intercept clicks, and the bottom-right menu remains reachable.
    assert(ut3_apple_pointer_position(512,384,1024,768,2048,1536,1280,1024,0,&x,&y)&&x==640&&y==512);
    assert(!ut3_apple_pointer_position(20,384,1024,768,2048,1536,1280,1024,0,&x,&y));
    assert(ut3_apple_pointer_position(991.9,767.9,1024,768,2048,1536,1280,1024,0,&x,&y)&&x==1279&&y==1023);
    // Rotate the same native view with a retained 720p backbuffer.
    assert(ut3_apple_pointer_position(384,512,768,1024,1536,2048,1280,720,0,&x,&y)&&x==640&&y==360);
    assert(!ut3_apple_pointer_position(384,100,768,1024,1536,2048,1280,720,0,&x,&y));
    assert(!ut3_apple_pointer_position(NAN,1,600,1000,1200,2000,640,480,0,&x,&y));
    assert(!ut3_apple_pointer_position(1,1,0,1000,1200,2000,640,480,0,&x,&y));
    assert(!ut3_apple_pointer_position(1,1,600,1000,1200,2000,0,480,0,&x,&y));
    assert(!ut3_apple_pointer_position(1,1,600,1000,1200,2000,UINT32_MAX,480,0,&x,&y));
    puts("PASS iOS touch-to-mouse letterboxing, point/pixel scaling, Y direction, captured drag clamping and invalid extents");
    return 0;
}
