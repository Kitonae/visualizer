-- ndi.lua
-- NDI (Network Device Interface) integration for Love2D
-- This module provides NDI streaming capability using FFI

local M = {}

-- Load FFI for native library access
local has_ffi, ffi = pcall(require, "ffi")

if not has_ffi then
    error("FFI is required for NDI functionality")
end

local is_initialized = false
local is_streaming = false
local ndi_lib = nil
local ndi_sender = nil
local capture_canvas = nil
local ndi_frame_buffer = nil  -- Persistent buffer for frame data
local frame_counter = 0  -- Frame counter for timestamps

-- NDI type definitions
pcall(function()
    ffi.cdef[[
    // C standard library functions
        void* malloc(size_t size);
        void free(void* ptr);
        
        // Basic NDI structures for video frames
        typedef enum {
            NDIlib_FourCC_type_UYVY = 0x59565955,  // UYVY
            NDIlib_FourCC_type_BGRA = 0x41524742,  // BGRA  
            NDIlib_FourCC_type_BGRX = 0x58524742,  // BGRX
            NDIlib_FourCC_type_RGBA = 0x41424752,  // RGBA
            NDIlib_FourCC_type_RGBX = 0x58424752   // RGBX
        } NDIlib_FourCC_video_type_e;
        
        typedef struct {
            int xres, yres;
            int frame_rate_N, frame_rate_D;
            int picture_aspect_ratio_N, picture_aspect_ratio_D;
            int frame_format_type;  // 0 = interleaved, 1 = progressive, 2 = field_0, 3 = field_1
            int FourCC;            // Pixel format (use enum values)
            long long timecode;
            uint8_t* p_data;
            int line_stride_in_bytes;
            char* p_metadata;
            long long timestamp;
        } NDIlib_video_frame_v2_t;
        
        typedef struct {
            char* p_ndi_name;
            char* p_groups;
            bool clock_video;
            bool clock_audio;
        } NDIlib_send_create_t;
        
        // Function prototypes
        bool NDIlib_initialize(void);
        void NDIlib_destroy(void);
        void* NDIlib_send_create(const NDIlib_send_create_t* p_create_settings);
        void NDIlib_send_destroy(void* p_instance);
        void NDIlib_send_send_video_v2(void* p_instance, const NDIlib_video_frame_v2_t* p_video_data);
        
        // Connection management - CRITICAL MISSING FUNCTION
        int NDIlib_send_get_no_connections(void* p_instance, uint32_t timeout_in_ms);
        
        // Additional functions that might be needed
        bool NDIlib_is_supported_CPU(void);
        const char* NDIlib_version(void);
        ]]
end)

-- Load NDI library using FFI
local function load_ndi_library()
    if not has_ffi then
        return nil
    end
    
    local ndi_paths = {
        "C:\\Program Files\\NDI\\NDI 6 Tools\\Runtime\\Processing.NDI.Lib.x64.dll",
        "Processing.NDI.Lib.x64.dll",
        "C:\\Program Files\\NDI\\Runtime\\v6\\Processing.NDI.Lib.x64.dll"
    }
    
    for _, path in ipairs(ndi_paths) do
        local success, lib = pcall(function()
            return ffi.load(path)
        end)
        if success then
            print("Loaded NDI library from: " .. path)
            return lib
        end
    end
    
    return nil
end

-- Initialize NDI
function M.initialize()
    if is_initialized then
        return true
    end
    
    -- Try FFI approach first
    if has_ffi then
        local success, result = pcall(function()
            ndi_lib = load_ndi_library()
            if not ndi_lib then
                error("Could not load NDI library")
            end
            
            -- Check CPU support
            local cpu_supported = ndi_lib.NDIlib_is_supported_CPU()
            if not cpu_supported then
                error("CPU does not support NDI")
            end
            print("NDI CPU support verified")
            
            -- Get NDI version
            local version = ndi_lib.NDIlib_version()
            if version ~= nil then
                print("NDI version: " .. ffi.string(version))
            end
            
            -- Initialize NDI
            local init_result = ndi_lib.NDIlib_initialize()
            if not init_result then
                error("Failed to initialize NDI")
            end
            
            is_initialized = true
            print("NDI initialized with FFI mode")
            return true
        end)
        
        if success and result then
            return true
        else
            print("NDI initialization failed: " .. tostring(result))
            return false
        end
    else
        print("FFI not available for NDI")
        return false
    end
end

