/* IOKit power-source facts mapped to Win32's AC and battery fields. */
#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/ps/IOPowerSources.h>
#include <IOKit/ps/IOPSKeys.h>
#include <stdint.h>

static int read_capacity(CFDictionaryRef source, CFStringRef key, int *value)
{
    CFTypeRef property = CFDictionaryGetValue(source, key);
    return property && CFGetTypeID(property) == CFNumberGetTypeID() &&
           CFNumberGetValue(property, kCFNumberIntType, value);
}

void ut3_apple_power_status(uint8_t *ac, uint8_t *battery, uint8_t *percent)
{
    CFTypeRef snapshot = IOPSCopyPowerSourcesInfo();
    if (!snapshot) return;
    CFStringRef active = IOPSGetProvidingPowerSourceType(snapshot);
    if (active && CFEqual(active, CFSTR(kIOPSACPowerValue))) *ac = 1;
    else if (active && CFEqual(active, CFSTR(kIOPSBatteryPowerValue))) *ac = 0;

    CFArrayRef sources = IOPSCopyPowerSourcesList(snapshot);
    if (sources) {
        *battery = 128; /* No internal battery unless one is present. */
        for (CFIndex i = 0; i < CFArrayGetCount(sources); ++i) {
            CFDictionaryRef source = IOPSGetPowerSourceDescription(snapshot, CFArrayGetValueAtIndex(sources, i));
            if (!source) continue;
            CFTypeRef type = CFDictionaryGetValue(source, CFSTR(kIOPSTypeKey));
            if (!type || !CFEqual(type, CFSTR(kIOPSInternalBatteryType)) ||
                CFDictionaryGetValue(source, CFSTR(kIOPSIsPresentKey)) == kCFBooleanFalse) continue;
            *battery = 255;
            int current, maximum;
            if (read_capacity(source, CFSTR(kIOPSCurrentCapacityKey), &current) &&
                read_capacity(source, CFSTR(kIOPSMaxCapacityKey), &maximum) &&
                maximum > 0 && current >= 0 && current <= maximum) {
                *percent = (uint8_t)((uint64_t)current * 100 / maximum);
                *battery = *percent > 66 ? 1 : *percent < 33 ? 2 : 0;
                if (*percent < 5) *battery |= 4;
                if (CFDictionaryGetValue(source, CFSTR(kIOPSIsChargingKey)) == kCFBooleanTrue) *battery |= 8;
            }
            break;
        }
        CFRelease(sources);
    }
    CFRelease(snapshot);
}
