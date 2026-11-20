/* Data-source adapter for the pinned game's GetProductKey(out, capacity).
 * Its callers still perform the original key validation. No IsKeyValid,
 * entitlement check, key generator, or generic Crypt32 routine is replaced. */
#include "host.h"
#include "ProductKey.h"
#include <ctype.h>
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <sys/stat.h>
#include <unistd.h>

enum { PRODUCT_KEY_GETTER = 0x0120E200u, PRODUCT_KEY_VALIDATOR = 0x01228D20u,
       PRODUCT_ID_OFFSET = 0x27cu, PRODUCT_KEY_BYTES = 19 };
static unsigned char file_key[PRODUCT_KEY_BYTES];
static int file_key_loaded;
static void_fn original_getter;
static int validation_done, validation_result;
static uint16_t validated_product;
int ut3_apple_has_product_key_file(void) { return file_key_loaded; }

static void key_wipe(void *memory, size_t size)
{
    volatile unsigned char *p = memory;
    while (size--) *p++ = 0;
}

static int key_space(unsigned char c)
{
    return c == ' ' || c == '\t' || c == '\r' || c == '\n';
}

static int parse_key(const unsigned char *bytes, size_t count, unsigned char out[PRODUCT_KEY_BYTES])
{
    if (count >= 3 && !memcmp(bytes, "\xef\xbb\xbf", 3)) { bytes += 3; count -= 3; }
    while (count && key_space(*bytes)) { ++bytes; --count; }
    while (count && key_space(bytes[count - 1])) --count;
    if (count != 16 && count != PRODUCT_KEY_BYTES) return -1;
    size_t at = 0;
    for (unsigned i = 0; i < PRODUCT_KEY_BYTES; ++i) {
        if (i == 4 || i == 9 || i == 14) {
            if (count == PRODUCT_KEY_BYTES && bytes[at++] != '-') return -1;
            out[i] = '-';
        } else {
            unsigned char c = bytes[at++];
            if (c >= 'a' && c <= 'z') c -= 'a' - 'A';
            if (!((c >= 'A' && c <= 'Z') || (c >= '0' && c <= '9'))) return -1;
            out[i] = c;
        }
    }
    return 1;
}

static int read_key(const char *directory)
{
    if (!directory || !*directory) return 0;
    char path[4096];
    int count = snprintf(path, sizeof path, "%s/cdkey.txt", directory);
    if (count < 0 || (size_t)count >= sizeof path) return -1;
    int fd = open(path, O_RDONLY | O_CLOEXEC | O_NOFOLLOW);
    if (fd < 0) return errno == ENOENT ? 0 : -1;
    struct stat info;
    unsigned char bytes[257] = {0}, parsed[PRODUCT_KEY_BYTES] = {0};
    int result = -1;
    if (fstat(fd, &info) || !S_ISREG(info.st_mode) || info.st_size < 1 || info.st_size > 256) goto done;
    size_t used = 0;
    for (;;) {
        ssize_t amount = read(fd, bytes + used, sizeof bytes - used);
        if (amount < 0) { if (errno == EINTR) continue; goto done; }
        if (!amount) break;
        used += (size_t)amount;
        if (used == sizeof bytes) goto done;
    }
    result = parse_key(bytes, used, parsed);
    if (result == 1) {
        memcpy(file_key, parsed, sizeof file_key);
        file_key_loaded = 1;
    }
done:
    close(fd);
    key_wipe(bytes, sizeof bytes);
    key_wipe(parsed, sizeof parsed);
    return result;
}

int ut3_apple_configure_product_key(const char *game, const char *data, const char *documents)
{
    file_key_loaded = 0;
    validation_done = validation_result = 0;
    key_wipe(file_key, sizeof file_key);
    const char *candidates[] = {documents, game, data};
    for (unsigned i = 0; i < sizeof candidates / sizeof candidates[0]; ++i) {
        int result = read_key(candidates[i]);
        if (result) return result;
    }
    return 0;
}

static int validate_file_key(void)
{
    if (g_ecx > UINT32_MAX - PRODUCT_ID_OFFSET ||
        !void_vm_readable(g_ecx + PRODUCT_ID_OFFSET, 2)) return 0;
    uint16_t product;
    memcpy(&product, GPTR(g_ecx + PRODUCT_ID_OFFSET), sizeof product);
    if (validation_done && product == validated_product) return validation_result;
    void_regs before;
    void_regs_save(&before);
    uint32_t input = void_galloc(PRODUCT_KEY_BYTES + 1);
    if (!input) return 0;
    memcpy(GPTR(input), file_key, PRODUCT_KEY_BYTES);
    ((unsigned char *)GPTR(input))[PRODUCT_KEY_BYTES] = 0;
    const uint32_t arguments[] = {input, product};
    /* Original SetProductKey calls this exact cdecl validator before saving.
     * In particular, a successful file read alone must not count as a valid key. */
    uint32_t accepted = void_call_guest(PRODUCT_KEY_VALIDATOR, 2, arguments, 0);
    key_wipe(GPTR(input), PRODUCT_KEY_BYTES + 1);
    void_gfree(input);
    void_regs_load(&before);
    validated_product = product;
    validation_done = 1;
    validation_result = accepted != 0;
    void_log(validation_result ? "[product-key] original game validator accepted cdkey.txt"
                               : "[product-key] original game validator rejected cdkey.txt");
    return validation_result;
}

static void product_key_getter(void)
{
    if (!file_key_loaded) { original_getter(); return; }
    uint32_t output = ARG(0), capacity = ARG(1);
    int accepted = capacity >= PRODUCT_KEY_BYTES && void_vm_writable(output, PRODUCT_KEY_BYTES) && validate_file_key();
    g_eax = accepted;
    if (g_eax) memcpy(GPTR(output), file_key, PRODUCT_KEY_BYTES);
    /* Pinned thiscall returns exactly 19 ANSI bytes (no NUL), BOOL, ret 8. */
    g_esp += 12;
}

int ut3_apple_install_product_key(void)
{
    if (!file_key_loaded || original_getter) return 1;
    static const unsigned char expected[] = {
        0x55,0x8b,0xec,0x81,0xec,0x0c,0x01,0,0,0xa1,0xe0,0x24,0xd3,0x01,0x33,0xc5
    };
    static const unsigned char validator_expected[] = {
        0x55,0x8b,0xec,0x83,0xec,0x58,0xa1,0xe0,0x24,0xd3,0x01,0x33,0xc5,0x89,0x45,0xf8
    };
    void_fn original = void_dispatch_find(PRODUCT_KEY_GETTER);
    if (!original || !void_vm_readable(PRODUCT_KEY_GETTER, sizeof expected) ||
        memcmp(GPTR(PRODUCT_KEY_GETTER), expected, sizeof expected) ||
        !void_dispatch_find(PRODUCT_KEY_VALIDATOR) ||
        !void_vm_readable(PRODUCT_KEY_VALIDATOR, sizeof validator_expected) ||
        memcmp(GPTR(PRODUCT_KEY_VALIDATOR), validator_expected, sizeof validator_expected)) {
        void_log("[product-key] pinned reader mismatch; refusing file adapter");
        return 0;
    }
    original_getter = original;
    void_dispatch_add(PRODUCT_KEY_GETTER, product_key_getter);
    void_log("[product-key] using owner-provided cdkey.txt; original game validation unchanged");
    return 1;
}
