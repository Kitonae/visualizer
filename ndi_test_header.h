// NDI Test Header - Minimal definitions if SDK headers not available
#ifndef NDI_TEST_HEADER_H
#define NDI_TEST_HEADER_H

#include <cstdint>

// If NDI SDK headers are not available, define minimal structures
#ifndef PROCESSING_NDI_LIB_H

// NDI library function types
typedef void* NDIlib_send_instance_t;

// NDI FourCC constants
#define NDIlib_FourCC_type_UYVY 0x59565955
#define NDIlib_FourCC_type_BGRA 0x41524742

// Frame format types
typedef enum {
    NDIlib_frame_format_type_progressive = 1
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
    int xres;
    int yres;
    uint32_t FourCC;
    int frame_rate_N;
    int frame_rate_D;
    float picture_aspect_ratio_N;
    float picture_aspect_ratio_D;
    int frame_format_type;
    int64_t timecode;
    int64_t timestamp;
    const char* p_metadata;
    int line_stride_in_bytes;
    uint8_t* p_data;
} NDIlib_video_frame_v2_t;

// Function declarations
extern "C" {
    bool NDIlib_initialize();
    void NDIlib_destroy();
    NDIlib_send_instance_t NDIlib_send_create(const NDIlib_send_create_t* p_create_settings);
    void NDIlib_send_destroy(NDIlib_send_instance_t p_instance);
    void NDIlib_send_send_video_v2(NDIlib_send_instance_t p_instance, const NDIlib_video_frame_v2_t* p_video_data);
    int NDIlib_send_get_no_connections(NDIlib_send_instance_t p_instance, uint32_t timeout_in_ms);
}

#endif // PROCESSING_NDI_LIB_H

#endif // NDI_TEST_HEADER_H
