<div align="center">
  
  <img src="docs/assets/ricebarmac-icon.png" alt="RiceBarMac Icon" width="128" height="128">
  
  # RiceBarMac
  
  ### Lightning-fast macOS menu bar app for effortless desktop profile switching
  
  [![macOS](https://img.shields.io/badge/macOS-14.0+-blue.svg)](https://www.apple.com/macos/)
  [![Swift](https://img.shields.io/badge/Swift-5.9+-orange.svg)](https://swift.org/)
  [![Xcode](https://img.shields.io/badge/Xcode-15.0+-blue.svg)](https://developer.apple.com/xcode/)
  [![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
  [![Platform](https://img.shields.io/badge/Platform-macOS-lightgrey.svg)](https://www.apple.com/macos/)
  
</div>

> **⚠️ BETA WARNING**: RiceBarMac is currently in beta. Please backup your `.config` directory and any important configuration files before use. The author is not responsible for any data loss or system damage. Use at your own risk.

## 🚀 Overview

RiceBarMac is a powerful macOS menu bar application that manages your **desktop rice configurations** by creating symbolic links from profile directories to your actual system locations. It's designed for developers and power users who maintain multiple aesthetic setups and want to switch between them instantly using keyboard shortcuts.

## 🔧 How It Works

RiceBarMac operates as a **symlink-based overlay system** that manages your rice configurations:

### 🎯 **Core Functionality**

-   **Menu Bar Integration**: Runs silently in your menu bar with a rice bowl icon
-   **Profile Management**: Stores rice configurations in `~/.ricebarmac/profiles/`
-   **Symlink Management**: Creates symbolic links from profile files to your actual system locations
-   **Hotkey Registration**: Uses macOS global hotkey system for instant switching

### 📁 **Profile Structure**

```
~/.ricebarmac/profiles/
├── Work/
│   ├── home/                    # Overlays your home directory
│   │   └── .config/            # Symlinked to ~/.config/
│   │       ├── alacritty/
│   │       ├── nvim/
│   │       └── tmux/
│   ├── vscode/                 # VS Code settings
│   │   ├── settings.json
│   │   ├── keybindings.json
│   │   └── extensions.txt
│   ├── wallpaper.jpg
│   ├── profile.json            # Profile configuration
│   └── startup.sh              # Script to run when profile is applied
└── Gaming/
    ├── home/.config/...
    ├── wallpaper.png
    └── profile.json
```

### ⚡ **Profile Application Process**

1. **User triggers shortcut** (e.g., ⌘+1)
2. **RiceBarMac loads profile** from `~/.ricebarmac/profiles/`
3. **Applies wallpaper** using macOS APIs
4. **Creates symbolic links** from profile files to your actual system locations
5. **Symlinks IDE settings** (VS Code, Cursor, etc.)
6. **Runs startup scripts** if configured
7. **Provides visual feedback** in menu bar

### 🔄 **File Replacement Methods**

-   **Direct Symlinks**: Specific file mappings defined in `profile.json`
-   **Home Overlay**: Automatic symlinking of `home/` directory contents
-   **IDE Integration**: VS Code, Cursor, Alacritty, iTerm2 support
-   **Backup System**: Creates backups of existing files before creating symlinks

## ✨ Features

### 🎨 **Profile Management**

-   **Menu Bar Interface**: Clean, accessible menu bar app with rice bowl icon
-   **Multiple Profiles**: Create and manage unlimited rice profiles
-   **Instant Switching**: Switch between profiles with keyboard shortcuts or menu clicks
-   **Profile Ordering**: Customize the order of profiles in the menu via `order` property

### 🔧 **File Management**

-   **Config File Symlinking**: Create symbolic links from `.config` directories and files to your system
-   **Home Directory Overlay**: Automatic symlinking of `home/` directory contents
-   **IDE Integration**: VS Code, Cursor, Alacritty, iTerm2 configuration support

### 🖼️ **Visual Customization**

-   **Wallpaper Switching**: Change desktop wallpapers instantly with drag-and-drop or file picker
-   **Multiple Formats**: Support for PNG, JPG, HEIC, GIF, BMP, TIFF formats
-   **Terminal Themes**: Alacritty, Terminal.app, iTerm2 theme switching
-   **IDE Themes**: VS Code and Cursor theme management via settings.json

### ⌨️ **Keyboard Shortcuts**

-   **Profile Shortcuts**: Direct profile switching (⌘+1, ⌘+2, etc.) for up to 9 profiles
-   **Navigation Shortcuts**: Next/Previous profile cycling, reload profiles, open folder

## 📦 Installation

### Prerequisites

-   macOS 14.0 or later
-   Xcode 15.0+ (for development)

### Quick Install via Homebrew (Recommended)

```bash
# Add the tap first
brew tap mateocerquetella/ricebarmac

# Install RiceBarMac
brew install --cask ricebarmac
```

### Manual Installation

#### Option 1: Download Pre-built Release

1. Download the latest `RiceBarMac.zip` from [Releases](https://github.com/MateoCerquetella/RiceBarMac/releases)
2. Extract and move `RiceBarMac.app` to `/Applications/`
3. Launch the app - it will appear in your menu bar

#### Option 2: Build from Source

1. **Clone the repository**

    ```bash
    git clone https://github.com/MateoCerquetella/RiceBarMac.git
    cd RiceBarMac
    ```

2. **Install dependencies**

    ```bash
    # Install XcodeGen if you don't have it
    brew install xcodegen

    # Generate Xcode project
    xcodegen generate
    ```

3. **Build and run**

    ```bash
    # Build the project
    xcodebuild -project RiceBarMac.xcodeproj -scheme RiceBarMac -configuration Release build

    # Open the app
    open /Users/$(whoami)/Library/Developer/Xcode/DerivedData/RiceBarMac-*/Build/Products/Release/RiceBarMac.app
    ```

### Development Setup

1. **Open in Xcode**

    ```bash
    open RiceBarMac.xcodeproj
    ```

2. **Run the project**
    - Select your target device (macOS)
    - Press ⌘+R to build and run

## 🛠️ Configuration

### 📁 Profile Structure

Profiles are stored at `~/.ricebarmac/profiles/<ProfileName>/` with this structure:

```
~/.ricebarmac/profiles/
├── Work/
│   ├── wallpaper.jpg
│   └── profile.json
└── Gaming/
    ├── wallpaper.png
    └── profile.json
```

### Profile Configuration

```json
{
    "name": "Work Setup",
    "wallpaper": "wallpaper.jpg",
    "order": 1,
    "hotkey": "cmd+1",
    "terminal": {
        "kind": "alacritty",
        "theme": "alacritty.yml"
    },
    "ide": {
        "kind": "vscode",
        "theme": "vscode/settings.json",
        "extensions": ["ms-vscode.vscode-typescript-next"]
    },
    "replacements": [
        {
            "source": "home/.config/nvim",
            "destination": "~/.config/nvim"
        },
        {
            "source": "home/.config/tmux",
            "destination": "~/.config/tmux"
        }
    ],
    "startupScript": "startup.sh"
}
```

## 🐛 Troubleshooting

### Common Issues

**Shortcuts not working?**

-   Check if the shortcut conflicts with other apps
-   Ensure the app has accessibility permissions
-   Try restarting the app

**Profiles not switching?**

-   Verify file paths in your configuration
-   Check console logs for error messages
-   Ensure proper file permissions

**App not launching?**

-   Check if it's blocked by Gatekeeper
-   Verify macOS version compatibility (requires macOS 14.0+)
-   Try building from source with Xcode 15.0+

**Launch at Login not working?**

-   Requires macOS 13.0 or later for automatic registration
-   On older versions, manually add to System Preferences > Users & Groups > Login Items
-   Check if the toggle is properly enabled in Settings

## 🤝 Contributing

We welcome contributions! Here's how you can help:

1. **Fork the repository**
2. **Create a feature branch** (`git checkout -b feature/amazing-feature`)
3. **Commit your changes** (`git commit -m 'Add amazing feature'`)
4. **Push to the branch** (`git push origin feature/amazing-feature`)
5. **Open a Pull Request**

### Development Guidelines

-   Follow Swift style guidelines
-   Add tests for new features
-   Update documentation
-   Ensure compatibility with both Intel and Apple Silicon

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

-   **HotKey Library**: For global keyboard shortcut support
-   **Yams**: For YAML parsing capabilities
-   **macOS Community**: For inspiration and feedback

## 📞 Support

-   **Issues**: [GitHub Issues](https://github.com/MateoCerquetella/RiceBarMac/issues)
-   **Discussions**: [GitHub Discussions](https://github.com/MateoCerquetella/RiceBarMac/discussions)

---

<div align="center">
  <p>Made with ❤️ by Mateo Cerquetella for the macOS community</p>
  <p>If you find this project helpful, please give it a ⭐️</p>
</div>
