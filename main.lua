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

    -- Initialize post-process effects
    _G.effect_enabled = false
    -- Box blur
    _G.blur_strength = 1.0
    _G.blur_radius = 3.0
    local blur_ok, blur_or_err = pcall(function()
        _G.blur_shader = love.graphics.newShader("shaders/effects/box_blur.frag")
    end)
    if blur_ok and _G.blur_shader then
        if _G.blur_shader:hasUniform("strength") then _G.blur_shader:send("strength", _G.blur_strength) end
        if _G.blur_shader:hasUniform("radius") then _G.blur_shader:send("radius", _G.blur_radius) end
    end
    -- Vignette
    _G.vignette_strength = 0.7
    _G.vignette_radius = 0.75
    _G.vignette_softness = 0.45
    local vig_ok, vig_or_err = pcall(function()
        _G.vignette_shader = love.graphics.newShader("shaders/effects/vignette.frag")
    end)
    if vig_ok and _G.vignette_shader then
        if _G.vignette_shader:hasUniform("strength") then _G.vignette_shader:send("strength", _G.vignette_strength) end
        if _G.vignette_shader:hasUniform("radius") then _G.vignette_shader:send("radius", _G.vignette_radius) end
        if _G.vignette_shader:hasUniform("softness") then _G.vignette_shader:send("softness", _G.vignette_softness) end
    end
    -- Pixelate
    _G.pixelate_size = 8.0
    local pix_ok, pix_or_err = pcall(function()
        _G.pixelate_shader = love.graphics.newShader("shaders/effects/pixelate.frag")
    end)
    if pix_ok and _G.pixelate_shader and _G.pixelate_shader:hasUniform("pixel_size") then
        _G.pixelate_shader:send("pixel_size", _G.pixelate_size)
    end
    -- Directional blur
    _G.dirblur_strength = 0.7
    _G.dirblur_radius = 6.0
    _G.dirblur_angle = 0.0
    local dbr_ok = pcall(function() _G.dirblur_shader = love.graphics.newShader("shaders/effects/directional_blur.frag") end)
    if _G.dirblur_shader then
        if _G.dirblur_shader:hasUniform("strength") then _G.dirblur_shader:send("strength", _G.dirblur_strength) end
        if _G.dirblur_shader:hasUniform("radius") then _G.dirblur_shader:send("radius", _G.dirblur_radius) end
        if _G.dirblur_shader:hasUniform("angle") then _G.dirblur_shader:send("angle", _G.dirblur_angle) end
    end
    -- Radial blur
    _G.radial_strength = 0.6
    _G.radial_radius = 5.0
    local rbl_ok = pcall(function() _G.radial_shader = love.graphics.newShader("shaders/effects/radial_blur.frag") end)
    if _G.radial_shader then
        if _G.radial_shader:hasUniform("strength") then _G.radial_shader:send("strength", _G.radial_strength) end
        if _G.radial_shader:hasUniform("radius") then _G.radial_shader:send("radius", _G.radial_radius) end
    end
    -- Zoom blur
    _G.zoom_strength = 0.5
    _G.zoom_amount = 0.5
    local zbl_ok = pcall(function() _G.zoom_shader = love.graphics.newShader("shaders/effects/zoom_blur.frag") end)
    if _G.zoom_shader then
        if _G.zoom_shader:hasUniform("strength") then _G.zoom_shader:send("strength", _G.zoom_strength) end
        if _G.zoom_shader:hasUniform("amount") then _G.zoom_shader:send("amount", _G.zoom_amount) end
    end
    -- Barrel distortion
    _G.barrel_amount = -0.15
    local brl_ok = pcall(function() _G.barrel_shader = love.graphics.newShader("shaders/effects/barrel_distortion.frag") end)
    if _G.barrel_shader and _G.barrel_shader:hasUniform("amount") then _G.barrel_shader:send("amount", _G.barrel_amount) end
    -- Heat haze
    _G.haze_strength = 0.5
    _G.haze_speed = 0.6
    _G.haze_scale = 1.0
    local hz_ok = pcall(function() _G.haze_shader = love.graphics.newShader("shaders/effects/heat_haze.frag") end)
    if _G.haze_shader then
        if _G.haze_shader:hasUniform("strength") then _G.haze_shader:send("strength", _G.haze_strength) end
        if _G.haze_shader:hasUniform("speed") then _G.haze_shader:send("speed", _G.haze_speed) end
        if _G.haze_shader:hasUniform("scale") then _G.haze_shader:send("scale", _G.haze_scale) end
    end
    -- Grayscale
    _G.gray_strength = 1.0
    local gs_ok = pcall(function() _G.gray_shader = love.graphics.newShader("shaders/effects/grayscale.frag") end)
    if _G.gray_shader and _G.gray_shader:hasUniform("strength") then _G.gray_shader:send("strength", _G.gray_strength) end
    -- Sepia
    _G.sepia_strength = 1.0
    local sp_ok = pcall(function() _G.sepia_shader = love.graphics.newShader("shaders/effects/sepia.frag") end)
    if _G.sepia_shader and _G.sepia_shader:hasUniform("strength") then _G.sepia_shader:send("strength", _G.sepia_strength) end
    -- Posterize
    _G.poster_levels = 5.0
    _G.poster_strength = 1.0
    local po_ok = pcall(function() _G.poster_shader = love.graphics.newShader("shaders/effects/posterize.frag") end)
    if _G.poster_shader then
        if _G.poster_shader:hasUniform("levels") then _G.poster_shader:send("levels", _G.poster_levels) end
        if _G.poster_shader:hasUniform("strength") then _G.poster_shader:send("strength", _G.poster_strength) end
    end
    -- Sobel edge
    _G.edge_strength = 1.0
    local sb_ok = pcall(function() _G.sobel_shader = love.graphics.newShader("shaders/effects/sobel_edge.frag") end)
    if _G.sobel_shader and _G.sobel_shader:hasUniform("strength") then _G.sobel_shader:send("strength", _G.edge_strength) end
    -- Chromatic aberration
    _G.ca_amount = 2.0
    local ca_ok = pcall(function() _G.ca_shader = love.graphics.newShader("shaders/effects/chromatic_aberration.frag") end)
    if _G.ca_shader and _G.ca_shader:hasUniform("amount") then _G.ca_shader:send("amount", _G.ca_amount) end
    -- Scanlines
    _G.scan_intensity = 0.6
    _G.scan_thickness = 2.0
    local sl_ok = pcall(function() _G.scan_shader = love.graphics.newShader("shaders/effects/scanlines.frag") end)
    if _G.scan_shader then
        if _G.scan_shader:hasUniform("intensity") then _G.scan_shader:send("intensity", _G.scan_intensity) end
        if _G.scan_shader:hasUniform("thickness") then _G.scan_shader:send("thickness", _G.scan_thickness) end
    end
    -- Bloom
    _G.bloom_strength = 0.6
    _G.bloom_threshold = 0.7
    local bl_ok = pcall(function() _G.bloom_shader = love.graphics.newShader("shaders/effects/bloom.frag") end)
    if _G.bloom_shader then
        if _G.bloom_shader:hasUniform("strength") then _G.bloom_shader:send("strength", _G.bloom_strength) end
        if _G.bloom_shader:hasUniform("threshold") then _G.bloom_shader:send("threshold", _G.bloom_threshold) end
    end
    -- Twirl
    _G.twirl_angle = 1.2
    _G.twirl_radius = 0.6
    local tw_ok = pcall(function() _G.twirl_shader = love.graphics.newShader("shaders/effects/twirl.frag") end)
    if _G.twirl_shader then
        if _G.twirl_shader:hasUniform("angle") then _G.twirl_shader:send("angle", _G.twirl_angle) end
        if _G.twirl_shader:hasUniform("radius") then _G.twirl_shader:send("radius", _G.twirl_radius) end
    end
    -- Ripple
    _G.ripple_amplitude = 8.0
    _G.ripple_frequency = 12.0
    _G.ripple_speed = 4.0
    local rp_ok = pcall(function() _G.ripple_shader = love.graphics.newShader("shaders/effects/ripple.frag") end)
    if _G.ripple_shader then
        if _G.ripple_shader:hasUniform("amplitude") then _G.ripple_shader:send("amplitude", _G.ripple_amplitude) end
        if _G.ripple_shader:hasUniform("frequency") then _G.ripple_shader:send("frequency", _G.ripple_frequency) end
        if _G.ripple_shader:hasUniform("speed") then _G.ripple_shader:send("speed", _G.ripple_speed) end
    end
    -- Displacement
    _G.disp_amount = 8.0
    local dp_ok = pcall(function() _G.disp_shader = love.graphics.newShader("shaders/effects/displacement.frag") end)
    if _G.disp_shader and _G.disp_shader:hasUniform("amount") then _G.disp_shader:send("amount", _G.disp_amount) end
    -- Pixel Sort
    _G.pxsort_strength = 1.0
    _G.pxsort_distance = 80.0
    _G.pxsort_angle = 0.0
    _G.pxsort_threshold = 0.5
    local ps_ok = pcall(function() _G.pxsort_shader = love.graphics.newShader("shaders/effects/pixel_sort.frag") end)
    if _G.pxsort_shader then
        if _G.pxsort_shader:hasUniform("strength") then _G.pxsort_shader:send("strength", _G.pxsort_strength) end
        if _G.pxsort_shader:hasUniform("distance") then _G.pxsort_shader:send("distance", _G.pxsort_distance) end
        if _G.pxsort_shader:hasUniform("angle") then _G.pxsort_shader:send("angle", _G.pxsort_angle) end
        if _G.pxsort_shader:hasUniform("threshold") then _G.pxsort_shader:send("threshold", _G.pxsort_threshold) end
    end
    -- Effect list and selection
    _G.post_effects = {
        { name = "None", key = "none", shader = nil },
        { name = "Box Blur", key = "blur", shader = _G.blur_shader },
        { name = "Vignette", key = "vignette", shader = _G.vignette_shader },
        { name = "Pixelate", key = "pixelate", shader = _G.pixelate_shader },
        { name = "Directional Blur", key = "dirblur", shader = _G.dirblur_shader },
        { name = "Radial Blur", key = "radial", shader = _G.radial_shader },
        { name = "Zoom Blur", key = "zoom", shader = _G.zoom_shader },
        { name = "Barrel Distortion", key = "barrel", shader = _G.barrel_shader },
        { name = "Heat Haze", key = "haze", shader = _G.haze_shader },
        { name = "Grayscale", key = "gray", shader = _G.gray_shader },
        { name = "Sepia", key = "sepia", shader = _G.sepia_shader },
        { name = "Posterize", key = "poster", shader = _G.poster_shader },
        { name = "Sobel Edge", key = "sobel", shader = _G.sobel_shader },
        { name = "Chromatic Aberration", key = "ca", shader = _G.ca_shader },
        { name = "Scanlines", key = "scan", shader = _G.scan_shader },
        { name = "Bloom", key = "bloom", shader = _G.bloom_shader },
        { name = "Twirl", key = "twirl", shader = _G.twirl_shader },
        { name = "Ripple", key = "ripple", shader = _G.ripple_shader },
        { name = "Displacement", key = "disp", shader = _G.disp_shader },
        { name = "Pixel Sort", key = "pxsort", shader = _G.pxsort_shader },
    }
    _G.current_effect_index = 1 -- start at None
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
    
    -- Ensure scene canvas exists and matches window size
    local w, h = love.graphics.getWidth(), love.graphics.getHeight()
    if not _G.scene_canvas or _G.scene_canvas:getWidth() ~= w or _G.scene_canvas:getHeight() ~= h then
        if _G.scene_canvas then _G.scene_canvas:release() end
        _G.scene_canvas = love.graphics.newCanvas(w, h)
    end

    -- Render content once into scene canvas (without UI)
    love.graphics.setCanvas(_G.scene_canvas)
    love.graphics.clear(0, 0, 0, 0)
    renderContent()
    love.graphics.setCanvas()

    -- Helper: bind current post-process shader and send uniforms
    local function bind_current_effect_shader()
        local e = _G.post_effects[_G.current_effect_index]
        if not e or not e.shader then return false end
        -- Send effect-specific uniforms
        if e.key == "blur" then
            if e.shader:hasUniform("strength") then e.shader:send("strength", _G.blur_strength or 1.0) end
            if e.shader:hasUniform("radius") then e.shader:send("radius", _G.blur_radius or 3.0) end
        elseif e.key == "vignette" then
            if e.shader:hasUniform("strength") then e.shader:send("strength", _G.vignette_strength or 0.7) end
            if e.shader:hasUniform("radius") then e.shader:send("radius", _G.vignette_radius or 0.75) end
            if e.shader:hasUniform("softness") then e.shader:send("softness", _G.vignette_softness or 0.45) end
        elseif e.key == "pixelate" then
            if e.shader:hasUniform("pixel_size") then e.shader:send("pixel_size", _G.pixelate_size or 8.0) end
        elseif e.key == "dirblur" then
            if e.shader:hasUniform("strength") then e.shader:send("strength", _G.dirblur_strength or 0.7) end
            if e.shader:hasUniform("radius") then e.shader:send("radius", _G.dirblur_radius or 6.0) end
            if e.shader:hasUniform("angle") then e.shader:send("angle", _G.dirblur_angle or 0.0) end
        elseif e.key == "radial" then
            if e.shader:hasUniform("strength") then e.shader:send("strength", _G.radial_strength or 0.6) end
            if e.shader:hasUniform("radius") then e.shader:send("radius", _G.radial_radius or 5.0) end
        elseif e.key == "zoom" then
            if e.shader:hasUniform("strength") then e.shader:send("strength", _G.zoom_strength or 0.5) end
            if e.shader:hasUniform("amount") then e.shader:send("amount", _G.zoom_amount or 0.5) end
        elseif e.key == "barrel" then
            if e.shader:hasUniform("amount") then e.shader:send("amount", _G.barrel_amount or -0.15) end
        elseif e.key == "haze" then
            if e.shader:hasUniform("strength") then e.shader:send("strength", _G.haze_strength or 0.5) end
            if e.shader:hasUniform("speed") then e.shader:send("speed", _G.haze_speed or 0.6) end
            if e.shader:hasUniform("scale") then e.shader:send("scale", _G.haze_scale or 1.0) end
        elseif e.key == "gray" then
            if e.shader:hasUniform("strength") then e.shader:send("strength", _G.gray_strength or 1.0) end
        elseif e.key == "sepia" then
            if e.shader:hasUniform("strength") then e.shader:send("strength", _G.sepia_strength or 1.0) end
        elseif e.key == "poster" then
            if e.shader:hasUniform("levels") then e.shader:send("levels", _G.poster_levels or 5.0) end
            if e.shader:hasUniform("strength") then e.shader:send("strength", _G.poster_strength or 1.0) end
        elseif e.key == "sobel" then
            if e.shader:hasUniform("strength") then e.shader:send("strength", _G.edge_strength or 1.0) end
        elseif e.key == "ca" then
            if e.shader:hasUniform("amount") then e.shader:send("amount", _G.ca_amount or 2.0) end
        elseif e.key == "scan" then
            if e.shader:hasUniform("intensity") then e.shader:send("intensity", _G.scan_intensity or 0.6) end
            if e.shader:hasUniform("thickness") then e.shader:send("thickness", _G.scan_thickness or 2.0) end
        elseif e.key == "bloom" then
            if e.shader:hasUniform("strength") then e.shader:send("strength", _G.bloom_strength or 0.6) end
            if e.shader:hasUniform("threshold") then e.shader:send("threshold", _G.bloom_threshold or 0.7) end
        elseif e.key == "twirl" then
            if e.shader:hasUniform("angle") then e.shader:send("angle", _G.twirl_angle or 1.2) end
            if e.shader:hasUniform("radius") then e.shader:send("radius", _G.twirl_radius or 0.6) end
        elseif e.key == "ripple" then
            if e.shader:hasUniform("amplitude") then e.shader:send("amplitude", _G.ripple_amplitude or 8.0) end
            if e.shader:hasUniform("frequency") then e.shader:send("frequency", _G.ripple_frequency or 12.0) end
            if e.shader:hasUniform("speed") then e.shader:send("speed", _G.ripple_speed or 4.0) end
        elseif e.key == "disp" then
            if e.shader:hasUniform("amount") then e.shader:send("amount", _G.disp_amount or 8.0) end
        elseif e.key == "pxsort" then
            if e.shader:hasUniform("strength") then e.shader:send("strength", _G.pxsort_strength or 1.0) end
            if e.shader:hasUniform("distance") then e.shader:send("distance", _G.pxsort_distance or 80.0) end
            if e.shader:hasUniform("angle") then e.shader:send("angle", _G.pxsort_angle or 0.0) end
            if e.shader:hasUniform("threshold") then e.shader:send("threshold", _G.pxsort_threshold or 0.5) end
        end
        if e.shader:hasUniform("time") then e.shader:send("time", love.timer.getTime()) end
        love.graphics.setShader(e.shader)
        return true
    end

    -- Draw to screen (post-processed if an effect is enabled)
    love.graphics.setColor(1, 1, 1, 1)
    if _G.effect_enabled then
        bind_current_effect_shader()
    end
    love.graphics.draw(_G.scene_canvas, 0, 0)
    love.graphics.setShader()
    
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
        
        -- Draw the rendered scene to NDI canvas (post-processed if an effect is enabled)
        love.graphics.setCanvas(_G.ndi_capture_canvas)
        love.graphics.clear(0, 0, 0, 0)
        love.graphics.setColor(1, 1, 1, 1)
        if _G.effect_enabled then
            bind_current_effect_shader()
        end
        love.graphics.draw(_G.scene_canvas, 0, 0)
        love.graphics.setShader()
        love.graphics.setCanvas()
        
        -- Send frame via shared memory to C++ NDI sender
        ndi.send_frame(_G.ndi_capture_canvas)
    end

    -- Draw UI (only on screen, not in NDI stream)
    love.graphics.setColor(0.5, 1, 0.8, 0.8)  -- Mint green color
    love.graphics.print("Current: " .. shaderInfo.name, 10, 10)
    love.graphics.setColor(1, 1, 1, 0.8)  -- Reset to white for other text
    love.graphics.print("Press [Tab] to switch shaders, [Q] to quit, [`] for console", 10, 30)
    local eff = _G.post_effects[_G.current_effect_index]
    local effName = eff and eff.name or "None"
    local param_str = ""
    if eff then
        if eff.key == "blur" then param_str = string.format(" (strength %.1f, radius %.0fpx)", _G.blur_strength or 1.0, _G.blur_radius or 3.0)
        elseif eff.key == "vignette" then param_str = string.format(" (strength %.1f)", _G.vignette_strength or 0.7)
        elseif eff.key == "pixelate" then param_str = string.format(" (size %.0fpx)", _G.pixelate_size or 8.0)
        elseif eff.key == "dirblur" then param_str = string.format(" (strength %.1f)", _G.dirblur_strength or 0.7)
        elseif eff.key == "radial" then param_str = string.format(" (strength %.1f)", _G.radial_strength or 0.6)
        elseif eff.key == "zoom" then param_str = string.format(" (strength %.1f)", _G.zoom_strength or 0.5)
        elseif eff.key == "barrel" then param_str = string.format(" (amount %.2f)", _G.barrel_amount or -0.15)
        elseif eff.key == "haze" then param_str = string.format(" (strength %.1f)", _G.haze_strength or 0.5)
        elseif eff.key == "gray" then param_str = string.format(" (strength %.1f)", _G.gray_strength or 1.0)
        elseif eff.key == "sepia" then param_str = string.format(" (strength %.1f)", _G.sepia_strength or 1.0)
        elseif eff.key == "poster" then param_str = string.format(" (levels %.0f)", _G.poster_levels or 5.0)
        elseif eff.key == "sobel" then param_str = string.format(" (strength %.1f)", _G.edge_strength or 1.0)
        elseif eff.key == "ca" then param_str = string.format(" (amount %.1f)", _G.ca_amount or 2.0)
        elseif eff.key == "scan" then param_str = string.format(" (intensity %.1f)", _G.scan_intensity or 0.6)
        elseif eff.key == "bloom" then param_str = string.format(" (strength %.1f, thresh %.2f)", _G.bloom_strength or 0.6, _G.bloom_threshold or 0.7)
        elseif eff.key == "twirl" then param_str = string.format(" (angle %.1f)", _G.twirl_angle or 1.2)
        elseif eff.key == "ripple" then param_str = string.format(" (amp %.0f)", _G.ripple_amplitude or 8.0)
        elseif eff.key == "disp" then param_str = string.format(" (amount %.0f)", _G.disp_amount or 8.0)
        elseif eff.key == "pxsort" then param_str = string.format(" (distance %.0fpx)", _G.pxsort_distance or 80.0)
        end
    end
    love.graphics.print("Effect: " .. effName .. param_str .. "  [E] switch  [B] toggle  Alt+Number select", 10, 50)
    
    -- NDI status (basic info on left)
    if ndi_enabled then
        local ndi_status = ndi.is_streaming() and "STREAMING" or "READY"
        local ndi_mode = ndi.get_mode()
        love.graphics.setColor(1, 1, 1, 0.8)
        love.graphics.print("NDI: " .. ndi_status .. " (" .. ndi_mode .. ") - Press [N] to toggle", 10, 70)
        love.graphics.print("Source: " .. ndi_source_name, 10, 90)
        
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
        love.graphics.print("NDI: DISABLED", 10, 70)
    end
    
    -- Show available shaders (left side, no longer needs to move)
    love.graphics.setColor(1, 1, 1, 0.8)
    for i, s in ipairs(shaders) do
        local prefix = (i == currentShaderIndex) and "> " or "  "
        love.graphics.print(prefix .. i .. ". " .. s.name, 10, 110 + i * 20)
    end

    -- Show available post effects list below shaders
    local base_y = 110 + (#shaders + 2) * 20
    love.graphics.setColor(0.8, 1, 0.8, 0.9)
    love.graphics.print("Effects (Alt+1-" .. #_G.post_effects .. "):", 10, base_y)
    love.graphics.setColor(1, 1, 1, 0.8)
    for i, e in ipairs(_G.post_effects) do
        local prefix = (i == _G.current_effect_index) and "> " or "  "
        love.graphics.print(prefix .. i .. ". " .. e.name, 10, base_y + i * 20)
    end
    
    -- Draw console last (on top)
    console.draw()
end


function love.keypressed(key)
    -- Let console handle key first
    if console and console.keypressed(key) then
        return  -- Console consumed the key
    end
    local altDown = love.keyboard.isDown('lalt') or love.keyboard.isDown('ralt')
    
    if key == "q" then 
        -- Cleanup console and NDI before quitting
        console.cleanup()
        if ndi_enabled then
            ndi.cleanup()  -- This will now stop the managed subprocess
        end
        love.event.quit() 
    end
    if key == "tab" then
        if altDown then
            -- Cycle post effects instead of shaders
            _G.current_effect_index = (_G.current_effect_index % #_G.post_effects) + 1
            console.info("Effect: " .. _G.post_effects[_G.current_effect_index].name)
        else
            currentShaderIndex = currentShaderIndex + 1
            if currentShaderIndex > #shaders then
                currentShaderIndex = 1
            end
            loadCurrentShader()
            console.info("Switched to shader: " .. shaders[currentShaderIndex].name)
        end
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
    if key == "e" then
        _G.current_effect_index = (_G.current_effect_index % #_G.post_effects) + 1
        local name = _G.post_effects[_G.current_effect_index].name
        console.info("Effect switched: " .. name)
    end
    if key == "b" then
        _G.effect_enabled = not _G.effect_enabled
        local state = _G.effect_enabled and "ON" or "OFF"
        console.info("Post effect: " .. state)
    end
    if key == "]" then
        local eff = _G.post_effects[_G.current_effect_index]
        if eff and eff.key == "blur" then
            _G.blur_strength = math.min(1.0, (_G.blur_strength or 1.0) + 0.1)
            if _G.blur_shader and _G.blur_shader:hasUniform("strength") then _G.blur_shader:send("strength", _G.blur_strength) end
            console.info(string.format("Blur strength: %.1f", _G.blur_strength))
        elseif eff and eff.key == "vignette" then
            _G.vignette_strength = math.min(1.0, (_G.vignette_strength or 0.7) + 0.1)
            if _G.vignette_shader and _G.vignette_shader:hasUniform("strength") then _G.vignette_shader:send("strength", _G.vignette_strength) end
            console.info(string.format("Vignette strength: %.1f", _G.vignette_strength))
        elseif eff and eff.key == "pixelate" then
            _G.pixelate_size = math.min(128.0, (_G.pixelate_size or 8.0) + 1.0)
            if _G.pixelate_shader and _G.pixelate_shader:hasUniform("pixel_size") then _G.pixelate_shader:send("pixel_size", _G.pixelate_size) end
            console.info(string.format("Pixelate size: %.0f px", _G.pixelate_size))
        elseif eff and eff.key == "dirblur" then
            _G.dirblur_strength = math.min(1.0, (_G.dirblur_strength or 0.7) + 0.1)
            console.info(string.format("Directional blur strength: %.1f", _G.dirblur_strength))
        elseif eff and eff.key == "radial" then
            _G.radial_strength = math.min(1.0, (_G.radial_strength or 0.6) + 0.1)
            console.info(string.format("Radial blur strength: %.1f", _G.radial_strength))
        elseif eff and eff.key == "zoom" then
            _G.zoom_strength = math.min(1.0, (_G.zoom_strength or 0.5) + 0.1)
            console.info(string.format("Zoom blur strength: %.1f", _G.zoom_strength))
        elseif eff and eff.key == "barrel" then
            _G.barrel_amount = math.min(0.8, (_G.barrel_amount or -0.15) + 0.05)
            console.info(string.format("Barrel amount: %.2f", _G.barrel_amount))
        elseif eff and eff.key == "haze" then
            _G.haze_strength = math.min(1.0, (_G.haze_strength or 0.5) + 0.1)
            console.info(string.format("Haze strength: %.1f", _G.haze_strength))
        elseif eff and eff.key == "gray" then
            _G.gray_strength = math.min(1.0, (_G.gray_strength or 1.0) + 0.1)
            console.info(string.format("Grayscale strength: %.1f", _G.gray_strength))
        elseif eff and eff.key == "sepia" then
            _G.sepia_strength = math.min(1.0, (_G.sepia_strength or 1.0) + 0.1)
            console.info(string.format("Sepia strength: %.1f", _G.sepia_strength))
        elseif eff and eff.key == "poster" then
            _G.poster_levels = math.min(16.0, (_G.poster_levels or 5.0) + 1.0)
            console.info(string.format("Posterize levels: %.0f", _G.poster_levels))
        elseif eff and eff.key == "sobel" then
            _G.edge_strength = math.min(1.0, (_G.edge_strength or 1.0) + 0.1)
            console.info(string.format("Edge strength: %.1f", _G.edge_strength))
        elseif eff and eff.key == "ca" then
            _G.ca_amount = math.min(10.0, (_G.ca_amount or 2.0) + 0.5)
            console.info(string.format("Chromatic aberration: %.1f", _G.ca_amount))
        elseif eff and eff.key == "scan" then
            _G.scan_intensity = math.min(1.0, (_G.scan_intensity or 0.6) + 0.1)
            console.info(string.format("Scanline intensity: %.1f", _G.scan_intensity))
        elseif eff and eff.key == "bloom" then
            _G.bloom_strength = math.min(2.0, (_G.bloom_strength or 0.6) + 0.1)
            console.info(string.format("Bloom strength: %.1f", _G.bloom_strength))
        elseif eff and eff.key == "twirl" then
            _G.twirl_angle = math.min(6.28, (_G.twirl_angle or 1.2) + 0.1)
            console.info(string.format("Twirl angle: %.2f", _G.twirl_angle))
        elseif eff and eff.key == "ripple" then
            _G.ripple_amplitude = math.min(64.0, (_G.ripple_amplitude or 8.0) + 1.0)
            console.info(string.format("Ripple amplitude: %.0f", _G.ripple_amplitude))
        elseif eff and eff.key == "disp" then
            _G.disp_amount = math.min(64.0, (_G.disp_amount or 8.0) + 1.0)
            console.info(string.format("Displacement amount: %.0f", _G.disp_amount))
        elseif eff and eff.key == "pxsort" then
            _G.pxsort_distance = math.min(1024.0, (_G.pxsort_distance or 80.0) + 8.0)
            console.info(string.format("Pixel sort distance: %.0f px", _G.pxsort_distance))
        end
    end
    if key == "[" then
        local eff = _G.post_effects[_G.current_effect_index]
        if eff and eff.key == "blur" then
            _G.blur_strength = math.max(0.0, (_G.blur_strength or 1.0) - 0.1)
            if _G.blur_shader and _G.blur_shader:hasUniform("strength") then _G.blur_shader:send("strength", _G.blur_strength) end
            console.info(string.format("Blur strength: %.1f", _G.blur_strength))
        elseif eff and eff.key == "vignette" then
            _G.vignette_strength = math.max(0.0, (_G.vignette_strength or 0.7) - 0.1)
            if _G.vignette_shader and _G.vignette_shader:hasUniform("strength") then _G.vignette_shader:send("strength", _G.vignette_strength) end
            console.info(string.format("Vignette strength: %.1f", _G.vignette_strength))
        elseif eff and eff.key == "pixelate" then
            _G.pixelate_size = math.max(1.0, (_G.pixelate_size or 8.0) - 1.0)
            if _G.pixelate_shader and _G.pixelate_shader:hasUniform("pixel_size") then _G.pixelate_shader:send("pixel_size", _G.pixelate_size) end
            console.info(string.format("Pixelate size: %.0f px", _G.pixelate_size))
        elseif eff and eff.key == "dirblur" then
            _G.dirblur_strength = math.max(0.0, (_G.dirblur_strength or 0.7) - 0.1)
            console.info(string.format("Directional blur strength: %.1f", _G.dirblur_strength))
        elseif eff and eff.key == "radial" then
            _G.radial_strength = math.max(0.0, (_G.radial_strength or 0.6) - 0.1)
            console.info(string.format("Radial blur strength: %.1f", _G.radial_strength))
        elseif eff and eff.key == "zoom" then
            _G.zoom_strength = math.max(0.0, (_G.zoom_strength or 0.5) - 0.1)
            console.info(string.format("Zoom blur strength: %.1f", _G.zoom_strength))
        elseif eff and eff.key == "barrel" then
            _G.barrel_amount = math.max(-0.8, (_G.barrel_amount or -0.15) - 0.05)
            console.info(string.format("Barrel amount: %.2f", _G.barrel_amount))
        elseif eff and eff.key == "haze" then
            _G.haze_strength = math.max(0.0, (_G.haze_strength or 0.5) - 0.1)
            console.info(string.format("Haze strength: %.1f", _G.haze_strength))
        elseif eff and eff.key == "gray" then
            _G.gray_strength = math.max(0.0, (_G.gray_strength or 1.0) - 0.1)
            console.info(string.format("Grayscale strength: %.1f", _G.gray_strength))
        elseif eff and eff.key == "sepia" then
            _G.sepia_strength = math.max(0.0, (_G.sepia_strength or 1.0) - 0.1)
            console.info(string.format("Sepia strength: %.1f", _G.sepia_strength))
        elseif eff and eff.key == "poster" then
            _G.poster_levels = math.max(2.0, (_G.poster_levels or 5.0) - 1.0)
            console.info(string.format("Posterize levels: %.0f", _G.poster_levels))
        elseif eff and eff.key == "sobel" then
            _G.edge_strength = math.max(0.0, (_G.edge_strength or 1.0) - 0.1)
            console.info(string.format("Edge strength: %.1f", _G.edge_strength))
        elseif eff and eff.key == "ca" then
            _G.ca_amount = math.max(0.0, (_G.ca_amount or 2.0) - 0.5)
            console.info(string.format("Chromatic aberration: %.1f", _G.ca_amount))
        elseif eff and eff.key == "scan" then
            _G.scan_intensity = math.max(0.0, (_G.scan_intensity or 0.6) - 0.1)
            console.info(string.format("Scanline intensity: %.1f", _G.scan_intensity))
        elseif eff and eff.key == "bloom" then
            _G.bloom_strength = math.max(0.0, (_G.bloom_strength or 0.6) - 0.1)
            console.info(string.format("Bloom strength: %.1f", _G.bloom_strength))
        elseif eff and eff.key == "twirl" then
            _G.twirl_angle = math.max(0.0, (_G.twirl_angle or 1.2) - 0.1)
            console.info(string.format("Twirl angle: %.2f", _G.twirl_angle))
        elseif eff and eff.key == "ripple" then
            _G.ripple_amplitude = math.max(0.0, (_G.ripple_amplitude or 8.0) - 1.0)
            console.info(string.format("Ripple amplitude: %.0f", _G.ripple_amplitude))
        elseif eff and eff.key == "disp" then
            _G.disp_amount = math.max(0.0, (_G.disp_amount or 8.0) - 1.0)
            console.info(string.format("Displacement amount: %.0f", _G.disp_amount))
        elseif eff and eff.key == "pxsort" then
            _G.pxsort_distance = math.max(0.0, (_G.pxsort_distance or 80.0) - 8.0)
            console.info(string.format("Pixel sort distance: %.0f px", _G.pxsort_distance))
        end
    end
    -- Number keys for direct selection
    local num = tonumber(key)
    if num then
        if altDown and num >= 1 and num <= #_G.post_effects then
            _G.current_effect_index = num
            console.info("Effect: " .. _G.post_effects[_G.current_effect_index].name)
        elseif (not altDown) and num >= 1 and num <= #shaders then
            currentShaderIndex = num
            loadCurrentShader()
            console.info("Switched to shader: " .. shaders[currentShaderIndex].name)
        end
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
