@echo off
echo Creating standalone executable from .love file...

set PROJECT_NAME=visualizer
set BUILD_DIR=dist

:: Check if the .love file exists
if not exist "%BUILD_DIR%\%PROJECT_NAME%.love" (
    echo Error: %PROJECT_NAME%.love not found in %BUILD_DIR%\
    echo Please run build.bat first to create the .love file.
    pause
    exit /b 1
)

:: Try to find LÖVE2D installation
set LOVE_EXE=
if exist "C:\Program Files\LOVE\love.exe" set LOVE_EXE=C:\Program Files\LOVE\love.exe
if exist "C:\Program Files (x86)\LOVE\love.exe" set LOVE_EXE=C:\Program Files (x86)\LOVE\love.exe

:: Try to find love.exe in PATH
if "%LOVE_EXE%"=="" (
    where love.exe >nul 2>&1
    if !errorlevel!==0 set LOVE_EXE=love.exe
)

if "%LOVE_EXE%"=="" (
    echo Error: Could not find love.exe
    echo Please either:
    echo 1. Install LÖVE2D from https://love2d.org/
    echo 2. Or manually download love.exe and place it in this directory
    echo 3. Then run: copy /b love.exe+%BUILD_DIR%\%PROJECT_NAME%.love %BUILD_DIR%\%PROJECT_NAME%.exe
    pause
    exit /b 1
)

:: Create standalone executable
echo Found LÖVE2D at: %LOVE_EXE%
echo Creating standalone executable...
copy /b "%LOVE_EXE%"+"%BUILD_DIR%\%PROJECT_NAME%.love" "%BUILD_DIR%\%PROJECT_NAME%.exe"

if exist "%BUILD_DIR%\%PROJECT_NAME%.exe" (
    echo.
    echo Success! Standalone executable created: %BUILD_DIR%\%PROJECT_NAME%.exe
    echo.
    echo Note: The executable will need the following DLLs in the same directory:
    echo - Processing.NDI.Lib.Runtime.x64.dll
    echo - Processing.NDI.Lib.x64.dll
    echo - ndi_sender.exe
    echo These are already included in the build.
) else (
    echo Error: Failed to create executable
)

pause
