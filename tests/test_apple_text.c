/* Actual production input queue; no JNI or script publisher required. */
#include "../engine/host/input.c"
#include <assert.h>
static unsigned count, key_events;
static uint32_t chars[1024];
int void_machine_is_owned(void) { return 0; }
int void_touch_game_details(uint32_t out[2]) { (void)out; return 0; }
int void_touch_game_read(uint32_t out[4]) { (void)out; return 0; }
int void_touch_steer(float out[3], uint32_t *flags) { (void)out;(void)flags;return 0; }
int void_touch_text_request(int cmd,const uint16_t *text,int len,uint32_t target) { (void)cmd;(void)text;(void)len;(void)target;return 0; }
int void_touch_text_snapshot(uint16_t text[257],uint32_t *target,uint32_t *flags) { (void)text;(void)target;(void)flags;return 0; }
int void_touch_ui_control(void) { return 0; }
int void_touch_ui_mouse(uint32_t out[2]) { (void)out;return 0; }
int void_touch_ui_scroll(int steps) { (void)steps;return 0; }
int void_touch_weapon_request(uint32_t request) { (void)request;return 0; }
void void_loading_movie_input(void) {}
uint32_t void_tick_ms(void) { return 1; }
uint64_t void_monotonic_ns(void) { return 1000000; }
uint32_t void_window_main(void) { return 1; }
void void_log(const char *format,...) { (void)format; }
void void_post_message(uint32_t window,uint32_t message,uint32_t value,uint32_t parameter)
{
    assert(window==1);
    if(message==0x102) { assert(parameter==1 && count<1024); chars[count++]=value; }
    if(message==0x100 || message==0x101) ++key_events;
}
int main(void)
{
    const uint16_t text[]={'A',0x416,0xd83d,0xde00};
    assert(void_input_text_utf16(text,4));
    void_input_pump(); assert(count==4 && chars[0]=='A' && chars[1]==0x416 && chars[2]==0xd83d && chars[3]==0xde00);
    assert(!touch_game_active && !key_events); // Native typing is independent of Android UI metadata.
    const uint16_t malformed[][2]={{0xd800,0},{0xdc00,0},{0xd800,'x'},{8,0},{13,0},{0x2028,0}};
    for(unsigned i=0;i<sizeof malformed/sizeof *malformed;++i) assert(!void_input_text_utf16(malformed[i],i==2?2:1));
    assert(!void_input_text_utf16(NULL,1) && !void_input_text_utf16(text,-1));
    assert(void_input_text_utf16(NULL,0));
    uint16_t full[257];for(unsigned i=0;i<257;++i)full[i]='x';
    assert(!void_input_text_utf16(full,257));
    assert(void_input_text_utf16(full,256) && void_input_text_utf16(full,256));
    assert(!void_input_text_utf16(text,4));
    void_input_pump();assert(count==516);
    void_input_key('W',1);
    assert(void_input_text_utf16(text,4));
    void_input_pump();assert(void_input_key_state('W')<0 && count==520);
    void_input_release_physical();void_input_pump();assert(void_input_key_state('W')>=0);
    // A full-surface ClipCursor follows an iOS back-buffer Reset, while
    // ordinary desktop changes and custom guest clips retain their contract.
    void_input_set_screen_size(640,480);
    int32_t full_clip[4]={0,0,640,480}, bounds[4];
    assert(void_input_clip_cursor(full_clip));
    void_input_resize_surface(1920,1080);
    void_input_mouse_motion(0,0,1910,1070);
    uint32_t x,y;void_input_cursor(&x,&y);assert(x==1910&&y==1070);
    void_input_clip_bounds(bounds);assert(bounds[2]==1920&&bounds[3]==1080);
    int32_t custom_clip[4]={10,20,100,200};
    assert(void_input_clip_cursor(custom_clip));
    void_input_resize_surface(1280,720);void_input_mouse_motion(0,0,1270,710);
    void_input_cursor(&x,&y);assert(x==99&&y==199);
    assert(void_input_clip_cursor(NULL));
    void_input_resize_surface(640,480);void_input_mouse_motion(0,0,639,479);
    void_input_cursor(&x,&y);assert(x==639&&y==479);
    void_input_resize_surface(0,1080);int w,h;void_input_screen_size(&w,&h);assert(w==640&&h==480);
    puts("PASS native UTF16 WM_CHAR queue, surrogate validation, capacity, no publisher dependency and physical-key ownership");
    return 0;
}
