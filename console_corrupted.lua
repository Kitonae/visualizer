-- console.lua
-- Debug console drawer for the visualizer

local M = {}

-- Store original print function
local original_print = print

-- Console state
local console = {
    visible = false,
    height = 0,
    t        elseif args[1] == "info" then
            local ndi = require("ndi")
            M.log("=== NDI Information ===")
            M.log("Initialized: " .. tostring(ndi.is_initialized()))
            M.log("Streaming: " .. tostring(ndi.is_streaming()))
            M.log("Mode: " .. ndi.get_mode())
            M.log("Source Name: LÖVE Visualizer")
            M.log("Expected Resolution: 800x600")
            M.log("Expected Frame Rate: 60fps")
            M.log("Pixel Format: RGBA")
        elseif args[1] == "stats" then
            local ndi = require("ndi")
            if ndi.is_streaming() then
                local stats = ndi.get_network_stats()
                M.log("=== NDI Network Statistics ===")
                M.log("Frames Sent: " .. stats.frames_sent)
                M.log("Current FPS: " .. stats.current_fps)
                M.log("Receivers Connected: " .. stats.receiver_count)
                M.log("Total Data Sent: " .. ndi.format_bytes(stats.bytes_sent))
                M.log("Current Bandwidth: " .. string.format("%.1f MB/s", stats.bandwidth_mbps))
                M.log("Peak Bandwidth: " .. string.format("%.1f MB/s", stats.max_bandwidth_mbps))
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
            endht = 300,
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
        local message = ""
        for i, arg in ipairs(args) do
            if i > 1 then message = message .. "\t" end
            message = message .. tostring(arg)
        end
        
        -- Add to console with special color for LÖVE output
        M.log_love_output(message)
    end
end

-- Restore original print function
local function restore_print()
    print = original_print
end

-- Initialize console
function M.init()
    console.font = love.graphics.getFont()
    console.line_height = console.font:getHeight() + 2
    
    -- Set up print capture
    setup_print_capture()
    
    -- Add welcome message
    M.log("Console initialized. Type 'help' for commands.")
    M.log("Press ` to toggle console")
end

-- Toggle console visibility
function M.toggle()
    console.visible = not console.visible
    if console.visible then
        console.cursor_blink = 0
        console.cursor_visible = true
    end
end

-- Show console
function M.show()
    console.visible = true
    console.cursor_blink = 0
    console.cursor_visible = true
end

-- Hide console
function M.hide()
    console.visible = false
end

-- Check if console is visible
function M.is_visible()
    return console.visible
end

-- Add a log message to console
function M.log(message, color)
    color = color or console.text_color
    local timestamp = os.date("[%H:%M:%S] ")
    
    table.insert(console.lines, {
        text = timestamp .. tostring(message),
        color = color,
        timestamp = love.timer.getTime()
    })
    
    -- Keep only max_lines
    if #console.lines > console.max_lines then
        table.remove(console.lines, 1)
    end
end

-- Log error message
function M.error(message)
    M.log("ERROR: " .. tostring(message), {1, 0.3, 0.3, 1})
end

-- Log warning message
function M.warn(message)
    M.log("WARN: " .. tostring(message), {1, 1, 0.3, 1})
end

-- Log info message
function M.info(message)
    M.log("INFO: " .. tostring(message), {0.3, 0.8, 1, 1})
end

-- Log success message
function M.success(message)
    M.log("SUCCESS: " .. tostring(message), {0.3, 1, 0.3, 1})
end

-- Log LÖVE output (from captured print statements)
function M.log_love_output(message)
    local timestamp = os.date("[%H:%M:%S] ")
    
    table.insert(console.lines, {
        text = timestamp .. "LÖVE: " .. tostring(message),
        color = console.love_output_color,
        timestamp = love.timer.getTime()
    })
    
    -- Keep only max_lines
    if #console.lines > console.max_lines then
        table.remove(console.lines, 1)
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
        M.log("  ndi - NDI commands (status, start, stop, info, stats, debug, send)")
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
            M.log("Expected Resolution: 800x600")
            M.log("Expected Frame Rate: 60fps")
            M.log("Pixel Format: RGBA")
        elseif args[1] == "dump" then
            -- Support simplified: ndi dump <n> <dir>
            local n = tonumber(args[2]) or 0
            local dir = args[3] or ""
            local ndi = require("ndi")
            if ndi and ndi.dump_frames_request then
                ndi.dump_frames_request(n, dir)
                M.success(string.format("NDI: dumping %d frames to %s", n, dir ~= "" and dir or "."))
            else
                M.error("NDI dump not available")
            end
        elseif args[1] == "test" then
            -- Run SDK-style test implementation
            local ndi_test = require("ndi_test")
            M.log("Running NDI SDK test implementation...")
            local success = ndi_test.run_test()
            if success then
                M.success("NDI SDK test completed")
            else
                M.error("NDI SDK test failed")
            end
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
                        
                        -- Update shader resolution uniform if shader exists
                        if _G.shader and _G.shader.hasUniform and _G.shader:hasUniform("resolution") then
                            _G.shader:send("resolution", {width, height})
                        end
                        
                        -- NDI canvas will automatically adjust to new resolution on next frame
                        M.log("NDI canvas will adjust to new resolution automatically")
                    else
                        M.error("Failed to set resolution to " .. width .. "x" .. height)
                    end
                end
            else
                M.error("Invalid resolution values. Use: resolution set <width> <height>")
            end
        else
            M.log("Usage: resolution [get] or resolution set <width> <height>")
            M.log("Examples:")
            M.log("  resolution - Show current resolution")
            M.log("  resolution get - Show current resolution")
            M.log("  resolution set 1920 1080 - Set to 1920x1080")
            M.log("  resolution set 800 600 - Set to 800x600")
        end
        
    elseif command == "quit" or command == "exit" then
        M.log("Quitting application...")
        love.event.quit()
        
    elseif command == "print" then
        local message = table.concat(args, " ")
        if message == "" then
            message = "Test print output"
        end
        -- This will be captured by our print override
        original_print(message)
        
    elseif command == "debug" then
        M.log("=== Debug Information ===")
        M.log("Console visible: " .. tostring(console.visible))
        M.log("Console lines: " .. #console.lines)
        M.log("History entries: " .. #console.history)
        M.log("Screen size: " .. love.graphics.getWidth() .. "x" .. love.graphics.getHeight())
        M.log("LÖVE version: " .. love.getVersion())
        original_print("Debug info displayed in console")
        
    elseif command == "test" then
        M.log("Running test sequence...")
        original_print("This is a test print statement")
        M.info("This is an info message")
        M.warn("This is a warning message")
        M.error("This is an error message (not a real error)")
        M.success("This is a success message")
        original_print("Test sequence completed")
        
    else
        M.error("Unknown command: " .. command .. ". Type 'help' for available commands.")
    end
end

-- Handle text input
function M.textinput(text)
    if not console.visible then return end
    
    -- Ignore backtick and tilde when console is open (they're handled in keypressed)
    if text == "`" or text == "~" then
        return
    end
    
    -- Insert text at cursor position
    local before = console.input_text:sub(1, console.cursor_pos)
    local after = console.input_text:sub(console.cursor_pos + 1)
    console.input_text = before .. text .. after
    console.cursor_pos = console.cursor_pos + #text
    
    -- Reset cursor blink
    console.cursor_blink = 0
    console.cursor_visible = true
end

-- Handle key presses
function M.keypressed(key)
    -- Debug: log key presses to help diagnose the issue
    if key == "`" or key == "~" or key == "grave" then
        M.toggle()
        return true -- Consume the key event
    end
    
    if not console.visible then return false end
    
    if key == "return" or key == "kpenter" then
        execute_command(console.input_text)
        console.input_text = ""
        console.cursor_pos = 0
        
    elseif key == "backspace" then
        if console.cursor_pos > 0 then
            local before = console.input_text:sub(1, console.cursor_pos - 1)
            local after = console.input_text:sub(console.cursor_pos + 1)
            console.input_text = before .. after
            console.cursor_pos = console.cursor_pos - 1
        end
        
    elseif key == "delete" then
        if console.cursor_pos < #console.input_text then
            local before = console.input_text:sub(1, console.cursor_pos)
            local after = console.input_text:sub(console.cursor_pos + 2)
            console.input_text = before .. after
        end
        
    elseif key == "left" then
        if console.cursor_pos > 0 then
            console.cursor_pos = console.cursor_pos - 1
        end
        
    elseif key == "right" then
        if console.cursor_pos < #console.input_text then
            console.cursor_pos = console.cursor_pos + 1
        end
        
    elseif key == "home" then
        console.cursor_pos = 0
        
    elseif key == "end" then
        console.cursor_pos = #console.input_text
        
    elseif key == "up" then
        if console.history_index > 1 then
            console.history_index = console.history_index - 1
            console.input_text = console.history[console.history_index] or ""
            console.cursor_pos = #console.input_text
        end
        
    elseif key == "down" then
        if console.history_index <= #console.history then
            console.history_index = console.history_index + 1
            console.input_text = console.history[console.history_index] or ""
            console.cursor_pos = #console.input_text
        end
        
    elseif key == "escape" then
        M.hide()
    end
    
    -- Reset cursor blink on any key
    console.cursor_blink = 0
    console.cursor_visible = true
    
    return true -- Consume all key events when console is visible
end

-- Update console animation and cursor
function M.update(dt)
    -- Animate console height
    if console.visible then
        if console.height < console.target_height then
            console.height = math.min(console.target_height, 
                                     console.height + console.animation_speed * dt)
        end
        if console.alpha < 1 then
            console.alpha = math.min(1, console.alpha + 4 * dt)
        end
    else
        if console.height > 0 then
            console.height = math.max(0, console.height - console.animation_speed * dt)
        end
        if console.alpha > 0 then
            console.alpha = math.max(0, console.alpha - 4 * dt)
        end
    end
    
    -- Update cursor blink
    console.cursor_blink = console.cursor_blink + dt
    if console.cursor_blink >= 0.5 then
        console.cursor_blink = 0
        console.cursor_visible = not console.cursor_visible
    end
end

-- Draw console
function M.draw()
    if console.height <= 0 then return end
    
    local width = love.graphics.getWidth()
    local height = console.height
    
    -- Draw background
    love.graphics.setColor(console.bg_color[1], console.bg_color[2], 
                          console.bg_color[3], console.bg_color[4] * console.alpha)
    love.graphics.rectangle("fill", 0, 0, width, height)
    
    -- Draw border
    love.graphics.setColor(0.3, 0.3, 0.3, console.alpha)
    love.graphics.setLineWidth(1)
    love.graphics.line(0, height, width, height)
    
    local y = console.padding
    local font = console.font
    
    -- Draw console lines
    local visible_lines = math.floor((height - console.padding * 2 - console.line_height) / console.line_height)
    local start_line = math.max(1, #console.lines - visible_lines + 1)
    
    for i = start_line, #console.lines do
        local line = console.lines[i]
        if y + console.line_height > height - console.line_height - console.padding then
            break
        end
        
        love.graphics.setColor(line.color[1], line.color[2], line.color[3], 
                              line.color[4] * console.alpha)
        love.graphics.print(line.text, console.padding, y)
        y = y + console.line_height
    end
    
    -- Draw input line
    local input_y = height - console.line_height - console.padding
    love.graphics.setColor(console.prompt_color[1], console.prompt_color[2], 
                          console.prompt_color[3], console.prompt_color[4] * console.alpha)
    love.graphics.print("> ", console.padding, input_y)
    
    local prompt_width = font:getWidth("> ")
    love.graphics.setColor(console.input_color[1], console.input_color[2], 
                          console.input_color[3], console.input_color[4] * console.alpha)
    love.graphics.print(console.input_text, console.padding + prompt_width, input_y)
    
    -- Draw cursor
    if console.cursor_visible and console.visible then
        local cursor_text = console.input_text:sub(1, console.cursor_pos)
        local cursor_x = console.padding + prompt_width + font:getWidth(cursor_text)
        love.graphics.setColor(console.cursor_color[1], console.cursor_color[2], 
                              console.cursor_color[3], console.cursor_color[4] * console.alpha)
        love.graphics.rectangle("fill", cursor_x, input_y, 1, console.line_height)
    end
end

-- Utility function for string trimming
string.trim = string.trim or function(s)
    return s:match("^%s*(.-)%s*$")
end

-- Cleanup function
function M.cleanup()
    restore_print()
end

-- Get original print function (for external use)
function M.get_original_print()
    return original_print
end

return M
