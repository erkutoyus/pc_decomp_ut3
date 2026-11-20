/* No real Keychain is touched. Exercise the production legacy-API gate,
 * including restoration on failure and serialization of concurrent reads. */
#import <Foundation/Foundation.h>
#import <Security/Security.h>
#include <assert.h>
#include <unistd.h>

static int fileMode, reads, writes, getCalls, setCalls;
static Boolean interaction = TRUE;
static OSStatus getStatus, firstSetStatus, restoreStatus, itemStatus;
static OSStatus fixture_get(Boolean *value) { ++getCalls; *value = interaction; return getStatus; }
static OSStatus fixture_set(Boolean value)
{
    ++setCalls;
    OSStatus status = setCalls & 1 ? firstSetStatus : restoreStatus;
    if (!status) interaction = value;
    return status;
}
static OSStatus fixture_add(CFDictionaryRef attrs, CFTypeRef *result)
{
    (void)attrs; (void)result;
    if (fileMode) assert(!interaction);
    ++writes; return itemStatus;
}
static OSStatus fixture_copy(CFDictionaryRef attrs, CFTypeRef *result)
{
    (void)attrs;
    if (fileMode) assert(!interaction);
    ++reads; usleep(1000);
    if (!itemStatus && result) {
        const UInt8 data[] = {1,2};
        *result = CFDataCreate(NULL, data, sizeof data);
    }
    return itemStatus;
}
int ut3_apple_has_product_key_file(void) { return fileMode; }
#define SecItemAdd fixture_add
#define SecItemCopyMatching fixture_copy
#define SecKeychainGetUserInteractionAllowed fixture_get
#define SecKeychainSetUserInteractionAllowed fixture_set
#include "../platform/apple/ProtectedData.m"
void ut3_apple_set_crypt_backend(crypt_backend *callback) { (void)callback; }

static void reset(void)
{
    fileMode=1; reads=writes=getCalls=setCalls=0; interaction=TRUE;
    getStatus=firstSetStatus=restoreStatus=itemStatus=errSecSuccess;
}
int main(void)
{
    @autoreleasepool {
        CFDictionaryRef attrs=(__bridge CFDictionaryRef)@{};
        reset(); fileMode=0;
        assert(!keychain_item(1,attrs,NULL));
        assert(writes==1 && !getCalls && !setCalls && interaction);
        reset();
        assert(!keychain_item(1,attrs,NULL));
        assert(writes==1 && getCalls==1 && setCalls==2 && interaction);
        reset(); itemStatus=errSecInteractionNotAllowed;
        assert(keychain_item(0,attrs,NULL)==errSecInteractionNotAllowed);
        assert(reads==1 && getCalls==1 && setCalls==2 && interaction);
        reset(); interaction=FALSE;
        assert(!keychain_item(1,attrs,NULL) && !interaction && setCalls==2);
        reset(); getStatus=errSecNotAvailable;
        assert(keychain_item(0,attrs,NULL)==errSecNotAvailable);
        assert(!reads && !setCalls && interaction);
        reset(); firstSetStatus=errSecAuthFailed;
        assert(keychain_item(0,attrs,NULL)==errSecAuthFailed);
        assert(!reads && setCalls==1 && interaction);
        reset(); restoreStatus=errSecNotAvailable;
        CFTypeRef data=NULL;
        assert(keychain_item(0,attrs,&data)==errSecNotAvailable);
        assert(reads==1 && setCalls==2 && !data);
        reset();
        dispatch_apply(16,dispatch_get_global_queue(QOS_CLASS_DEFAULT,0),^(size_t index) {
            (void)index;
            assert(!keychain_item(0,attrs,NULL));
        });
        assert(reads==16 && getCalls==16 && setCalls==32 && interaction);
        puts("PASS file-mode Keychain no-UI policy, missing-file behavior, failure restoration and concurrent serialization; no real Keychain used");
    }
    return 0;
}
