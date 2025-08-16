# Build Dependencies and Setup

This document explains how to set up the build environment and dependencies for the LÖVE2D Visualizer.

## Required Dependencies

### NDI SDK
The project requires the NDI SDK libraries which are not included in the repository due to their size and licensing. 

**To obtain NDI SDK:**
1. Download the NDI SDK from [NDI Developer Portal](https://ndi.video/for-developers/)
2. Extract the following files to the project root:
   - `Processing.NDI.Lib.Runtime.x64.dll`
   - `Processing.NDI.Lib.x64.dll`

### LÖVE2D (for development)
- Download from [love2d.org](https://love2d.org/)
- The build scripts can automatically download LÖVE2D if needed

## Build Process

### Quick Build
```bash
# Create .love file only
.\build.bat

# Create standalone executable (auto-downloads LÖVE2D)
powershell -ExecutionPolicy Bypass -File .\build.ps1 -DownloadLove

# Create deployment package
.\package.bat
```

### Manual Build
1. Ensure NDI DLLs are in place
2. Build NDI sender: `.\build_ndi.bat`
3. Run build script: `.\build.bat`
4. Optionally create executable: `.\create_exe.bat`

## Development

### Running the Project
```bash
# With LÖVE2D installed
love .

# Or with console output
love . --console
```

### Building NDI Sender
The NDI sender component needs to be compiled:
```bash
.\build_ndi.bat
```

This creates `build/ndi_sender.exe` which handles the actual NDI streaming.

## Distribution Files

After building, these files are created in `dist/`:
- `visualizer.exe` - Standalone executable
- `visualizer.love` - LÖVE2D game file
- `ndi_sender.exe` - NDI streaming component
- `Processing.NDI.Lib.Runtime.x64.dll` - NDI runtime
- `Processing.NDI.Lib.x64.dll` - NDI library
- `README.txt` - End-user documentation

## Notes

- Binary files (DLLs, executables) are not tracked in git
- Download NDI SDK separately for legal compliance
- Build scripts handle most dependency management automatically
- The project works without NDI if libraries are missing (graceful fallback)
