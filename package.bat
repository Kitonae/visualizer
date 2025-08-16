@echo off
echo Creating deployment package...

set PROJECT_NAME=visualizer
set VERSION=1.0
set DEPLOY_NAME=%PROJECT_NAME%_v%VERSION%_win64

:: Create deployment directory
if exist %DEPLOY_NAME% rmdir /s /q %DEPLOY_NAME%
mkdir %DEPLOY_NAME%

:: Copy all distribution files
echo Copying files...
copy dist\*.* %DEPLOY_NAME%\

:: Create a simple batch launcher
echo @echo off > %DEPLOY_NAME%\run.bat
echo echo Starting LÖVE2D Visualizer... >> %DEPLOY_NAME%\run.bat
echo .\visualizer.exe >> %DEPLOY_NAME%\run.bat

:: Create zip package
echo Creating zip package...
powershell -Command "Compress-Archive -Path %DEPLOY_NAME% -DestinationPath %DEPLOY_NAME%.zip -Force"

echo.
echo Deployment package created: %DEPLOY_NAME%.zip
echo Contents:
dir %DEPLOY_NAME%

echo.
echo Package is ready for distribution!
pause
