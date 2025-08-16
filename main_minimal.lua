function love.load()
    print("Minimal LÖVE loaded successfully!")
    love.graphics.setBackgroundColor(0.2, 0.3, 0.5)
end

function love.update(dt)
    -- Do nothing
end

function love.draw()
    love.graphics.setColor(1, 1, 1)
    love.graphics.print("LÖVE is working! Press ESC to quit.", 100, 100)
    love.graphics.print("Current time: " .. love.timer.getTime(), 100, 130)
end

function love.keypressed(key)
    if key == "escape" then
        love.event.quit()
    end
end
