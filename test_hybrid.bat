@echo off
echo === Testing Hybrid LÖVE-NDI System ===
echo.

echo 1. Checking if hybrid_ndi_sender.exe is running...
tasklist | findstr hybrid_ndi_sender.exe
if %ERRORLEVEL% EQU 0 (
    echo ✓ Hybrid sender is running
) else (
    echo ✗ Hybrid sender not found - starting it...
    cd build
    start hybrid_ndi_sender.exe
    timeout /t 2 >nul
    cd ..
)

echo.
echo 2. Checking if LÖVE is running...
tasklist | findstr love.exe
if %ERRORLEVEL% EQU 0 (
    echo ✓ LÖVE is running
) else (
    echo ✗ LÖVE not found - please start it manually
    echo   Run: love.exe . --console
)

echo.
echo 3. Instructions to test hybrid system:
echo    a) Press ` (backtick) in LÖVE to open console
echo    b) Type: hybrid start
echo    c) Check NDI Studio Monitor for "LÖVE Hybrid Stream" source
echo    d) Connect to the source to see live video
echo.
echo 4. Available console commands:
echo    - hybrid start   : Initialize shared memory connection
echo    - hybrid status  : Check connection status  
echo    - hybrid send    : Send single test frame
echo    - hybrid stop    : Stop hybrid streaming
echo.

echo Press any key to open NDI Studio Monitor (if available)...
pause >nul

REM Try to open NDI Studio Monitor
set NDI_TOOLS="C:\Program Files\NDI\NDI 6 Tools"
if exist %NDI_TOOLS%\Studio_Monitor.exe (
    echo Starting NDI Studio Monitor...
    start "" %NDI_TOOLS%\Studio_Monitor.exe
) else (
    echo NDI Studio Monitor not found at %NDI_TOOLS%
    echo Please open it manually to see the video stream
)

echo.
echo Test setup complete!
echo Look for "LÖVE Hybrid Stream" in NDI Studio Monitor
