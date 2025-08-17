-- main.lua
-- Love2D app to render shaders with Tab switching and NDI streaming

-- Safely load NDI module
local ndi = nil
local ndi_load_success, ndi_load_error = pcall(function()
    ndi = require("ndi")
end)

-- Load console module
local console_load_success, console_load_error = pcall(function()
    return require("console")
end)

local console
if console_load_success then
    console = console_load_error  -- pcall returns the result in the error parameter when successful
else
    print("Failed to load console module: " .. tostring(console_load_error))
    -- Create dummy console module
    console = {
        init = function() end,
        update = function() end,
        draw = function() end,
        keypressed = function() return false end,
        textinput = function() end,
        log = function() end,
        info = function() end,
        warn = function() end,
        error = function() end,
        success = function() end
    }
end

if not ndi_load_success then
    print("Failed to load NDI module: " .. tostring(ndi_load_error))
    -- Create dummy NDI module
    ndi = {
        initialize = function() return false end,
        is_streaming = function() return false end,
        is_initialized = function() return false end,
        get_mode = function() return "disabled" end,
        setup_realtime_capture = function() return false end,
        begin_capture = function() end,
        end_capture_and_send = function() end,
        start_streaming = function() return false end,
        stop_streaming = function() end,
        destroy = function() end
    }
end

function love.load()
    print("Starting LÖVE application...")
    
    -- List of available shaders
    shaders = {
        {name = "Kaleidoscope", file = "shaders/kaleidoscope.frag", hasBackground = false},
        {name = "Water Waves", file = "shaders/waves.frag", hasBackground = false},
        {name = "Animated Lines", file = "shaders/lines.frag", hasBackground = false},
        {name = "Mono Lines", file = "shaders/lines_mono.frag", hasBackground = true},
        {name = "Tunnel", file = "shaders/tunnel.frag", hasBackground = false},
        {name = "Nebula", file = "shaders/nebula.frag", hasBackground = false},
        {name = "Tunnel Purple", file = "shaders/tunnel_purple.frag", hasBackground = false},
        {name = "Falling Stars", file = "shaders/falling_stars.frag", hasBackground = false}
    }
    
    currentShaderIndex = 4 -- Start with mono lines (update to 4 or 5 if you want to start with new shaders)
    
    -- Initialize console first so we can log errors
    local console_success, console_error = pcall(function()
        console.init()
    end)
    
    if not console_success then
        print("Console initialization failed: " .. tostring(console_error))
    else
        print("Console initialized successfully")
    end
    
    -- Load forest background image
    local bg_success, bg_error = pcall(function()
        backgroundImage = love.graphics.newImage("forest.png")
    end)
    
    if not bg_success then
        print("Failed to load background image: " .. tostring(bg_error))
        console.error("Failed to load background image: " .. tostring(bg_error))
    else
        print("Background image loaded successfully")
    end
    
    -- NDI initialization
    ndi_enabled = false
    ndi_source_name = "LÖVE Visualizer"
    ndi_groups = nil
    
    -- Try to initialize NDI
    local ndi_success, ndi_error = pcall(function()
        return ndi.initialize()
    end)
    
    if ndi_success and ndi_error then -- ndi_error is actually the return value when pcall succeeds
        print("NDI initialized successfully")
        console.success("NDI initialized successfully")
        ndi_enabled = true
    else
        local error_msg = ndi_success and "NDI initialization returned false" or tostring(ndi_error)
        print("NDI initialization failed - streaming will be disabled: " .. error_msg)
        console.warn("NDI initialization failed - streaming will be disabled: " .. error_msg)
    end
    
    -- Load shader
    local shader_success, shader_error = pcall(loadCurrentShader)
    if not shader_success then
        print("Failed to load shader: " .. tostring(shader_error))
        console.error("Failed to load shader: " .. tostring(shader_error))
    else
        print("Shader loaded successfully")
    end
    
    print("LÖVE application startup complete")
end

function loadCurrentShader()
    local shaderInfo = shaders[currentShaderIndex]
    shader = love.graphics.newShader(shaderInfo.file)
    
    -- Set initial resolution
    if shader:hasUniform("resolution") then
        shader:send("resolution", {love.graphics.getWidth(), love.graphics.getHeight()})
    end
    
    -- Initialize mouse position for shaders that need it
    if shader:hasUniform("mouse") then
        local mx, my = love.graphics.getWidth()/2, love.graphics.getHeight()/2
        shader:send("mouse", {mx, my})
    end
    
    -- Initialize palette colors for kaleidoscope shader
    if shaderInfo.name == "Kaleidoscope" then
        palette = {
            a = {0.5, 0.5, 0.5},
            b = {0.5, 0.5, 0.5},
            c = {1.0, 1.0, 1.0},
            d = {0.263, 0.416, 0.557}
        }
        animate_palette = false  -- Disable animation
        sendPalette()
    end
