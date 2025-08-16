@echo off
echo === NDI Source Discovery Test ===
echo.
echo This script will check for NDI sources on the network.
echo Make sure NDI Studio Monitor or another NDI receiver is running.
echo.

REM Check if NDI Analysis tool is available
set NDI_TOOLS="C:\Program Files\NDI\NDI 6 Tools"
if exist %NDI_TOOLS%\NDI_Analysis.exe (
    echo Starting NDI Analysis tool to monitor network...
    start "" %NDI_TOOLS%\NDI_Analysis.exe
    timeout /t 3 >nul
)

echo.
echo Please check the following:
echo 1. Is NDI Studio Monitor running?
echo 2. Can you see "C++ NDI Test" or "LÖVE Visualizer" in the source list?
echo 3. Do you see any frames when connecting to the source?
echo.
echo If sources are discovered but no frames appear:
echo - This indicates a timing or frame format issue
echo - Both our Lua and C++ implementations show the same pattern
echo - The NDI sender is working, but frame data might be invalid
echo.
echo Press any key to continue...
pause >nul
