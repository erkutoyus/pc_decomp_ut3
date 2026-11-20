/* Exercise the production guest memory map with UE3's actual allocation flags. */
#include "host.h"
#include <assert.h>
#include <unistd.h>
#if defined(__APPLE__)
#include <sys/mman.h>
#endif

void void_process_exit(uint32_t code, int detach) { (void)detach; _exit((int)code); }

static void zeroed(uint32_t address, uint32_t size)
{
    for (uint32_t i = 0; i < size; ++i) assert(!MEM8(address + i));
}

int main(void)
{
    assert(void_guest_reserve());
    uint32_t info = void_vm_alloc(0, 4096, 0x3000, 4);
    assert(info);
    const uint32_t sizes[] = {1, 0x10000, 0x10001};
    for (unsigned i = 0; i < sizeof sizes / sizeof *sizes; ++i) {
        uint32_t rounded = (sizes[i] + 4095) & ~4095u;
        uint32_t address = void_vm_alloc(0, sizes[i], 0x1000, 4);
        assert(address && !(address & 0xFFFF));
        assert(void_vm_readable(address, rounded) && void_vm_writable(address, rounded));
        zeroed(address, rounded);
        assert(void_vm_query(address, info) == 28);
        assert(MEM32(info) == address && MEM32(info + 4) == address);
        assert(MEM32(info + 8) == 4 && MEM32(info + 12) == rounded);
        assert(MEM32(info + 16) == 0x1000 && MEM32(info + 20) == 4 && MEM32(info + 24) == 0x20000);
        MEM32(address) = 0x12345678;
        assert(void_vm_alloc(address, sizes[i], 0x1000, 4) == address);
        assert(MEM32(address) == 0x12345678);  /* Recommit keeps live contents. */
        memset(GPTR(address), 0xAB, rounded);
        assert(void_vm_free(address, rounded, 0x4000));
        assert(!void_vm_readable(address, rounded));
        assert(void_vm_alloc(address, sizes[i], 0x1000, 4) == address);
        zeroed(address, rounded);
        assert(void_vm_free(address, 0, 0x8000));
        assert(void_vm_query(address, info) == 28 && MEM32(info + 16) == 0x10000);
        assert(!void_vm_alloc(address, sizes[i], 0x1000, 4));
        assert(void_get_last_error() == ERROR_INVALID_ADDRESS_);
    }
    uint32_t reserved = void_vm_alloc(0, 0x3000, 0x2000, 4);
    assert(reserved && !void_vm_readable(reserved, 0x3000));
    assert(void_vm_alloc(reserved + 0xFFF, 2, 0x1000, 4) == reserved);
    assert(void_vm_readable(reserved, 0x2000) && !void_vm_readable(reserved + 0x2000, 1));
    assert(!void_vm_alloc(reserved + 0x2FFF, 2, 0x1000, 4));
    assert(!void_vm_readable(reserved + 0x2000, 1)); /* Failed ranges are not partially committed. */
    MEM8(reserved) = 0xA5;
    MEM8(reserved + 0x1000) = 0x5A;
    assert(void_vm_free(reserved, 0x1000, 0x4000));
    assert(!void_vm_readable(reserved, 0x1000));
    assert(void_vm_alloc(reserved, 0x1000, 0x1000, 4) == reserved);
    assert(MEM8(reserved) == 0 && MEM8(reserved + 0x1000) == 0x5A);
    assert(void_vm_free(reserved, 0, 0x8000));
    assert(!void_vm_alloc(0, 0xFFFFFFFF, 0x1000, 4));
    assert(!void_vm_alloc(0xFFFFFFF0, 0x100, 0x1000, 4));
    assert(!void_vm_alloc(0x7FFDFFF0, 0x100, 0x1000, 4));
    assert(!void_vm_alloc(0, 0, 0x1000, 4));
#if defined(__APPLE__)
    FILE *file = tmpfile();
    assert(file);
    int fd = fileno(file);
    uint8_t byte = 0xA5;
    assert(!ftruncate(fd, 0x20000));
    assert(pwrite(fd, &byte, 1, 0x10000) == 1);
    uint32_t view = void_vm_map_file(fd, 0x10000, GUEST_PAGE, 1, 1);
    assert(view && MEM8(view) == 0xA5);
    assert(void_vm_writable(view, GUEST_PAGE) && !void_vm_readable(view + GUEST_PAGE, 1));
    MEM8(view) = 0x5A;
    assert(!msync(GPTR(view), GUEST_PAGE, MS_SYNC));
    assert(void_vm_unmap_file(view) && !void_vm_readable(view, 1));
    assert(pread(fd, &byte, 1, 0x10000) == 1 && byte == 0x5A);
    assert(!void_vm_map_file(fd, 1, GUEST_PAGE, 0, 0));
    assert(void_get_last_error() == ERROR_INVALID_PARAMETER_);
    fclose(file);
    puts("Darwin file view PASS: aligned shared view, write-through, release, and invalid offset");
#endif
    assert(void_vm_free(info, 0, 0x8000));
    puts("VirtualAlloc production host PASS: NULL COMMIT reserve, alignment, rounding, query, zeroing, recommit, decommit/release, non-NULL failure and overflow");
    return 0;
}
