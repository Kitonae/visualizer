# WARP.md

This file provides guidance to WARP (warp.dev) when working with code in this repository.

## Overview

This is a real-time shader visualizer built with LÖVE 2D (Love2D) that includes NDI (Network Device Interface) streaming capability. The project combines Lua-based LÖVE 2D for graphics rendering with C++ for NDI streaming integration, using shared memory for efficient frame transfer.

## Common Development Commands

### Running the Application
```bash
# Run the LÖVE visualizer (requires LÖVE 2D 11.5+)
love .

# Run with specific window size
love . --width 1920 --height 1080
```

### Building NDI Components
```bash
# Build NDI sender (C++) - automated script
build_ndi.bat

# Build using CMake (alternative approach)
build_and_test.bat

# Manual CMake build
mkdir build
cd build
cmake .. -G "Visual Studio 17 2022" -A x64
cmake --build . --config Release
```

### Testing
```bash
# Test NDI C++ implementation
build\ndi_test.exe 150 "Test Source Name"

# Run hybrid NDI test
test_hybrid.bat

# Test NDI discovery
test_ndi_discovery.bat
```

### Development Workflow
```bash
# 1. Build NDI sender first
build_ndi.bat

# 2. Start LÖVE visualizer
love .

# 3. Use console commands (press ` key)
# In console: ndi start
```

## Code Architecture

### Core Components

1. **main.lua** - Primary LÖVE application entry point
   - Manages shader loading and switching
   - Handles user input and keyboard shortcuts
   - Coordinates NDI streaming with frame rendering
   - Implements dual rendering (screen + NDI canvas)

2. **ndi.lua** - NDI integration using shared memory + C++
   - Uses LuaJIT FFI for Windows shared memory APIs
   - Communicates with separate C++ NDI sender process
   - Transfers frame data via `SharedFrameData` structure
   - Handles timing and frame numbering

3. **console.lua** - Debug console system
   - Interactive command-line interface (toggle with `)
   - Real-time logging with color coding
   - Command history and editing support
   - NDI control commands and diagnostics

4. **ndi_sender.cpp** - C++ NDI streaming backend
   - Professional NDI implementation using official SDK
   - Shared memory reader for frame data from Lua
   - UYVY format with proper NTSC timing (59.94fps)
   - Connection monitoring and frame validation

### Architecture Patterns

**Dual-Process Design**: The application uses a hybrid architecture where LÖVE 2D handles graphics/UI and a separate C++ process handles NDI streaming. This separation provides:
- Better NDI SDK integration
- Fault isolation
- Performance optimization

**Shared Memory Communication**: Frame data transfer between processes uses Windows shared memory with a structured protocol:
```c
typedef struct {
    uint32_t magic;           // 0xDEADBEEF validation
    uint32_t width, height;
    uint32_t format;          // RGBA/BGRA/UYVY
    uint32_t frame_number;
    uint64_t timestamp_us;
    uint32_t data_size;
    uint8_t pixel_data[];
} SharedFrameData;
```

**Shader System**: Hot-swappable fragment shaders with metadata:
- Background support detection (`hasBackground`)
- Uniform parameter management (time, resolution, mouse)
- Palette animation system for complex shaders

### Key Design Decisions

1. **Console Integration**: All print() calls are intercepted and displayed in the debug console for unified logging
2. **Canvas-based NDI**: Uses separate canvas for NDI to avoid UI elements in stream
3. **Graceful Fallbacks**: NDI failure doesn't crash the visualizer - creates dummy NDI module
4. **Professional NDI**: C++ component follows NDI best practices (no video clocking, proper timing)

## Project Structure

```
visualizer/
├── main.lua              # Main LÖVE application
├── ndi.lua               # Lua NDI integration (shared memory)
├── console.lua           # Debug console system
├── conf.lua              # LÖVE configuration (1920x1080)
├── ndi_sender.cpp        # C++ NDI streaming backend
├── ndi_test.cpp          # NDI testing utility
├── shaders/              # Fragment shader files
│   ├── kaleidoscope.frag
│   ├── waves.frag
│   ├── lines.frag
│   └── lines_mono.frag
├── build*.bat            # Build automation scripts
├── CMakeLists.txt        # CMake configuration
└── Processing.NDI.Lib.x64.dll  # NDI runtime library
```

## Development Notes

### Console Commands
- `help` - Show available commands
- `ndi status/start/stop` - Control NDI streaming
- `shader list/switch <n>` - Manage shaders
- `fps`, `version`, `debug` - System info

### Shader Development
- Add `.frag` files to `shaders/` directory
- Update `shaders` table in `main.lua`
- Specify `hasBackground` property for transparency support
- Use standard uniforms: `time`, `resolution`, `mouse`

### NDI Integration
- Requires NDI Tools 6 and Visual Studio 2022
- C++ sender must be running before starting LÖVE
- Shared memory name: `"LOVE_NDI_SHARED_FRAME"`
- Maximum frame size: 8MB buffer

### Controls
- **Tab**: Switch shaders
- **1-4**: Direct shader selection
- **N**: Toggle NDI streaming
- **`**: Toggle debug console
- **Q**: Quit application

## Requirements

- LÖVE 2D 11.5 or later
- NDI Tools 6 (for NDI functionality)
- Visual Studio 2022 (for C++ components)
- Windows (current implementation)
