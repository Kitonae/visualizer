-- NDI Test Implementation - Closely mimics official SDK examples
-- Based on C:\Program Files\NDI\NDI 6 SDK\Examples\C++\NDIlib_Send_Video\NDIlib_Send_Video.cpp

local M = {}

local ffi = require("ffi")

-- NDI structures and functions (exact from SDK headers)
ffi.cdef[[
    // Basic types
    typedef unsigned char uint8_t;
    typedef unsigned int uint32_t;
    typedef long long int64_t;
    typedef void* NDIlib_send_instance_t;
    
    // NDI video frame structure (exact from SDK)
    typedef struct NDIlib_video_frame_v2_t {
        int xres, yres;
        int FourCC;
        int frame_rate_N, frame_rate_D;
        float picture_aspect_ratio;
        int frame_format_type;
        int64_t timecode;
        uint8_t* p_data;
        int line_stride_in_bytes;
        char* p_metadata;
        int64_t timestamp;
    } NDIlib_video_frame_v2_t;
    
    // NDI sender creation structure
    typedef struct NDIlib_send_create_t {
        char* p_ndi_name;
        char* p_groups;
        int clock_video;
        int clock_audio;
    } NDIlib_send_create_t;
    
    // NDI function prototypes (exact from SDK)
    int NDIlib_initialize(void);
    void NDIlib_destroy(void);
    NDIlib_send_instance_t NDIlib_send_create(const NDIlib_send_create_t* p_create_settings);
    void NDIlib_send_destroy(NDIlib_send_instance_t p_instance);
    void NDIlib_send_send_video_v2(NDIlib_send_instance_t p_instance, const NDIlib_video_frame_v2_t* p_video_data);
    int NDIlib_send_get_no_connections(NDIlib_send_instance_t p_instance, uint32_t timeout_in_ms);
    
    // Memory functions
    void* malloc(size_t size);
    void free(void* ptr);
    void* memset(void* s, int c, size_t n);
]]

-- NDI constants (exact values from SDK)
local NDIlib_FourCC_type_BGRX = 0x58524742
local NDIlib_FourCC_type_BGRA = 0x41524742
local NDIlib_FourCC_type_UYVY = 0x59565955

local ndi_lib = nil
local ndi_sender = nil

-- Load NDI library (try local copies first, then system paths)
local function load_ndi_library()
    local ndi_paths = {
        "Processing.NDI.Lib.x64.dll",  -- Local SDK version
        "Processing.NDI.Lib.Runtime.x64.dll",  -- Local runtime version
        "C:\\Program Files\\NDI\\NDI 6 SDK\\Bin\\x64\\Processing.NDI.Lib.x64.dll",  -- SDK version (newer)
        "C:\\Program Files\\NDI\\NDI 6 Tools\\Runtime\\Processing.NDI.Lib.x64.dll", -- Runtime version
    }
    
    for _, path in ipairs(ndi_paths) do
        local success, lib = pcall(function()
            return ffi.load(path)
        end)
        if success then
            print("NDI Test: Loaded library from " .. path)
            return lib
        end
    end
    return nil
end

-- Initialize NDI (exact pattern from SDK example)
function M.initialize()
    ndi_lib = load_ndi_library()
    if not ndi_lib then
        print("NDI Test: Failed to load NDI library")
        return false
    end
    
    -- Initialize NDI (exact call from SDK)
    if not ndi_lib.NDIlib_initialize() then
        print("NDI Test: NDI initialization failed")
        return false
    end
    
    print("NDI Test: NDI initialized successfully")
    return true
end

-- Create sender (exact pattern from SDK example)
function M.create_sender(source_name)
    source_name = source_name or "NDI Test Sender"
    
    -- Create sender with default settings (like SDK example)
    ndi_sender = ndi_lib.NDIlib_send_create(nil)
    if not ndi_sender or ndi_sender == ffi.cast("void*", 0) then
        print("NDI Test: Failed to create sender")
        return false
    end
    
    print("NDI Test: Sender created successfully")
    return true
