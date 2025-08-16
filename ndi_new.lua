-- Hybrid NDI sender using shared memory with C++ process
local ffi = require("ffi")
local bit = require("bit")

local M = {}

-- FFI definitions for Windows shared memory
ffi.cdef[[
    // Windows API for shared memory
    void* CreateFileMappingA(void* hFile, void* lpAttributes, uint32_t flProtect, 
                            uint32_t dwMaximumSizeHigh, uint32_t dwMaximumSizeLow, const char* lpName);
    void* MapViewOfFile(void* hFileMappingObject, uint32_t dwDesiredAccess, 
                       uint32_t dwFileOffsetHigh, uint32_t dwFileOffsetLow, size_t dwNumberOfBytesToMap);
    int UnmapViewOfFile(void* lpBaseAddress);
    int CloseHandle(void* hObject);
    uint32_t GetLastError();
]]

-- Constants (outside of cdef)
local PAGE_READWRITE = 0x04
local FILE_MAP_ALL_ACCESS = 0xF001F
local INVALID_HANDLE_VALUE = ffi.cast("void*", -1)

-- Shared frame data structure (must match C++)
ffi.cdef[[
    typedef struct {
        uint32_t magic;           // 0xDEADBEEF for validation
        uint32_t width;
        uint32_t height;
        uint32_t format;          // 0=RGBA, 1=BGRA, 2=UYVY
        uint32_t frame_number;
        uint64_t timestamp_us;    // Microseconds since start
        uint32_t data_size;
        uint8_t pixel_data[1];    // Variable length array (we'll handle size separately)
    } SharedFrameData;
]]

-- Module state
local shared_memory = nil
local shared_data = nil
local is_initialized = false
local frame_counter = 0
local start_time = nil

local SHARED_MEMORY_NAME = "LOVE_NDI_SHARED_FRAME"
local MAGIC_NUMBER = 0xDEADBEEF

function M.initialize()
    if is_initialized then
        return true
    end
    
    local success, result = pcall(function()
        print("Hybrid NDI: Initializing shared memory connection...")
        
        -- Try to open existing shared memory (created by C++ process)
        shared_memory = ffi.C.CreateFileMappingA(
            INVALID_HANDLE_VALUE,
            nil,
            PAGE_READWRITE,
            0,
            8 * 1024 * 1024, -- 8MB for large frames
            SHARED_MEMORY_NAME
        )
        
        if shared_memory == nil or shared_memory == ffi.cast("void*", 0) then
            local error_code = ffi.C.GetLastError()
            error("Failed to create/open shared memory. Error: " .. error_code .. 
                  "\nMake sure hybrid_ndi_sender.exe is running first!")
        end
        
        shared_data = ffi.cast("uint8_t*", ffi.C.MapViewOfFile(
            shared_memory,
            FILE_MAP_ALL_ACCESS,
            0,
            0,
            8 * 1024 * 1024 -- 8MB
        ))
        
        if shared_data == nil or shared_data == ffi.cast("uint8_t*", 0) then
            local error_code = ffi.C.GetLastError()
            error("Failed to map shared memory view. Error: " .. error_code)
        end
        
        -- Cast to structure for easier access
        local header = ffi.cast("SharedFrameData*", shared_data)
        
        -- Initialize timing
        start_time = love.timer.getTime()
        frame_counter = 0
        
        print("Hybrid NDI: Shared memory connection established")
        print("Shared memory address: " .. tostring(shared_data))
        print("Magic number check: " .. string.format("0x%08X", header.magic))
        
        is_initialized = true
        return true
    end)
    
    if not success then
        print("Hybrid NDI initialization failed: " .. tostring(result))
        M.cleanup()
        return false
    end
    
    return result
end

function M.send_frame(capture_canvas)
    if not is_initialized or not shared_data then
        print("Hybrid NDI not initialized")
        return false
    end
    
    local success, result = pcall(function()
        -- Cast to structure for header access
        local header = ffi.cast("SharedFrameData*", shared_data)
        
        -- Get image data from canvas
        local imageData = capture_canvas:newImageData()
        local width = capture_canvas:getWidth()
        local height = capture_canvas:getHeight()
        
        -- Validate dimensions
        if width <= 0 or height <= 0 then
            print("Invalid canvas dimensions: " .. width .. "x" .. height)
            return false
        end
        
        local data_size = width * height * 4 -- RGBA
        local max_data_size = 8 * 1024 * 1024 - ffi.offsetof("SharedFrameData", "pixel_data")
        if data_size > max_data_size then
            print("Frame too large for shared memory buffer: " .. data_size)
            return false
        end
        
        -- Calculate timing
        local current_time = love.timer.getTime()
        local timestamp_us = math.floor((current_time - start_time) * 1000000)
        frame_counter = frame_counter + 1
        
        -- Fill shared data structure
        header.magic = MAGIC_NUMBER
        header.width = width
        header.height = height
        header.format = 0 -- RGBA format
        header.frame_number = frame_counter
        header.timestamp_us = timestamp_us
        header.data_size = data_size
        
        -- Copy pixel data to the area after the header
        local pixels = imageData:getString()
        local pixel_data_ptr = shared_data + ffi.offsetof("SharedFrameData", "pixel_data")
        ffi.copy(pixel_data_ptr, pixels, math.min(data_size, #pixels))
        
        -- Debug output
        if frame_counter % 60 == 0 then
            print(string.format("Hybrid NDI: Sent frame %d (%dx%d) timestamp: %d", 
                frame_counter, width, height, timestamp_us))
        end
        
        return true
    end)
    
    if not success then
        print("Hybrid NDI send frame failed: " .. tostring(result))
        return false
    end
    
    return result
end

function M.cleanup()
    if shared_data and shared_data ~= ffi.cast("SharedFrameData*", 0) then
        ffi.C.UnmapViewOfFile(shared_data)
        shared_data = nil
    end
    
    if shared_memory and shared_memory ~= ffi.cast("void*", 0) then
        ffi.C.CloseHandle(shared_memory)
        shared_memory = nil
    end
    
    is_initialized = false
    print("Hybrid NDI: Cleaned up shared memory")
end

function M.is_ready()
    return is_initialized and shared_data ~= nil
end

function M.get_status()
    if not is_initialized then
        return "Not initialized"
    end
    
    if not shared_data then
        return "No shared memory"
    end
    
    local header = ffi.cast("SharedFrameData*", shared_data)
    local magic_ok = header.magic == MAGIC_NUMBER
    return string.format("Ready (magic: %s, frames: %d)", 
        magic_ok and "OK" or "INVALID", frame_counter)
end

-- Cleanup on module unload
function M.__gc()
    M.cleanup()
end

return setmetatable(M, {__gc = M.__gc})
