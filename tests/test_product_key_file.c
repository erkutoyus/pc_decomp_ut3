/* Synthetic data only. Exercises the real parser, source precedence, pinned
 * dispatch/validator guard and x86 thiscall output boundary. The validator's
 * controlled result is an ABI oracle, not a claim of a valid license key. */
#include <assert.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/stat.h>
#define VOID_HOST_H
typedef void (*void_fn)(void);
static uint8_t *memory;
static uint32_t g_eax, g_ecx, g_esp;
static unsigned calls, installed;
static void_fn reader;
static unsigned validate_calls, validation_oracle = 1;
typedef struct { uint32_t eax, ecx, esp; } void_regs;
#define GPTR(p) (memory + (uint32_t)(p))
#define ARG(n) (*(uint32_t *)GPTR(g_esp + 4 + 4 * (n)))
static int void_vm_readable(uint32_t p, uint32_t size) { return p && p < 0x2000000 && size <= 0x2000000 - p; }
static int void_vm_writable(uint32_t p, uint32_t size) { return void_vm_readable(p, size); }
static void original(void) { ++calls; g_eax = 77; g_esp += 12; }
static void_fn void_dispatch_find(uint32_t p) { assert(p == 0x120e200 || p == 0x1228d20); return p == 0x120e200 ? reader : original; }
static void void_dispatch_add(uint32_t p, void_fn fn) { assert(p == 0x120e200); reader = fn; ++installed; }
static void void_log(const char *text) { (void)text; }
static void void_regs_save(void_regs *r) { *r = (void_regs){g_eax,g_ecx,g_esp}; }
static void void_regs_load(const void_regs *r) { g_eax=r->eax; g_ecx=r->ecx; g_esp=r->esp; }
static uint32_t void_galloc(uint32_t size) { assert(size==20); return 0x9000; }
static void void_gfree(uint32_t p) { assert(p==0x9000); for(unsigned i=0;i<20;++i) assert(!*GPTR(p+i)); }
static uint32_t void_call_guest(uint32_t fn,int count,const uint32_t *args,int pops) {
    assert(fn==0x1228d20 && count==2 && pops==0 && args[0]==0x9000 && args[1]==0x1234);
    assert(strlen((char*)GPTR(args[0]))==19);
    ++validate_calls; g_eax=123; g_ecx=456; g_esp=789;
    return validation_oracle;
}
#include "../platform/apple/ProductKey.c"

