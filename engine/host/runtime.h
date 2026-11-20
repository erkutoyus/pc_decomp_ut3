#ifndef UT3_RUNTIME_H
#define UT3_RUNTIME_H

#include <stdint.h>

int ut3_game_main(const char *game, const char *data, int selftest);
_Noreturn void void_process_exit(uint32_t code, int run_detach);

/* Run one startup check on the engine thread. Process-owned guest state
 * survives until shutdown. Call once per process. */
#if defined(__APPLE__)
int ut3_validate_startup(const char *game, const char *data);
#endif

#endif
