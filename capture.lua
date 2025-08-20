-- capture.lua
-- Windows Graphics Capture integration via shared memory + managed subprocess

local ffi = require("ffi")

local M = {}

ffi.cdef[[
    void* CreateFileMappingA(void* hFile, void* lpAttributes, uint32_t flProtect,
                             uint32_t dwMaximumSizeHigh, uint32_t dwMaximumSizeLow, const char* lpName);
    void* MapViewOfFile(void* hFileMappingObject, uint32_t dwDesiredAccess,
                        uint32_t dwFileOffsetHigh, uint32_t dwFileOffsetLow, size_t dwNumberOfBytesToMap);
    int UnmapViewOfFile(void* lpBaseAddress);
    int CloseHandle(void* hObject);
    uint32_t GetLastError();

    typedef struct {
        uint32_t cb;
        void* lpReserved;
        char* lpDesktop;
        char* lpTitle;
        uint32_t dwX; uint32_t dwY; uint32_t dwXSize; uint32_t dwYSize;
        uint32_t dwXCountChars; uint32_t dwYCountChars; uint32_t dwFillAttribute;
        uint32_t dwFlags; uint16_t wShowWindow; uint16_t cbReserved2; void* lpReserved2;
        void* hStdInput; void* hStdOutput; void* hStdError;
    } STARTUPINFOA;

    typedef struct { void* hProcess; void* hThread; uint32_t dwProcessId; uint32_t dwThreadId; } PROCESS_INFORMATION;

    int CreateProcessA(char* lpApplicationName, char* lpCommandLine, void* lpProcessAttributes,
                      void* lpThreadAttributes, int bInheritHandles, uint32_t dwCreationFlags,
                      void* lpEnvironment, char* lpCurrentDirectory, STARTUPINFOA* lpStartupInfo,
                      PROCESS_INFORMATION* lpProcessInformation);
    int TerminateProcess(void* hProcess, uint32_t uExitCode);
    uint32_t WaitForSingleObject(void* hHandle, uint32_t dwMilliseconds);
    uint32_t GetExitCodeProcess(void* hProcess, uint32_t* lpExitCode);
]]

-- Note on struct layout:
-- The C++ helper uses #pragma pack(push, 1) for the header, so fields are tightly packed.
-- LuaJIT FFI uses natural alignment, which would insert padding before a uint64_t.
-- To ensure matching offsets, we split the 64-bit timestamp into two 32-bit fields.
ffi.cdef[[
    typedef struct {
        uint32_t magic;           // 0xC0FFEE01 for validation
        uint32_t width;
        uint32_t height;
        uint32_t format;          // 0=RGBA, 1=BGRA
        uint32_t frame_number;
        uint32_t timestamp_lo;    // low 32 bits of timestamp_us
        uint32_t timestamp_hi;    // high 32 bits of timestamp_us
        uint32_t data_size;
        uint32_t reserved;
        uint8_t  pixel_data[1];
    } CaptureSharedFrame;
]]

local PAGE_READWRITE = 0x04
local FILE_MAP_ALL_ACCESS = 0xF001F
local INVALID_HANDLE_VALUE = ffi.cast("void*", -1)
local STARTF_USESHOWWINDOW = 0x00000001
local SW_HIDE = 0
local CREATE_NO_WINDOW = 0x08000000
local STILL_ACTIVE = 259

local SHARED_MEMORY_NAME = "LOVE_CAPTURE_SHARED_FRAME"
local MAGIC = 0xC0FFEE01
local CAPTURE_EXE_CANDIDATES = { "build/capture_sender.exe", "capture_sender.exe" }
local CAPTURE_LOG_PATH = "logs/capture.log"

local shared_memory = nil
local shared_data = nil
local proc_handle = nil
local proc_info = nil
local ready = false

local last_frame = 0
local image = nil
local last_w, last_h = 0, 0
local last_image_data = nil

-- forward declaration for process state check used in start()
local is_process_running

-- simple file logger to logs/capture.log (LÖVE save dir or current dir)
local function ensure_logs_dir()
    if love and love.filesystem and love.filesystem.createDirectory then
        love.filesystem.createDirectory("logs")
    else
        local is_windows = package.config and package.config:sub(1,1) == "\\"
        local cmd = is_windows and 'if not exist "logs" mkdir "logs"' or 'mkdir -p "logs"'
        os.execute(cmd)
    end
end

