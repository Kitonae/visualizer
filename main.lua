-- main.lua
-- Love2D app to render shaders with Tab switching

function love.load()
    -- List of available shaders
    shaders = {
        {name = "Kaleidoscope", file = "shaders/kaleidoscope.frag", hasBackground = false},
        {name = "Water Waves", file = "shaders/waves.frag", hasBackground = false},
        {name = "Animated Lines", file = "shaders/lines.frag", hasBackground = false},
        {name = "Mono Lines", file = "shaders/lines_mono.frag", hasBackground = true}
    }
    
    currentShaderIndex = 4 -- Start with mono lines
    
    -- Load forest background image
    backgroundImage = love.graphics.newImage("forest.png")
    
    loadCurrentShader()
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
    
end


function love.draw()
    local shaderInfo = shaders[currentShaderIndex]
    
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

    -- Draw shader switcher UI
    love.graphics.setColor(1, 1, 1, 0.8)
    love.graphics.print("Current: " .. shaderInfo.name, 10, 10)
    love.graphics.print("Press [Tab] to switch shaders, [Q] to quit", 10, 30)
    
    -- Show available shaders
    for i, s in ipairs(shaders) do
        local prefix = (i == currentShaderIndex) and "> " or "  "
        love.graphics.print(prefix .. i .. ". " .. s.name, 10, 50 + i * 20)
    end
end


function love.keypressed(key)
    if key == "q" then 
        love.event.quit() 
    end
    if key == "tab" then
        currentShaderIndex = currentShaderIndex + 1
        if currentShaderIndex > #shaders then
            currentShaderIndex = 1
        end
        loadCurrentShader()
    end
    -- Number keys for direct shader selection
    local num = tonumber(key)
    if num and num >= 1 and num <= #shaders then
        currentShaderIndex = num
        loadCurrentShader()
    end
end