end

-- Send test frames (exact pattern from SDK example)
function M.send_test_frames(width, height, frame_count)
    width = width or 800
    height = height or 600
    frame_count = frame_count or 10
    
    if not ndi_sender then
        print("NDI Test: No sender available")
        return false
    end
    
    print(string.format("NDI Test: Sending %d test frames (%dx%d)", frame_count, width, height))
    
    -- Create video frame structure (exact from SDK + documentation best practices)
    local video_frame = ffi.new("NDIlib_video_frame_v2_t")
    
    -- Zero-initialize the entire structure (critical per documentation)
    ffi.fill(video_frame, ffi.sizeof("NDIlib_video_frame_v2_t"), 0)
    
    -- Only set the essential fields (following SDK example + documentation)
    video_frame.xres = width
    video_frame.yres = height
    video_frame.FourCC = NDIlib_FourCC_type_BGRX  -- Use BGRX for maximum compatibility
    video_frame.frame_rate_N = 30000  -- NTSC frame rate (recommended)
    video_frame.frame_rate_D = 1001
    -- Skip picture_aspect_ratio (let it stay 0.0 from zero-init)
    video_frame.frame_format_type = 1  -- Progressive (recommended)
    video_frame.timecode = 0  -- Let NDI synthesize timecode
    video_frame.line_stride_in_bytes = width * 4  -- 4 bytes per pixel for BGRX
    video_frame.timestamp = 0  -- Let NDI handle timing
    
    -- Allocate buffer (exact pattern from SDK)
    local buffer_size = width * height * 4
    local p_data = ffi.C.malloc(buffer_size)
    if not p_data then
        print("NDI Test: Failed to allocate frame buffer")
        return false
    end
    
    video_frame.p_data = ffi.cast("uint8_t*", p_data)
    
    -- Send frames (exact pattern from SDK example)
    local start_time = love.timer.getTime()
    
    for frame_idx = 1, frame_count do
        -- Fill buffer with alternating pattern (like SDK memset example)
        local fill_value = (frame_idx % 2 == 0) and 255 or 0
        ffi.C.memset(p_data, fill_value, buffer_size)
        
        -- Check connections before sending
        local connections = ndi_lib.NDIlib_send_get_no_connections(ndi_sender, 0)
        
        -- Send frame (exact call from SDK)
        ndi_lib.NDIlib_send_send_video_v2(ndi_sender, video_frame)
        
        print(string.format("NDI Test: Frame %d sent (BGRX %dx%d, %d connections, fill=%d)", 
            frame_idx, width, height, connections, fill_value))
        
        -- Small delay between frames
        love.timer.sleep(1/30)  -- 30 FPS
    end
    
    local elapsed = love.timer.getTime() - start_time
    local fps = frame_count / elapsed
    print(string.format("NDI Test: Sent %d frames in %.2f seconds (%.2f fps)", frame_count, elapsed, fps))
    
    -- Free buffer (exact pattern from SDK)
    ffi.C.free(p_data)
    
    return true
end

-- Cleanup (exact pattern from SDK example)
function M.cleanup()
    if ndi_sender then
        ndi_lib.NDIlib_send_destroy(ndi_sender)
        ndi_sender = nil
        print("NDI Test: Sender destroyed")
    end
    
    if ndi_lib then
        ndi_lib.NDIlib_destroy()
        print("NDI Test: NDI destroyed")
    end
end

-- Simple test function that runs the complete SDK example pattern
function M.run_test()
    print("=== NDI Test Implementation (SDK Pattern) ===")
    
    if not M.initialize() then
        return false
    end
    
    if not M.create_sender("NDI SDK Test") then
        M.cleanup()
        return false
    end
    
    -- Send test frames
    M.send_test_frames(800, 600, 300)  -- 300 frames at 800x600
    
    print("NDI Test: Waiting 2 seconds...")
    love.timer.sleep(2)
    
    M.cleanup()
    print("NDI Test: Complete")
    return true
end

return M
