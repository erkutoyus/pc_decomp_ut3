#define UT3_IOS
#include "../platform/apple/frame.c"
#include <assert.h>
#include <unistd.h>
static atomic_int begun, frames;
void void_ui_hud_frame_begin(void) { atomic_fetch_add(&frames,1); }
void void_ui_camera_frame_begin(void) {}
int void_vm_readable(uint32_t p,uint32_t n) { (void)p;(void)n;return 0; }
void void_log(const char *format,...) { (void)format; }
uint32_t void_call_guest(uint32_t va,int n,const uint32_t *args,int pops)
{ (void)va;(void)n;(void)args;(void)pops;assert(0);return 0; }
void_fn void_dispatch_find(uint32_t va) { (void)va;return NULL; }
static void *tick(void *unused)
{
    (void)unused;atomic_store(&begun,1);ut3_adpf_work_begin();return NULL;
}
static pthread_t suspended_tick(void)
{
    ut3_apple_set_suspended(1);atomic_store(&begun,0);
    pthread_t thread;assert(!pthread_create(&thread,NULL,tick,NULL));
    for(unsigned n=0;!atomic_load(&begun)&&n<1000;++n)usleep(1000);
    assert(atomic_load(&begun));usleep(20000);
    return thread;
}
int main(void)
{
    pthread_t thread=suspended_tick();assert(!atomic_load(&frames));
    ut3_apple_set_suspended(0);assert(!pthread_join(thread,NULL));assert(atomic_load(&frames)==1);
    thread=suspended_tick();assert(atomic_load(&frames)==1);
    ut3_apple_request_guest_close();assert(!pthread_join(thread,NULL));assert(atomic_load(&frames)==2);
    ut3_apple_set_suspended(0);ut3_adpf_work_begin();assert(atomic_load(&frames)==3);
    puts("PASS Apple frame suspension, resume and close-request wakeup; original frame observers retained");
    return 0;
}
