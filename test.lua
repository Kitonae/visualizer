-- test.lua
-- Minimal test to check if LÖVE is working

function love.load()
    print("Test app loaded successfully")
end

function love.draw()
    love.graphics.print("Test app running - Press Q to quit", 10, 10)
end

function love.keypressed(key)
    if key == "q" then
        love.event.quit()
    end
end
