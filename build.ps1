# PowerShell Build Script for LÖVE2D Visualizer
param(
    [switch]$DownloadLove,
    [switch]$Clean
)

$ProjectName = "visualizer"
$BuildDir = "dist"
$LoveVersion = "11.5"
$LoveUrl = "https://github.com/love2d/love/releases/download/$LoveVersion/love-$LoveVersion-win64.zip"

Write-Host "Building LÖVE2D Visualizer..." -ForegroundColor Green

# Clean previous build
if ($Clean -or (Test-Path $BuildDir)) {
    Write-Host "Cleaning previous build..." -ForegroundColor Yellow
    Remove-Item $BuildDir -Recurse -Force -ErrorAction SilentlyContinue
}

# Create build directory
New-Item -ItemType Directory -Path $BuildDir -Force | Out-Null

# Create temporary directory for .love file
$TempDir = "temp_build"
if (Test-Path $TempDir) {
    Remove-Item $TempDir -Recurse -Force
}
New-Item -ItemType Directory -Path $TempDir -Force | Out-Null

# Copy project files
Write-Host "Copying project files..." -ForegroundColor Blue
$FilesToCopy = @(
    "main.lua",
    "console.lua", 
    "conf.lua",
    "ndi.lua",
    "forest.png",
    "Processing.NDI.Lib.Runtime.x64.dll",
    "Processing.NDI.Lib.x64.dll"
)

foreach ($file in $FilesToCopy) {
    if (Test-Path $file) {
        Copy-Item $file $TempDir -Force
        Write-Host "  Copied: $file" -ForegroundColor Gray
    } else {
        Write-Host "  Warning: $file not found" -ForegroundColor Yellow
    }
}

# Copy shaders directory
if (Test-Path "shaders") {
    Copy-Item "shaders" $TempDir -Recurse -Force
    Write-Host "  Copied: shaders/" -ForegroundColor Gray
}

# Copy NDI sender executable
if (Test-Path "build\ndi_sender.exe") {
    Copy-Item "build\ndi_sender.exe" $TempDir -Force
    Write-Host "  Copied: ndi_sender.exe" -ForegroundColor Gray
}

# Create .love file
Write-Host "Creating .love file..." -ForegroundColor Blue
$ZipFile = "$BuildDir\$ProjectName.zip"
$LoveFile = "$BuildDir\$ProjectName.love"
Compress-Archive -Path "$TempDir\*" -DestinationPath $ZipFile -Force
# Rename .zip to .love (they are the same format)
Move-Item $ZipFile $LoveFile -Force

# Clean up temp directory
Remove-Item $TempDir -Recurse -Force

Write-Host ".love file created successfully!" -ForegroundColor Green

# Try to create standalone executable
$LoveExe = $null

# Look for existing LÖVE installation
$LovePaths = @(
    "C:\Program Files\LOVE\love.exe",
    "C:\Program Files (x86)\LOVE\love.exe",
    ".\love.exe"
)

foreach ($path in $LovePaths) {
    if (Test-Path $path) {
        $LoveExe = $path
        break
    }
}

# Try to find love.exe in PATH
if (-not $LoveExe) {
    try {
        $null = Get-Command love.exe -ErrorAction Stop
        $LoveExe = "love.exe"
    } catch {
        # Not in PATH
    }
}

# Download LÖVE2D if requested and not found
if (-not $LoveExe -and $DownloadLove) {
    Write-Host "Downloading LÖVE2D..." -ForegroundColor Blue
    $LoveZip = "$BuildDir\love.zip"
    
    try {
        Invoke-WebRequest -Uri $LoveUrl -OutFile $LoveZip -UseBasicParsing
        Expand-Archive -Path $LoveZip -DestinationPath "$BuildDir\love_temp" -Force
        
        # Find love.exe in extracted files
        $ExtractedLove = Get-ChildItem "$BuildDir\love_temp" -Recurse -Name "love.exe" | Select-Object -First 1
        if ($ExtractedLove) {
            $LoveExe = "$BuildDir\love_temp\$ExtractedLove"
        }
        
        Remove-Item $LoveZip -Force
    } catch {
        Write-Host "Failed to download LÖVE2D: $_" -ForegroundColor Red
    }
}

# Create standalone executable
if ($LoveExe -and (Test-Path $LoveExe)) {
    Write-Host "Creating standalone executable..." -ForegroundColor Blue
    $ExeFile = "$BuildDir\$ProjectName.exe"
    
    # Read both files as bytes and combine them
    $LoveBytes = [System.IO.File]::ReadAllBytes($LoveExe)
    $GameBytes = [System.IO.File]::ReadAllBytes($LoveFile)
    $CombinedBytes = $LoveBytes + $GameBytes
    [System.IO.File]::WriteAllBytes($ExeFile, $CombinedBytes)
    
    if (Test-Path $ExeFile) {
        Write-Host "Standalone executable created: $ExeFile" -ForegroundColor Green
        
        # Copy required DLLs to build directory
        Write-Host "Copying required DLLs..." -ForegroundColor Blue
        $DllFiles = @(
            "Processing.NDI.Lib.Runtime.x64.dll",
            "Processing.NDI.Lib.x64.dll"
        )
        
        foreach ($dll in $DllFiles) {
            if (Test-Path $dll) {
                Copy-Item $dll $BuildDir -Force
                Write-Host "  Copied: $dll" -ForegroundColor Gray
            }
        }
        
        # Copy NDI sender
        if (Test-Path "build\ndi_sender.exe") {
            Copy-Item "build\ndi_sender.exe" $BuildDir -Force
            Write-Host "  Copied: ndi_sender.exe" -ForegroundColor Gray
        }
    } else {
        Write-Host "Failed to create executable" -ForegroundColor Red
    }
    
    # Clean up LÖVE temp files
    if (Test-Path "$BuildDir\love_temp") {
        Remove-Item "$BuildDir\love_temp" -Recurse -Force
    }
} else {
    Write-Host "LÖVE2D executable not found." -ForegroundColor Yellow
    Write-Host "To create a standalone executable:" -ForegroundColor Yellow
    Write-Host "1. Run this script with -DownloadLove parameter, or" -ForegroundColor Yellow
    Write-Host "2. Download LÖVE2D manually from https://love2d.org/" -ForegroundColor Yellow
    Write-Host "3. Extract love.exe and run:" -ForegroundColor Yellow
    Write-Host "   Get-Content love.exe,dist\\$ProjectName.love -Encoding Byte | Set-Content dist\\$ProjectName.exe -Encoding Byte" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "Build complete! Files in ${BuildDir}:" -ForegroundColor Green
Get-ChildItem $BuildDir | ForEach-Object { Write-Host "  $($_.Name)" -ForegroundColor Gray }

Write-Host ""
Write-Host "Usage:" -ForegroundColor Cyan
Write-Host "  Run $ProjectName.love with LÖVE2D installed, or" -ForegroundColor Cyan
Write-Host "  Run $ProjectName.exe as standalone (if created)" -ForegroundColor Cyan
