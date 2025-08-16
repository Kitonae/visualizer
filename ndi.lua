-- NDI sender using shared memory with managed C++ subprocess
local ffi = require("ffi")
local bit = require("bit")

local M = {}

-- FFI definitions for Windows shared memory and process management
ffi.cdef[[
    // Windows API for shared memory
    void* CreateFileMappingA(void* hFile, void* lpAttributes, uint32_t flProtect, 
                            uint32_t dwMaximumSizeHigh, uint32_t dwMaximumSizeLow, const char* lpName);
    void* MapViewOfFile(void* hFileMappingObject, uint32_t dwDesiredAccess, 
                       uint32_t dwFileOffsetHigh, uint32_t dwFileOffsetLow, size_t dwNumberOfBytesToMap);
    int UnmapViewOfFile(void* lpBaseAddress);
    int CloseHandle(void* hObject);
    uint32_t GetLastError();
    
    // Process management
    typedef struct {
        uint32_t cb;
        void* lpReserved;
        char* lpDesktop;
        char* lpTitle;
        uint32_t dwX;
        uint32_t dwY;
        uint32_t dwXSize;
        uint32_t dwYSize;
        uint32_t dwXCountChars;
        uint32_t dwYCountChars;
        uint32_t dwFillAttribute;
        uint32_t dwFlags;
        uint16_t wShowWindow;
        uint16_t cbReserved2;
        void* lpReserved2;
        void* hStdInput;
        void* hStdOutput;
        void* hStdError;
    } STARTUPINFOA;
    
    typedef struct {
        void* hProcess;
        void* hThread;
        uint32_t dwProcessId;
        uint32_t dwThreadId;
    } PROCESS_INFORMATION;
    
    int CreateProcessA(char* lpApplicationName, char* lpCommandLine, void* lpProcessAttributes,
                      void* lpThreadAttributes, int bInheritHandles, uint32_t dwCreationFlags,
                      void* lpEnvironment, char* lpCurrentDirectory, STARTUPINFOA* lpStartupInfo,
                      PROCESS_INFORMATION* lpProcessInformation);
    int TerminateProcess(void* hProcess, uint32_t uExitCode);
    uint32_t WaitForSingleObject(void* hHandle, uint32_t dwMilliseconds);
    uint32_t GetExitCodeProcess(void* hProcess, uint32_t* lpExitCode);
]]

-- Constants (outside of cdef)
local PAGE_READWRITE = 0x04
local FILE_MAP_ALL_ACCESS = 0xF001F
local INVALID_HANDLE_VALUE = ffi.cast("void*", -1)

-- Process creation constants
local STARTF_USESHOWWINDOW = 0x00000001
local SW_HIDE = 0
local CREATE_NO_WINDOW = 0x08000000
local STILL_ACTIVE = 259
local WAIT_TIMEOUT = 258

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
local ndi_process = nil
local process_info = nil

local SHARED_MEMORY_NAME = "LOVE_NDI_SHARED_FRAME"
local MAGIC_NUMBER = 0xDEADBEEF
local NDI_SENDER_PATH = "build/ndi_sender.exe"

