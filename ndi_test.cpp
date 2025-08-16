#include <iostream>
#include <chrono>
#include <thread>
#include <vector>
#include <cstring>

// Try to include official NDI headers, fallback to our definitions
#ifdef _WIN32
    #pragma comment(lib, "Processing.NDI.Lib.x64.lib")
#endif

// Include NDI headers with fallback
#if __has_include("Processing.NDI.Lib.h")
    #include "Processing.NDI.Lib.h"
#else
    #include "ndi_test_header.h"
    #pragma message("Using fallback NDI definitions - link manually to Processing.NDI.Lib.x64.dll")
#endif

class NDITestSender {
private:
    NDIlib_send_instance_t ndi_sender;
    bool is_initialized;
    
public:
    NDITestSender() : ndi_sender(nullptr), is_initialized(false) {}
    
    ~NDITestSender() {
        cleanup();
    }
    
    bool initialize() {
        std::cout << "Initializing NDI..." << std::endl;
        
        if (!NDIlib_initialize()) {
            std::cout << "ERROR: Failed to initialize NDI" << std::endl;
            return false;
        }
        
        is_initialized = true;
        std::cout << "NDI initialized successfully" << std::endl;
        return true;
    }
    
    bool createSender(const char* source_name) {
        if (!is_initialized) {
            std::cout << "ERROR: NDI not initialized" << std::endl;
            return false;
        }
        
        // Create sender settings (following professional implementation pattern)
        NDIlib_send_create_t sender_settings;
        memset(&sender_settings, 0, sizeof(sender_settings));
        
        sender_settings.p_ndi_name = source_name;
        sender_settings.p_groups = nullptr;
        sender_settings.clock_video = false;  // CRITICAL: Don't clock video
        sender_settings.clock_audio = false;  // CRITICAL: Don't clock audio
        
        std::cout << "Creating NDI sender with settings:" << std::endl;
        std::cout << "  Name: " << (source_name ? source_name : "NULL") << std::endl;
        std::cout << "  Clock video: " << sender_settings.clock_video << std::endl;
        std::cout << "  Clock audio: " << sender_settings.clock_audio << std::endl;
        
        ndi_sender = NDIlib_send_create(&sender_settings);
        
        if (!ndi_sender) {
            std::cout << "ERROR: Failed to create NDI sender" << std::endl;
            return false;
        }
        
        std::cout << "NDI sender created successfully: " << ndi_sender << std::endl;
        return true;
    }
    
