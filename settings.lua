-- settings.lua
-- Simple persistent settings using a Lua table file in LÖVE save directory.

local M = {}

local defaults = {
    window_width = 1920,
    window_height = 1080,
    render_width = 1920,
    render_height = 1080,
    capture_pool = 2,
    capture_memlog = 0,
    ndi_debug = false,
}

local path = "config/settings.lua"
local data = nil

local function serialize_value(v)
    local t = type(v)
    if t == "number" or t == "boolean" then
        return tostring(v)
    elseif t == "string" then
        return string.format("%q", v)
    elseif t == "table" then
        local parts = {"{"}
        for k, val in pairs(v) do
            local key
            if type(k) == "string" and k:match("^[_%a][_%w]*$") then
                key = k
            else
                key = "[" .. serialize_value(k) .. "]"
            end
            table.insert(parts, string.format("%s = %s,", key, serialize_value(val)))
        end
        table.insert(parts, "}")
        return table.concat(parts, " ")
    else
        return "nil"
    end
end

local function merge_defaults(dst, src)
    for k, v in pairs(src) do
        if dst[k] == nil then dst[k] = v end
    end
end

function M.load()
    if data then return data end
    -- Ensure directory exists
    if love and love.filesystem and love.filesystem.createDirectory then
        love.filesystem.createDirectory("config")
    end
    local ok, contents = pcall(function()
        if love and love.filesystem and love.filesystem.read then
            return love.filesystem.read(path)
        else
            local f = io.open(path, "rb"); if not f then return nil end
            local c = f:read("*a"); f:close(); return c
        end
    end)
    local loaded = {}
    if ok and contents and #contents > 0 then
        local chunk, err = load(contents, "@settings", "t", {})
        if chunk then
            local ok2, tbl = pcall(chunk)
            if ok2 and type(tbl) == "table" then
                loaded = tbl
            end
        end
    end
    data = loaded
    merge_defaults(data, defaults)
    return data
end

function M.get(key)
    local d = M.load()
    return d[key]
end

function M.set(key, value)
    local d = M.load()
    d[key] = value
end

function M.save()
    local d = M.load()
    local contents = "return " .. serialize_value(d) .. "\n"
    if love and love.filesystem and love.filesystem.write then
        love.filesystem.createDirectory("config")
        love.filesystem.write(path, contents)
    else
        local dir = path:match("^(.*)/")
        if dir and dir ~= "" then os.execute('mkdir "'..dir..'" 2>nul >nul') end
        local f = assert(io.open(path, "wb"))
        f:write(contents)
        f:close()
    end
end

return M

