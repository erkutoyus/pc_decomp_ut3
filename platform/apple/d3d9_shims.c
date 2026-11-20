/* Native DXVK guest exports selected for the Apple bundle. */
#include "host.h"

uint32_t ut3_dxvk_create9(uint32_t sdk);
int void_d3d_scene_open;

WINAPI_EXPORT("d3d9.dll", Direct3DCreate9, 1) { return ut3_dxvk_create9(ARG(0)); }
WINAPI_EXPORT("d3d9.dll", D3DPERF_SetOptions, 1) { return 0; }
WINAPI_EXPORT("d3d9.dll", D3DPERF_BeginEvent, 2) { return 0; }
WINAPI_EXPORT("d3d9.dll", D3DPERF_EndEvent, 0) { return 0; }
WINAPI_EXPORT("d3d9.dll", D3DPERF_GetStatus, 0) { return 0; }

WINAPI_EXPORT("d3dx9_35.dll", D3DXCheckVersion, 2)
{
    return (ARG(0) & 0x7FFFFFFFu) == 32 && ARG(1) == 35;
}

/* CPU hint reporting is provided by ADPF on Android. */
void ut3_adpf_work_end(void) {}
