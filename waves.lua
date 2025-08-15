-- waves.lua
-- Love2D app to render the waves.frag shader

function love.load()
    -- Load the waves shader
    shader = love.graphics.newShader("waves.frag")
    
    -- Set initial uniforms
    if shader:hasUniform("resolution") then
        shader:send("resolution", {love.graphics.getWidth(), love.graphics.getHeight()})
    end
    if shader:hasUniform("mouse") then
        shader:send("mouse", {love.graphics.getWidth()/2, love.graphics.getHeight()/2})
    end
end

function love.update(dt)
    -- Pass time to the shader for animation
    if shader:hasUniform("time") then
        shader:send("time", love.timer.getTime())
    end
    
    -- Update resolution in case window is resized
    if shader:hasUniform("resolution") then
        shader:send("resolution", {love.graphics.getWidth(), love.graphics.getHeight()})
    end
    
    -- Update mouse position for camera control
    if shader:hasUniform("mouse") then
        local mx, my = love.mouse.getPosition()
        shader:send("mouse", {mx, my})
    end
end

function love.draw()
    love.graphics.setShader(shader)
    love.graphics.rectangle("fill", 0, 0, love.graphics.getWidth(), love.graphics.getHeight())
    love.graphics.setShader()
    
    -- Draw instructions
    love.graphics.setColor(1, 1, 1, 0.8)
    love.graphics.print("Move mouse to look around the water scene", 10, 10)
    love.graphics.print("Press Q to quit", 10, 30)
end

function love.keypressed(key)
    if key == "q" then
        love.event.quit()
    end
end
