-- NDI sender using shared memory with managed C++ subprocess
local ffi = require("ffi")
local bit = require("bit")
local logger = require("logger")

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

    // Performance Counters API
    typedef void* PDH_HQUERY;
    typedef void* PDH_HCOUNTER;
    
    typedef struct {
        uint32_t    CStatus;
        union {
            int32_t     longValue;
            double      doubleValue;
            int64_t     largeValue;
            char*       AnsiStringValue;
            wchar_t*    WideStringValue;
        };
    } PDH_FMT_COUNTERVALUE;
    
    uint32_t PdhOpenQueryA(const char* szDataSource, uint32_t dwUserData, PDH_HQUERY* phQuery);
    uint32_t PdhAddCounterA(PDH_HQUERY hQuery, const char* szFullCounterPath, uint32_t dwUserData, PDH_HCOUNTER* phCounter);
    uint32_t PdhAddEnglishCounterA(PDH_HQUERY hQuery, const char* szFullCounterPath, uint32_t dwUserData, PDH_HCOUNTER* phCounter);
    uint32_t PdhCollectQueryData(PDH_HQUERY hQuery);
    uint32_t PdhGetFormattedCounterValue(PDH_HCOUNTER hCounter, uint32_t dwFormat, uint32_t* lpdwType, PDH_FMT_COUNTERVALUE* pValue);
    uint32_t PdhCloseQuery(PDH_HQUERY hQuery);
    uint32_t PdhExpandWildCardPathA(const char* szDataSource, const char* szWildCardPath, char* mszExpandedPathList, uint32_t* pcchPathListLength, uint32_t dwFlags);

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

-- Use DOUBLE format for rate counters like Bytes/sec
local PDH_FMT_DOUBLE = 0x00000200
local PDH_FMT_LARGE = 0x00000400 -- kept for reference (not used)
local PDH_CSTATUS_VALID_DATA = 0x00000000
local PDH_CSTATUS_NEW_DATA = 0x00000001

-- Load PDH library
local pdh = ffi.load("pdh")

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
        uint32_t receiver_count;  // Number of connected NDI receivers
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
local debug_output = false -- Debug output disabled by default

-- Network statistics
local network_stats = {
    bytes_sent = 0,
    frames_sent = 0,
    last_frame_time = 0,
    fps_counter = 0,
    fps_time = 0,
    current_fps = 0,
    bandwidth_history = {}, -- Last 60 samples for graph (real network interface stats)
    max_bandwidth = 0,
    avg_bandwidth = 0
}

local network_interface_stats = {
    last_bytes_sent = 0,
    last_check_time = 0,
    interface_name = nil,
    use_fallback = false,
    zero_count = 0
}

-- Performance counters
local perf_counters = {
    query = nil,
    counter = nil,
    counters = nil,
    initialized = false
}

local SHARED_MEMORY_NAME = "LOVE_NDI_SHARED_FRAME"
local MAGIC_NUMBER = 0xDEADBEEF
local NDI_SENDER_PATH = "ndi_sender.exe"

