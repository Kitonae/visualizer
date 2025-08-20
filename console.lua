-- console.lua
-- Debug console drawer for the visualizer

local M = {}

-- Store original print function
local original_print = print

-- Console state
local console = {
    visible = false,
    height = 0,
    target_height = 300,
    animation_speed = 1000, -- pixels per second
    alpha = 0,
    
    -- Console content
    lines = {},
    max_lines = 50,
    input_text = "",
    cursor_pos = 0,
    cursor_blink = 0,
    cursor_visible = true,
    
    -- History
    history = {},
    history_index = 0,
    max_history = 100,
    
    -- Fonts and styling
    font = nil,
    line_height = 16,
    padding = 10,
    
    -- Colors
    bg_color = {0, 0, 0, 0.9},
    text_color = {0.9, 0.9, 0.9, 1},
    input_color = {1, 1, 1, 1},
    cursor_color = {1, 1, 1, 1},
    prompt_color = {0.5, 1, 0.5, 1},
    love_output_color = {0.7, 0.7, 1, 1}
}

-- Override global print to capture LÖVE output
local function setup_print_capture()
    print = function(...)
        -- Call original print
        original_print(...)
        
        -- Also log to our console
        local args = {...}
        local str = ""
        for i, v in ipairs(args) do
            if i > 1 then str = str .. "\t" end
            str = str .. tostring(v)
        end
        M.log(str, console.love_output_color)
    end
end

-- String trim function
function string:trim()
    return self:match("^%s*(.-)%s*$")
end

-- Key repeat handling
local key_repeat = {
    key = nil,
    initial_delay = 0.5,
    repeat_delay = 0.03,
    time_held = 0,
    repeating = false
}

function M.init()
    -- Setup print capture
    setup_print_capture()
    
    -- Load font
    console.font = love.graphics.getFont() -- Use default font
    console.line_height = console.font:getHeight() + 2
    
    M.log("Console initialized. Type 'help' for commands.")
end

function M.cleanup()
    -- Restore original print
    print = original_print
end

-- Logging functions
function M.log(message, color)
    color = color or console.text_color
    table.insert(console.lines, {
        text = tostring(message),
        color = color,
        timestamp = love.timer.getTime()
    })
    
    -- Limit lines
    if #console.lines > console.max_lines then
        table.remove(console.lines, 1)
    end
end

function M.info(message)
    M.log("INFO: " .. tostring(message), {0.5, 0.7, 1, 1})
end

function M.warn(message)
    M.log("WARN: " .. tostring(message), {1, 0.8, 0, 1})
end

function M.error(message)
    M.log("ERROR: " .. tostring(message), {1, 0.3, 0.3, 1})
end

function M.success(message)
    M.log("SUCCESS: " .. tostring(message), {0.3, 1, 0.3, 1})
end

-- Key repeat update
local function update_key_repeat(dt)
    if key_repeat.key then
        key_repeat.time_held = key_repeat.time_held + dt
        
        local delay = key_repeat.repeating and key_repeat.repeat_delay or key_repeat.initial_delay
        
        if key_repeat.time_held >= delay then
            key_repeat.time_held = 0
            key_repeat.repeating = true
            
            -- Trigger the key action
            if key_repeat.key == "backspace" then
                handle_backspace()
            elseif key_repeat.key == "delete" then
                handle_delete()
            end
        end
    end
end

local function start_key_repeat(key)
    key_repeat.key = key
    key_repeat.time_held = 0
    key_repeat.repeating = false
end

local function stop_key_repeat()
    key_repeat.key = nil
    key_repeat.time_held = 0
    key_repeat.repeating = false
end

-- Backspace handling
function handle_backspace()
    if console.cursor_pos > 0 then
        console.input_text = console.input_text:sub(1, console.cursor_pos - 1) .. 
                            console.input_text:sub(console.cursor_pos + 1)
        console.cursor_pos = console.cursor_pos - 1
    end
end

-- Delete handling  
function handle_delete()
    if console.cursor_pos < #console.input_text then
        console.input_text = console.input_text:sub(1, console.cursor_pos) .. 
                            console.input_text:sub(console.cursor_pos + 2)
    end
end

