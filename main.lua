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

-- Load capture module (shared memory Windows Graphics Capture)
local capture_load_success, capture_load_error = pcall(function()
    return require("capture")
end)

local capture
if capture_load_success then
    capture = capture_load_error
else
    print("Failed to load capture module: " .. tostring(capture_load_error))
    capture = {
        start = function() return false end,
        stop = function() end,
        is_ready = function() return false end,
        update = function() end,
        draw = function() end,
        get_status = function() return "Unavailable" end
    }
end

-- Loading screen state
local loading = {
    active = true,
    step = 0,
    message = "Starting...",
    start_time = 0,
    fading = false,
    fade_t = 0,
    fade_duration = 0.6,
}

function love.load()
    print("Starting LÖVE application...")

    -- List of available shaders
    shaders = {
        {name = "None", file = nil, hasBackground = false},
        {name = "Kaleidoscope", file = "shaders/kaleidoscope.frag", hasBackground = false},
        {name = "Water Waves", file = "shaders/waves.frag", hasBackground = false},
        {name = "Animated Lines", file = "shaders/lines.frag", hasBackground = false},
        {name = "Mono Lines", file = "shaders/lines_mono.frag", hasBackground = true},
        {name = "Tunnel", file = "shaders/tunnel.frag", hasBackground = false},
        {name = "Nebula", file = "shaders/nebula.frag", hasBackground = false},
        {name = "Tunnel Purple", file = "shaders/tunnel_purple.frag", hasBackground = false},
        {name = "Falling Stars", file = "shaders/falling_stars.frag", hasBackground = false}
    }
    currentShaderIndex = 5 -- Start with mono lines (index shifted by 'None')

    -- Defer initialization steps to loading sequence
    ndi_enabled = false
    ndi_source_name = "LÖVE Visualizer"
    ndi_groups = nil
    backgroundImage = nil
    logoImage = nil
    loading.active = true
    loading.step = 0
    loading.start_time = love.timer.getTime()
end

function loadCurrentShader()
    local shaderInfo = shaders[currentShaderIndex]
    if not shaderInfo.file then
        shader = nil
        return
    end
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
    -- Loading sequence: run step-by-step over frames so the loading screen is visible
    if loading.active then
        if loading.step == 0 then
            loading.message = "Initializing console..."
            local ok, err = pcall(function() console.init() end)
            if not ok then print("Console initialization failed: " .. tostring(err)) end
            loading.step = 1
            return
        elseif loading.step == 1 then
            loading.message = "Loading assets..."
            local ok, err = pcall(function()
                backgroundImage = love.graphics.newImage("forest.png")
                -- Optional logo (shown on loading overlay if present)
                logoImage = love.graphics.newImage("logo.png")
            end)
            if not ok then
                print("Failed to load background image: " .. tostring(err))
                if console and console.error then console.error("Failed to load background image: " .. tostring(err)) end
            end
            loading.step = 2
            return
        elseif loading.step == 2 then
            loading.message = "Initializing NDI..."
            local ndi_success, ndi_error = pcall(function() return ndi.initialize() end)
            if ndi_success and ndi_error then
                print("NDI initialized successfully")
                if console and console.success then console.success("NDI initialized successfully") end
                ndi_enabled = true
            else
                local error_msg = ndi_success and "NDI initialization returned false" or tostring(ndi_error)
                print("NDI initialization failed - streaming will be disabled: " .. error_msg)
                if console and console.warn then console.warn("NDI initialization failed - streaming will be disabled: " .. error_msg) end
            end
            loading.step = 3
            return
        elseif loading.step == 3 then
            loading.message = "Loading shader..."
            local ok, err = pcall(loadCurrentShader)
            if not ok then
                print("Failed to load shader: " .. tostring(err))
                if console and console.error then console.error("Failed to load shader: " .. tostring(err)) end
            end
            loading.step = 4
            return
        else
            loading.active = false
            loading.fading = true
            loading.fade_t = 0
            print("LÖVE application startup complete")
        end
    end

    -- Advance fade-out if active
    if loading.fading then
        loading.fade_t = math.min(loading.fade_t + dt, loading.fade_duration)
        if loading.fade_t >= loading.fade_duration then
            loading.fading = false
        end
    end

    -- Pass time to the shader for animation
    local t = love.timer.getTime()
    if shader and shader:hasUniform("time") then
        shader:send("time", t)
    end
    
    -- Update resolution in case window is resized
    if shader and shader:hasUniform("resolution") then
        shader:send("resolution", {love.graphics.getWidth(), love.graphics.getHeight()})
    end
    
    -- Update console
    console.update(dt)

    -- Update capture texture if active
    if capture and capture.is_ready() then
        capture.update()
    end
end


