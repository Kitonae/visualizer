@echo off
setlocal enableextensions enabledelayedexpansion

echo === Building capture_sender (Windows Graphics Capture) ===

REM Ensure cl.exe is available, otherwise try to call VS 2022 vcvarsall
where cl.exe >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
  echo Visual Studio compiler not found in PATH. Trying to locate VS 2022...
  if exist "C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvarsall.bat" (
    call "C:\Program Files\Microsoft Visual Studio\2022\Community\VC\Auxiliary\Build\vcvarsall.bat" x64
  ) else if exist "C:\Program Files\Microsoft Visual Studio\2022\Professional\VC\Auxiliary\Build\vcvarsall.bat" (
    call "C:\Program Files\Microsoft Visual Studio\2022\Professional\VC\Auxiliary\Build\vcvarsall.bat" x64
  ) else if exist "C:\Program Files\Microsoft Visual Studio\2022\Enterprise\VC\Auxiliary\Build\vcvarsall.bat" (
    call "C:\Program Files\Microsoft Visual Studio\2022\Enterprise\VC\Auxiliary\Build\vcvarsall.bat" x64
  ) else (
    echo Visual Studio 2022 not found. Please run from a Developer Command Prompt.
    exit /b 1
  )
)

if not exist build mkdir build

set SRC=capture_sender.cpp
set OUT=build\capture_sender.exe

echo Compiling %SRC% ...
cl /nologo /std:c++20 /EHsc /permissive- %SRC% ^
  /link windowsapp.lib d3d11.lib dxgi.lib user32.lib psapi.lib /OUT:%OUT%

if %ERRORLEVEL% NEQ 0 (
  echo Build failed.
  exit /b 1
)

echo Build succeeded: %OUT%
exit /b 0
