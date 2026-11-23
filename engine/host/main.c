/* ARM64 command-line bring-up; the guest instructions are compiled ahead of time. */
#define _GNU_SOURCE
#include "host.h"
#include "runtime.h"
#include <errno.h>
#include <sys/stat.h>
#include <unistd.h>

#if defined(__APPLE__)
int ut3_apple_install_product_key(void);
static void (*guest_did_exit)(uint32_t);
void ut3_apple_set_exit_callback(void (*callback)(uint32_t)) { guest_did_exit = callback; }
#endif

int void_modules_start(void);
void void_files_std_init(void);
void void_loading_init(void);
void void_ui_hud_init(void);
int void_openspy_init(void);
int void_profiles_init(void);
void void_texture_cache_init(const char *game);
extern void void_crash_exit(uint32_t code);
extern void void_features_init(void);
#ifdef VOID_FUNCTION_COVERAGE
extern int void_function_coverage_start(const char *userdata);
#endif

_Noreturn void void_process_exit(uint32_t code, int run_detach)
{
    if (run_detach) void_modules_detach_all(1);
    void_log("[ut3] process exit %u", code);
    void_log_flush();
    void_crash_exit(code);
#if defined(__APPLE__)
    if (guest_did_exit) guest_did_exit(code);
#endif
    _exit((int)code);
}

#if defined(__APPLE__)
void void_uninstall_fault_handlers(void);
void void_crash_close(void);

int ut3_validate_startup(const char *game, const char *data)
{
    int code = ut3_game_main(game, data, 1);
    void_log("[ut3] startup worker finished with status %d", code);
    void_log_flush();
    void_crash_exit((uint32_t)code);
    void_uninstall_fault_handlers();
    void_crash_close();
    void_log_open(NULL);
    return code;
}
#endif

int ut3_game_main(const char *game, const char *data, int selftest)
{
    setvbuf(stderr, NULL, _IONBF, 0);
    void_install_fault_handlers();
    if (mkdir(data, 0775) && errno != EEXIST) {
        fprintf(stderr, "cannot create userdata %s: %s\n", data, strerror(errno));
        return 66;
    }
    char log_path[1024];
    if (snprintf(log_path, sizeof log_path, "%s/ut3.log", data) >= (int)sizeof log_path) return 64;
    void_log_open(log_path);
#ifdef VOID_FUNCTION_COVERAGE
    if (!void_function_coverage_start(data)) return 69;
#endif
    void_log("[ut3] ARM64 static host: game=%s data=%s", game, data);
    if (!void_guest_reserve()) return 65;
    void_threads_init();
    void_dispatch_init();
    if (!void_files_init(game, data)) return 66;
#if defined(__APPLE__)
    extern int ut3_apple_controller_config(const char *,const char *);
    if (!selftest && !ut3_apple_controller_config(game,data)) return 66;
#endif
    void_files_std_init();
    if (!void_modules_init(NULL)) return 67;
    if (!void_openspy_init()) return 67;
    if (!void_profiles_init()) return 67;
#if defined(__APPLE__)
    if (!ut3_apple_install_product_key()) return 67;
#endif
    void_texture_cache_init(game);
    void_loading_init();
    void_ui_hud_init();
    void_features_init();
    void_machine_enter();
    if (!void_modules_start()) return 68;
    uint32_t base = void_module_exe_base();
    uint32_t entry = base + MEM32(base + MEM32(base + 0x3C) + 0x28);
    if (!void_dispatch_find(entry)) void_lift_trap(entry, "PE entry has no statically compiled function");
    if (selftest) {
        uint32_t block = void_galloc(32);
        if (!block || !void_vm_writable(block, 32)) void_fatal("guest heap selftest failed");
        MEM32(block) = 0x12345678u;
        if (MEM32(block) != 0x12345678u) void_fatal("guest memory selftest failed");
        void_gfree(block);
        void_log("[selftest] PE binding, DLL/TLS startup, guest heap and static entry lookup PASS; game entry not executed");
        void_machine_leave();
        return 0;
    }
    void_log("[ut3] starting lifted UT3.exe at %08X", entry);
    uint32_t result = void_call_guest(entry, 0, NULL, 1);
    void_log("[ut3] UT3.exe entry returned %08X", result);
    void_machine_leave();
    return (int)result;
}

#if !defined(UT3_ANDROID_APP) && !defined(UT3_MACOS_HEADLESS)
int main(int argc, char **argv)
{
    const char *game = "/sdcard/UT3/game", *data = "/sdcard/UT3/userdata";
    int selftest = 0;
    for (int i = 1; i < argc; ++i) {
        if (!strcmp(argv[i], "--game") && i + 1 < argc) game = argv[++i];
        else if (!strcmp(argv[i], "--data") && i + 1 < argc) data = argv[++i];
        else if (!strcmp(argv[i], "--selftest")) selftest = 1;
        else if (!strcmp(argv[i], "-v")) void_verbose = 1;
        else { fprintf(stderr, "unknown or incomplete option %s\n", argv[i]); return 64; }
    }
    int code = ut3_game_main(game, data, selftest);
    void_process_exit((uint32_t)code, 0);
}
#endif
