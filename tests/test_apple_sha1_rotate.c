/* Differential execution of the complete original and transformed guest body. */
#define RECOMP_GENERATED_CODE
#include "../engine/runtime/recomp_types.h"
#include <assert.h>
#include <stdio.h>
#include <string.h>
#include <sys/mman.h>
#include <time.h>
#include <CommonCrypto/CommonDigest.h>
#if defined(UT3_IOS)
#include <mach/mach.h>
#endif
#if !defined(UT3_IOS)
uint32_t g_eax,g_ecx,g_edx,g_esp,g_ebx,g_esi,g_edi,g_ebp;
uint32_t g_flag_k,g_flag_a,g_flag_b,g_flag_cf;
#endif
#include "sha1_rotate_bodies.inc"
enum { SPAN=0x20000, OBJECT=0x1000, STATE=0x2000, DATA=0x3000, WORK=0x4000, STACK=0x18000 };
static uint32_t random_state=0x13579bdf;
static uint32_t random_word(void) { random_state^=random_state<<13;random_state^=random_state>>17;return random_state^=random_state<<5; }
static void setup(void)
{
    MEM32(OBJECT+0xc0)=WORK;
    MEM32(STACK)=0xdead0000;MEM32(STACK+4)=STATE;MEM32(STACK+8)=DATA;
    g_ecx=OBJECT;g_esp=STACK;g_eax=0x12345678;g_edx=0xabcdef01;
    g_ebx=0x10203040;g_esi=0x50607080;g_edi=0x90a0b0c0;g_ebp=0xd0e0f010;
    g_flag_k=FK_EFLAGS;g_flag_a=0x202;g_flag_b=0;g_flag_cf=0;
}
static void registers(uint32_t out[12])
{
    uint32_t values[]={g_eax,g_ecx,g_edx,g_esp,g_ebx,g_esi,g_edi,g_ebp,g_flag_k,g_flag_a,g_flag_b,g_flag_cf};
    memcpy(out,values,sizeof values);
}
static double seconds(void) { struct timespec t;clock_gettime(CLOCK_MONOTONIC,&t);return t.tv_sec+t.tv_nsec*1e-9; }
#if defined(UT3_IOS)
int ut3_validate_sha1_rotates(void)
#else
int main(void)
#endif
{
#if defined(UT3_IOS)
    vm_address_t address=VOID_GUEST_BASE;
    assert(vm_allocate(mach_task_self(),&address,SPAN,VM_FLAGS_FIXED)==KERN_SUCCESS);
    void *base=(void *)address;
#else
    void *base=mmap((void *)VOID_GUEST_BASE,SPAN,PROT_READ|PROT_WRITE,MAP_PRIVATE|MAP_ANON,-1,0);
#endif
    assert(base==(void *)VOID_GUEST_BASE);
    uint8_t before[SPAN],reference[SPAN];uint32_t ref_regs[12],got_regs[12];
    for(unsigned n=0;n<2000;++n) {
        for(unsigned i=0;i<SPAN;i+=4) MEM32(i)=random_word();
        setup();memcpy(before,base,SPAN);sha1_reference();registers(ref_regs);memcpy(reference,base,SPAN);
        memcpy(base,before,SPAN);setup();sha1_candidate();registers(got_regs);
        assert(!memcmp(base,reference,SPAN)&&!memcmp(ref_regs,got_regs,sizeof ref_regs));
        // Independently check the compression result against Apple's SHA-1.
        CC_SHA1_CTX digest;CC_SHA1_Init(&digest);
        memcpy(&digest.h0,before+STATE,20);CC_SHA1_Update(&digest,before+DATA,64);
        assert(!memcmp(&digest.h0,GPTR(STATE),20));
    }
    double start=seconds();for(unsigned i=0;i<100000;++i){setup();sha1_reference();}double reference_s=seconds()-start;
    start=seconds();for(unsigned i=0;i<100000;++i){setup();sha1_candidate();}double candidate_s=seconds()-start;
    printf("PASS 2000 original guest SHA1 differential cases: whole memory, registers/flags/stack and independent CommonCrypto state; 100000-block reference %.6fs candidate %.6fs speedup %.2fx\n",reference_s,candidate_s,reference_s/candidate_s);
#if defined(UT3_IOS)
    assert(vm_deallocate(mach_task_self(),address,SPAN)==KERN_SUCCESS);
#else
    assert(!munmap(base,SPAN));
#endif
    return 0;
}
