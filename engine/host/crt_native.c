/* msvcr80 memory primitives in native code: memcpy 0x10014FB0, memmove 0x10015320, memset 0x10014A20.
 *
 * The original memcpy is memmove in MSVC 8 (it copies downwards when the destination starts inside the
 * source, upwards otherwise, with the SSE2 fastcopy_I block loop for large co-aligned copies), so both
 * become bionic memmove over the guest window; memset becomes memset. A WAR-Torlan bot match spent
 * about 1.5% of the game thread in the lifted copies. Memory effects and EAX (the destination) are the
 * original's; the C calling convention leaves ECX, EDX, the flags and the XMM registers undefined after
 * the call, and the original's scratch values there are not reproduced. Ranges that would wrap the
 * 4 GiB guest space keep the lifted code. Callers reach these through the msvcr80 import slots
 * (dispatch); direct calls inside msvcr80 keep the lifted bodies. Exact mode keeps the originals. */
#include "host.h"
#include "native_mode.inc"

static void_fn original_memcpy, original_memmove, original_memset;
static int crt_mode = -1;

static __attribute__((cold, noinline)) int crt_mode_load(void)
{
    crt_mode = void_native_mode(1);
    void_log("[native-crt] memcpy/memmove/memset: mode %d", crt_mode);
    return crt_mode;
}

static inline int crt_native(void)
{
    return __builtin_expect(crt_mode >= 0, 1) ? crt_mode : crt_mode_load();
}

static inline int crt_range(uint32_t address, uint32_t count)
{
    return (uint64_t)address + count <= 0x100000000ull;
}

static void crt_copy(void_fn original)
{
    const uint32_t dst = ARG(0), src = ARG(1), count = ARG(2);
    if (!crt_native() || !crt_range(dst, count) || !crt_range(src, count)) { original(); return; }
    if (count) memmove(GPTR(dst), GPTR(src), count);
    g_eax = dst;
    g_esp += 4;
}

static void crt_memcpy(void) { crt_copy(original_memcpy); }
static void crt_memmove(void) { crt_copy(original_memmove); }

static void crt_memset(void)
{
    const uint32_t dst = ARG(0), value = ARG(1), count = ARG(2);
    if (!crt_native() || !crt_range(dst, count)) { original_memset(); return; }
    if (count) memset(GPTR(dst), (int)(uint8_t)value, count);
    g_eax = dst;
    g_esp += 4;
}

#if defined(__APPLE__)
static void_fn original_vsnwprintf_s;
static int verify_vsnwprintf_s;
enum { CRT_WIDE_LIMIT = 16384, CRT_WIDE_FALLBACK = -2 };

/* Bound each string scan and validate every guest page it reaches. A Windows
 * wchar_t is a UTF-16 code unit, independent of wchar_t on the host. */
static int crt_wide_length(uint32_t address, unsigned limit)
{
    if (!address || (address & 1) || !crt_range(address, 2 * limit)) return -1;
    for (unsigned offset = 0; offset < limit;) {
        uint32_t at = address + 2 * offset;
        unsigned span = (4096 - (at & 4095)) / 2;
        if (span > limit - offset) span = limit - offset;
        if (!void_vm_readable(at, 2 * span)) return -1;
        const uint16_t *units = GPTR(at);
        for (unsigned i = 0; i < span; ++i)
            if (!units[i]) return (int)(offset + i);
        offset += span;
    }
    return -1;
}

static int crt_wide_overlaps(uint32_t dst, unsigned capacity, uint32_t src, unsigned bytes)
{
    return (uint64_t)dst < (uint64_t)src + bytes && (uint64_t)src < (uint64_t)dst + 2 * capacity;
}

static unsigned crt_print_integer(uint16_t *out, uint32_t value, uint16_t type)
{
    const int hexadecimal = type == 'x' || type == 'X';
    const unsigned base = hexadecimal ? 16 : 10;
    const char *digits = type == 'X' ? "0123456789ABCDEF" : "0123456789abcdef";
    unsigned prefix = 0, count = 0;
    uint16_t reversed[10];
    if ((type == 'd' || type == 'i') && value > INT32_MAX) {
        out[prefix++] = '-';
        value = 0u - value;
    }
    do {
        reversed[count++] = (uint8_t)digits[value % base];
        value /= base;
    } while (value);
    for (unsigned i = 0; i < count; ++i) out[prefix + i] = reversed[count - i - 1];
    return prefix + count;
}

static void crt_append_wide(uint16_t *out, unsigned limit, unsigned *used,
                            const uint16_t *units, unsigned length)
{
    if (*used < limit) {
        unsigned available = limit - *used;
        memcpy(out + *used, units, 2 * (length < available ? length : available));
    }
    *used += length;
}