function love.draw()
    local shaderInfo = shaders[currentShaderIndex]
    
    -- Function to render the main content
    local function renderContent()
        -- Draw forest background if shader supports transparency (preserve aspect ratio; no stretching)
        if shaderInfo.hasBackground and backgroundImage then
            love.graphics.setColor(1, 1, 1, 1)
            local winW, winH = love.graphics.getWidth(), love.graphics.getHeight()
            local imgW, imgH = backgroundImage:getWidth(), backgroundImage:getHeight()
            local scale = math.min(winW / imgW, winH / imgH)
            local drawW, drawH = imgW * scale, imgH * scale
            local x = (winW - drawW) * 0.5
            local y = (winH - drawH) * 0.5
            love.graphics.draw(backgroundImage, x, y, 0, scale, scale)
        end
        
        -- Draw shader
        if shader then
            love.graphics.setShader(shader)
            love.graphics.rectangle("fill", 0, 0, love.graphics.getWidth(), love.graphics.getHeight())
            love.graphics.setShader()
        end
    end
    
    -- Optional: draw captured window beneath shader if available
    if capture and capture.is_ready() then
        capture.draw(0, 0, love.graphics.getWidth(), love.graphics.getHeight())
    end

    -- Render shader content on top
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
    if capture and capture.is_ready() then
        love.graphics.print("Capture: READY (Press [P] to stop)", 10, 90)
    else
        love.graphics.print("Capture: OFF (Press [P] to start)", 10, 90)
    end
    
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
            love.graphics.print(string.format("Bandwidth: %.1f Mbps", 
                stats.bandwidth_mbps), telemetry_x, 50)
            love.graphics.print(string.format("Peak: %.1f Mbps | Uptime: %.0fs", 
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
                love.graphics.print("Network Load (Mbps)", graph_x + 5, graph_y - 15)
                
                -- Draw graph lines
                local max_value = math.max(stats.max_bandwidth_mbps, 1) -- Avoid division by zero
                love.graphics.setColor(0, 1, 0, 0.8)

                for i = 2, #stats.bandwidth_history do
                    local x1 = graph_x + ((i - 2) / (#stats.bandwidth_history - 1)) * graph_width
                    local x2 = graph_x + ((i - 1) / (#stats.bandwidth_history - 1)) * graph_width

                    -- Convert bytes/sec to Mbps for plotting
                    local mbps1 = (stats.bandwidth_history[i - 1] * 8) / 1e6
                    local mbps2 = (stats.bandwidth_history[i] * 8) / 1e6
                    local y1 = graph_y + graph_height - (mbps1 / max_value) * graph_height
                    local y2 = graph_y + graph_height - (mbps2 / max_value) * graph_height
                    
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
        love.graphics.print(prefix .. i .. ". " .. s.name, 10, 110 + i * 20)
    end
    
    -- Draw console last (on top)
    console.draw()

    -- Loading overlay (drawn on top of everything)
    if loading.active or loading.fading then
        local w, h = love.graphics.getWidth(), love.graphics.getHeight()
        local fade_ratio = loading.fading and (1 - (loading.fade_t / loading.fade_duration)) or 1

        -- Draw background image with a gentle zoom (cover, no stretching)
        if backgroundImage then
            local imgW, imgH = backgroundImage:getWidth(), backgroundImage:getHeight()
            local baseScale = math.max(w / imgW, h / imgH)
            local t = love.timer.getTime() - (loading.start_time or 0)
            -- Zoom in up to +8% over ~6 seconds
            local zoom = 1 + math.min(t / 6, 0.08)
            local scale = baseScale * zoom
            local drawW, drawH = imgW * scale, imgH * scale
            local x = (w - drawW) * 0.5
            local y = (h - drawH) * 0.5
            love.graphics.setColor(1, 1, 1, 1)
            love.graphics.draw(backgroundImage, x, y, 0, scale, scale)
        end

        -- Dim overlay
        love.graphics.setColor(0, 0, 0, 0.7 * fade_ratio)
        love.graphics.rectangle("fill", 0, 0, w, h)
        love.graphics.setColor(1, 1, 1, fade_ratio)
        -- Draw logo if available, bottom-right with margin (preserve aspect ratio)
        if logoImage then
            local imgW, imgH = logoImage:getWidth(), logoImage:getHeight()
            local maxW, maxH = w * 0.25, h * 0.15 -- keep subtle on loading screen
            local scale = math.min(maxW / imgW, maxH / imgH, 1)
            local drawW, drawH = imgW * scale, imgH * scale
            local margin = 20
            local x = w - drawW - margin
            local y = h - drawH - margin
            love.graphics.draw(logoImage, x, y, 0, scale, scale)
        end
        local msg = loading.message or "Loading..."
        local spinner = "|/-\\"
        local idx = math.floor(love.timer.getTime() * 10) % #spinner + 1
        local text = string.format("%s  %s", spinner:sub(idx, idx), msg)
        love.graphics.print(text, w/2 - 80, h/2)
    end
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
        if capture then capture.stop() end
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
    if key == "p" then
        if capture and capture.is_ready() then
            capture.stop()
            console.info("Capture stopped")
        else
            -- Start capture targeting PowerPoint Slide Show by default
            local ok = capture.start("PowerPoint Slide Show")
            if ok then console.success("Capture started") else console.error("Failed to start capture") end
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

-- Ensure cleanup when the window is closed via OS controls
function love.quit()
    if capture and capture.stop then capture.stop() end
    if ndi and ndi.cleanup then ndi.cleanup() end
end
