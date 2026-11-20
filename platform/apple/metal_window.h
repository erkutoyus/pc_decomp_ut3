#ifndef UT3_METAL_WINDOW_H
#define UT3_METAL_WINDOW_H

#include <stdint.h>

/* The owner keeps layer alive until all device/window leases have ended.
 * read_drawable is thread-safe and returns zero while the window is hidden. */
typedef struct ut3_metal_window {
    const void *layer;
    void *context;
    int (*read_drawable)(void *context, uint32_t *width, uint32_t *height);
} ut3_metal_window;

#endif
