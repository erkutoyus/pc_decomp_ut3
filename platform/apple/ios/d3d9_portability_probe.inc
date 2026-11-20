/* GPU readback through the existing guest COM ABI. Distinguish real bound
 * sampling from null textures, and in-range from negative/large relative
 * vertex constants. No Vulkan feature bits are falsified by these tests. */
static int portability_pixel(uint32_t device, uint32_t args, uint32_t expected)
{
    uint32_t source = 0, copy = 0;
    int status = 1;
    if (COM(device, 18, 0, 0, 0, args + 1024)) goto done;
    source = MEM32(args + 1024);
    if (COM(device, 36, 640, 400, 21, 2, args + 1028, 0)) goto done;
    copy = MEM32(args + 1028);
    if (COM(device, 32, source, copy)) goto done;
    if (COM(copy, 13, args + 1040, 0, 0x10)) goto done;
    uint32_t pitch = MEM32(args + 1040), pixels = MEM32(args + 1044);
    uint32_t pixel = MEM32(pixels + pitch * 200 + 320 * 4);
    COM(copy, 14);
    if (pixel != expected) {
        void_log("[d3d9-portability] ARGB expected %08x, got %08x", expected, pixel);
        goto done;
    }
    status = 0;
done:
    if (copy) COM(copy, 2);
    if (source) COM(source, 2);
    return status;
}

static int portability_probe(uint32_t device, uint32_t texture, uint32_t args)
{
    uint32_t ps = 0, vs = 0;
    int status = 1;
    const float quad[][6] = {
        {0, 0, 0.5f, 1, 0, 0}, {640, 0, 0.5f, 1, 1, 0},
        {0, 400, 0.5f, 1, 0, 1}, {640, 400, 0.5f, 1, 1, 1}
    };
    CHECK(COM(device, 57, 7, 0));
    CHECK(COM(device, 57, 22, 1));
    CHECK(COM(device, 57, 27, 0));
    CHECK(COM(device, 92, 0));
    CHECK(COM(device, 89, 0x104));
    for (unsigned test = 0; test < 5; ++test) {
        uint32_t shader[] = {
            0xffff0300, 0x0200001f, 0x80000005, 0x900f0000,
            0x0200001f, 0x90000000, 0xa00f0800,
            0x03000042, 0x800f0000, 0x90e40000, 0xa0e40800,
            0x02000001, 0x800f0800, 0x80e40000, 0xffff
        };
        if (test == 2) shader[5] = 0xa0000000; // volume sampler
        if (test == 3) shader[5] = 0x98000000; // cube sampler
        memcpy(GPTR(args + 1280), shader, sizeof shader);
        CHECK(COM(device, 106, args + 1280, args + 1080));
        ps = MEM32(args + 1080);
        CHECK(COM(device, 107, ps));
        CHECK(COM(device, 65, 0, test == 0 || test == 4 ? texture : 0));
        memcpy(GPTR(args + 1536), quad, sizeof quad);
        CHECK(COM(device, 43, 0, 0, 1, 0xff123456, 0, 0));
        CHECK(COM(device, 41));
        CHECK(COM(device, 83, 5, 2, args + 1536, sizeof quad[0]));
        CHECK(COM(device, 42));
        if (portability_pixel(device, args, test == 0 || test == 4 ? 0xffffffff : 0xff000000)) goto done;
        void_log("[d3d9-portability] %s pixel readback PASS", (const char *[]) {
            "bound 2D", "null 2D", "null volume", "null cube", "rebound 2D"
        }[test]);
        CHECK(COM(device, 107, 0));
        COM(ps, 2); ps = 0;
    }
    const uint32_t passColor[] = {0xffff0300, 0x0200001f, 0x8000000a, 0x900f0000,
                                 0x02000001, 0x800f0800, 0x90e40000, 0xffff};
    memcpy(GPTR(args + 1280), passColor, sizeof passColor);
    CHECK(COM(device, 106, args + 1280, args + 1080));
    ps = MEM32(args + 1080);
    CHECK(COM(device, 107, ps));
    CHECK(COM(device, 89, 0x4002)); // XYZW position0
    const float clipQuad[][4] = {{-1,1,0.5f,1},{1,1,0.5f,1},{-1,-1,0.5f,1},{1,-1,0.5f,1}};
    memcpy(GPTR(args + 1536), clipQuad, sizeof clipQuad);
    for (unsigned test = 0; test < 3; ++test) {
        uint32_t code[] = {
            0xfffe0300,
            0x0200001f, 0x80000000, 0x900f0000, // dcl_position v0
            0x0200001f, 0x80000000, 0xe00f0000, // dcl_position o0
            0x0200001f, 0x8000000a, 0xe00f0001, // dcl_color o1
            0x05000051, 0xa00f0000, 0x3f800000, 0, 0, 0x3f800000, // def c0 red
            0x05000051, 0xa00f0001, 0, 0, 0, 0, // def c1 address
            0x0200002e, 0xb0010000, 0xa0000001, // mova a0.x,c1.x
            0x02000001, 0xe00f0000, 0x90e40000, // mov o0,v0
            0x03000001, 0xe00f0001, 0xa0e42000, 0xb0000000, // mov o1,c[a0.x]
            0xffff
        };
        code[18] = test == 0 ? 0 : test == 1 ? 0xbf800000 : 0x45800000; // 0,-1,4096
        memcpy(GPTR(args + 1280), code, sizeof code);
        CHECK(COM(device, 91, args + 1280, args + 1084));
        vs = MEM32(args + 1084);
        CHECK(COM(device, 92, vs));
        CHECK(COM(device, 43, 0, 0, 1, 0xff123456, 0, 0));
        CHECK(COM(device, 41));
        CHECK(COM(device, 83, 5, 2, args + 1536, sizeof clipQuad[0]));
        CHECK(COM(device, 42));
        if (portability_pixel(device, args, test == 0 ? 0xffff0000 : 0)) goto done;
        void_log("[d3d9-portability] relative constant %s pixel readback PASS", (const char *[]) {
            "in range", "negative", "4096 out of range"
        }[test]);
        CHECK(COM(device, 92, 0));
        COM(vs, 2); vs = 0;
    }
    status = 0;
done:
    COM(device, 92, 0);
    COM(device, 107, 0);
    COM(device, 65, 0, 0);
    if (vs) COM(vs, 2);
    if (ps) COM(ps, 2);
    return status;
}
