# LÖVE Visualizer with NDI Streaming

A real-time shader visualizer built with LÖVE 2D (Love2D) that includes NDI (Network Device Interface) streaming capability using a managed C++ subprocess architecture.

## Features

- **Real-time Shader Rendering**: Multiple beautiful shaders including kaleidoscope, water waves, animated lines, and mono lines
- **Managed NDI Streaming**: Automatic headless C++ subprocess for NDI streaming
- **Interactive Controls**: Switch between shaders and control NDI streaming with simple keyboard shortcuts
- **Process Management**: Automatically spawns and manages NDI sender process

## Requirements

- LÖVE 2D 11.5 or later
- NDI Tools 6 (for NDI streaming functionality)
- Windows (current implementation)
- Visual Studio Build Tools (for building NDI sender)

## Installation

1. Install [LÖVE 2D](https://love2d.org/)
2. Install [NDI Tools](https://ndi.tv/tools/) from NewTek
3. Clone or download this project
4. Build the NDI sender: `.\build_ndi.bat`
5. Run with `love . --console` from the project directory

## Controls

- **Tab**: Switch between shaders
- **1-4**: Direct shader selection
- **N**: Toggle NDI streaming on/off (automatically manages subprocess)
- **`** (backtick): Toggle debug console
- **Q**: Quit application (automatically stops subprocess)

## Architecture

### NDI Subprocess Management

The visualizer uses a sophisticated subprocess architecture:

- **Main LÖVE App**: Handles rendering and user interface
- **C++ NDI Sender**: Headless subprocess for NDI streaming (`build/ndi_sender.exe`)
- **Shared Memory**: High-performance frame transfer between processes
- **Automatic Management**: Subprocess is spawned when streaming starts and killed when stopped

### Process Flow

1. User presses **N** to start streaming
2. LÖVE app spawns `ndi_sender.exe` as headless subprocess
3. Shared memory connection established
4. Frames rendered to canvas and copied to shared memory
5. C++ process reads frames and streams via NDI
6. When streaming stops, subprocess is automatically terminated

## Debug Console

The visualizer includes a powerful debug console that can be toggled with the backtick (`) key. The console provides:

### Console Features
- **Command execution** with history (up/down arrows)
- **Real-time logging** with timestamps and color coding
- **NDI process monitoring** and control
- **Shader management** commands  
- **System information** and diagnostics

### Console Commands
- `help` - Show available commands
- `clear` - Clear console output
- `ndi` - NDI commands:
  - `ndi status` - Show NDI and subprocess status
  - `ndi start` - Start NDI streaming (spawns subprocess)
  - `ndi stop` - Stop NDI streaming (terminates subprocess)
- `shader` - Shader commands:
  - `shader list` - List available shaders
  - `shader switch <num>` - Switch to shader number
- `fps` - Show current frame rate
- `version` - Show LÖVE version info
- `quit` - Exit application

## NDI Streaming

### Managed Subprocess Architecture

The NDI streaming uses a managed C++ subprocess approach:

- **Shared Memory Communication**: High-performance frame transfer
- **Automatic Process Management**: No manual subprocess handling required
- **Headless Operation**: NDI sender runs without visible windows
- **Graceful Shutdown**: Proper cleanup when stopping or exiting

### Building the NDI Sender

Before using NDI streaming, build the C++ sender:

```bash
.\build_ndi.bat
```

This creates `build/ndi_sender.exe` which is automatically managed by the main app.

### Usage

1. Build the NDI sender: `.\build_ndi.bat`
2. Start the visualizer: `love . --console`
3. Press **N** to start NDI streaming (automatically spawns subprocess)
4. The NDI source will appear as "LÖVE NDI Stream" on your network
5. Use any NDI receiver (OBS Studio, vMix, etc.) to receive the stream
6. Press **N** again to stop streaming (automatically terminates subprocess)

## Shaders

### Available Shaders

1. **Kaleidoscope** - Colorful geometric patterns
2. **Water Waves** - Animated wave patterns
3. **Animated Lines** - Dynamic line effects
4. **Mono Lines** - Monochrome line patterns with background

### Adding Custom Shaders

1. Create a new `.frag` file in the `shaders/` directory
2. Add the shader to the `shaders` table in `main.lua`
3. Specify whether it has a background with the `hasBackground` property

## Technical Details

### NDI Integration Architecture

The NDI integration uses a managed subprocess approach:

- `ndi.lua`: Main NDI module with subprocess management and FFI for shared memory
- `ndi_sender.cpp`: C++ headless NDI sender subprocess
- `build_ndi.bat`: Build script for the C++ component
- Automatic process lifecycle management

### Performance

- Real-time rendering at 60 FPS
- NDI streaming maintains frame rate via subprocess
- Optimized shared memory for frame transfer
- Headless subprocess for minimal overhead

### Network

- NDI source name: "LÖVE NDI Stream" (configurable in source)
- Compatible with all NDI-enabled software
- Professional NDI SDK implementation

## Troubleshooting

### Build Issues

1. Ensure Visual Studio Build Tools are installed
2. Check that NDI SDK is installed in the default location
3. Run `.\build_ndi.bat` before first use

### NDI Not Working

1. Ensure NDI Tools 6 is installed
2. Check that `build/ndi_sender.exe` exists (run build script)
3. Verify firewall settings allow NDI traffic
4. Check the console output for subprocess status

### Performance Issues

1. Reduce window size for better performance
2. Close other applications using NDI
3. Check network bandwidth if streaming over WiFi

### Common Error Messages

- **"NDI sender executable not found"**: Run `.\build_ndi.bat` first
- **"Failed to start NDI process"**: Check Visual Studio Build Tools installation
- **"Process not running"**: Subprocess crashed, check NDI SDK installation

## File Structure

```
visualizer/
├── main.lua              # Main LÖVE application
├── ndi.lua               # NDI subprocess management
├── ndi_sender.cpp        # C++ NDI sender subprocess
├── console.lua           # Debug console system
├── conf.lua              # LÖVE configuration
├── forest.png            # Background image
├── ndi_fallback.h        # NDI SDK fallback definitions
├── build_ndi.bat         # Build script for C++ component
├── build/                # Build output directory
│   ├── ndi_sender.exe    # Compiled NDI sender
│   └── *.dll             # NDI runtime libraries
├── shaders/              # Shader files
│   ├── kaleidoscope.frag
│   ├── waves.frag
│   ├── lines.frag
│   └── lines_mono.frag
└── README.md            # This file
```

## Development

### Adding New Features

1. Fork the repository
2. Create feature branch
3. Test subprocess management
4. Submit pull request

### Subprocess Architecture

The C++ subprocess uses:
- Windows API for process management
- Shared memory for high-performance frame transfer
- NDI SDK for professional streaming
- Signal handling for graceful shutdown

## License

This project is open source. NDI is a trademark of Vizrt NDI AB.

## Credits

- Built with LÖVE 2D
- NDI technology by Vizrt NDI AB
- Shader effects inspired by Shadertoy community
