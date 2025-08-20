@echo off
echo Building LÖVE2D Visualizer Executable...

:: Set variables
set PROJECT_NAME=visualizer
set BUILD_DIR=dist
set LOVE_VERSION=11.5

:: Create build directory
if exist %BUILD_DIR% rmdir /s /q %BUILD_DIR%
mkdir %BUILD_DIR%

:: Create a temporary directory for the love file contents
mkdir temp_build

:: Copy all necessary files to temp directory
echo Copying project files...
copy main.lua temp_build\
copy console.lua temp_build\
copy conf.lua temp_build\
copy ndi.lua temp_build\
copy forest.png temp_build\
copy logo.png temp_build\
xcopy shaders temp_build\shaders\ /E /I
copy Processing.NDI.Lib.Runtime.x64.dll temp_build\
copy Processing.NDI.Lib.x64.dll temp_build\
copy build\ndi_sender.exe temp_build\

:: Create .love file (zip with .love extension)
echo Creating .love file...
cd temp_build
powershell -Command "Compress-Archive -Path * -DestinationPath ../%BUILD_DIR%/%PROJECT_NAME%.love -Force"
cd ..

:: Clean up temp directory
rmdir /s /q temp_build

echo.
echo Build complete! Files created in %BUILD_DIR%\:
echo - %PROJECT_NAME%.love (LÖVE2D game file)
echo.
echo To create a standalone executable:
echo 1. Download LÖVE2D from https://love2d.org/
echo 2. Extract love.exe from the download
echo 3. Run: copy /b love.exe+%PROJECT_NAME%.love %PROJECT_NAME%.exe
echo.
echo Or use the create_exe.bat script if you have LÖVE2D installed.

pause
