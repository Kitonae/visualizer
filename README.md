# LÖVE Visualizer with NDI Streaming

A real-time shader visualizer built with LÖVE 2D (Love2D) that includes NDI (Network Device Interface) streaming capability.

## Features

- **Real-time Shader Rendering**: Multiple beautiful shaders including kaleidoscope, water waves, animated lines, and mono lines
- **NDI Streaming**: Stream your visuals over the network using NDI protocol
- **Interactive Controls**: Switch between shaders and control NDI streaming with simple keyboard shortcuts
- **Multiple NDI Modes**: Supports both direct FFI integration and fallback modes

## Requirements

- LÖVE 2D 11.5 or later
- NDI Tools 6 (for NDI streaming functionality)
- Windows (current implementation)

## Installation

1. Install [LÖVE 2D](https://love2d.org/)
2. Install [NDI Tools](https://ndi.tv/tools/) from NewTek
3. Clone or download this project
4. Run with `love .` from the project directory

## Controls

- **Tab**: Switch between shaders
- **1-4**: Direct shader selection
- **N**: Toggle NDI streaming on/off
- **`** (backtick): Toggle debug console
- **Q**: Quit application

## Debug Console

The visualizer includes a powerful debug console that can be toggled with the backtick (`) key. The console provides:

### Console Features
- **Command execution** with history (up/down arrows)
- **Real-time logging** with timestamps and color coding
- **NDI control** commands
- **Shader management** commands  
- **System information** and diagnostics

### Console Commands
- `help` - Show available commands
- `clear` - Clear console output
- `ndi` - NDI commands:
  - `ndi status` - Show NDI status
  - `ndi start` - Start NDI streaming
  - `ndi stop` - Stop NDI streaming
- `shader` - Shader commands:
  - `shader list` - List available shaders
  - `shader switch <num>` - Switch to shader number
- `fps` - Show current frame rate
- `version` - Show LÖVE version info
- `quit` - Exit application

### Console Navigation
- **Enter**: Execute command
- **Up/Down arrows**: Navigate command history
- **Left/Right arrows**: Move cursor in command line
- **Home/End**: Jump to start/end of line
- **Backspace/Delete**: Edit command text
- **Escape**: Hide console

## NDI Streaming

The visualizer supports NDI streaming in multiple modes:

### FFI Mode (Preferred)
- Direct integration with NDI library using LuaJIT FFI
- Low latency, high performance
- Automatically selected when NDI library is available

### Usage

1. Start the visualizer: `love .`
2. Press **N** to start NDI streaming
3. The NDI source will appear as "LÖVE Visualizer" on your network
4. Use any NDI receiver (OBS Studio, vMix, etc.) to receive the stream

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

The NDI integration uses a modular approach:

- `ndi.lua`: Main NDI module with FFI integration
- `ndi_simple.lua`: Fallback implementation using external processes
- Automatic fallback between modes based on availability

### Performance

- Real-time rendering at 60 FPS
- NDI streaming maintains frame rate
- Optimized canvas-based frame capture

### Network

- NDI source name: "LÖVE Visualizer" (configurable)
- Supports NDI groups for organization
- Compatible with all NDI-enabled software

## Troubleshooting

### NDI Not Working

1. Ensure NDI Tools 6 is installed
2. Check that the NDI runtime DLL is accessible
3. Verify firewall settings allow NDI traffic
4. Check the console output for specific error messages

### Performance Issues

1. Reduce window size for better performance
2. Close other applications using NDI
3. Check network bandwidth if streaming over WiFi

### Common Error Messages

- **"NDI initialization failed"**: NDI library not found or incompatible version
- **"FFI NDI initialization failed"**: Falling back to simple mode
- **"FFmpeg not found"**: Install FFmpeg for simple mode fallback

## File Structure

```
visualizer/
├── main.lua              # Main application
├── ndi.lua               # NDI FFI integration
├── ndi_simple.lua        # NDI fallback implementation
├── console.lua           # Debug console system
├── conf.lua              # LÖVE configuration
├── forest.png            # Background image
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
3. Test with both NDI modes
4. Submit pull request

### NDI API Reference

The implementation uses standard NDI SDK functions:
- `NDIlib_initialize()`: Initialize NDI
- `NDIlib_send_create()`: Create sender
- `NDIlib_send_send_video_v2()`: Send video frames
- `NDIlib_send_destroy()`: Cleanup sender
- `NDIlib_destroy()`: Cleanup NDI

## License

This project is open source. NDI is a trademark of Vizrt NDI AB.

## Credits

- Built with LÖVE 2D
- NDI technology by Vizrt NDI AB
- Shader effects inspired by Shadertoy community
