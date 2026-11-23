/* Host input state shared by user32, DirectInput and the Android layer. */
#ifndef VOID_INPUT_H
#define VOID_INPUT_H
#include <stdint.h>

/* Screen ("desktop") size the guest sees. */
void void_input_screen_size(int *w, int *h);
void void_input_set_screen_size(int w, int h);
/* A replaced full-screen presentation surface: follow its full-screen clip,
 * preserving deliberately smaller guest clipping rectangles. */
void void_input_resize_surface(int w, int h);
/* Cursor in screen coordinates. */
void void_input_cursor(uint32_t *x, uint32_t *y);
void void_input_set_cursor(int x, int y);
/* GetKeyState: bit 15 down, bit 0 toggled. */
int16_t void_input_key_state(uint32_t vk);
/* Character a WM_KEYDOWN of vk produces (TranslateMessage), 0 if none. */
uint32_t void_input_vk_char(uint32_t vk);
/* Called from message APIs: moves queued host events into guest queues. */
void void_input_pump(void);

/* Host side (any thread): record physical input. */
void void_input_key(uint32_t vk, int down);
void void_input_mouse_move(int dx, int dy);
void void_input_mouse_warp(int x, int y);   /* cursor only: no DirectInput motion */
void void_input_mouse_button(int button, int down);
void void_input_mouse_wheel(int delta);
/* A relative event with the corresponding absolute cursor in guest pixels. */
void void_input_mouse_motion(int dx, int dy, int x, int y);
void void_input_release_physical(void);
/* Native committed text to WM_CHAR. UTF-16 pairs are preserved; no key
 * synthesis, pointer ownership, or Android UI publisher is required. */
int void_input_text_utf16(const uint16_t *text, int length);
/* Last physical pointer position and age; untouched by guest SetCursorPos. */
int void_input_pointer(uint32_t *x, uint32_t *y, uint64_t *moved_ns);

/* DirectInput snapshots. */
void void_input_keyboard_snapshot(uint8_t keys[256]);
void void_input_mouse_snapshot(int32_t *dx, int32_t *dy, int32_t *dz, uint8_t buttons[8]);
/* Buffered DirectInput events: returns count copied (dwOfs, dwData, dwTimeStamp, dwSequence). */
typedef struct { uint32_t ofs, data, time, seq; } void_input_event;
int void_input_keyboard_events(void_input_event *out, int max, int peek);
int void_input_mouse_events(void_input_event *out, int max, int peek);
uint32_t void_vk_to_dik(uint32_t vk);

#if defined(__APPLE__)
typedef struct {
    uint16_t buttons;
    uint8_t left_trigger, right_trigger;
    int16_t lx, ly, rx, ry;
} void_controller_state;
/* The native controller owns XInput slot zero while connected. NULL releases it. */
void void_input_set_controller(const void_controller_state *state);
int void_input_touch_pad(uint32_t index, uint8_t out[16]);
/* Latest slot-zero motors (left in high word), with a 250 ms stale-command
 * cutoff. Clearing on focus loss/disconnect prevents replay on reconnection. */
uint32_t void_input_get_rumble(void);
void void_input_clear_rumble(void);
#endif

/* Scripted input from $VOID_INPUT or <data>/input.txt, if present (script.c). */
void void_input_script_start(void);

#endif
