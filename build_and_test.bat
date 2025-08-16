@echo off
echo === NDI C++ Test Build Script ===
echo.

REM Create build directory
if not exist build mkdir build
cd build

REM Run CMake to generate project files
echo Configuring with CMake...
cmake .. -G "Visual Studio 17 2022" -A x64

if %ERRORLEVEL% neq 0 (
    echo ERROR: CMake configuration failed
    pause
    exit /b 1
)

REM Build the project
echo.
echo Building project...
cmake --build . --config Release

if %ERRORLEVEL% neq 0 (
    echo ERROR: Build failed
    pause
    exit /b 1
)

REM Copy NDI DLL if it exists in parent directory
if exist "..\Processing.NDI.Lib.x64.dll" (
    echo Copying NDI DLL...
    copy "..\Processing.NDI.Lib.x64.dll" "Release\" >nul
)

echo.
echo Build successful! Running test program...
echo.

REM Run the test program
cd Release
ndi_test.exe 150 "C++ NDI Professional Test"

echo.
echo Test completed. Press any key to exit.
pause >nul
