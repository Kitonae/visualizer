#include <iostream>
#include <chrono>
#include <thread>
#include <cstring>
#include <windows.h>
#include <memory>
#include <signal.h>
#include <atomic>
#include <cstddef> // for offsetof

// Global flag for graceful shutdown
std::atomic<bool> should_exit(false);

void signal_handler(int signal) {
    std::cout << "Received signal " << signal << ", shutting down gracefully..." << std::endl;
    should_exit = true;
}

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

struct SharedFrameData {
    uint32_t magic;           // 0xDEADBEEF for validation
    uint32_t width;
    uint32_t height;
    uint32_t format;          // 0=RGBA, 1=BGRA, 2=UYVY
    uint32_t frame_number;
    uint64_t timestamp_us;    // Microseconds since start
    uint32_t data_size;
    uint32_t receiver_count;  // Number of connected NDI receivers
    uint32_t active_index;    // 0 or 1
    uint32_t buffer_capacity; // bytes per buffer
    uint32_t reserved0;
    uint32_t reserved1;
    uint64_t buf_offset[2];   // offsets from base to each buffer
    // Flexible-size trailing buffer. The mapped view provides the full capacity.
    uint8_t pixel_data[1];
};

class NDISender {
private:
    NDIlib_send_instance_t ndi_sender = nullptr;
    bool is_initialized = false;
    HANDLE shared_memory = nullptr;
    SharedFrameData* shared_data = nullptr;
    bool should_stop = false;
    std::thread sender_thread;
    
