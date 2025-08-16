#pragma once

// Fallback NDI definitions if SDK is not available
#ifndef PROCESSING_NDI_LIB_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

// Basic NDI types
typedef void* NDIlib_send_instance_t;

// FourCC definitions
#define NDIlib_FourCC_type_UYVY 0x59565955
#define NDIlib_FourCC_type_BGRA 0x41524742
#define NDIlib_FourCC_type_BGRX 0x58524742

// Frame format types
typedef enum {
    NDIlib_frame_format_type_progressive = 1,
    NDIlib_frame_format_type_interleaved = 0,
    NDIlib_frame_format_type_field_0 = 2,
    NDIlib_frame_format_type_field_1 = 3
} NDIlib_frame_format_type_e;

// Send create structure
typedef struct {
    const char* p_ndi_name;
    const char* p_groups;
    bool clock_video;
    bool clock_audio;
} NDIlib_send_create_t;

// Video frame structure
typedef struct {
    int xres, yres;
    uint32_t FourCC;
    int frame_rate_N, frame_rate_D;
    float picture_aspect_ratio_N, picture_aspect_ratio_D;
    NDIlib_frame_format_type_e frame_format_type;
    int64_t timecode;
    uint8_t* p_data;
    int line_stride_in_bytes;
    const char* p_metadata;
    int64_t timestamp;
} NDIlib_video_frame_v2_t;

// Function declarations
bool NDIlib_initialize();
void NDIlib_destroy();
NDIlib_send_instance_t NDIlib_send_create(const NDIlib_send_create_t* p_create_settings);
void NDIlib_send_destroy(NDIlib_send_instance_t p_instance);
void NDIlib_send_send_video_v2(NDIlib_send_instance_t p_instance, const NDIlib_video_frame_v2_t* p_video_data);
int NDIlib_send_get_no_connections(NDIlib_send_instance_t p_instance, int timeout_in_ms);

#ifdef __cplusplus
}
#endif

#endif // PROCESSING_NDI_LIB_H