-- Create NDI sender
function M.create_sender(source_name, groups)
    if not is_initialized then
        if not M.initialize() then
            return false
        end
    end
    
    if not has_ffi or not ndi_lib then
        return false
    end
    
    local success, result = pcall(function()
        print("Attempting to create NDI sender...")
        
        -- Create sender settings with minimal configuration
        local sender_settings = ffi.new("NDIlib_send_create_t")
        
        -- Initialize all fields to zero/null first
        ffi.fill(sender_settings, ffi.sizeof("NDIlib_send_create_t"), 0)
        
        -- Set source name if provided
        if source_name and #source_name > 0 then
            -- Use ffi.new to create a persistent string buffer
            local name_str = ffi.new("char[?]", #source_name + 1)
            ffi.copy(name_str, source_name)
            
            sender_settings.p_ndi_name = name_str
            -- Keep reference to prevent GC
            _G._ndi_name_ref = name_str
            print("NDI source name set to: " .. source_name)
            print("Name pointer: " .. tostring(name_str))
        else
            sender_settings.p_ndi_name = nil
        end
        
        -- Set other fields
        sender_settings.p_groups = nil
        sender_settings.clock_video = false
        sender_settings.clock_audio = false
        
        -- Debug: print sender settings
        print("Sender settings:")
        print("  p_ndi_name: " .. tostring(sender_settings.p_ndi_name))
        print("  p_groups: " .. tostring(sender_settings.p_groups))
        print("  clock_video: " .. tostring(sender_settings.clock_video))
        print("  clock_audio: " .. tostring(sender_settings.clock_audio))
        
        -- Try creating sender
        print("Calling NDIlib_send_create...")
        ndi_sender = ndi_lib.NDIlib_send_create(sender_settings)
        
        if ndi_sender == nil or ndi_sender == ffi.cast("void*", 0) then
            error("NDI sender creation returned null pointer")
        end
        
        print("NDI sender created successfully: " .. tostring(ndi_sender))
        
        -- Test that sender is actually valid by checking if it's non-null
        local sender_addr = tonumber(ffi.cast("intptr_t", ndi_sender))
        print("NDI sender address: 0x" .. string.format("%x", sender_addr))
        
        if sender_addr == 0 then
            error("NDI sender has null address")
        end
        
        print("NDI sender validation passed")
        return true
    end)
    
    if not success then
        print("NDI sender creation failed: " .. tostring(result))
        return false
    end
    
    return result
end

-- Start streaming
function M.start_streaming(source_name, groups)
    if is_streaming then
        return true
    end
    
    source_name = source_name or "LÖVE Visualizer"
    
    if not ndi_sender then
        if not M.create_sender(source_name, groups) then
            return false
        end
    end
    
    -- Reset frame counter only when streaming starts
    frame_counter = 0
    
    is_streaming = true
    print("NDI streaming started: " .. source_name)
    return true
end

-- Stop streaming
function M.stop_streaming()
    is_streaming = false
end

-- Setup real-time capture
function M.setup_realtime_capture()
    if not is_initialized then
        return false
    end
    
    local width = love.graphics.getWidth()
    local height = love.graphics.getHeight()
    
    -- Create capture canvas for frame capture
    capture_canvas = love.graphics.newCanvas(width, height, {format = "rgba8"})
    
    return true
end

-- Begin frame capture
function M.begin_capture()
    if capture_canvas and is_streaming then
        love.graphics.setCanvas(capture_canvas)
        love.graphics.clear(0, 0, 0, 1)
    end
end

-- End capture and send frame
function M.end_capture_and_send()
    if not capture_canvas or not is_streaming then
        return false
    end
    
    love.graphics.setCanvas()
    
    -- Send the frame data via NDI
    if not has_ffi or not ndi_lib or not ndi_sender then
        print("NDI frame send failed: missing components")
        print("  has_ffi: " .. tostring(has_ffi))
        print("  ndi_lib: " .. tostring(ndi_lib))
        print("  ndi_sender: " .. tostring(ndi_sender))
        return false
    end
    
    -- Validate sender is still valid
    local sender_addr = tonumber(ffi.cast("intptr_t", ndi_sender))
    if sender_addr == 0 then
        print("NDI sender is null, cannot send frame")
        return false
    end
    
    -- CRITICAL: Check if there are any connections (like official examples)
    local num_connections = ndi_lib.NDIlib_send_get_no_connections(ndi_sender, 0)
    if num_connections == 0 then
        -- No receivers connected, don't waste resources
        return true
    end
    
    local success, result = pcall(function()
        -- Get image data from canvas
        local imageData = capture_canvas:newImageData()
        local width = capture_canvas:getWidth()
        local height = capture_canvas:getHeight()
        
        -- Validate dimensions
        if width <= 0 or height <= 0 then
            print("Invalid canvas dimensions: " .. width .. "x" .. height)
            return false
        end
        
        -- Convert RGBA to BGRA for NDI compatibility
        local data_size = width * height * 4
        
        -- MINIMAL TEST: Use malloc like official examples
        local data_size = width * height * 4
        local test_buffer = ffi.C.malloc(data_size)
        if test_buffer == nil then
            print("Failed to allocate test buffer")
            return false
        end
        
        local test_ptr = ffi.cast("uint8_t*", test_buffer)
        
        -- Fill with simple pattern like official NDI examples
        local frame_counter = math.floor(love.timer.getTime() * 10) % 2  -- Blink pattern
        local color_value = frame_counter == 0 and 255 or 0
        
        -- Simple memset-like pattern (like the official example)
        for i = 0, data_size - 1, 4 do
            test_ptr[i] = color_value     -- B
            test_ptr[i + 1] = color_value -- G
            test_ptr[i + 2] = color_value -- R
            test_ptr[i + 3] = 255         -- A
        end
        
        -- Debug: Check if pixel data is actually changing
        local sample_pixel_r = color_value  -- R channel value
        local sample_pixel_g = color_value  -- G channel value  
        local sample_pixel_b = color_value  -- B channel value
        
        -- Create NDI video frame
        local video_frame = ffi.new("NDIlib_video_frame_v2_t")
        
        -- Initialize all fields properly
        ffi.fill(video_frame, ffi.sizeof("NDIlib_video_frame_v2_t"), 0)
        
        video_frame.xres = width
        video_frame.yres = height
        video_frame.frame_rate_N = 60
        video_frame.frame_rate_D = 1
        video_frame.picture_aspect_ratio_N = width
        video_frame.picture_aspect_ratio_D = height
        video_frame.frame_format_type = 1  -- Progressive (like the examples)
        video_frame.FourCC = 0x41524742  -- BGRA format (standard)
        video_frame.timecode = 0  -- Set to 0 like examples
        video_frame.line_stride_in_bytes = width * 4  -- Explicit stride calculation
        -- Use simple time-based timestamp
        local current_time = love.timer.getTime()
        video_frame.timestamp = math.floor(current_time * 1000000)  -- Convert to microseconds
        
        -- Debug timestamp
        if math.floor(current_time) % 2 == 0 and math.fmod(current_time, 1) < 0.016 then  -- Every 2 seconds
            print(string.format("Current time: %.3f, timestamp: %d", current_time, video_frame.timestamp))
        end
        video_frame.p_metadata = ffi.cast("char*", 0)  -- No metadata
        
        -- Use malloc'd buffer (like official examples)
        video_frame.p_data = test_ptr
        
        -- Send frame synchronously - this should work now
        ndi_lib.NDIlib_send_send_video_v2(ndi_sender, video_frame)
        
        -- Free the buffer immediately after sending (like examples)
        ffi.C.free(test_buffer)
        
        -- Debug output (only occasionally to avoid spam)
        if love.timer.getTime() % 2 < 0.016 then  -- Every ~2 seconds
            print(string.format("NDI frame sent: %dx%d at %.2f fps (BGRX) - %d connections", 
                width, height, love.timer.getFPS(), num_connections))
            print(string.format("Frame data: ptr=%s, stride=%d, fourcc=0x%08X, timestamp=%d", 
                tostring(video_frame.p_data), video_frame.line_stride_in_bytes, video_frame.FourCC, video_frame.timestamp))
        end
        
        return true
    end)
    
    if not success then
        print("Failed to send NDI frame: " .. tostring(result))
        return false
    end
    
    return result
end

-- Cleanup function
function M.cleanup()
    if is_streaming then
        M.stop_streaming()
    end
    
    if ndi_sender then
        ndi_lib.NDIlib_send_destroy(ndi_sender)
        ndi_sender = nil
    end
    
    if is_initialized and ndi_lib then
        ndi_lib.NDIlib_destroy()
        is_initialized = false
    end
    
    print("NDI cleanup completed")
end

-- Check if streaming
function M.is_streaming()
    return is_streaming
end

-- Check if initialized
function M.is_initialized()
    return is_initialized
end

-- Get current mode
function M.get_mode()
    if has_ffi then
        return "ffi"
    else
        return "disabled"
    end
end

-- Cleanup
function M.destroy()
    if ndi_sender and ndi_lib then
        ndi_lib.NDIlib_send_destroy(ndi_sender)
        ndi_sender = nil
    end
    
    -- Clear name reference (ffi.new memory is garbage collected)
    if _G._ndi_name_ref then
        _G._ndi_name_ref = nil
    end
    
    if is_initialized and ndi_lib then
        ndi_lib.NDIlib_destroy()
    end
    
    is_initialized = false
    is_streaming = false
    capture_canvas = nil
end

return M
