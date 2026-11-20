#include "host.h"
#include "runtime.h"

int main(int argc, char **argv)
{
    const char *game = NULL, *data = NULL;
    int selftest = 0;
    for (int i = 1; i < argc; ++i) {
        if (!strcmp(argv[i], "--game") && i + 1 < argc) game = argv[++i];
        else if (!strcmp(argv[i], "--data") && i + 1 < argc) data = argv[++i];
        else if (!strcmp(argv[i], "--selftest")) selftest = 1;
        else if (!strcmp(argv[i], "-v")) void_verbose = 1;
        else {
            fprintf(stderr, "unknown or incomplete option %s\n", argv[i]);
            return 64;
        }
    }
    if (!game || !data || !selftest) {
        fputs("usage: ut3-runtime-selftest --game PATH --data PATH --selftest [-v]\n", stderr);
        return 64;
    }
    void_process_exit((uint32_t)ut3_game_main(game, data, 1), 0);
    return 0;
}
