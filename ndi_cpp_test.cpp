#include <iostream>
#include <chrono>
#include <thread>
#include <cstring>
#include <windows.h>

// Try to include NDI SDK, fallback to our definitions
#ifdef _WIN32
    #pragma comment(lib, "Processing.NDI.Lib.x64.lib")
#endif

#if __has_include("Processing.NDI.Lib.h")
    #include "Processing.NDI.Lib.h"
#else
    #include "ndi_fallback.h"
    #pragma message("Using fallback NDI definitions - make sure Processing.NDI.Lib.x64.dll is available")
#endif

class NDITestSender {
private:
    NDIlib_send_instance_t ndi_sender = nullptr;
    bool is_initialized = false;
    
public:
    bool initialize() {
        if (!NDIlib_initialize()) {
            std::cerr << "Failed to initialize NDI library" << std::endl;
            return false;
        }
        
        is_initialized = true;
        std::cout << "NDI library initialized successfully" << std::endl;
        return true;
    }
    
    bool create_sender(const char* source_name) {
        if (!is_initialized) {
            std::cerr << "NDI not initialized" << std::endl;
            return false;
        }
        
        // Create sender settings (following professional implementation)
        NDIlib_send_create_t send_create;
        memset(&send_create, 0, sizeof(send_create));
        
        send_create.p_ndi_name = source_name;
        send_create.p_groups = nullptr;
        send_create.clock_video = false;  // Critical: disable clocking like professional code
        send_create.clock_audio = false;
        
        std::cout << "Creating NDI sender with settings:" << std::endl;
        std::cout << "  Name: " << (source_name ? source_name : "NULL") << std::endl;
        std::cout << "  Clock video: " << send_create.clock_video << std::endl;
        std::cout << "  Clock audio: " << send_create.clock_audio << std::endl;
        
        ndi_sender = NDIlib_send_create(&send_create);
        
        if (!ndi_sender) {
            std::cerr << "Failed to create NDI sender" << std::endl;
            return false;
        }
        
        std::cout << "NDI sender created successfully" << std::endl;
        return true;
    }
    
    void send_test_frames(int frame_count = 100) {
        if (!ndi_sender) {
            std::cerr << "No NDI sender available" << std::endl;
            return;
        }
        
        const int width = 1280;
        const int height = 720;
        
        // Create UYVY buffer (like professional implementation)
        const int buffer_size = width * height * 2; // UYVY = 2 bytes per pixel
        uint8_t* buffer = new uint8_t[buffer_size];
        
        std::cout << "Starting to send " << frame_count << " test frames (" << width << "x" << height << ", UYVY)" << std::endl;
        
        auto start_time = std::chrono::high_resolution_clock::now();
        
        for (int frame = 0; frame < frame_count; frame++) {
            // Wait for connections (like professional code)
            int connections = NDIlib_send_get_no_connections(ndi_sender, 0);
            if (connections == 0 && frame % 30 == 0) {
                std::cout << "Waiting for NDI receivers... (frame " << frame << ")" << std::endl;
            }
            
            // Create test pattern (alternating black/white)
            uint8_t y_value = (frame % 60 < 30) ? 235 : 16; // Bright/dark
            uint8_t u_value = 128; // Neutral chroma
            uint8_t v_value = 128;
            
            // Fill UYVY buffer
            for (int i = 0; i < buffer_size; i += 4) {
                buffer[i] = u_value;     // U
                buffer[i + 1] = y_value; // Y0
                buffer[i + 2] = v_value; // V
                buffer[i + 3] = y_value; // Y1
            }
            
            // Create video frame (following professional implementation exactly)
            NDIlib_video_frame_v2_t video_frame;
            memset(&video_frame, 0, sizeof(video_frame));
            
            video_frame.xres = width;
            video_frame.yres = height;
            video_frame.FourCC = NDIlib_FourCC_type_UYVY;
            video_frame.frame_rate_N = 60000; // NTSC (like professional)
            video_frame.frame_rate_D = 1001;  // 59.94 fps
            video_frame.picture_aspect_ratio = (float)width / (float)height; // Single field, not N/D
            video_frame.frame_format_type = NDIlib_frame_format_type_progressive;
            video_frame.line_stride_in_bytes = width * 2; // UYVY stride
            video_frame.p_data = buffer;
            video_frame.p_metadata = nullptr;
            
            // CRITICAL: Proper timing (like professional implementation)
            auto current_time = std::chrono::high_resolution_clock::now();
            auto timestamp_us = std::chrono::duration_cast<std::chrono::microseconds>(
                current_time - start_time).count();
            
            video_frame.timecode = timestamp_us * 10; // Convert to 100ns intervals
            video_frame.timestamp = timestamp_us;     // Microseconds
            
            // Send frame
            NDIlib_send_send_video_v2(ndi_sender, &video_frame);
            
            // Progress report
            if (frame % 30 == 0 || connections > 0) {
                std::cout << "Sent frame " << frame << "/" << frame_count 
                         << " (connections: " << connections << ")" 
                         << " timecode: " << video_frame.timecode 
                         << " timestamp: " << video_frame.timestamp << std::endl;
            }
            
            // Maintain ~60fps timing
            std::this_thread::sleep_for(std::chrono::milliseconds(16));
        }
        
        delete[] buffer;
        std::cout << "Finished sending " << frame_count << " frames" << std::endl;
    }
    
    ~NDITestSender() {
        if (ndi_sender) {
            NDIlib_send_destroy(ndi_sender);
            std::cout << "NDI sender destroyed" << std::endl;
        }
        
        if (is_initialized) {
            NDIlib_destroy();
            std::cout << "NDI library destroyed" << std::endl;
        }
    }
};

int main() {
    std::cout << "=== NDI C++ Test Program ===" << std::endl;
    std::cout << "This program tests NDI streaming with professional implementation patterns" << std::endl;
    
    NDITestSender sender;
    
    if (!sender.initialize()) {
        std::cerr << "Failed to initialize NDI" << std::endl;
        return 1;
    }
    
    if (!sender.create_sender("C++ NDI Test")) {
        std::cerr << "Failed to create NDI sender" << std::endl;
        return 1;
    }
    
    std::cout << "\nPress Enter to start sending frames (or Ctrl+C to exit)...";
    std::cin.get();
    
    // Send test frames
    sender.send_test_frames(300);
    
    std::cout << "\nTest completed. Check NDI Studio Monitor for the 'C++ NDI Test' source." << std::endl;
    std::cout << "Press Enter to exit...";
    std::cin.get();
    
    return 0;
}