    void sendTestFrames(int frame_count, int width = 800, int height = 600) {
        if (!ndi_sender) {
            std::cout << "ERROR: No NDI sender available" << std::endl;
            return;
        }
        
        std::cout << "Sending " << frame_count << " test frames (" << width << "x" << height << ")" << std::endl;
        
        // Calculate frame timing (59.94 fps like professional implementation)
        const int64_t frame_duration_us = 1000000 * 1001 / 60000;  // ~16683 microseconds
        auto start_time = std::chrono::steady_clock::now();
        
        for (int frame = 0; frame < frame_count; ++frame) {
            // Check connections (like professional implementation)
            int connections = NDIlib_send_get_no_connections(ndi_sender, 0);
            if (connections == 0 && frame % 30 == 0) {
                std::cout << "Frame " << frame << ": No NDI receivers connected" << std::endl;
            }
            
            // Create test frame data
            sendSingleFrame(frame, width, height);
            
            // Progress reporting
            if (frame % 30 == 0 || frame == frame_count - 1) {
                std::cout << "Sent frame " << (frame + 1) << "/" << frame_count 
                         << " (" << connections << " connections)" << std::endl;
            }
            
            // Frame rate limiting
            std::this_thread::sleep_for(std::chrono::microseconds(frame_duration_us));
        }
        
        std::cout << "Finished sending test frames" << std::endl;
    }
    
private:
    void sendSingleFrame(int frame_number, int width, int height) {
        // Create video frame structure
        NDIlib_video_frame_v2_t video_frame;
        memset(&video_frame, 0, sizeof(video_frame));
        
        // Set frame properties
        video_frame.xres = width;
        video_frame.yres = height;
        video_frame.FourCC = NDIlib_FourCC_type_UYVY;  // Use UYVY like professional
        video_frame.frame_rate_N = 60000;  // NTSC numerator
        video_frame.frame_rate_D = 1001;   // NTSC denominator
        video_frame.picture_aspect_ratio_N = width;
        video_frame.picture_aspect_ratio_D = height;
        video_frame.frame_format_type = NDIlib_frame_format_type_progressive;
        
        // CRITICAL: Proper timing (like professional implementation)
        auto now = std::chrono::steady_clock::now();
        auto timestamp_us = std::chrono::duration_cast<std::chrono::microseconds>(
            now.time_since_epoch()).count();
        
        video_frame.timecode = timestamp_us * 10;  // Convert to 100ns intervals
        video_frame.timestamp = timestamp_us;      // Microseconds since epoch
        video_frame.p_metadata = nullptr;
        
        // Create UYVY test pattern (2 bytes per pixel)
        size_t data_size = width * height * 2;
        std::vector<uint8_t> frame_data(data_size);
        
        // Generate test pattern: alternating black/white based on frame number
        uint8_t y_value = (frame_number % 60 < 30) ? 235 : 16;  // Bright/Dark luma
        uint8_t u_value = 128;  // Neutral chroma
        uint8_t v_value = 128;  // Neutral chroma
        
        // Fill UYVY pattern: U0 Y0 V0 Y1 (4 bytes for 2 pixels)
        for (size_t i = 0; i < data_size; i += 4) {
            frame_data[i]     = u_value;  // U
            frame_data[i + 1] = y_value;  // Y0
            frame_data[i + 2] = v_value;  // V
            frame_data[i + 3] = y_value;  // Y1
        }
        
        video_frame.line_stride_in_bytes = width * 2;  // 2 bytes per pixel for UYVY
        video_frame.p_data = frame_data.data();
        
        // Send frame
        NDIlib_send_send_video_v2(ndi_sender, &video_frame);
    }
    
    void cleanup() {
        if (ndi_sender) {
            std::cout << "Destroying NDI sender..." << std::endl;
            NDIlib_send_destroy(ndi_sender);
            ndi_sender = nullptr;
        }
        
        if (is_initialized) {
            std::cout << "Shutting down NDI..." << std::endl;
            NDIlib_destroy();
            is_initialized = false;
        }
    }
};

int main(int argc, char* argv[]) {
    std::cout << "=== NDI C++ Test Program ===" << std::endl;
    std::cout << "Testing NDI implementation with professional patterns" << std::endl;
    
    // Parse command line arguments
    int frame_count = 100;
    std::string source_name = "C++ NDI Test";
    
    if (argc > 1) {
        frame_count = std::atoi(argv[1]);
    }
    if (argc > 2) {
        source_name = argv[2];
    }
    
    std::cout << "Configuration:" << std::endl;
    std::cout << "  Frame count: " << frame_count << std::endl;
    std::cout << "  Source name: " << source_name << std::endl;
    std::cout << "  Format: UYVY (professional standard)" << std::endl;
    std::cout << "  Frame rate: 60000/1001 (59.94 fps NTSC)" << std::endl;
    std::cout << "  Timing: Precise microsecond timestamps" << std::endl;
    std::cout << std::endl;
    
    // Create and run test
    NDITestSender sender;
    
    if (!sender.initialize()) {
        std::cout << "Failed to initialize NDI" << std::endl;
        return 1;
    }
    
    if (!sender.createSender(source_name.c_str())) {
        std::cout << "Failed to create NDI sender" << std::endl;
        return 1;
    }
    
    std::cout << "NDI sender ready. Check NDI Studio Monitor for source: " << source_name << std::endl;
    std::cout << "Starting frame transmission in 2 seconds..." << std::endl;
    std::this_thread::sleep_for(std::chrono::seconds(2));
    
    sender.sendTestFrames(frame_count);
    
    std::cout << std::endl << "Test completed. NDI sender will be destroyed." << std::endl;
    std::cout << "Check NDI Studio Monitor to verify frame reception." << std::endl;
    
    return 0;
}
