local logger = {}

local LEVELS = { error = 1, warn = 2, info = 3, debug = 4 }
local current_level = LEVELS.info
local log_file = "logs/ndi.log"
local console_echo = false

local function now_ts()
    if love and love.timer then
        return string.format("%.3f", love.timer.getTime())
    else
        return os.date("%H:%M:%S")
    end
end

local function ensure_dir()
    -- Ensure the "logs" directory exists in both LÖVE and plain Lua contexts.
    if love and love.filesystem and love.filesystem.createDirectory then
        -- In LÖVE: create within the save directory
        love.filesystem.createDirectory("logs")
        return
    end

    -- Plain Lua fallback: create an OS directory named "logs" next to the script
    local is_windows = package.config and package.config:sub(1,1) == "\\"
    local cmd
    if is_windows then
        -- Windows `mkdir` creates intermediate dirs if needed; avoid POSIX flags
        cmd = 'if not exist "logs" mkdir "logs"'
    else
        -- POSIX systems
        cmd = 'mkdir -p "logs"'
    end
    -- Best-effort; ignore exit code
    os.execute(cmd)
end

local function rotate_if_needed()
    local max_bytes = 1024 * 1024 -- 1 MB
    if love and love.filesystem and love.filesystem.getInfo then
        local info = love.filesystem.getInfo(log_file)
        if info and info.size and info.size > max_bytes then
            local ok, data = pcall(love.filesystem.read, log_file)
            if ok and data then
                love.filesystem.write(log_file .. ".1", data)
            end
            love.filesystem.write(log_file, "")
        end
    else
        -- io fallback rotation is omitted for simplicity
    end
end

local function write_line(line)
    ensure_dir()
    rotate_if_needed()
    local out = string.format("[%s] %s\n", now_ts(), line)
    if love and love.filesystem and love.filesystem.append then
        love.filesystem.append(log_file, out)
    else
        local f = io.open(log_file, "a")
        if f then f:write(out); f:close() end
    end
    if console_echo then
        print(line)
    end
end

function logger.init(path)
    if path and type(path) == "string" then
        log_file = path
    end
    ensure_dir()
    -- start fresh session marker
    write_line("=== Logger initialized ===")
end

function logger.set_level(level)
    current_level = LEVELS[level] or current_level
end

function logger.get_level()
    for k, v in pairs(LEVELS) do if v == current_level then return k end end
    return "info"
end

function logger.enable_console(enable)
    console_echo = not not enable
end

function logger.get_log_path()
    return log_file
end

local function log_at(level, prefix, msg)
    if LEVELS[level] <= current_level then
        write_line(prefix .. ": " .. tostring(msg))
    end
end

function logger.error(msg) log_at("error", "ERROR", msg) end
function logger.warn(msg)  log_at("warn",  "WARN",  msg) end
function logger.info(msg)  log_at("info",  "INFO",  msg) end
function logger.debug(msg) log_at("debug", "DEBUG", msg) end

return logger

