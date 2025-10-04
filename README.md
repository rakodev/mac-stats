# MacStats 📊

A lightweight, native macOS menu bar application that displays real-time CPU and memory usage statistics.

![MacStats Demo](assets/demo.gif)

## Quick Start 🚀

1. **Clone and build:**
   ```bash
   git clone <your-repo-url>
   cd mac-stats
   make run
   ```

2. **The app will appear in your menu bar showing:**
   - CPU usage percentage
   - Memory usage percentage

3. **Click the menu bar item to:**
   - View detailed system information
   - Toggle between light/dark theme
   - Quit the application

## Features ✨

- **Real-time Monitoring**: Live CPU and memory usage displayed in your menu bar
- **Multiple Display Formats**: Choose from compact, detailed, CPU-only, or memory-only views
- **Customizable Refresh Rate**: Set update intervals from 1 to 10 seconds
- **Native macOS Design**: Built with SwiftUI for a clean, modern interface
- **Lightweight**: Minimal resource usage while monitoring your system
- **Menu Bar Only**: Stays out of your way in the dock
- **Interactive Popover**: Click the menu bar item to see detailed statistics
- **Right-click Menu**: Quick access to settings and preferences

## Screenshots 📸

### Menu Bar Display Formats

| Compact | Detailed | CPU Only | Memory Only |
|---------|----------|----------|-------------|
| `CPU 45% MEM 60%` | `CPU 45.2% \| MEM 8.1GB/16.0GB` | `CPU 45%` | `MEM 60%` |

### Detailed Popover View
- Interactive progress bars for CPU and memory usage
- Real-time statistics with formatted memory values
- Settings panel for customizing display format and refresh rate

## Requirements 📋

- **macOS 13.0** or later
- **Xcode 15.0** or later (for building from source)
- **Apple Silicon** or **Intel** Mac

## Installation 🚀

### Option 1: Download Pre-built Binary (Recommended)

