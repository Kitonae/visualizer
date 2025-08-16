@echo off
echo === Building NDI C++ Test Program ===

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
echo Building with Visual Studio compiler...

REM Create output directory
if not exist "build" mkdir build

REM Compile the program
cl.exe /EHsc /std:c++17 ^
    /I%NDI_INCLUDE% ^
    ndi_cpp_test.cpp ^
    /link %NDI_LIB%\Processing.NDI.Lib.x64.lib ^
    /OUT:build\ndi_cpp_test.exe

if %ERRORLEVEL% NEQ 0 (
    echo Build failed!
    pause
    exit /b 1
)

REM Copy NDI DLL to build directory
copy Processing.NDI.Lib.x64.dll build\ >nul 2>&1

echo Build successful! Executable created at: build\ndi_cpp_test.exe
echo.
echo Press any key to run the test program...
pause >nul

REM Run the test
cd build
ndi_cpp_test.exe
cd ..

echo.
echo Test completed. Press any key to exit...
pause >nul
