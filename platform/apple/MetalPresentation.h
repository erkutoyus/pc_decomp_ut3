#ifndef UT3_METAL_PRESENTATION_H
#define UT3_METAL_PRESENTATION_H

#import <QuartzCore/CAMetalLayer.h>

#ifdef __cplusplus
extern "C" {
#endif
int ut3_apple_metal_attach(CAMetalLayer *layer);
void ut3_apple_metal_resize(uint32_t width, uint32_t height);
void ut3_apple_metal_detach(void);
int ut3_apple_metal_has_presented(void);
int ut3_validate_d3d9(const char *game, const char *data);
#ifdef __cplusplus
}
#endif
#endif
