@echo off
echo === Building LÖVE NDI Sender ===

REM Check if Visual Studio is available
where cl.exe >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    echo Visual Studio compiler not found in PATH
    echo Trying to find Visual Studio...
    
    REM Try to find VS 2022
    if exist "C:\Program Files\Microsoft Visual Studio\2022\Professional\VC\Auxiliary\Build\vcvarsall.bat" (
        call "C:\Program Files\Microsoft Visual Studio\2022\Professional\VC\Auxiliary\Build\vcvarsall.bat" x64
    ) else if exist "C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvarsall.bat" (
        call "C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvarsall.bat" x64
    ) else if exist "C:\Program Files\Microsoft Visual Studio\2022\Enterprise\VC\Auxiliary\Build\vcvarsall.bat" (
        call "C:\Program Files\Microsoft Visual Studio\2022\Enterprise\VC\Auxiliary\Build\vcvarsall.bat" x64
    ) else (
        echo Visual Studio 2022 not found. Please install Visual Studio or run from Developer Command Prompt.
        pause
        exit /b 1
    )
)

REM Set NDI SDK paths
set NDI_SDK="C:\Program Files\NDI\NDI 6 SDK"
set NDI_INCLUDE=%NDI_SDK%\Include
set NDI_LIB=%NDI_SDK%\Lib\x64

REM Check if NDI SDK exists
if not exist %NDI_INCLUDE%\Processing.NDI.Lib.h (
    echo NDI SDK not found at %NDI_SDK%
    echo Please install NDI SDK v6 or adjust the path in this script
    pause
    exit /b 1
)

echo NDI SDK found at: %NDI_SDK%
echo Building LÖVE NDI sender...

REM Create output directory
if not exist "build" mkdir build

REM Kill any running NDI sender to allow rebuild
taskkill /f /im ndi_sender.exe 2>nul >nul

REM Compile the NDI sender
cl.exe /EHsc /std:c++17 ^
    /I%NDI_INCLUDE% ^
    ndi_sender.cpp ^
    /link %NDI_LIB%\Processing.NDI.Lib.x64.lib ^
    /OUT:build\ndi_sender.exe

if %ERRORLEVEL% NEQ 0 (
    echo Build failed!
    pause
    exit /b 1
)

REM Copy NDI DLL to build directory
copy Processing.NDI.Lib.x64.dll build\ >nul 2>&1

echo Build successful! Executable created at: build\ndi_sender.exe
echo.
echo USAGE:
echo 1. Start: build\ndi_sender.exe
echo 2. Then start LÖVE visualizer 
echo 3. Use 'ndi start' command in LÖVE console
echo.
echo Press any key to start the NDI sender now...
pause >nul

REM Start the NDI sender
echo Starting NDI sender...
cd build
start ndi_sender.exe
cd ..

echo NDI sender started in background.
echo Now start LÖVE and use console command: ndi start
pause
