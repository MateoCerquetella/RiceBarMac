<div align="center">
  
  # 🍚 RiceBarMac
  
  ### Lightning-fast macOS menu bar app for effortless desktop profile switching
  
  [![macOS](https://img.shields.io/badge/macOS-14.0+-blue.svg)](https://www.apple.com/macos/)
  [![Swift](https://img.shields.io/badge/Swift-5.9+-orange.svg)](https://swift.org/)
  [![Xcode](https://img.shields.io/badge/Xcode-15.0+-blue.svg)](https://developer.apple.com/xcode/)
  [![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
  [![Platform](https://img.shields.io/badge/Platform-macOS-lightgrey.svg)](https://www.apple.com/macos/)
  
</div>

## 🚀 Overview

RiceBarMac is a powerful macOS menu bar application that manages your **desktop rice configurations** by creating symbolic links from profile directories to your actual system locations. It's designed for developers and power users who maintain multiple aesthetic setups and want to switch between them instantly using keyboard shortcuts.

## 🔧 How It Works

RiceBarMac operates as a **symlink-based overlay system** that manages your rice configurations:

### 🎯 **Core Functionality**

-   **Menu Bar Integration**: Runs silently in your menu bar with a rice bowl icon 🍚
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

-   **Menu Bar Interface**: Clean, accessible menu bar app with rice bowl icon 🍚
-   **Multiple Profiles**: Create and manage unlimited rice profiles
-   **Instant Switching**: Switch between profiles with keyboard shortcuts or menu clicks
-   **Profile Ordering**: Customize the order of profiles in the menu via `order` property
-   **Profile Creation**: Create empty profiles or capture current system configuration
-   **Profile Actions**: Reapply, delete, open folder, save current config, set wallpaper

### 🔧 **File Management**

-   **Config File Symlinking**: Create symbolic links from `.config` directories and files to your system
-   **Home Directory Overlay**: Automatic symlinking of `home/` directory contents
-   **IDE Integration**: VS Code, Cursor, Alacritty, iTerm2 configuration support  
-   **Backup System**: Automatic backup of existing files to `~/.ricebarmac/backups/` before creating symlinks
-   **Startup Scripts**: Execute custom scripts when profiles are applied
-   **File Validation**: Comprehensive validation of profile configurations and file paths

### 🖼️ **Visual Customization**

-   **Wallpaper Switching**: Change desktop wallpapers instantly with drag-and-drop or file picker
-   **Multiple Formats**: Support for PNG, JPG, HEIC, GIF, BMP, TIFF formats
-   **Terminal Themes**: Alacritty, Terminal.app, iTerm2 theme switching
-   **IDE Themes**: VS Code and Cursor theme management via settings.json

### ⌨️ **Keyboard Shortcuts**

-   **Profile Shortcuts**: Direct profile switching (⌘+1, ⌘+2, etc.) for up to 9 profiles
-   **Navigation Shortcuts**: Next/Previous profile cycling, reload profiles, open folder
-   **Quick Actions**: Create profiles, open settings, quit app
-   **Global Hotkeys**: System-wide shortcuts that work even when other apps are active
-   **Menu Shortcuts**: All menu items have configurable keyboard shortcuts

### 🔧 **System Integration**

-   **Launch at Login**: Seamless integration with macOS login items (macOS 13.0+)
-   **Dock Visibility**: Option to show/hide from Dock while maintaining menu bar presence
-   **Settings Window**: Clean, minimal settings interface for system preferences
-   **Status Tracking**: Real-time status updates and progress indicators
-   **Error Handling**: Robust error handling with user-friendly messages and recovery suggestions

### 🛠️ **Advanced Capabilities**

-   **JSON Configuration**: Easy-to-edit configuration files with full schema
-   **Hotkey Registration**: Advanced global hotkey system with conflict detection
-   **Debug Logging**: Comprehensive logging for troubleshooting and development
-   **Universal Binary**: Native support for both Intel and Apple Silicon Macs
-   **Async Operations**: Non-blocking profile application with progress tracking

## 📦 Installation

### Prerequisites

-   macOS 14.0 or later
-   Xcode 15.0+ (for development)

### Quick Start

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

## 🎮 Usage

### First Launch

1. **Launch RiceBarMac** - The app will appear in your menu bar with a rice bowl icon 🍚
2. **Click the menu bar icon** to access the main menu
3. **Create your first profile** using the "Create Profile" menu options

### Creating Profiles

**From the menu bar, you can:**

1. **Create Profile** → **Empty Profile...** to start from scratch
2. **Create Profile** → **From Current Setup...** to capture your existing configuration
3. **Profile folders** are automatically created in `~/.ricebarmac/profiles/`

### Managing Profiles

**Each profile in the menu has a submenu with options:**
- **Reapply**: Reapply the currently active profile
- **Set Wallpaper...**: Change the wallpaper for the profile
- **Save Current Config to This Profile**: Update profile with current system state
- **Open Profile Folder**: Open the profile directory in Finder
- **Delete Profile...**: Remove the profile (with confirmation)

### Setting Up Shortcuts

**Keyboard shortcuts are configured in the main configuration file:**
- **Profile shortcuts**: ⌘+1, ⌘+2, etc. for direct profile switching
- **Navigation shortcuts**: Cycle through profiles and reload
- **Quick actions**: Create profiles, open settings, quit app

### System Settings

**Access settings through:**
- **Menu bar** → **Settings...** 
- **Settings window includes:**
  - **Launch at Login**: Toggle automatic startup with macOS
  - **Registered Hotkeys**: View count of active global shortcuts
  - **About**: App version and build information

### Navigation Shortcuts

**Default navigation shortcuts (customizable in config):**
-   **Next Profile**: ⌘+⌥+⌃+] 
-   **Previous Profile**: ⌘+⌥+⌃+[
-   **Reload Profiles**: ⌘+⌥+⌃+R

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

### Shortcut Configuration

Configuration file located at `~/.ricebarmac/config.json`:

```json
{
    "shortcuts": {
        "profileShortcuts": {
            "profile1": "cmd+1",
            "profile2": "cmd+2",
            "profile3": "cmd+3",
            "profile4": "cmd+4",
            "profile5": "cmd+5",
            "profile6": "cmd+6",
            "profile7": "cmd+7",
            "profile8": "cmd+8",
            "profile9": "cmd+9"
        },
        "navigationShortcuts": {
            "nextProfile": "cmd+option+control+]",
            "previousProfile": "cmd+option+control+[",
            "reloadProfiles": "cmd+option+control+r",
            "openProfilesFolder": "cmd+option+control+o"
        },
        "quickActions": {
            "createEmptyProfile": "cmd+option+control+e",
            "createFromCurrentSetup": "cmd+option+control+n",
            "openSettings": "cmd+option+control+,",
            "quitApp": "cmd+option+control+q"
        }
    },
    "general": {
        "launchAtLogin": false,
        "showInDock": false
    }
}
```

## 🎨 Customization

### Supported Key Combinations

-   **Letters**: `a`, `b`, `c`, etc.
-   **Numbers**: `1`, `2`, `3`, etc.
-   **Brackets**: `[`, `]`
-   **Special Characters**: `\`, `;`, `'`, `,`, `.`, `/`, `` ` ``, `-`, `=`
-   **Function Keys**: `F1`, `F2`, etc.
-   **Navigation**: `UP`, `DOWN`, `LEFT`, `RIGHT`, `HOME`, `END`
-   **Modifiers**: `cmd`, `option`, `control`, `shift`

### Theme Integration

RiceBarMac integrates with popular development tools and configurations:

-   **Terminal Emulators**: Alacritty, Terminal.app, iTerm2 theme switching
-   **Code Editors**: VS Code and Cursor settings, themes, and extensions
-   **Shell Configurations**: Neovim, Tmux, and other `.config` files
-   **Custom Scripts**: Execute startup scripts when profiles are applied

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

### Debug Mode

Enable debug logging by running from terminal:

```bash
# If installed in Applications
/Applications/RiceBarMac.app/Contents/MacOS/RiceBarMac

# If running from build directory
./RiceBarMac.app/Contents/MacOS/RiceBarMac
```

**Console logs** can be viewed in Console.app by filtering for "RiceBarMac".

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
-   **Email**: mateo.cerquetella@gmail.com

---

<div align="center">
  <p>Made with ❤️ by Mateo Cerquetella for the macOS community</p>
  <p>If you find this project helpful, please give it a ⭐️</p>
</div>