    const char* SHARED_MEMORY_NAME = "LOVE_NDI_SHARED_FRAME";
    const uint32_t MAGIC_NUMBER = 0xDEADBEEF;
    
public:
    bool initialize() {
        // Initialize NDI
        if (!NDIlib_initialize()) {
            std::cerr << "Failed to initialize NDI library" << std::endl;
            return false;
        }
        
        is_initialized = true;
        std::cout << "NDI library initialized successfully" << std::endl;
        
        // Create shared memory
        const size_t MAPPING_SIZE = size_t(256) * 1024 * 1024; // 256MB
        shared_memory = CreateFileMappingA(
            INVALID_HANDLE_VALUE,
            nullptr,
            PAGE_READWRITE,
            0,
            (DWORD)MAPPING_SIZE, // large enough for double buffering
            SHARED_MEMORY_NAME
        );
        
        if (!shared_memory) {
            std::cerr << "Failed to create shared memory: " << GetLastError() << std::endl;
            return false;
        }
        
        shared_data = static_cast<SharedFrameData*>(MapViewOfFile(
            shared_memory,
            FILE_MAP_ALL_ACCESS,
            0,
            0,
            MAPPING_SIZE
        ));
        
        if (!shared_data) {
            std::cerr << "Failed to map shared memory: " << GetLastError() << std::endl;
            return false;
        }
        
        // Initialize shared data header (do not assume fixed struct size)
        const size_t header_size = offsetof(SharedFrameData, pixel_data);
        memset(shared_data, 0, header_size);
        shared_data->magic = MAGIC_NUMBER;
        shared_data->receiver_count = 0;
        // Compute double-buffer layout
        const size_t capacity = MAPPING_SIZE - header_size;
        const size_t per_buffer = capacity / 2;
        shared_data->active_index = 0;
        shared_data->buffer_capacity = static_cast<uint32_t>(per_buffer);
        shared_data->buf_offset[0] = header_size;
        shared_data->buf_offset[1] = header_size + per_buffer;
        
        std::cout << "Shared memory created successfully at: " << SHARED_MEMORY_NAME << std::endl;
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
    
    void start_sender_thread() {
        if (!ndi_sender || !shared_data) {
            std::cerr << "NDI sender or shared memory not ready" << std::endl;
            return;
        }
        
        should_stop = false;
        sender_thread = std::thread(&NDISender::sender_loop, this);
        std::cout << "Sender thread started - waiting for LÖVE to provide frames..." << std::endl;
    }
    
    void sender_loop() {
        uint32_t last_frame_number = 0;
        auto start_time = std::chrono::high_resolution_clock::now();
        
        while (!should_stop && !should_exit) {
            // Check if we have new frame data
            if (shared_data->magic != MAGIC_NUMBER) {
                std::this_thread::sleep_for(std::chrono::milliseconds(1));
                continue;
            }
            
            // Check if frame number changed (new frame available)
            if (shared_data->frame_number == last_frame_number) {
                std::this_thread::sleep_for(std::chrono::milliseconds(1));
                continue;
            }
            
            // Check for connections
            int connections = NDIlib_send_get_no_connections(ndi_sender, 0);
            shared_data->receiver_count = connections; // Update receiver count in shared memory
            
            if (connections == 0) {
                last_frame_number = shared_data->frame_number;
                std::this_thread::sleep_for(std::chrono::milliseconds(16));
                continue;
            }
            
            // Process the frame
            send_frame_from_shared_data(shared_data);
            last_frame_number = shared_data->frame_number;
            
            // Report progress
            if (shared_data->frame_number % 60 == 0) {
                std::cout << "Sent frame " << shared_data->frame_number 
                         << " (" << shared_data->width << "x" << shared_data->height 
                         << ") - " << connections << " connections" << std::endl;
            }
        }
        
        std::cout << "Sender loop exited" << std::endl;
    }
    
    void send_frame_from_shared_data(SharedFrameData* data) {
        if (!data || data->magic != MAGIC_NUMBER) {
            return;
        }

        // Convert format based on what LÖVE provided
        NDIlib_video_frame_v2_t video_frame;
        memset(&video_frame, 0, sizeof(video_frame));

        video_frame.xres = data->width;
        video_frame.yres = data->height;
        video_frame.frame_rate_N = 60000; // NTSC (like professional)
        video_frame.frame_rate_D = 1001;  // 59.94 fps
        video_frame.picture_aspect_ratio = (float)data->width / (float)data->height;
        video_frame.frame_format_type = NDIlib_frame_format_type_progressive;

        // Source pointer into the currently active shared buffer
        const uint32_t idx = data->active_index & 1U;
        const uint8_t* base = reinterpret_cast<const uint8_t*>(shared_data);
        const uint8_t* src = base + data->buf_offset[idx];
        const size_t bytes = static_cast<size_t>(data->data_size);

        // Always copy to a local buffer to avoid races while sending
        std::unique_ptr<uint8_t[]> send_buf(new uint8_t[data->width * data->height * 4]);
        if (data->format == 0) { // RGBA -> BGRA
            convert_rgba_to_bgra(const_cast<uint8_t*>(src), send_buf.get(), data->width * data->height);
        } else {
            // BGRA: copy as-is
            memcpy(send_buf.get(), src, bytes);
        }

        video_frame.FourCC = NDIlib_FourCC_type_BGRA;
        video_frame.line_stride_in_bytes = data->width * 4;
        video_frame.p_data = send_buf.get();

        // Timing
        video_frame.timecode = data->timestamp_us * 10;
        video_frame.timestamp = data->timestamp_us;
        video_frame.p_metadata = nullptr;

        // Send frame
        NDIlib_send_send_video_v2(ndi_sender, &video_frame);
    }
    
    void convert_rgba_to_bgra(uint8_t* rgba_data, uint8_t* bgra_data, int pixel_count) {
        for (int i = 0; i < pixel_count; i++) {
            int idx = i * 4;
            bgra_data[idx] = rgba_data[idx + 2];     // B = R
            bgra_data[idx + 1] = rgba_data[idx + 1]; // G = G
            bgra_data[idx + 2] = rgba_data[idx];     // R = B
            bgra_data[idx + 3] = rgba_data[idx + 3]; // A = A
        }
    }
    
    void stop() {
        should_stop = true;
        if (sender_thread.joinable()) {
            sender_thread.join();
        }
    }
    
    ~NDISender() {
        stop();
        
        if (ndi_sender) {
            NDIlib_send_destroy(ndi_sender);
            std::cout << "NDI sender destroyed" << std::endl;
        }
        
        if (shared_data) {
            UnmapViewOfFile(shared_data);
        }
        
        if (shared_memory) {
            CloseHandle(shared_memory);
        }
        
        if (is_initialized) {
            NDIlib_destroy();
            std::cout << "NDI library destroyed" << std::endl;
        }
    }
};

int main() {
    // Set up signal handlers for graceful shutdown
    signal(SIGINT, signal_handler);
    signal(SIGTERM, signal_handler);
    
    std::cout << "=== LÖVE NDI Sender (Managed Mode) ===" << std::endl;
    std::cout << "This program receives texture data from LÖVE and streams via NDI" << std::endl;
    std::cout << "Running in headless mode - managed by LÖVE application" << std::endl;
    
    NDISender sender;
    
    if (!sender.initialize()) {
        std::cerr << "Failed to initialize hybrid sender" << std::endl;
        return 1;
    }
    
    if (!sender.create_sender("LÖVE Visualizer")) {
        std::cerr << "Failed to create NDI sender" << std::endl;
        return 1;
    }
    
    sender.start_sender_thread();
    
    std::cout << "NDI sender running in managed mode!" << std::endl;
    std::cout << "- Waiting for LÖVE visualizer to provide frames" << std::endl;
    std::cout << "- Will exit when terminated by parent process" << std::endl;
    
    // Run until signaled to exit
    while (!should_exit) {
        std::this_thread::sleep_for(std::chrono::milliseconds(100));
    }
    
    std::cout << "Stopping NDI sender..." << std::endl;
    sender.stop();
    
    return 0;
}