function M.init_performance_counters()
    if perf_counters.initialized then
        return true
    end
    
    local success, result = pcall(function()
        logger.info("PDH: Initializing performance counters")
        -- Create a new query
        local query = ffi.new("PDH_HQUERY[1]")
        local status = pdh.PdhOpenQueryA(nil, 0, query)
        if status ~= 0 then
            logger.error("PDH: PdhOpenQueryA failed status=" .. tostring(status))
            error("Failed to open PDH query: " .. status)
        end
        perf_counters.query = query[0]
        
        -- Prefer English counter names (works across locales)
        local function try_add_counter(path)
            local c = ffi.new("PDH_HCOUNTER[1]")
            local st
            -- Try the English variant if available on this OS; call in pcall to avoid symbol errors
            local ok_call, ret = pcall(function()
                return pdh.PdhAddEnglishCounterA(perf_counters.query, path, 0, c)
            end)
            if ok_call then
                st = ret
            else
                st = pdh.PdhAddCounterA(perf_counters.query, path, 0, c)
            end
            if st == 0 then
                logger.info("PDH: Added counter " .. path)
                return true, c[0]
            else
                logger.debug("PDH: Failed to add counter " .. path .. " status=" .. tostring(st))
                return false, st
            end
        end

        -- First try total bytes (TX+RX), then TX only
        local ok, c = try_add_counter("\\Network Interface(_Total)\\Bytes Total/sec")
        if ok then
            perf_counters.counter = c
            if debug_output then print("PDH: Using _Total Bytes Total/sec") end
        else
            ok, c = try_add_counter("\\Network Interface(_Total)\\Bytes Sent/sec")
            if ok then
                perf_counters.counter = c
                if debug_output then print("PDH: Using _Total Bytes Sent/sec") end
            else
                -- Fall back to summing all interfaces via wildcard expansion
                local function add_wildcard(wildcard)
                    local needed = ffi.new("uint32_t[1]", 0)
                    pdh.PdhExpandWildCardPathA(nil, wildcard, nil, needed, 0)
                    local sz = tonumber(needed[0])
                    if not sz or sz == 0 then return false end
                    local buf = ffi.new("char[?]", sz)
                    local st = pdh.PdhExpandWildCardPathA(nil, wildcard, buf, needed, 0)
                    if st ~= 0 then return false end
                    perf_counters.counters = {}
                    local i = 0
                    while true do
                        local s = ffi.string(buf + i)
                        if #s == 0 then break end
                        local ok_one, c_one = try_add_counter(s)
                        if ok_one then table.insert(perf_counters.counters, c_one) end
                        i = i + #s + 1
                    end
                    local ok_list = perf_counters.counters and #perf_counters.counters > 0
                    if ok_list and debug_output then
                        print("PDH: Using wildcard " .. wildcard .. " across " .. tostring(#perf_counters.counters) .. " counters")
                    end
                    return ok_list
                end
                if not add_wildcard("\\Network Interface(*)\\Bytes Total/sec") then
                    if not add_wildcard("\\Network Interface(*)\\Bytes Sent/sec") then
                        logger.error("PDH: Failed to add any network interface counters")
                        error("Failed to add any network interface counters")
                    end
                end
            end
        end
        
        -- Collect initial data multiple times to ensure it's working
        for i = 1, 3 do
            local s = pdh.PdhCollectQueryData(perf_counters.query)
            logger.debug("PDH: Initial collect status=" .. tostring(s))
            love.timer.sleep(0.1)
        end
        
        perf_counters.initialized = true
        logger.info("PDH: Initialized successfully")
        return true
    end)
    
    if not success then
        logger.warn("PDH: Initialization failed, will fall back if needed")
        return false
    end
    
    return result
end

-- Fallback to simpler network monitoring if performance counters fail
function M.fallback_to_simple_monitoring()
    perf_counters.initialized = false
    network_interface_stats.use_fallback = true
end

function M.get_network_interface_bytes()
    -- If performance counters failed, use fallback method
    if network_interface_stats.use_fallback then
        -- Return a reasonable estimate based on NDI frame data
        if network_stats.current_fps > 0 and network_stats.last_frame_time > 0 then
            -- Estimate network usage based on NDI frames being sent
            -- Assume some overhead and compression for actual network traffic
            local estimated_bandwidth = (network_stats.bytes_sent / (love.timer.getTime() - (start_time or 0))) * 0.8 -- 80% efficiency estimate
            logger.debug("PDH: Using fallback estimate Bps=" .. tostring(estimated_bandwidth))
            return estimated_bandwidth
        end
        logger.debug("PDH: Fallback active but insufficient data, returning 0")
        return 0
    end
    
    if not perf_counters.initialized then
        if not M.init_performance_counters() then
            M.fallback_to_simple_monitoring()
            return M.get_network_interface_bytes() -- Retry with fallback
        end
    end
    
    local success, result = pcall(function()
        -- Collect current data
        local status = pdh.PdhCollectQueryData(perf_counters.query)
        if status ~= 0 then
            logger.warn("PDH: CollectQueryData failed status=" .. tostring(status) .. ", enabling fallback")
            M.fallback_to_simple_monitoring()
            return 0
        end
        
        -- Read either the single total counter or sum per-interface counters
        local function read_counter(c)
            local v = ffi.new("PDH_FMT_COUNTERVALUE")
            local t = ffi.new("uint32_t[1]")
            local st = pdh.PdhGetFormattedCounterValue(c, PDH_FMT_DOUBLE, t, v)
            if st == PDH_CSTATUS_VALID_DATA or st == PDH_CSTATUS_NEW_DATA then
                return tonumber(v.doubleValue) or 0
            end
            logger.debug("PDH: GetFormattedCounterValue non-success status=" .. tostring(st))
            return 0
        end

        if perf_counters.counter ~= nil then
            local val = read_counter(perf_counters.counter)
            logger.debug("PDH: _Total sample Bps=" .. tostring(val))
            return val
        elseif perf_counters.counters ~= nil then
            local sum = 0
            for _, c in ipairs(perf_counters.counters) do
                sum = sum + read_counter(c)
            end
            logger.debug("PDH: Summed interfaces sample Bps=" .. tostring(sum))
            return sum
        else
            M.fallback_to_simple_monitoring()
        end
        
        return 0
    end)
    
    if not success then
        M.fallback_to_simple_monitoring()
        return 0
    end
    
    return result
end

function M.cleanup_performance_counters()
    if perf_counters.query then
        pdh.PdhCloseQuery(perf_counters.query)
        perf_counters.query = nil
    end
    perf_counters.counter = nil
    perf_counters.counters = nil
    perf_counters.initialized = false
end

function M.update_network_interface_stats()
    local current_time = love.timer.getTime()
    
    -- Update network interface stats every second
    if current_time - network_interface_stats.last_check_time >= 1.0 then
        -- Get current network bytes per second (this is already a rate from performance counters)
        local bandwidth = M.get_network_interface_bytes() -- bytes per second
        
        -- Always add data to history, even if zero, to keep the graph updating
        table.insert(network_stats.bandwidth_history, bandwidth)
        if #network_stats.bandwidth_history > 60 then
            table.remove(network_stats.bandwidth_history, 1)
        end
        
        -- If PDH appears stuck at zero while frames are being sent, fall back
        if bandwidth <= 0 and network_stats.frames_sent > 0 then
            network_interface_stats.zero_count = network_interface_stats.zero_count + 1
            if network_interface_stats.zero_count >= 3 then
                logger.warn("PDH: 3 consecutive zero samples while sending frames; switching to fallback estimate")
                M.fallback_to_simple_monitoring()
                bandwidth = M.get_network_interface_bytes()
            end
        else
            network_interface_stats.zero_count = 0
        end

        -- Update max bandwidth if we have a positive value
        if bandwidth > 0 and bandwidth > network_stats.max_bandwidth then
            network_stats.max_bandwidth = bandwidth
        end
        
        -- Always calculate average from existing history
        local sum = 0
        for _, bw in ipairs(network_stats.bandwidth_history) do
            sum = sum + bw
        end
        network_stats.avg_bandwidth = #network_stats.bandwidth_history > 0 and (sum / #network_stats.bandwidth_history) or 0
        
        network_interface_stats.last_check_time = current_time
        logger.debug(string.format("PDH: bandwidth %.2f B/s (%.2f MB/s)", bandwidth, bandwidth / (1024*1024)))
    end
end

function M.kill_existing_ndi_processes()
    local success, result = pcall(function()
        print("Checking for existing ndi_sender.exe processes...")
        
        -- Use PowerShell to kill any existing ndi_sender processes
        local command = 'powershell -Command "Get-Process -Name ndi_sender -ErrorAction SilentlyContinue | Stop-Process -Force"'
        local handle = io.popen(command)
        if handle then
            local output = handle:read("*a")
            handle:close()
            if output and output ~= "" then
                print("Killed existing ndi_sender processes")
            else
                print("No existing ndi_sender processes found")
            end
        end
        
        -- Small delay to ensure processes are fully terminated
        love.timer.sleep(0.1)
        return true
    end)
    
    if not success then
        print("Warning: Failed to check/kill existing NDI processes: " .. tostring(result))
    end
end

function M.start_ndi_process()
    if ndi_process then
        print("NDI process already running")
        return true
    end
    
    -- Kill any existing ndi_sender.exe processes before starting
    M.kill_existing_ndi_processes()
    
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
                64 * 1024 * 1024, -- 64MB for 4K+ frames
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
            64 * 1024 * 1024 -- 64MB
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
        local max_data_size = 64 * 1024 * 1024 - ffi.offsetof("SharedFrameData", "pixel_data")
        if data_size > max_data_size then
            print("Frame too large for shared memory buffer: " .. data_size .. " (max: " .. max_data_size .. ")")
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
        
        -- Update network statistics
        network_stats.bytes_sent = network_stats.bytes_sent + data_size
        network_stats.frames_sent = network_stats.frames_sent + 1
        network_stats.last_frame_time = current_time
        
        -- Calculate FPS
        network_stats.fps_counter = network_stats.fps_counter + 1
        if current_time - network_stats.fps_time >= 1.0 then
            network_stats.current_fps = network_stats.fps_counter
            network_stats.fps_counter = 0
            network_stats.fps_time = current_time
        end
        
        -- Update real network interface statistics
        M.update_network_interface_stats()
        
        -- Debug output (only if enabled)
        if debug_output and frame_counter % 60 == 0 then
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
    
    -- Force kill any remaining ndi_sender processes as backup
    M.kill_existing_ndi_processes()
    
    -- Cleanup performance counters
    M.cleanup_performance_counters()
    
    if shared_data and shared_data ~= ffi.cast("SharedFrameData*", 0) then
        ffi.C.UnmapViewOfFile(shared_data)
        shared_data = nil
    end
    
    if shared_memory and shared_memory ~= ffi.cast("void*", 0) then
        ffi.C.CloseHandle(shared_memory)
        shared_memory = nil
    end
    
    -- Reset network statistics
    network_stats.bytes_sent = 0
    network_stats.frames_sent = 0
    network_stats.last_frame_time = 0
    network_stats.fps_counter = 0
    network_stats.fps_time = 0
    network_stats.current_fps = 0
    network_stats.bandwidth_history = {}
    network_stats.max_bandwidth = 0
    network_stats.avg_bandwidth = 0
    
    -- Reset network interface stats
    network_interface_stats.last_bytes_sent = 0
    network_interface_stats.last_check_time = 0
    network_interface_stats.interface_name = nil
    network_interface_stats.use_fallback = false
    
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
    source_name = source_name or "LÖVE Visualizer"
    if M.initialize() then
        -- Initialize performance counters for real-time network monitoring
        logger.init("logs/ndi.log")
        logger.set_level(debug_output and "debug" or "info")
        M.init_performance_counters()
        network_interface_stats.last_check_time = love.timer.getTime()
        
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

function M.get_receiver_count()
    if not is_initialized or not shared_data then
        return 0
    end
    
    local success, result = pcall(function()
        local header = ffi.cast("SharedFrameData*", shared_data)
        return header.receiver_count
    end)
    
    if not success then
        return 0
    end
    
    return result
end

function M.get_network_stats()
    return {
        frames_sent = network_stats.frames_sent,
        bytes_sent = network_stats.bytes_sent,
        current_fps = network_stats.current_fps,
        bandwidth_mbps = network_stats.avg_bandwidth / (1024 * 1024),
        max_bandwidth_mbps = network_stats.max_bandwidth / (1024 * 1024),
        bandwidth_history = network_stats.bandwidth_history,
        uptime = start_time and (love.timer.getTime() - start_time) or 0,
        receiver_count = M.get_receiver_count()
    }
end

function M.set_debug_output(enabled)
    debug_output = enabled
    logger.set_level(enabled and "debug" or "info")
    return debug_output
end

function M.get_debug_output()
    return debug_output
end

function M.format_bytes(bytes)
    if bytes < 1024 then
        return string.format("%.0f B", bytes)
    elseif bytes < 1024 * 1024 then
        return string.format("%.1f KB", bytes / 1024)
    elseif bytes < 1024 * 1024 * 1024 then
        return string.format("%.1f MB", bytes / (1024 * 1024))
    else
        return string.format("%.2f GB", bytes / (1024 * 1024 * 1024))
    end
end

-- Cleanup on module unload
function M.__gc()
    M.cleanup()
end

return setmetatable(M, {__gc = M.__gc})