1. Go to the [Releases](https://github.com/yourusername/mac-stats/releases) page
2. Download the latest `MacStats.dmg` or `MacStats.zip`
3. If using DMG:
   - Mount the DMG file
   - Drag MacStats.app to your Applications folder
4. If using ZIP:
   - Extract the ZIP file
   - Move MacStats.app to your Applications folder
5. Launch MacStats from Applications or Spotlight

### Option 2: Build from Source

#### Prerequisites

Make sure you have the required tools installed:

```bash
# Check if Xcode command line tools are installed
xcode-select --version

# If not installed, install them:
xcode-select --install

# Optional: Install create-dmg for DMG creation
brew install create-dmg
```

#### Building

1. **Clone the repository:**
   ```bash
   git clone https://github.com/yourusername/mac-stats.git
   cd mac-stats
   ```

2. **Build using the provided scripts:**
   ```bash
   # For release build (creates distributable app)
   make build
   # or
   ./build.sh

   # For development build (quick testing)
   make dev
   # or
   ./dev-build.sh
   ```

3. **Alternative: Build with Xcode:**
   ```bash
   # Open the project in Xcode
   open MacStats.xcodeproj
   
   # Build and run using Xcode (⌘+R)
   ```

4. **Install the built app:**
   ```bash
   # The built app will be in build/export/MacStats.app
   cp -r build/export/MacStats.app /Applications/
   ```

## Usage 💡

### First Launch

1. Launch MacStats from Applications
2. Grant necessary permissions if prompted
3. Look for CPU and memory stats in your menu bar (usually in the top-right area)

### Interacting with MacStats

- **Left Click**: Opens detailed popover with progress bars and settings
- **Right Click**: Opens context menu with display format and refresh rate options
- **Settings**: Customize display format and refresh interval from the popover or context menu

### Display Formats

- **Compact**: `CPU 45% MEM 60%` - Shows both CPU and memory percentages
- **Detailed**: `CPU 45.2% | MEM 8.1GB/16.0GB` - Shows precise values with memory in GB
- **CPU Only**: `CPU 45%` - Shows only CPU usage
- **Memory Only**: `MEM 60%` - Shows only memory usage percentage

### Refresh Intervals

Choose from 1s, 2s, 5s, or 10s refresh rates based on your preference and system performance needs.

## Configuration ⚙️

MacStats automatically saves your preferences. Settings are stored in macOS user defaults and include:

- Display format preference
- Refresh interval setting
- Theme preference (follows system theme by default)

## Troubleshooting 🔧

### Common Issues

**App doesn't appear in menu bar:**
- Make sure you've granted necessary permissions
- Try restarting the app
- Check if the app is running in Activity Monitor

**Inaccurate CPU readings:**
- CPU usage calculations may vary depending on system load
- Try adjusting the refresh interval

**High CPU usage by MacStats itself:**
- Increase the refresh interval to reduce monitoring frequency
- Restart the app if it's consuming excessive resources

**Build errors:**
- Ensure you have Xcode 15.0 or later
- Make sure macOS deployment target is set to 13.0+
- Try cleaning the build folder: `make clean`

### Permission Issues

If MacStats can't access system information:

1. Go to **System Preferences → Security & Privacy → Privacy**
2. Look for relevant permissions and add MacStats if needed
3. Restart the application

### Uninstalling

To completely remove MacStats:

1. Quit the application (right-click menu → Quit)
2. Delete from Applications: `rm -rf /Applications/MacStats.app`
3. Remove preferences: `defaults delete com.macstats.app`

## Development 🛠️

### Project Structure

```
MacStats/
├── MacStats.xcodeproj/          # Xcode project file
├── MacStats/                    # Source code
│   ├── MacStatsApp.swift       # Main app entry point
│   ├── MenuBarController.swift  # Menu bar interface controller
│   ├── SystemMonitor.swift     # System monitoring logic
│   ├── UserPreferences.swift   # Settings and preferences
│   ├── ContentView.swift       # SwiftUI views
│   └── Assets.xcassets/        # App icons and assets
├── build.sh                     # Release build script
├── dev-build.sh                # Development build script
├── Makefile                    # Build automation
└── README.md                   # This file
```

### Building for Distribution

The build script creates:
- Unsigned `.app` bundle
- ZIP archive for distribution
- DMG installer (if `create-dmg` is available)

### Code Signing

For distribution outside the App Store, you'll need to:

1. Get a Developer ID certificate from Apple
2. Update the build scripts to include code signing
3. Notarize the app for Gatekeeper compatibility

### Contributing

1. Fork the repository
2. Create a feature branch: `git checkout -b feature/new-feature`
3. Make your changes and test thoroughly
4. Commit your changes: `git commit -am 'Add new feature'`
5. Push to the branch: `git push origin feature/new-feature`
6. Submit a pull request

## Technical Details 🔍

### System APIs Used

- **CPU Monitoring**: Uses `mach_task_info` and `host_processor_info` APIs
- **Memory Monitoring**: Uses `vm_statistics64` and `mach_task_basic_info` APIs
- **Menu Bar Integration**: NSStatusItem with SwiftUI popover
- **Preferences**: UserDefaults for persistent settings

### Performance

- Lightweight Swift implementation
- Configurable refresh rates to balance accuracy vs. performance
- Efficient memory management with automatic cleanup
- Background thread processing to avoid UI blocking

### Compatibility

- **macOS 13.0+**: Uses modern SwiftUI and Combine frameworks
- **Universal Binary**: Supports both Apple Silicon and Intel Macs
- **Sandboxed**: Designed to work within App Store sandbox restrictions

## License 📄

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Acknowledgments 🙏

- Apple's System Information APIs documentation
- macOS Human Interface Guidelines
- SwiftUI and Combine frameworks

## Support 💬

If you encounter any issues or have questions:

1. Check the [Issues](https://github.com/yourusername/mac-stats/issues) page
2. Create a new issue with detailed information about your problem
3. Include your macOS version and any error messages

---

**Made with ❤️ for the macOS community**