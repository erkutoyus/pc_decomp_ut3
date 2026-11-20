#include <stdatomic.h>
#include "host.h"
#include <time.h>

/* The generated frame hook also publishes HUD and camera state. Apple has no ADPF session. */
void void_ui_hud_frame_begin(void);
void void_ui_camera_frame_begin(void);
static void (*log_audio)(void);
void ut3_apple_set_audio_logger(void (*callback)(void)) { log_audio = callback; }

/* Called only from the frame's diagnostics callback while the VM is owned.
 * GWorld is also used by game_native.c; FName's UTF-16 layout is shared with
 * touch_game.c. Never call a guest function or mutate its objects to profile. */
static int profile_word(uint32_t address,uint32_t *value)
{
    if(!address||!void_vm_readable(address,4))return 0;
    memcpy(value,GPTR(address),4);return 1;
}
static int profile_object_name(uint32_t object,char out[80])
{
    uint32_t index,table,entry;
    if(!object||object>UINT32_MAX-0x30||!profile_word(object+0x2c,&index)||index>=1048576||
       !profile_word(0x01DD46E8u,&table)||!table||index>(UINT32_MAX-table)/4||
       !profile_word(table+index*4,&entry)||!entry||entry>UINT32_MAX-176)return 0;
    for(unsigned i=0;i<80;++i) {
        uint16_t c;if(!void_vm_readable(entry+16+i*2,2))return 0;
        memcpy(&c,GPTR(entry+16+i*2),2);
        if(!c){out[i]=0;return 1;}if(c<32||c>126)return 0;out[i]=(char)c;
    }
    return 0;
}
const char *ut3_apple_profile_world(void)
{
    static char package[80];char name[80];uint32_t world,outer;
    if(!profile_word(0x01DEE5ECu,&world)||!profile_object_name(world,name)||strcmp(name,"TheWorld")||
       !profile_word(world+0x28,&outer)||!profile_object_name(outer,package))return "unknown";
    return package;
}

static atomic_bool close_requested;
static pthread_mutex_t frame_mutex = PTHREAD_MUTEX_INITIALIZER;
static pthread_cond_t frame_cond = PTHREAD_COND_INITIALIZER;
static int suspended;

void ut3_apple_set_suspended(int value)
{
    pthread_mutex_lock(&frame_mutex);
    suspended = value != 0;
    pthread_cond_broadcast(&frame_cond);
    pthread_mutex_unlock(&frame_mutex);
}

void ut3_apple_request_guest_close(void)
{
    atomic_store_explicit(&close_requested, 1, memory_order_release);
    pthread_mutex_lock(&frame_mutex);
    pthread_cond_broadcast(&frame_cond);
    pthread_mutex_unlock(&frame_mutex);
}

void ut3_adpf_work_begin(void)
{
#if defined(UT3_IOS)
    pthread_mutex_lock(&frame_mutex);
    while (suspended && !atomic_load_explicit(&close_requested, memory_order_acquire))
        pthread_cond_wait(&frame_cond, &frame_mutex);
    pthread_mutex_unlock(&frame_mutex);
#endif
    if (atomic_exchange_explicit(&close_requested, 0, memory_order_acq_rel)) {
        /* UT3 2.1's orderly appRequestExit path sets the launch loop's exit flag.
         * A desktop WM_CLOSE alone only destroys the emulated viewport. */
        const uint32_t requestExit = 0x00B6B2E0, exitStore = 0x00B6B30E;
        static const uint8_t entry[] = {0xa1,0x40,0x30,0xd1,0x01,0x56,0x8b,0x74,0x24,0x08};
        static const uint8_t store[] = {0xc7,0x05,0xd0,0x44,0xdb,0x01,0x01,0,0,0};
        if (void_vm_readable(requestExit, sizeof entry) && !memcmp(GPTR(requestExit), entry, sizeof entry) &&
            void_vm_readable(exitStore, sizeof store) && !memcmp(GPTR(exitStore), store, sizeof store) &&
            void_dispatch_find(requestExit)) {
            const uint32_t force = 0;
            void_log("[ut3-shell] requesting orderly guest exit on the engine thread");
            void_call_guest(requestExit, 1, &force, 0);
        } else void_log("[ut3-shell] guest exit routine did not match the pinned image");
    }
    void_ui_hud_frame_begin();
    void_ui_camera_frame_begin();
    if (log_audio) {
        static time_t last;
        struct timespec now;
        if (!clock_gettime(CLOCK_MONOTONIC, &now) && now.tv_sec - last >= 5) {
            last = now.tv_sec;
            log_audio();
        }
    }
}