static void write_test_file(const char *directory, const void *bytes, size_t size)
{
    char path[4096]; snprintf(path, sizeof path, "%s/cdkey.txt", directory);
    FILE *f = fopen(path, "wb"); assert(f);
    assert(fwrite(bytes, 1, size, f) == size); assert(!fclose(f));
}
static void remove_test_file(const char *directory)
{
    char path[4096]; snprintf(path, sizeof path, "%s/cdkey.txt", directory); assert(!unlink(path));
}
static void invoke(uint32_t capacity, uint32_t output)
{
    g_ecx = 0x4321; g_esp = 4096; ARG(0) = output; ARG(1) = capacity;
    reader(); assert(g_esp == 4108 && g_ecx == 0x4321);
}
int main(int argc, char **argv)
{
    if (argc == 3 && !strcmp(argv[1], "--check-file")) {
        int result = ut3_apple_configure_product_key(argv[2], NULL, NULL);
        key_wipe(file_key, sizeof file_key); file_key_loaded = 0;
        puts(result == 1 ? "cdkey.txt format accepted; contents not printed" : "cdkey.txt missing, unreadable or malformed");
        return result == 1 ? 0 : 1;
    }
    char directory[] = "/tmp/ut3-key-test-XXXXXX"; assert(mkdtemp(directory));
    char primary[4096], secondary[4096];
    snprintf(primary, sizeof primary, "%s/primary", directory);
    snprintf(secondary, sizeof secondary, "%s/secondary", directory);
    assert(!mkdir(primary, 0700) && !mkdir(secondary, 0700));
    memory = calloc(1, 0x2000000); assert(memory); reader = original;
    const uint16_t product=0x1234;
    memcpy(GPTR(0x4321+0x27c), &product, 2);
    assert(ut3_apple_configure_product_key(primary, secondary, NULL) == 0);
    assert(ut3_apple_install_product_key() == 1 && installed == 0);
    invoke(19, 8192); assert(calls == 1 && g_eax == 77);

    const char formatted[] = "test-only-notr-eal0\r\n";
    write_test_file(secondary, formatted, sizeof formatted - 1);
    assert(ut3_apple_configure_product_key(primary, secondary, NULL) == 1);
    assert(!ut3_apple_install_product_key() && installed == 0); // Wrong PE entry.
    const uint8_t expected[] = {0x55,0x8b,0xec,0x81,0xec,0x0c,1,0,0,0xa1,0xe0,0x24,0xd3,1,0x33,0xc5};
    memcpy(GPTR(PRODUCT_KEY_GETTER), expected, sizeof expected);
    const uint8_t validator[] = {0x55,0x8b,0xec,0x83,0xec,0x58,0xa1,0xe0,0x24,0xd3,1,0x33,0xc5,0x89,0x45,0xf8};
    memcpy(GPTR(PRODUCT_KEY_VALIDATOR),validator,sizeof validator);
    assert(ut3_apple_install_product_key() == 1 && installed == 1);
    memset(GPTR(8191), 0x5a, 23);
    invoke(19, 8192); assert(g_eax == 1 && calls == 1);
    assert(!memcmp(GPTR(8192), "TEST-ONLY-NOTR-EAL0", 19));
    assert(*GPTR(8191) == 0x5a && *GPTR(8211) == 0x5a); // No extra NUL.
    assert(validate_calls==1);
    memset(GPTR(8192), 0x5a, 19);
    invoke(18, 8192); assert(!g_eax && *GPTR(8192) == 0x5a);
    invoke(20, 0x2000000 - 18); assert(!g_eax);
    invoke(20, 0); assert(!g_eax);
    invoke(20, 8192); assert(g_eax == 1 && !memcmp(GPTR(8192), "TEST-ONLY-NOTR-EAL0", 19));
    assert(validate_calls==1); // Cache scoped to the file snapshot and product ID.
    validation_oracle=0;
    assert(ut3_apple_configure_product_key(primary, secondary, NULL)==1);
    memset(GPTR(8192),0x5a,19);
    invoke(19,8192); assert(!g_eax && *GPTR(8192)==0x5a && validate_calls==2);
    validation_oracle=1;

    const char compact[] = "\xef\xbb\xbf  TESTONLYNOTREAL1\n";
    write_test_file(primary, compact, sizeof compact - 1);
    assert(ut3_apple_configure_product_key(primary, secondary, NULL) == 1);
    invoke(19, 8192); assert(!memcmp(GPTR(8192), "TEST-ONLY-NOTR-EAL1", 19));
    write_test_file(primary, "invalid", 7);
    assert(ut3_apple_configure_product_key(primary, secondary, NULL) == -1); // Don't fall through stale key.
    invoke(19, 8192); assert(calls == 2 && g_eax == 77);
    remove_test_file(primary);
    char link[4096]; snprintf(link,sizeof link,"%s/cdkey.txt",primary);
    assert(!symlink("missing", link));
    assert(ut3_apple_configure_product_key(primary, secondary, NULL) == -1);
    remove_test_file(primary);
    unsigned char large[257]; memset(large, 'A', sizeof large);
    write_test_file(primary, large, sizeof large);
    assert(ut3_apple_configure_product_key(primary, secondary, NULL) == -1);
    write_test_file(primary, "TEST-ONLY-NOTR-EAL1\nTEST-ONLY-NOTR-EAL0", 39);
    assert(ut3_apple_configure_product_key(primary, secondary, NULL) == -1);
    remove_test_file(primary);
    assert(ut3_apple_configure_product_key(NULL, NULL, secondary) == 1); // iOS shared Documents.
    remove_test_file(secondary);
    assert(ut3_apple_configure_product_key(primary, secondary, NULL) == 0);
    assert(!file_key_loaded);
    for (unsigned i = 0; i < sizeof file_key; ++i) assert(!file_key[i]);
    assert(!rmdir(primary) && !rmdir(secondary) && !rmdir(directory));
    free(memory);
    puts("PASS product-key file parsing, precedence, secret reset, pinned code guards, original validator call/rejection, CPU-state preservation and thiscall bounds");
    return 0;
}
