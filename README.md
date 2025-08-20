# RiceBarMac 🍚

[![macOS](https://img.shields.io/badge/macOS-14.0+-blue.svg)](https://www.apple.com/macos/)
[![Swift](https://img.shields.io/badge/Swift-5.0+-orange.svg)](https://swift.org/)
[![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/Platform-macOS-lightgrey.svg)](https://www.apple.com/macos/)

<div align="center">
  
  # 🍚 RiceBarMac
  
  ### Lightning-fast macOS menu bar app for effortless desktop profile switching
  
  [![macOS](https://img.shields.io/badge/macOS-14.0+-blue.svg)](https://www.apple.com/macos/)
  [![Swift](https://img.shields.io/badge/Swift-5.0+-orange.svg)](https://swift.org/)
  [![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
  [![Platform](https://img.shields.io/badge/Platform-macOS-lightgrey.svg)](https://www.apple.com/macos/)
  
</div>

## 🚀 Overview

RiceBarMac is a powerful macOS menu bar application that allows you to quickly switch between different Rice configurations (themes, wallpapers, and system settings) using keyboard shortcuts. Perfect for developers and power users who want to maintain multiple aesthetic setups and switch between them seamlessly.

## ✨ Features

### 🎨 **Profile Management**

-   **Multiple Rice Profiles**: Create and manage unlimited rice configurations
-   **Theme Switching**: Instantly switch between different color schemes and themes
-   **Wallpaper Management**: Automatic wallpaper switching with profile changes
-   **System Integration**: Apply system-wide changes with a single click

### ⌨️ **Keyboard Shortcuts**

-   **Global Hotkeys**: Switch profiles using customizable keyboard shortcuts (⌘+1, ⌘+2, etc.)
-   **Navigation Shortcuts**: Quick navigation between profiles (⌘+⌥+⌃+[, ⌘+⌥+⌃+])
-   **Auto-Save**: Shortcuts are automatically saved when configured
-   **Remove Shortcuts**: Option to disable shortcuts for any profile

### 🎯 **Smart Features**

-   **Universal Binary**: Works on both Intel and Apple Silicon Macs
-   **Auto-Launch**: Option to start with macOS
-   **Real-time Updates**: Hotkeys update immediately when changed
-   **Visual Feedback**: Clear indication of active profile and shortcut status

### 🔧 **Advanced Capabilities**

-   **YAML Configuration**: Easy-to-edit configuration files
-   **Backup System**: Automatic backup of existing configurations
-   **Error Handling**: Robust error handling and recovery
-   **Debug Logging**: Comprehensive logging for troubleshooting

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

1. **Launch RiceBarMac** - The app will appear in your menu bar
2. **Right-click the icon** to access the main menu
3. **Open Settings** to configure your first profile

### Creating Profiles

1. **Go to Settings** → **Profiles tab**
2. **Click "Add Profile"** to create a new rice configuration
3. **Configure your settings**:
    - **Theme**: Select your color scheme
    - **Wallpaper**: Choose your background image
    - **System Settings**: Configure additional preferences

### Setting Up Shortcuts

1. **Go to Settings** → **Shortcuts tab**
2. **Click on any shortcut field** to record a new shortcut
3. **Press your desired keys** (e.g., ⌘+1 for Profile 1)
4. **The shortcut saves automatically** - no need to click "Save"

### Navigation Shortcuts

-   **Next Profile**: ⌘+⌥+⌃+] (or customize)
-   **Previous Profile**: ⌘+⌥+⌃+[ (or customize)
-   **Reload Profiles**: ⌘+⌥+⌃+R (or customize)

## 🛠️ Configuration

### 📁 Profile Structure

Profiles are stored at `~/.ricebar/profiles/<ProfileName>/` with this structure:

```
~/.ricebar/profiles/
├── Work/
│   ├── home/
│   │   └── .config/
│   │       ├── alacritty/alacritty.yml
│   │       ├── nvim/
│   │       └── tmux/tmux.conf
│   ├── vscode/
│   │   ├── settings.json
│   │   ├── keybindings.json
│   │   └── extensions.txt
│   ├── wallpaper.jpg
│   ├── profile.json
│   └── hotkey.txt
└── Gaming/
    ├── home/.config/...
    ├── wallpaper.png
    └── startup.sh
```

### Profile Configuration

```yaml
profiles:
    - name: 'Dark Theme'
      theme: 'dark'
      wallpaper: '/path/to/dark-wallpaper.jpg'
      systemSettings:
          appearance: 'dark'
          accentColor: 'blue'

    - name: 'Light Theme'
      theme: 'light'
      wallpaper: '/path/to/light-wallpaper.jpg'
      systemSettings:
          appearance: 'light'
          accentColor: 'orange'
```

### Shortcut Configuration

```yaml
shortcuts:
    profileShortcuts:
        profile1: 'cmd+1'
        profile2: 'cmd+2'
        profile3: 'cmd+3'

    navigationShortcuts:
        nextProfile: 'cmd+option+control+]'
        previousProfile: 'cmd+option+control+['
        reloadProfiles: 'cmd+option+control+r'
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

RiceBarMac integrates with popular rice configurations:

-   **Alacritty themes**
-   **i3wm configurations**
-   **Polybar themes**
-   **Rofi themes**
-   **Custom wallpapers**

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
-   Verify macOS version compatibility
-   Try building from source

### Debug Mode

Enable debug logging by running from terminal:

```bash
/Applications/RiceBarMac.app/Contents/MacOS/RiceBarMac
```

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
