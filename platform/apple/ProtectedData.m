#import <Foundation/Foundation.h>
#import <Security/Security.h>
#include <CommonCrypto/CommonDigest.h>
#include <stdint.h>
#include <unistd.h>
#include <stdio.h>
#include <stdlib.h>
#include <pthread.h>
#include "ProductKey.h"

static NSString *const service = @"org.ut3.port.macos.protected-data";
static const uint8_t marker[] = {'U','T','3','K',1,0,0,0};
enum { tokenSize = sizeof marker + 36, digestSize = CC_SHA256_DIGEST_LENGTH };
enum { invalidData = 13, outOfMemory = 8, accessDenied = 5 };

typedef int crypt_backend(int, const uint8_t *, uint32_t, const uint8_t *, uint32_t,
    const uint8_t *, uint32_t, uint8_t **, uint32_t *, uint8_t **, uint32_t *);
void ut3_apple_set_crypt_backend(crypt_backend *);

static NSDictionary *query(NSString *account)
{
    return @{(__bridge id)kSecClass:(__bridge id)kSecClassGenericPassword,
             (__bridge id)kSecAttrService:service, (__bridge id)kSecAttrAccount:account};
}

static void erase(void *bytes, size_t length)
{
    volatile uint8_t *p = bytes;
    for (size_t i = 0; i < length; ++i) p[i] = 0;
}

/* These records predate the Data Protection keychain. Its modern per-query
 * no-UI attributes do not constrain legacy login-keychain authorization UI.
 * Serialize our calls, disable interaction only for the duration of each
 * file-mode operation, then restore the exact previous process setting.
 * Existing records and interactive behavior without cdkey.txt are preserved. */
static pthread_mutex_t keychainLock = PTHREAD_MUTEX_INITIALIZER;
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
static OSStatus keychain_item(int protect, CFDictionaryRef attributes, CFTypeRef *result)
{
    pthread_mutex_lock(&keychainLock);
    Boolean previous = TRUE;
    int noninteractive = ut3_apple_has_product_key_file(), changed = 0;
    OSStatus status = errSecSuccess;
    if (noninteractive) {
        status = SecKeychainGetUserInteractionAllowed(&previous);
        if (status == errSecSuccess) {
            status = SecKeychainSetUserInteractionAllowed(FALSE);
            changed = status == errSecSuccess;
        }
    }
    if (status == errSecSuccess)
        status = protect ? SecItemAdd(attributes, result) : SecItemCopyMatching(attributes, result);
    if (changed) {
        OSStatus restored = SecKeychainSetUserInteractionAllowed(previous);
        if (restored != errSecSuccess && status == errSecSuccess) {
            if (result && *result) { CFRelease(*result); *result = NULL; }
            status = restored;
        }
    }
    if (getenv("UT3_TRACE_KEYCHAIN"))
        fprintf(stderr, "[protected-data] Keychain %s completed: interaction=%s status=%d\n",
                protect ? "write" : "read", noninteractive ? "forbidden" : "unchanged", (int)status);
    pthread_mutex_unlock(&keychainLock);
    return status;
}
#pragma clang diagnostic pop