-- Execute console command
local function execute_command(cmd)
    cmd = cmd:trim()
    if cmd == "" then return end
    
    -- Add to history
    table.insert(console.history, cmd)
    if #console.history > console.max_history then
        table.remove(console.history, 1)
    end
    console.history_index = #console.history + 1
    
    -- Log the command
    M.log("> " .. cmd, console.prompt_color)
    
    -- Parse command
    local parts = {}
    for part in cmd:gmatch("%S+") do
        table.insert(parts, part)
    end
    
    if #parts == 0 then return end
    
    local command = parts[1]:lower()
    local args = {}
    for i = 2, #parts do
        table.insert(args, parts[i])
    end
    
    -- Execute commands
    if command == "help" then
        M.log("Available commands:")
        M.log("  help - Show this help")
        M.log("  clear - Clear console")
        M.log("  ndi - NDI commands (status, start, stop, info, stats, debug)")
        M.log("  shader - Shader commands (list, switch <num>)")
        M.log("  fps - Show current FPS")
        M.log("  version - Show version info")
        M.log("  resolution - Resolution commands (get, set <width> <height>)")
        M.log("  quit - Quit application")
        
    elseif command == "clear" then
        console.lines = {}
        M.log("Console cleared")
        
    elseif command == "ndi" then
        if #args == 0 then
            local ndi = require("ndi")
            M.log("NDI Status: " .. (ndi.is_streaming() and "STREAMING" or "STOPPED"))
            M.log("NDI Mode: " .. ndi.get_mode())
        elseif args[1] == "start" then
            local ndi = require("ndi")
            if ndi.start_streaming() then
                M.success("NDI streaming started")
            else
                M.error("Failed to start NDI streaming")
            end
        elseif args[1] == "stop" then
            local ndi = require("ndi")
            ndi.stop_streaming()
            M.success("NDI streaming stopped")
        elseif args[1] == "status" then
            local ndi = require("ndi")
            M.log("NDI Initialized: " .. tostring(ndi.is_initialized()))
            M.log("NDI Streaming: " .. tostring(ndi.is_streaming()))
            M.log("NDI Mode: " .. ndi.get_mode())
        elseif args[1] == "info" then
            local ndi = require("ndi")
            M.log("=== NDI Information ===")
            M.log("Initialized: " .. tostring(ndi.is_initialized()))
            M.log("Streaming: " .. tostring(ndi.is_streaming()))
            M.log("Mode: " .. ndi.get_mode())
            M.log("Source Name: LÖVE Visualizer")
        elseif args[1] == "stats" then
            local ndi = require("ndi")
            if ndi.is_streaming() then
                local stats = ndi.get_network_stats()
                M.log("=== NDI Network Statistics ===")
                M.log("Frames Sent: " .. stats.frames_sent)
                M.log("Current FPS: " .. stats.current_fps)
                M.log("Receivers Connected: " .. stats.receiver_count)
                M.log("Total Data Sent: " .. ndi.format_bytes(stats.bytes_sent))
                M.log("Current Bandwidth: " .. string.format("%.1f Mbps", stats.bandwidth_mbps))
                M.log("Peak Bandwidth: " .. string.format("%.1f Mbps", stats.max_bandwidth_mbps))
                M.log("Uptime: " .. string.format("%.1f seconds", stats.uptime))
                M.log("Bandwidth History: " .. #stats.bandwidth_history .. " samples")
                if #stats.bandwidth_history > 0 then
                    local recent = stats.bandwidth_history[#stats.bandwidth_history]
                    M.log("Most Recent: " .. ndi.format_bytes(recent) .. "/s")
                end
            else
                M.warn("NDI is not currently streaming")
            end
        elseif args[1] == "debug" then
            local ndi = require("ndi")
            if #args == 1 then
                -- Show current debug state
                M.log("NDI Debug Output: " .. (ndi.get_debug_output() and "ENABLED" or "DISABLED"))
            elseif args[2] == "on" or args[2] == "true" or args[2] == "1" then
                ndi.set_debug_output(true)
                M.success("NDI debug output enabled")
            elseif args[2] == "off" or args[2] == "false" or args[2] == "0" then
                ndi.set_debug_output(false)
                M.success("NDI debug output disabled")
            else
                M.error("Usage: ndi debug [on|off]")
            end
        end
    elseif command == "capture" then
        if #args == 0 or args[1] == "status" then
            local cap = require("capture")
            M.log("Capture: " .. cap.get_status())
        elseif args[1] == "start" then
            local cap = require("capture")
            local title = table.concat(args, " ", 2)
            -- Default to PowerPoint Slide Show when no title provided
            if title == "" then title = "PowerPoint Slide Show" end
            if cap.start(title) then
                M.success("Capture started for title contains: '" .. title .. "'")
            else
                M.error("Failed to start capture")
            end
        elseif args[1] == "stop" then
            local cap = require("capture")
            cap.stop()
            M.success("Capture stopped")
        elseif args[1] == "dump" or args[1] == "screenshot" or args[1] == "shot" then
            local cap = require("capture")
            local filename = args[2] or ""
            local ok, out = cap.dump(filename)
            if ok then
                M.success("Saved capture screenshot: " .. out)
            else
                M.error("Failed to save screenshot: " .. tostring(out))
            end
        else
            M.error("Usage: capture [status|start [title...]|stop|dump [filename]]")
        end
    elseif command == "shader" then
        if #args == 0 or args[1] == "list" then
            M.log("Available shaders:")
            for i, shader in ipairs(shaders) do
                local marker = (i == currentShaderIndex) and " [CURRENT]" or ""
                M.log("  " .. i .. ". " .. shader.name .. marker)
            end
        elseif args[1] == "switch" and args[2] then
            local num = tonumber(args[2])
            if num and num >= 1 and num <= #shaders then
                currentShaderIndex = num
                loadCurrentShader()
                M.success("Switched to shader: " .. shaders[num].name)
            else
                M.error("Invalid shader number. Use 1-" .. #shaders)
            end
        end
        
    elseif command == "fps" then
        M.log("Current FPS: " .. string.format("%.1f", love.timer.getFPS()))
        
    elseif command == "version" then
        local major, minor, revision, codename = love.getVersion()
        M.log("LÖVE Version: " .. major .. "." .. minor .. "." .. revision .. " (" .. codename .. ")")
        
    elseif command == "resolution" then
        if #args == 0 or args[1] == "get" then
            local width = love.graphics.getWidth()
            local height = love.graphics.getHeight()
            M.log("Current resolution: " .. width .. "x" .. height)
        elseif args[1] == "set" and args[2] and args[3] then
            local width = tonumber(args[2])
            local height = tonumber(args[3])
            
            if width and height and width > 0 and height > 0 then
                -- Validate reasonable resolution limits
                if width < 100 or height < 100 then
                    M.error("Resolution too small. Minimum: 100x100")
                elseif width > 7680 or height > 4320 then
                    M.error("Resolution too large. Maximum: 7680x4320")
                else
                    -- Set window size
                    local success = pcall(function()
                        love.window.setMode(width, height)
                    end)
                    
                    if success then
                        M.success("Resolution changed to " .. width .. "x" .. height)
                        -- Update shader resolution if it has the uniform
                        if shader and shader:hasUniform("resolution") then
                            shader:send("resolution", {width, height})
                        end
                    else
                        M.error("Failed to change resolution")
                    end
                end
            else
                M.error("Invalid resolution values")
            end
        else
            M.error("Usage: resolution [get] or resolution set <width> <height>")
        end
        
    elseif command == "quit" then
        M.log("Goodbye!")
        -- Give a moment for the message to appear
        love.timer.sleep(0.1)
        love.event.quit()
        
    else
        M.error("Unknown command: " .. command .. ". Type 'help' for available commands.")
    end
end

-- Clipboard functions
local function get_clipboard_text()
    local success, result = pcall(function()
        return love.system.getClipboardText()
    end)
    return success and result or ""
end

local function set_clipboard_text(text)
    local success = pcall(function()
        love.system.setClipboardText(text)
    end)
    return success
end

function M.update(dt)
    -- Update cursor blink
    console.cursor_blink = console.cursor_blink + dt
    if console.cursor_blink >= 1.0 then
        console.cursor_blink = 0
        console.cursor_visible = not console.cursor_visible
    end
    
    -- Update key repeat
    update_key_repeat(dt)
    
    -- Update console animation
    if console.visible then
        if console.height < console.target_height then
            console.height = math.min(console.target_height, 
                                    console.height + console.animation_speed * dt)
        end
        console.alpha = math.min(1, console.alpha + 4 * dt)
    else
        if console.height > 0 then
            console.height = math.max(0, console.height - console.animation_speed * dt)
        end
        console.alpha = math.max(0, console.alpha - 4 * dt)
    end
end

function M.draw()
    if console.alpha <= 0 then return end
    
    -- Save current graphics state
    local current_font = love.graphics.getFont()
    local r, g, b, a = love.graphics.getColor()
    
    -- Set console font
    love.graphics.setFont(console.font)
    
    -- Draw background
    love.graphics.setColor(console.bg_color[1], console.bg_color[2], 
                          console.bg_color[3], console.bg_color[4] * console.alpha)
    love.graphics.rectangle("fill", 0, 0, love.graphics.getWidth(), console.height)
    
    -- Calculate visible area
    local start_y = console.padding
    local end_y = console.height - console.line_height - console.padding
    
    -- Draw console lines
    local y = end_y - console.line_height
    for i = #console.lines, 1, -1 do
        if y < start_y then break end
        
        local line = console.lines[i]
        love.graphics.setColor(line.color[1], line.color[2], line.color[3], 
                              line.color[4] * console.alpha)
        love.graphics.print(line.text, console.padding, y)
        y = y - console.line_height
    end
    
    -- Draw input line
    local input_y = console.height - console.line_height - console.padding / 2
    love.graphics.setColor(console.prompt_color[1], console.prompt_color[2], 
                          console.prompt_color[3], console.prompt_color[4] * console.alpha)
    love.graphics.print("> ", console.padding, input_y)
    
    -- Draw input text
    love.graphics.setColor(console.input_color[1], console.input_color[2], 
                          console.input_color[3], console.input_color[4] * console.alpha)
    local prompt_width = console.font:getWidth("> ")
    love.graphics.print(console.input_text, console.padding + prompt_width, input_y)
    
    -- Draw cursor
    if console.cursor_visible then
        love.graphics.setColor(console.cursor_color[1], console.cursor_color[2], 
                              console.cursor_color[3], console.cursor_color[4] * console.alpha)
        local text_before_cursor = console.input_text:sub(1, console.cursor_pos)
        local cursor_x = console.padding + prompt_width + console.font:getWidth(text_before_cursor)
        love.graphics.rectangle("fill", cursor_x, input_y, 2, console.line_height)
    end
    
    -- Restore graphics state
    love.graphics.setFont(current_font)
    love.graphics.setColor(r, g, b, a)
end

function M.keypressed(key)
    if key == "`" or key == "grave" then
        console.visible = not console.visible
        console.cursor_blink = 0
        console.cursor_visible = true
        return true
    end
    
    if not console.visible then
        return false
    end
    
    if key == "escape" then
        console.visible = false
        return true
    elseif key == "return" or key == "kpenter" then
        execute_command(console.input_text)
        console.input_text = ""
        console.cursor_pos = 0
        console.history_index = #console.history + 1
        return true
    elseif key == "backspace" then
        handle_backspace()
        start_key_repeat("backspace")
        return true
    elseif key == "delete" then
        handle_delete()
        start_key_repeat("delete")
        return true
    elseif key == "left" then
        console.cursor_pos = math.max(0, console.cursor_pos - 1)
        return true
    elseif key == "right" then
        console.cursor_pos = math.min(#console.input_text, console.cursor_pos + 1)
        return true
    elseif key == "home" then
        console.cursor_pos = 0
        return true
    elseif key == "end" then
        console.cursor_pos = #console.input_text
        return true
    elseif key == "up" then
        if console.history_index > 1 then
            console.history_index = console.history_index - 1
            console.input_text = console.history[console.history_index] or ""
            console.cursor_pos = #console.input_text
        end
        return true
    elseif key == "down" then
        if console.history_index <= #console.history then
            console.history_index = console.history_index + 1
            console.input_text = console.history[console.history_index] or ""
            console.cursor_pos = #console.input_text
        end
        return true
    elseif love.keyboard.isDown("lctrl") or love.keyboard.isDown("rctrl") then
        if key == "v" then
            -- Paste
            local clipboard_text = get_clipboard_text()
            if clipboard_text then
                local before = console.input_text:sub(1, console.cursor_pos)
                local after = console.input_text:sub(console.cursor_pos + 1)
                console.input_text = before .. clipboard_text .. after
                console.cursor_pos = console.cursor_pos + #clipboard_text
            end
            return true
        elseif key == "c" then
            -- Copy
            if #console.input_text > 0 then
                set_clipboard_text(console.input_text)
            end
            return true
        elseif key == "a" then
            -- Select all (move cursor to end)
            console.cursor_pos = #console.input_text
            return true
        end
    end
    
    return true -- Console consumes all keys when visible
end

function M.keyreleased(key)
    if key == "backspace" or key == "delete" then
        stop_key_repeat()
    end
end

function M.textinput(text)
    if not console.visible then
        return
    end
    
    -- Ignore backtick character (used for console toggle)
    if text == "`" then
        return
    end
    
    -- Insert text at cursor position
    local before = console.input_text:sub(1, console.cursor_pos)
    local after = console.input_text:sub(console.cursor_pos + 1)
    console.input_text = before .. text .. after
    console.cursor_pos = console.cursor_pos + #text
end

return M
