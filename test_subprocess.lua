-- Simple test for subprocess management
local ndi = require("ndi")

print("Testing NDI subprocess management...")

-- Test starting the process
print("\n1. Starting NDI process...")
local success = ndi.start_ndi_process()
print("Start result:", success)

if success then
    print("\n2. Checking if process is running...")
    local running = ndi.is_process_running()
    print("Process running:", running)
    
    print("\n3. Waiting 2 seconds...")
    -- In a real app this would be love.timer.sleep, but for testing:
    os.execute("timeout /t 2 >nul")
    
    print("\n4. Checking process status again...")
    running = ndi.is_process_running()
    print("Process still running:", running)
    
    print("\n5. Stopping NDI process...")
    ndi.stop_ndi_process()
    
    print("\n6. Final status check...")
    running = ndi.is_process_running()
    print("Process running after stop:", running)
else
    print("Failed to start process - check if build/ndi_sender.exe exists")
end

print("\nTest complete.")