static int ut3_apple_crypt(int protect, const uint8_t *input, uint32_t inputBytes,
    const uint8_t *entropy, uint32_t entropyBytes, const uint8_t *description,
    uint32_t descriptionBytes, uint8_t **output, uint32_t *outputBytes,
    uint8_t **outputDescription, uint32_t *outputDescriptionBytes)
{
    @autoreleasepool {
        if (getenv("UT3_TRACE_KEYCHAIN"))
            fprintf(stderr, "[protected-data] Keychain %s requested\n", protect ? "write" : "read");
        uint8_t digest[digestSize];
        CC_SHA256(entropy, entropyBytes, digest);
        if (protect) {
            NSString *account = NSUUID.UUID.UUIDString;
            uint8_t *token = malloc(tokenSize);
            if (!token) return outOfMemory;
            NSMutableData *record = [NSMutableData dataWithBytes:digest length:digestSize];
            [record appendBytes:&descriptionBytes length:sizeof descriptionBytes];
            if (descriptionBytes) [record appendBytes:description length:descriptionBytes];
            if (inputBytes) [record appendBytes:input length:inputBytes];
            NSMutableDictionary *attributes = [query(account) mutableCopy];
            attributes[(__bridge id)kSecValueData] = record;
            OSStatus status = keychain_item(1, (__bridge CFDictionaryRef)attributes, NULL);
            erase(record.mutableBytes, record.length);
            if (status != errSecSuccess) { free(token); return accessDenied; }
            memcpy(token, marker, sizeof marker);
            memcpy(token + sizeof marker, account.UTF8String, tokenSize - sizeof marker);
            *output = token;
            *outputBytes = tokenSize;
            return 0;
        }

        if (inputBytes != tokenSize || memcmp(input, marker, sizeof marker)) return invalidData;
        NSString *account = [[NSString alloc] initWithBytes:input + sizeof marker
                                                     length:tokenSize - sizeof marker encoding:NSASCIIStringEncoding];
        if (!account || ![[NSUUID alloc] initWithUUIDString:account]) return invalidData;
        NSMutableDictionary *attributes = [query(account) mutableCopy];
        attributes[(__bridge id)kSecReturnData] = @YES;
        CFTypeRef contents = NULL;
        OSStatus status = keychain_item(0, (__bridge CFDictionaryRef)attributes, &contents);
        if (status != errSecSuccess) return status == errSecItemNotFound ? invalidData : accessDenied;
        NSData *record = CFBridgingRelease(contents);
        const uint8_t *bytes = record.bytes;
        if (record.length < digestSize + sizeof descriptionBytes) return invalidData;
        uint8_t match = 0;
        for (unsigned i = 0; i < digestSize; ++i) match |= bytes[i] ^ digest[i];
        if (match) return invalidData;
        memcpy(&descriptionBytes, bytes + digestSize, sizeof descriptionBytes);
        size_t payloadSize = record.length - digestSize - sizeof descriptionBytes;
        if (descriptionBytes > 8192 || descriptionBytes > payloadSize || payloadSize - descriptionBytes > (1u << 20))
            return invalidData;
        size_t plainSize = payloadSize - descriptionBytes;
        uint8_t *plain = malloc(plainSize ? plainSize : 1);
        uint8_t *metadata = descriptionBytes ? malloc(descriptionBytes) : NULL;
        if (!plain || (descriptionBytes && !metadata)) {
            free(plain);
            free(metadata);
            return outOfMemory;
        }
        const uint8_t *payload = bytes + digestSize + sizeof descriptionBytes;
        if (descriptionBytes) memcpy(metadata, payload, descriptionBytes);
        if (plainSize) memcpy(plain, payload + descriptionBytes, plainSize);
        *output = plain;
        *outputBytes = (uint32_t)plainSize;
        *outputDescription = metadata;
        *outputDescriptionBytes = descriptionBytes;
        return 0;
    }
}

/* Keep UE3's optional DPAPI entropy stable across Wi-Fi, Ethernet and offline starts. */
void ut3_apple_set_adapter_identity(const char *dataPath)
{
    if (getenv("UT3_TRACE_KEYCHAIN")) fprintf(stderr, "[protected-data] Keychain trace enabled\n");
    ut3_apple_set_crypt_backend(ut3_apple_crypt);
    char host[256] = {0};
    gethostname(host, sizeof host - 1);
    NSString *scope = [NSString stringWithFormat:@"%u:%s:%s", getuid(), host, dataPath];
    NSData *identity = [scope dataUsingEncoding:NSUTF8StringEncoding];
    uint8_t digest[digestSize];
    CC_SHA256(identity.bytes, (CC_LONG)identity.length, digest);
    digest[0] = (digest[0] & 0xfc) | 2;
    char mac[13];
    snprintf(mac, sizeof mac, "%02x%02x%02x%02x%02x%02x",
             digest[0], digest[1], digest[2], digest[3], digest[4], digest[5]);
    setenv("UT3_ADAPTER_MAC", mac, 0);
}