local function append_capture_log(line)
    ensure_logs_dir()
    local prefix
    if love and love.timer then
        prefix = string.format("[%.3f] ", love.timer.getTime())
    else
        prefix = string.format("[%s] ", os.date("%H:%M:%S"))
    end
    local out = prefix .. tostring(line) .. "\n"
    if love and love.filesystem and love.filesystem.append then
        love.filesystem.append(CAPTURE_LOG_PATH, out)
    else
        local f = io.open(CAPTURE_LOG_PATH, "a"); if f then f:write(out); f:close() end
    end
end

local function find_capture_exe()
    for _, p in ipairs(CAPTURE_EXE_CANDIDATES) do
        local f = io.open(p, "rb")
        if f then f:close(); return p end
    end
    return nil
end

local function start_process(window_hint)
    if proc_handle then return true end
    -- Best-effort: kill any stale capture_sender.exe processes before starting
    pcall(function()
        local cmd = 'powershell -Command "Get-Process -Name capture_sender -ErrorAction SilentlyContinue | Stop-Process -Force"'
        local h = io.popen(cmd)
        if h then h:read("*a"); h:close() end
        -- small delay to ensure process exit
        love.timer.sleep(0.1)
    end)
    local exe = find_capture_exe()
    if not exe then
        print("capture: executable not found; place capture_sender.exe in build/")
        return false
    end
    local cmd = exe
    if window_hint and #window_hint > 0 then
        cmd = string.format("%s --title=\"%s\"", exe, window_hint)
    end
    local si = ffi.new("STARTUPINFOA")
    si.cb = ffi.sizeof("STARTUPINFOA")
    si.dwFlags = STARTF_USESHOWWINDOW
    si.wShowWindow = SW_HIDE
    proc_info = ffi.new("PROCESS_INFORMATION")
    local cmd_c = ffi.new("char[?]", #cmd+1, cmd)
    local ok = ffi.C.CreateProcessA(nil, cmd_c, nil, nil, 0, CREATE_NO_WINDOW, nil, nil, si, proc_info)
    if ok == 0 then
        print("capture: failed to start process, error=" .. tostring(ffi.C.GetLastError()))
        proc_info = nil
        return false
    end
    proc_handle = proc_info.hProcess
    return true
end

local function map_shared()
    shared_memory = ffi.C.CreateFileMappingA(INVALID_HANDLE_VALUE, nil, PAGE_READWRITE, 0, 64*1024*1024, SHARED_MEMORY_NAME)
    if shared_memory == nil or shared_memory == ffi.cast("void*", 0) then
        return false
    end
    shared_data = ffi.cast("uint8_t*", ffi.C.MapViewOfFile(shared_memory, FILE_MAP_ALL_ACCESS, 0, 0, 0))
    if shared_data == nil or shared_data == ffi.cast("uint8_t*", 0) then
        ffi.C.CloseHandle(shared_memory)
        shared_memory = nil
        return false
    end
    return true
end

function M.start(window_title)
    if ready then return true end
    -- Start helper
    if not start_process(window_title or "") then
        return false
    end
    -- Wait for shared memory to be ready
    local retries = 0
    while retries < 20 do
        if map_shared() then break end
        love.timer.sleep(0.2)
        retries = retries + 1
    end
    if not shared_data then
        print("capture: failed to map shared memory")
        M.stop()
        return false
    end
    -- Ensure the process is actually running; give it a moment
    local wait_ms = 0
    while wait_ms < 1500 do
        if is_process_running() then break end
        love.timer.sleep(0.05)
        wait_ms = wait_ms + 50
    end
    if not is_process_running() then
        print("capture: helper process not running (likely no matching window); aborting")
        M.stop()
        return false
    end
    -- Wait briefly for the helper to publish a valid header
    local header = ffi.cast("CaptureSharedFrame*", shared_data)
    local waited = 0
    while waited < 2000 do
        if header.magic == MAGIC and header.data_size > 0 then break end
        love.timer.sleep(0.05)
        waited = waited + 50
    end
    ready = true
    -- Log capture status to logs/capture.log (after waiting for first frame if available)
    local status = M.get_status()
    if header.magic ~= MAGIC then
        append_capture_log(string.format("Capture started (title='%s') -> waiting for header...", window_title or ""))
    elseif header.data_size == 0 then
        append_capture_log(string.format("Capture started (title='%s') -> header OK, no frame yet", window_title or ""))
    else
        append_capture_log(string.format("Capture started (title='%s') -> %s", window_title or "", status))
    end
    return true
end

function is_process_running()
    if not proc_handle then return false end
    local exit_code = ffi.new("uint32_t[1]")
    local ok = ffi.C.GetExitCodeProcess(proc_handle, exit_code)
    if ok == 0 then return false end
    return exit_code[0] == STILL_ACTIVE
end

function M.stop()
    if image then image:release(); image = nil end
    if last_image_data then last_image_data:release(); last_image_data = nil end
    last_frame = 0; last_w = 0; last_h = 0
    if shared_data and shared_data ~= ffi.cast("uint8_t*", 0) then
        ffi.C.UnmapViewOfFile(shared_data); shared_data = nil
    end
    if shared_memory and shared_memory ~= ffi.cast("void*", 0) then
        ffi.C.CloseHandle(shared_memory); shared_memory = nil
    end
    if proc_handle then
        ffi.C.TerminateProcess(proc_handle, 0)
        if proc_info and proc_info.hThread and proc_info.hThread ~= ffi.cast("void*", 0) then
            ffi.C.CloseHandle(proc_info.hThread)
        end
        ffi.C.CloseHandle(proc_handle)
        proc_handle = nil; proc_info = nil
    end
    ready = false
end

-- For symmetry with other modules
function M.cleanup()
    M.stop()
end

function M.is_ready()
    return ready and shared_data ~= nil and is_process_running()
end

-- Updates internal texture if a new frame is available
function M.update()
    if not M.is_ready() then return end
    local header = ffi.cast("CaptureSharedFrame*", shared_data)
    if header.magic ~= MAGIC then return end
    if header.frame_number == last_frame or header.data_size == 0 then return end
    local w = tonumber(header.width)
    local h = tonumber(header.height)
    local size = tonumber(header.data_size)
    local fmt = tonumber(header.format) -- 0 RGBA, 1 BGRA
    -- Ensure we have a reusable ImageData backing store of the right size
    if (not last_image_data) or w ~= last_w or h ~= last_h then
        last_image_data = love.image.newImageData(w, h, "rgba8")
        if image then image:release() end
        image = love.graphics.newImage(last_image_data, { mipmaps = false, linear = true })
        last_w, last_h = w, h
    end

    -- Copy pixels directly into the ImageData buffer to avoid per-frame allocations
    local dst = ffi.cast("uint8_t*", last_image_data:getPointer())
    ffi.copy(dst, header.pixel_data, size)
    -- If BGRA, convert to RGBA in-place (simple swizzle)
    if fmt == 1 then
        for i = 0, size-1, 4 do
            local b = dst[i]; local r = dst[i+2]; dst[i] = r; dst[i+2] = b
        end
    end

    image:replacePixels(last_image_data)
    last_frame = header.frame_number
    if last_frame == 1 then
        append_capture_log(string.format("First frame received: %dx%d frame=%d", w, h, last_frame))
    end
end

function M.draw(x, y, w, h)
    if not image then return end
    w = w or image:getWidth(); h = h or image:getHeight()
    love.graphics.setColor(1,1,1,1)
    love.graphics.draw(image, x or 0, y or 0, 0, w / image:getWidth(), h / image:getHeight())
end

function M.get_status()
    if not ready then return "Not started" end
    if not is_process_running() then return "Process not running" end
    local header = ffi.cast("CaptureSharedFrame*", shared_data)
    if header.magic ~= MAGIC then return "No shared frame" end
    return string.format("%dx%d frame=%d bytes=%d", tonumber(header.width), tonumber(header.height), tonumber(header.frame_number), tonumber(header.data_size))
end

-- Dump the latest captured frame to a PNG file in the save directory.
-- If path is nil, saves to screenshots/capture_YYYYmmdd_HHMMSS.png
function M.dump(path)
    if not last_image_data then
        return false, "no frame available"
    end
    local out_path = path
    if not out_path or out_path == "" then
        local ts = os.date("%Y%m%d_%H%M%S")
        out_path = string.format("screenshots/capture_%s.png", ts)
    end
    -- Ensure directory exists
    local dir = out_path:match("^(.*)/")
    if dir and dir ~= "" then
        if love and love.filesystem and love.filesystem.createDirectory then
            love.filesystem.createDirectory(dir)
        else
            local is_windows = package.config and package.config:sub(1,1) == "\\"
            local cmd = is_windows and ('if not exist "'..dir..'" mkdir "'..dir..'"') or ('mkdir -p "'..dir..'"')
            os.execute(cmd)
        end
    end
    local ok, err = pcall(function()
        last_image_data:encode("png", out_path)
    end)
    if not ok then
        return false, tostring(err)
    end
    local full = out_path
    if love and love.filesystem and love.filesystem.getSaveDirectory then
        full = string.format("%s/%s", love.filesystem.getSaveDirectory(), out_path)
    end
    append_capture_log("Saved screenshot to: " .. full)
    return true, full
end

return M
