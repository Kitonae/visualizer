@echo off
echo === NDI C++ Test - Direct Compilation ===
echo.

REM Find Visual Studio build tools
set "VS_PATH="
for /d %%i in ("C:\Program Files\Microsoft Visual Studio\2022\*") do (
    if exist "%%i\VC\Auxiliary\Build\vcvars64.bat" (
        set "VS_PATH=%%i\VC\Auxiliary\Build\vcvars64.bat"
        goto :found_vs
    )
)

:found_vs
if "%VS_PATH%"=="" (
    echo ERROR: Visual Studio 2022 not found
    echo Please install Visual Studio 2022 with C++ tools
    pause
    exit /b 1
)

echo Found Visual Studio at: %VS_PATH%
echo.

REM Setup Visual Studio environment
call "%VS_PATH%"

REM Create build directory
if not exist build mkdir build

REM Try to find NDI SDK
set "NDI_INCLUDE="
set "NDI_LIB="

if exist "C:\Program Files\NDI\NDI 6 SDK\Include\Processing.NDI.Lib.h" (
    set "NDI_INCLUDE=C:\Program Files\NDI\NDI 6 SDK\Include"
    set "NDI_LIB=C:\Program Files\NDI\NDI 6 SDK\Lib\x64\Processing.NDI.Lib.x64.lib"
    echo Using NDI SDK headers and library
) else (
    echo NDI SDK not found - using local DLL and fallback headers
    set "NDI_INCLUDE=."
    set "NDI_LIB=Processing.NDI.Lib.x64.dll"
)

echo NDI Include: %NDI_INCLUDE%
echo NDI Library: %NDI_LIB%
echo.

REM Compile the test program
echo Compiling ndi_test.cpp...
cl.exe /EHsc /std:c++17 /I"%NDI_INCLUDE%" ndi_test.cpp /Fe:build\ndi_test.exe /link "%NDI_LIB%"

if %ERRORLEVEL% neq 0 (
    echo ERROR: Compilation failed
    pause
    exit /b 1
)

REM Copy NDI DLL to build directory
if exist "Processing.NDI.Lib.x64.dll" (
    echo Copying NDI DLL...
    copy "Processing.NDI.Lib.x64.dll" "build\" >nul
)

echo.
echo Compilation successful! Running test program...
echo.

REM Run the test
cd build
ndi_test.exe 150 "C++ NDI Professional Test"

echo.
echo Test completed. Check NDI Studio Monitor for results.
pause