function M.start_ndi_process()
    if ndi_process then
        print("NDI process already running")
        return true
    end
    
    local success, result = pcall(function()
        -- Check if NDI sender executable exists
        local file = io.open(NDI_SENDER_PATH, "r")
        if not file then
            error("NDI sender executable not found at: " .. NDI_SENDER_PATH)
        end
        file:close()
        
        print("Starting NDI sender process: " .. NDI_SENDER_PATH)
        
        -- Set up process startup info for headless operation
        local startup_info = ffi.new("STARTUPINFOA")
        startup_info.cb = ffi.sizeof("STARTUPINFOA")
        startup_info.dwFlags = STARTF_USESHOWWINDOW
        startup_info.wShowWindow = SW_HIDE  -- Hide window
        
        process_info = ffi.new("PROCESS_INFORMATION")
        
        -- Create the process
        local command_line = ffi.new("char[?]", #NDI_SENDER_PATH + 1, NDI_SENDER_PATH)
        local result = ffi.C.CreateProcessA(
            nil,  -- lpApplicationName
            command_line,  -- lpCommandLine (now properly converted)
            nil,  -- lpProcessAttributes
            nil,  -- lpThreadAttributes
            0,    -- bInheritHandles
            CREATE_NO_WINDOW,  -- dwCreationFlags - create without console window
            nil,  -- lpEnvironment
            nil,  -- lpCurrentDirectory
            startup_info,
            process_info
        )
        
        if result == 0 then
            local error_code = ffi.C.GetLastError()
            error("Failed to start NDI sender process. Error: " .. error_code)
        end
        
        ndi_process = process_info.hProcess
        
        print("NDI sender process started successfully")
        print("Process ID: " .. process_info.dwProcessId)
        
        -- Wait a moment for the process to initialize
        love.timer.sleep(0.5)
        
        return true
    end)
    
    if not success then
        print("Failed to start NDI process: " .. tostring(result))
        M.stop_ndi_process()
        return false
    end
    
    return result
end

function M.stop_ndi_process()
    if not ndi_process then
        return
    end
    
    print("Stopping NDI sender process...")
    
    -- First try to terminate gracefully
    local success = pcall(function()
        local result = ffi.C.TerminateProcess(ndi_process, 0)
        if result == 0 then
            print("Warning: Failed to terminate NDI process gracefully")
        end
        
        -- Wait for process to exit (up to 2 seconds)
        local wait_result = ffi.C.WaitForSingleObject(ndi_process, 2000)
        if wait_result == WAIT_TIMEOUT then
            print("Warning: NDI process did not exit within timeout")
        end
        
        -- Clean up handles
        if process_info and process_info.hThread and process_info.hThread ~= ffi.cast("void*", 0) then
            ffi.C.CloseHandle(process_info.hThread)
        end
        if ndi_process and ndi_process ~= ffi.cast("void*", 0) then
            ffi.C.CloseHandle(ndi_process)
        end
    end)
    
    if not success then
        print("Error during NDI process cleanup")
    end
    
    ndi_process = nil
    process_info = nil
    print("NDI sender process stopped")
end

function M.is_process_running()
    if not ndi_process then
        return false
    end
    
    local success, result = pcall(function()
        local exit_code = ffi.new("uint32_t[1]")
        local result = ffi.C.GetExitCodeProcess(ndi_process, exit_code)
        if result == 0 then
            return false
        end
        return exit_code[0] == STILL_ACTIVE
    end)
    
    if not success then
        return false
    end
    
    return result
end
function M.initialize()
    if is_initialized then
        return true
    end
    
    -- Start the NDI sender process first
    if not M.start_ndi_process() then
        return false
    end
    
    local success, result = pcall(function()
        print("NDI: Initializing shared memory connection...")
        
        -- Try to open existing shared memory (created by C++ process)
        -- Retry a few times as the process might need time to create it
        local retry_count = 0
        local max_retries = 10
        
        while retry_count < max_retries do
            shared_memory = ffi.C.CreateFileMappingA(
                INVALID_HANDLE_VALUE,
                nil,
                PAGE_READWRITE,
                0,
                8 * 1024 * 1024, -- 8MB for large frames
                SHARED_MEMORY_NAME
            )
            
            if shared_memory ~= nil and shared_memory ~= ffi.cast("void*", 0) then
                break
            end
            
            retry_count = retry_count + 1
            if retry_count < max_retries then
                print("Waiting for NDI process to create shared memory... (" .. retry_count .. "/" .. max_retries .. ")")
                love.timer.sleep(0.5)
            end
        end
        
        if shared_memory == nil or shared_memory == ffi.cast("void*", 0) then
            local error_code = ffi.C.GetLastError()
            error("Failed to create/open shared memory after " .. max_retries .. " attempts. Error: " .. error_code)
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
        
        print("NDI: Shared memory connection established")
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
        print("NDI not initialized")
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
            print(string.format("NDI: Sent frame %d (%dx%d) timestamp: %d", 
                frame_counter, width, height, timestamp_us))
        end
        
        return true
    end)
    
    if not success then
        print("NDI send frame failed: " .. tostring(result))
        return false
    end
    
    return result
end

function M.cleanup()
    -- Stop the NDI process first
    M.stop_ndi_process()
    
    if shared_data and shared_data ~= ffi.cast("SharedFrameData*", 0) then
        ffi.C.UnmapViewOfFile(shared_data)
        shared_data = nil
    end
    
    if shared_memory and shared_memory ~= ffi.cast("void*", 0) then
        ffi.C.CloseHandle(shared_memory)
        shared_memory = nil
    end
    
    is_initialized = false
    print("NDI: Cleaned up shared memory and stopped process")
end

function M.is_ready()
    return is_initialized and shared_data ~= nil
end

-- Compatibility functions for console
function M.is_initialized()
    return is_initialized
end

function M.is_streaming()
    return is_initialized and shared_data ~= nil and M.is_process_running()
end

function M.start_streaming(source_name)
    source_name = source_name or "LÖVE NDI Stream"
    if M.initialize() then
        print("NDI streaming started: " .. source_name)
        return true
    end
    return false
end

function M.stop_streaming()
    M.cleanup()
    print("NDI streaming stopped")
end

function M.get_mode()
    if is_initialized and M.is_process_running() then
        return "Managed Subprocess + Shared Memory"
    else
        return "Disabled"
    end
end

function M.get_status()
    if not is_initialized then
        return "Not initialized"
    end
    
    if not M.is_process_running() then
        return "Process not running"
    end
    
    if not shared_data then
        return "No shared memory"
    end
    
    local header = ffi.cast("SharedFrameData*", shared_data)
    local magic_ok = header.magic == MAGIC_NUMBER
    return string.format("Ready (magic: %s, frames: %d, PID: %d)", 
        magic_ok and "OK" or "INVALID", frame_counter, 
        process_info and process_info.dwProcessId or 0)
end

-- Cleanup on module unload
function M.__gc()
    M.cleanup()
end

return setmetatable(M, {__gc = M.__gc})
