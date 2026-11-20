#import "ShellValidation.h"
#import <Carbon/Carbon.h>
#import <IOKit/hidsystem/IOLLEvent.h>
#include "input.h"
#include <math.h>

static NSEvent *key_event(NSWindow *window, NSEventType type, unsigned code, NSEventModifierFlags modifiers)
{
    return [NSEvent keyEventWithType:type location:NSZeroPoint modifierFlags:modifiers timestamp:0
                        windowNumber:window.windowNumber context:nil characters:@"w"
         charactersIgnoringModifiers:@"w" isARepeat:NO keyCode:(unsigned short)code];
}

static NSEvent *mouse_event(NSWindow *window, NSEventType type, NSPoint point)
{
    return [NSEvent mouseEventWithType:type location:point modifierFlags:0 timestamp:0
                          windowNumber:window.windowNumber context:nil eventNumber:0 clickCount:1 pressure:1];
}

BOOL UT3ValidateWindowAndInput(NSWindow *window, UT3GameView *view)
{
#define CHECK(condition) do { \
    if (!(condition)) { fprintf(stderr, "[ut3-shell] Validation failed: %s\n", #condition); return NO; } \
} while (0)
    CHECK(window.visible && window.keyWindow && window.firstResponder == view);
    CHECK(window.windowNumber > 0 && [view.layer isKindOfClass:CAMetalLayer.class]);

    CAMetalLayer *layer = view.presentationLayer;
    CGSize before = layer.drawableSize;
    [window setContentSize:NSMakeSize(800, 460)];
    NSSize pixels = [view convertSizeToBacking:view.bounds.size];
    int width, height;
    void_input_screen_size(&width, &height);
    CHECK(layer == view.presentationLayer && layer.delegate == (id)view && !layer.device);
    CHECK(!CGSizeEqualToSize(before, layer.drawableSize));
    CHECK(width == lround(pixels.width) && height == lround(pixels.height));
    CHECK(CGSizeEqualToSize(CGSizeMake(width, height), layer.drawableSize));

    [window sendEvent:key_event(window, NSEventTypeKeyDown, kVK_ANSI_W, 0)];
    CHECK(void_input_key_state('W') < 0);
    uint8_t keys[256];
    void_input_keyboard_snapshot(keys);
    CHECK(keys[void_vk_to_dik('W')] == 0x80);
    [window sendEvent:key_event(window, NSEventTypeKeyUp, kVK_ANSI_W, 0)];
    CHECK(void_input_key_state('W') >= 0);
    [window sendEvent:key_event(window, NSEventTypeFlagsChanged, kVK_Shift,
                               NSEventModifierFlagShift | NX_DEVICELSHIFTKEYMASK)];
    CHECK(void_input_key_state(0xA0) < 0 && void_input_key_state(0x10) < 0);
    [window sendEvent:key_event(window, NSEventTypeFlagsChanged, kVK_RightShift,
                              NSEventModifierFlagShift | NX_DEVICELSHIFTKEYMASK | NX_DEVICERSHIFTKEYMASK)];
    CHECK(void_input_key_state(0xA1) < 0);
    [window sendEvent:key_event(window, NSEventTypeFlagsChanged, kVK_Shift,
                               NSEventModifierFlagShift | NX_DEVICERSHIFTKEYMASK)];
    CHECK(void_input_key_state(0xA0) >= 0 && void_input_key_state(0x10) < 0);
    [window sendEvent:key_event(window, NSEventTypeFlagsChanged, kVK_RightShift, 0)];
    CHECK(void_input_key_state(0x10) >= 0);

    NSRect content = [view convertRect:view.bounds toView:nil];
    NSPoint inWindow = NSMakePoint(NSMinX(content) + 32, NSMaxY(content) - 54);
    NSPoint expected = NSMakePoint(32 * window.backingScaleFactor, 54 * window.backingScaleFactor);
    [window sendEvent:mouse_event(window, NSEventTypeMouseMoved, inWindow)];
    uint32_t x, y;
    void_input_cursor(&x, &y);
    CHECK(x == (uint32_t)expected.x && y == (uint32_t)expected.y);
    [window sendEvent:mouse_event(window, NSEventTypeLeftMouseDown, inWindow)];
    CHECK(void_input_key_state(1) < 0);
    [window sendEvent:mouse_event(window, NSEventTypeLeftMouseUp, inWindow)];
    CHECK(void_input_key_state(1) >= 0);
    NSPoint lower = NSMakePoint(inWindow.x, inWindow.y - 31);
    [window sendEvent:mouse_event(window, NSEventTypeMouseMoved, lower)];
    void_input_cursor(&x, &y);
    CHECK(x == (uint32_t)expected.x && y == (uint32_t)(85 * window.backingScaleFactor));

    int32_t dx, dy, dz;
    uint8_t buttons[8];
    void_input_mouse_snapshot(&dx, &dy, &dz, buttons);
    CGEventRef movement = CGEventCreateMouseEvent(NULL, kCGEventMouseMoved,
                                                 CGPointMake(lower.x, lower.y - 10), kCGMouseButtonLeft);
    CHECK(movement);
    CGEventSetIntegerValueField(movement, kCGMouseEventDeltaX, 3);
    CGEventSetIntegerValueField(movement, kCGMouseEventDeltaY, -4);
    NSEvent *moveEvent = [NSEvent eventWithCGEvent:movement];
    CHECK(moveEvent);
    CGFloat expectedYDirection = moveEvent.locationInWindow.y < lower.y ? 1 : -1;
    [view mouseMoved:moveEvent];
    CFRelease(movement);
    CGEventRef scroll = CGEventCreateScrollWheelEvent(NULL, kCGScrollEventUnitLine, 1, 1);
    CHECK(scroll);
    [view scrollWheel:[NSEvent eventWithCGEvent:scroll]];
    CFRelease(scroll);
    void_input_mouse_snapshot(&dx, &dy, &dz, buttons);
    CHECK(dx == (int)(3 * window.backingScaleFactor) &&
          dy == (int)(expectedYDirection * 4 * window.backingScaleFactor) && dz == 120);

    [window sendEvent:key_event(window, NSEventTypeKeyDown, kVK_ANSI_W, 0)];
    [window sendEvent:mouse_event(window, NSEventTypeLeftMouseDown, inWindow)];
    CHECK(void_input_key_state('W') < 0 && void_input_key_state(1) < 0);
    [window orderOut:nil];
    void_input_keyboard_snapshot(keys);
    void_input_mouse_snapshot(&dx, &dy, &dz, buttons);
    CHECK(void_input_key_state('W') >= 0 && void_input_key_state(1) >= 0 &&
          !keys[void_vk_to_dik('W')] && !buttons[0]);
    [window makeKeyAndOrderFront:nil];

    void_input_set_controller(NULL);
    uint8_t state[16];
    void_controller_state sample = {.buttons = 0x1000, .left_trigger = 127, .lx = -15000, .ry = 24000};
    void_input_set_controller(&sample);
    CHECK(void_input_touch_pad(0, state) && !memcmp(state + 4, &sample, sizeof sample) &&
          !void_input_touch_pad(1, state));
    uint32_t packet;
    memcpy(&packet, state, 4);
    sample.buttons = 0;
    void_input_set_controller(&sample);
    CHECK(void_input_touch_pad(0, state) && !memcmp(state + 4, &sample, sizeof sample) &&
          memcmp(state, &packet, 4));
    void_input_set_controller(NULL);
    return !void_input_touch_pad(0, state);
#undef CHECK
}
