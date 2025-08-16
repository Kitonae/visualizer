-- Test script to check NDI status
local ndi = require("ndi")

print("Testing NDI status...")
local status = ndi.get_status()
print("Status:", status)

print("Testing NDI initialization...")
local success, err = ndi.initialize()
if success then
    print("NDI initialized successfully")
else
    print("NDI initialization failed:", err)
end

print("Done testing")
