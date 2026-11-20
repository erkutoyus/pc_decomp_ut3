/* Exercise the actual x86 COM slots and native DXVK device through the
 * existing Apple app. The fixture's draw is distinct from the UT3 capture. */
#include "host.h"
#include "runtime.h"
#include <unistd.h>

static uint32_t invoke(uint32_t object, unsigned slot, size_t count, const uint32_t *arguments)
{
    uint32_t stack[15] = {object};
    if (count) memcpy(stack + 1, arguments, count * sizeof *stack);
    return void_call_guest(MEM32(MEM32(object) + slot * 4), (int)count + 1, stack, 1);
}

#define COM(object, slot, ...) invoke(object, slot, sizeof((uint32_t[]){__VA_ARGS__}) / 4, (uint32_t[]){__VA_ARGS__})
#define CHECK(call) do { \
    uint32_t status = (call); \
    if ((int32_t)status < 0) { void_log("[d3d9-probe] %s failed: %08x", #call, status); goto done; } \
} while (0)

#if defined(UT3_IOS)
#include "ios/d3d9_portability_probe.inc"
#endif

static int probe(void)
{
    int result = 1;
    uint32_t args = void_galloc(4096);
    uint32_t parent = 0, device = 0, query = 0, shader = 0, texture = 0;
    const void_shim *create = void_shim_find("d3d9.dll", "Direct3DCreate9", 0);
    const uint32_t sdk = 32;
    if (!create || !args) goto done;
    parent = void_call_guest(void_thunk(create->fn, create->name), 1, &sdk, 1);
    if (!parent) { void_log("[d3d9-probe] Direct3DCreate9 returned NULL"); goto done; }
    const uint32_t count = COM(parent, 6, 0, 22);
    unsigned high_modes = 0;
    for (uint32_t i = 0; i < count; ++i) {
        CHECK(COM(parent, 7, 0, 22, i, args + 512));
        uint32_t width = MEM32(args + 512), height = MEM32(args + 516);
        if (width == 1280 && height == 720) high_modes |= 1;
        if (width == 1920 && height == 1080) high_modes |= 2;
    }
    if (high_modes != 3) {
        void_log("[d3d9-probe] 720p and 1080p mode enumeration failed");
        goto done;
    }
    for (size_t n = 0; n < 4; ++n) {
        static const uint32_t formats[] = {21, 113, 0x31545844, 0x35545844};
        uint32_t hr = COM(parent, 10, 0, 1, 22, n < 2 ? 1 : 0, 3, formats[n]);
        void_log("[d3d9-probe] CheckDeviceFormat(%08x)=%08x", formats[n], hr);
        if (hr) goto done;
    }
#if defined(UT3_IOS)
    const uint32_t backBufferFormat = 21; // Preserve alpha for exact fallback readback checks.
#else
    const uint32_t backBufferFormat = 22;
#endif
    const uint32_t present[14] = {640, 400, backBufferFormat, 1, 0, 0, 1, 0, 1, 1, 75, 0, 0, 0};
    memcpy(GPTR(args), present, sizeof present);
    CHECK(COM(parent, 16, 0, 1, 0, 0x40, args, args + 64));
    device = MEM32(args + 64);
    if (!device) goto done;
    void_log("[d3d9-probe] Device and D24S8-compatible depth surface created");
    CHECK(COM(device, 23, 4, 4, 1, 0, 21, 1, args + 80, 0));
    texture = MEM32(args + 80);
    if (!texture) goto done;
    CHECK(COM(texture, 19, 0, args + 88, 0, 0));
    if (!MEM32(args + 92) || MEM32(args + 88) < 16) goto done;
    for (unsigned row = 0; row < 4; ++row)
        memset(GPTR(MEM32(args + 92) + row * MEM32(args + 88)), 0xff, 16);
    CHECK(COM(texture, 20, 0));

#if defined(UT3_IOS)
    if (portability_probe(device, texture, args)) goto done;
    CHECK(COM(device, 89, 0x44));
#endif

    /* ps_3_0: def c0, 1, 0, 0, 1; mov oC0, c0; end. */
    const uint32_t bytecode[] = {0xffff0300, 0x05000051, 0xa00f0000, 0x3f800000, 0, 0, 0x3f800000,
                                 0x02000001, 0x800f0800, 0xa0e40000, 0x0000ffff};
    memcpy(GPTR(args + 128), bytecode, sizeof bytecode);
    CHECK(COM(device, 106, args + 128, args + 68));
    shader = MEM32(args + 68);
    if (!shader) goto done;
    CHECK(COM(device, 107, shader));
    CHECK(COM(device, 118, 9, args + 72));
    query = MEM32(args + 72);
    if (!query) goto done;
    const struct { float x, y, z, rhw; uint32_t color; } vertices[] = {
        {80, 60, 0.5f, 1, 0xffffffff}, {520, 120, 0.5f, 1, 0xffffffff}, {110, 320, 0.5f, 1, 0xffffffff}
    };
    memcpy(GPTR(args + 256), vertices, sizeof vertices);
    CHECK(COM(device, 43, 0, 0, 3, 0xff176287, UINT32_C(0x3f800000), 0));
    CHECK(COM(device, 41));
    CHECK(COM(device, 57, 22, 1));
    CHECK(COM(device, 89, 0x44));
    CHECK(COM(query, 6, 2));
    CHECK(COM(device, 83, 4, 1, args + 256, sizeof vertices[0]));
    CHECK(COM(query, 6, 1));
    CHECK(COM(device, 42));
    CHECK(COM(device, 17, 0, 0, 0, 0));
    uint32_t ready = 1;
    for (unsigned attempt = 0; attempt < 300 && ready == 1; ++attempt) {
        ready = COM(query, 7, args + 76, 4, 1);
        if (ready == 1) usleep(1000);
    }
    if (ready || !MEM32(args + 76)) {
        void_log("[d3d9-probe] occlusion result %08x, samples %u", ready, MEM32(args + 76));
        goto done;
    }
    void_log("[d3d9-probe] D3D9 COM, depth/BC formats, SM3, draw, Present and occlusion PASS (%u samples)", MEM32(args + 76));
    COM(query, 2);
    query = 0;
    COM(shader, 2);
    shader = 0;
    COM(texture, 2);
    texture = 0;
    static const uint32_t resolutions[][2] = {{1280, 720}, {1920, 1080}};
    for (unsigned i = 0; i < sizeof resolutions / sizeof resolutions[0]; ++i) {
        uint32_t width = resolutions[i][0], height = resolutions[i][1];
        memcpy(GPTR(args), present, sizeof present);
        MEM32(args) = width;
        MEM32(args + 4) = height;
        CHECK(COM(device, 16, args));
        CHECK(COM(device, 18, 0, 0, 0, args + 96));
        uint32_t surface = MEM32(args + 96);
        if (!surface) goto done;
        const uint32_t desc = COM(surface, 12, args + 544);
        COM(surface, 2);
        if (desc || MEM32(args + 568) != width || MEM32(args + 572) != height) {
            void_log("[d3d9-probe] expected back buffer %ux%u, got %ux%u", width, height,
                     MEM32(args + 568), MEM32(args + 572));
            goto done;
        }
        CHECK(COM(device, 43, 0, 0, 1, 0xff176287, 0, 0));
        CHECK(COM(device, 17, 0, 0, 0, 0));
        void_log("[d3d9-probe] %ux%u Reset, GetBackBuffer and Present PASS", width, height);
    }
    result = 0;

done:
    if (query) COM(query, 2);
    if (shader) COM(shader, 2);
    if (texture) COM(texture, 2);
    if (device) COM(device, 2);
    if (parent) COM(parent, 2);
    if (args) void_gfree(args);
    return result;
}

int ut3_validate_d3d9(const char *game, const char *data)
{
    int status = ut3_validate_startup(game, data);
    if (status) return status;
    void_machine_enter();
    status = probe();
    void_machine_leave();
    return status;
}