/* Unpadded UTF-16 formatting and its non-error truncation rules in VC80.
 * Keep invalid parameters, modifiers and locale conversions in the guest CRT. */
static int crt_format_wide(uint16_t *out, uint32_t dst, unsigned capacity,
                           unsigned count, uint32_t fmt, uint32_t args, unsigned *written)
{
    int length = crt_wide_length(fmt, 512);
    if (length < 0 || crt_wide_overlaps(dst, capacity, fmt, 2 * (length + 1)))
        return CRT_WIDE_FALLBACK;
    const uint16_t *format = GPTR(fmt);
    unsigned used = 0, limit = capacity - 1;
    if (count < limit) limit = count;
    for (int i = 0; i < length; ++i) {
        uint16_t ch = format[i];
        if (ch != '%' || (ch = format[++i]) == '%') {
            crt_append_wide(out, limit, &used, &ch, 1);
            continue;
        }
        if (ch != 's' && ch != 'd' && ch != 'i' && ch != 'u' && ch != 'x' && ch != 'X')
            return CRT_WIDE_FALLBACK;
        if (!args || !void_vm_readable(args, 4) || crt_wide_overlaps(dst, capacity, args, 4))
            return CRT_WIDE_FALLBACK;
        uint32_t value = MEM32(args);
        args += 4;
        if (ch == 's') {
            int units = crt_wide_length(value, CRT_WIDE_LIMIT);
            if (units < 0 || crt_wide_overlaps(dst, capacity, value, 2 * (units + 1)))
                return CRT_WIDE_FALLBACK;
            crt_append_wide(out, limit, &used, GPTR(value), (unsigned)units);
        } else {
            uint16_t number[11];
            unsigned units = crt_print_integer(number, value, ch);
            crt_append_wide(out, limit, &used, number, units);
        }
    }
    int truncated = used > limit;
    if (truncated && count >= capacity && count != UINT32_MAX) return CRT_WIDE_FALLBACK;
    unsigned produced = truncated ? limit : used;
    out[produced] = 0;
    *written = produced + 1;
    return truncated ? -1 : (int)produced;
}

static void crt_vsnwprintf_s(void)
{
    uint32_t dst = ARG(0), capacity = ARG(1);
    static _Thread_local uint16_t result[CRT_WIDE_LIMIT];
    unsigned written = 0;
    int status = CRT_WIDE_FALLBACK;
    if (dst && !(dst & 1) && capacity && capacity <= CRT_WIDE_LIMIT && void_vm_writable(dst, 2 * capacity))
        status = crt_format_wide(result, dst, capacity, ARG(2), ARG(3), ARG(4), &written);
    if (status == CRT_WIDE_FALLBACK) {
        original_vsnwprintf_s();
        return;
    }
    if (verify_vsnwprintf_s) {
        uint16_t expected[CRT_WIDE_LIMIT];
        memcpy(expected, GPTR(dst), 2 * capacity);
        memcpy(expected, result, 2 * written);
        original_vsnwprintf_s();
        if (g_eax != (uint32_t)status || memcmp(expected, GPTR(dst), 2 * capacity))
            void_fatal("native _vsnwprintf_s disagrees with the pinned VC80 implementation");
        static unsigned verified;
        if (++verified == 1 || verified % 10000 == 0)
            void_log("[native-crt] _vsnwprintf_s matched VC80 on %u calls", verified);
        return;
    }
    memcpy(GPTR(dst), result, 2 * written);
    g_eax = (uint32_t)status;
    g_esp += 4;
}
#endif

void void_crt_native_init(void)
{
    original_memcpy = void_dispatch_find(0x10014FB0u);
    original_memmove = void_dispatch_find(0x10015320u);
    original_memset = void_dispatch_find(0x10014A20u);
    if (!original_memcpy || !original_memmove || !original_memset) {
        void_log("[native-crt] msvcr80 memory primitives not found; keeping the lifted code");
        return;
    }
    void_dispatch_add(0x10014FB0u, crt_memcpy);
    void_dispatch_add(0x10015320u, crt_memmove);
    void_dispatch_add(0x10014A20u, crt_memset);
#if defined(__APPLE__)
    const char *printf_mode = getenv("UT3_CRT_PRINTF");
    if (void_native_mode(1) && (!printf_mode || strcmp(printf_mode, "0"))) {
        /* VC80 _vsnwprintf_s, imported by UT3.exe from the pinned guest DLL. */
        original_vsnwprintf_s = void_dispatch_find(0x1000E8CEu);
        if (original_vsnwprintf_s) {
            verify_vsnwprintf_s = printf_mode && !strcmp(printf_mode, "verify");
            void_dispatch_add(0x1000E8CEu, crt_vsnwprintf_s);
        }
    }
#endif
}
