@echo off
echo === Hybrid NDI System Test ===
echo.

echo Current Status:
echo ✓ Hybrid sender running: 
tasklist | findstr hybrid_ndi_sender.exe
echo ✓ LÖVE running:
tasklist | findstr love.exe

echo.
echo === Testing Instructions ===
echo 1. LÖVE is running with the fixed hybrid module
echo 2. Hybrid sender is ready and waiting for shared memory connection
echo 3. Now test the system:
echo.
echo IN LÖVE WINDOW:
echo   - Press ` (backtick) to open console
echo   - Type: hybrid start
echo   - Type: hybrid status  (to check connection)
echo   - Type: hybrid send    (to send a test frame)
echo.
echo 4. Check NDI Studio Monitor for "LÖVE Hybrid Stream" source
echo 5. Connect to see live LÖVE graphics streamed via C++ NDI!
echo.
echo Press any key when ready to continue...
pause >nul

echo.
echo === Expected Results ===
echo - "hybrid start" should show: "Hybrid NDI initialized successfully!"
echo - "hybrid status" should show: "Ready (magic: OK, frames: X)"
echo - NDI receivers should discover "LÖVE Hybrid Stream" source
echo - Connecting should show live LÖVE shader graphics
echo.
echo The hybrid system combines:
echo   LÖVE Graphics → Shared Memory → C++ NDI → Network Receivers
echo.
echo Press any key to exit...
pause >nul