end

function sendPalette()
    if palette then
        for k, v in pairs(palette) do
            if shader:hasUniform("palette_"..k) then
                shader:send("palette_"..k, v)
            end
        end
    end
end
    



function love.update(dt)
    -- Pass time to the shader for animation
    local t = love.timer.getTime()
    if shader:hasUniform("time") then
        shader:send("time", t)
    end
    
    -- Update resolution in case window is resized
    if shader:hasUniform("resolution") then
        shader:send("resolution", {love.graphics.getWidth(), love.graphics.getHeight()})
    end
    
    -- Update console
    console.update(dt)
end


function love.draw()
    local shaderInfo = shaders[currentShaderIndex]
    
    -- Function to render the main content
    local function renderContent()
        -- Draw forest background if shader supports transparency
        if shaderInfo.hasBackground then
            love.graphics.setColor(1, 1, 1, 1)
            love.graphics.draw(backgroundImage, 0, 0, 0, 
                              love.graphics.getWidth() / backgroundImage:getWidth(), 
                              love.graphics.getHeight() / backgroundImage:getHeight())
        end
        
        -- Draw shader
        love.graphics.setShader(shader)
        love.graphics.rectangle("fill", 0, 0, love.graphics.getWidth(), love.graphics.getHeight())
        love.graphics.setShader()
    end
    
    -- Render to screen
    renderContent()
    
    -- Send frame via NDI if streaming
    if ndi_enabled and ndi.is_streaming() then
        local w, h = love.graphics.getWidth(), love.graphics.getHeight()
        
        -- Create or recreate NDI canvas if size changed
        if not _G.ndi_capture_canvas or 
           _G.ndi_capture_canvas:getWidth() ~= w or 
           _G.ndi_capture_canvas:getHeight() ~= h then
            
            -- Release old canvas if it exists
            if _G.ndi_capture_canvas then
                _G.ndi_capture_canvas:release()
            end
            
            -- Create new canvas with current window size
            _G.ndi_capture_canvas = love.graphics.newCanvas(w, h)
            print("NDI canvas recreated for resolution: " .. w .. "x" .. h)
        end
        
        -- Render to NDI canvas
        love.graphics.setCanvas(_G.ndi_capture_canvas)
        love.graphics.clear()
        renderContent()
        love.graphics.setCanvas()
        
        -- Send frame via shared memory to C++ NDI sender
        ndi.send_frame(_G.ndi_capture_canvas)
    end

    -- Draw UI (only on screen, not in NDI stream)
    love.graphics.setColor(0.5, 1, 0.8, 0.8)  -- Mint green color
    love.graphics.print("Current: " .. shaderInfo.name, 10, 10)
    love.graphics.setColor(1, 1, 1, 0.8)  -- Reset to white for other text
    love.graphics.print("Press [Tab] to switch shaders, [Q] to quit, [`] for console", 10, 30)
    
    -- NDI status (basic info on left)
    if ndi_enabled then
        local ndi_status = ndi.is_streaming() and "STREAMING" or "READY"
        local ndi_mode = ndi.get_mode()
        love.graphics.setColor(1, 1, 1, 0.8)
        love.graphics.print("NDI: " .. ndi_status .. " (" .. ndi_mode .. ") - Press [N] to toggle", 10, 50)
        love.graphics.print("Source: " .. ndi_source_name, 10, 70)
        
        -- Show detailed telemetry on the right side if streaming
        if ndi.is_streaming() then
            local stats = ndi.get_network_stats()
            local screen_width = love.graphics.getWidth()
            local telemetry_x = screen_width - 360  -- 320px from right edge
            
            -- Network statistics text (right-aligned)
            love.graphics.setColor(1, 1, 1, 0.8)
            love.graphics.print(string.format("Frames: %d | FPS: %d | Receivers: %d", 
                stats.frames_sent, stats.current_fps, stats.receiver_count), telemetry_x, 10)
            love.graphics.print(string.format("Data: %s", 
                ndi.format_bytes(stats.bytes_sent)), telemetry_x, 30)
            love.graphics.print(string.format("Bandwidth: %.1f MB/s", 
                stats.bandwidth_mbps), telemetry_x, 50)
            love.graphics.print(string.format("Peak: %.1f MB/s | Uptime: %.0fs", 
                stats.max_bandwidth_mbps, stats.uptime), telemetry_x, 70)
            
            -- Draw network load graph (right side)
            if #stats.bandwidth_history > 1 then
                local graph_x = telemetry_x
                local graph_y = 110
                local graph_width = 300
                local graph_height = 60
                
                -- Graph background
                love.graphics.setColor(0, 0, 0, 0.7)
                love.graphics.rectangle("fill", graph_x, graph_y, graph_width, graph_height)
                
                -- Graph border
                love.graphics.setColor(1, 1, 1, 0.5)
                love.graphics.rectangle("line", graph_x, graph_y, graph_width, graph_height)
                
                -- Graph title
                love.graphics.setColor(1, 1, 1, 0.8)
                love.graphics.print("Network Load (MB/s)", graph_x + 5, graph_y - 15)
                
                -- Draw graph lines
                local max_value = math.max(stats.max_bandwidth_mbps, 1) -- Avoid division by zero
                love.graphics.setColor(0, 1, 0, 0.8)
                
                for i = 2, #stats.bandwidth_history do
                    local x1 = graph_x + ((i - 2) / (#stats.bandwidth_history - 1)) * graph_width
                    local x2 = graph_x + ((i - 1) / (#stats.bandwidth_history - 1)) * graph_width
                    
                    local y1 = graph_y + graph_height - ((stats.bandwidth_history[i - 1] / (1024 * 1024)) / max_value) * graph_height
                    local y2 = graph_y + graph_height - ((stats.bandwidth_history[i] / (1024 * 1024)) / max_value) * graph_height
                    
                    love.graphics.line(x1, y1, x2, y2)
                end
                
                -- Draw max line reference
                love.graphics.setColor(1, 1, 1, 0.5)
                local max_y = graph_y + 10
                love.graphics.line(graph_x, max_y, graph_x + graph_width, max_y)
                love.graphics.setColor(1, 1, 1, 0.8)
                love.graphics.print(string.format("%.1f", max_value), graph_x + graph_width + 5, max_y - 6)
                
                -- Draw average line reference
                love.graphics.setColor(1, 1, 1, 0.3)
                local avg_y = graph_y + graph_height - (stats.bandwidth_mbps / max_value) * graph_height
                love.graphics.line(graph_x, avg_y, graph_x + graph_width, avg_y)
                love.graphics.setColor(1, 1, 1, 0.8)
                love.graphics.print(string.format("%.1f", stats.bandwidth_mbps), graph_x + graph_width + 5, avg_y - 6)
            end
        end
    else
        love.graphics.setColor(1, 1, 1, 0.8)
        love.graphics.print("NDI: DISABLED", 10, 50)
    end
    
    -- Show available shaders (left side, no longer needs to move)
    love.graphics.setColor(1, 1, 1, 0.8)
    for i, s in ipairs(shaders) do
        local prefix = (i == currentShaderIndex) and "> " or "  "
        love.graphics.print(prefix .. i .. ". " .. s.name, 10, 90 + i * 20)
    end
    
    -- Draw console last (on top)
    console.draw()
end


function love.keypressed(key)
    -- Let console handle key first
    if console and console.keypressed(key) then
        return  -- Console consumed the key
    end
    
    if key == "q" then 
        -- Cleanup console and NDI before quitting
        console.cleanup()
        if ndi_enabled then
            ndi.cleanup()  -- This will now stop the managed subprocess
        end
        love.event.quit() 
    end
    if key == "tab" then
        currentShaderIndex = currentShaderIndex + 1
        if currentShaderIndex > #shaders then
            currentShaderIndex = 1
        end
        loadCurrentShader()
        console.info("Switched to shader: " .. shaders[currentShaderIndex].name)
    end
    if key == "n" and ndi_enabled then
        -- Toggle NDI streaming
        if ndi.is_streaming() then
            ndi.stop_streaming()
            print("NDI streaming stopped")
            console.info("NDI streaming stopped")
        else
            if ndi.start_streaming(ndi_source_name, ndi_groups) then
                print("NDI streaming started: " .. ndi_source_name)
                console.success("NDI streaming started: " .. ndi_source_name)
            else
                print("Failed to start NDI streaming")
                console.error("Failed to start NDI streaming")
            end
        end
    end
    -- Number keys for direct shader selection
    local num = tonumber(key)
    if num and num >= 1 and num <= #shaders then
        currentShaderIndex = num
        loadCurrentShader()
        console.info("Switched to shader: " .. shaders[currentShaderIndex].name)
    end
end

function love.textinput(text)
    console.textinput(text)
end

function love.keyreleased(key)
    -- Let console handle key release
    if console and console.keyreleased then
        console.keyreleased(key)
    end
end

function love.resize(w, h)
    -- Update shader resolution uniform
    if shader and shader:hasUniform("resolution") then
        shader:send("resolution", {w, h})
    end
    
    -- NDI canvas will be automatically recreated on next frame
    print("Window resized to " .. w .. "x" .. h .. " - NDI will adjust automatically")
end
