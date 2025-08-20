# RiceBarMac

🍚 **A lightning-fast macOS menu bar app for effortless desktop profile switching**

Switch between complete desktop environments in seconds. RiceBarMac lets you manage different "rices" (desktop configurations) by overlaying your `~/.config`, changing wallpapers, applying themes, and running custom scripts — all from your menu bar.

![RiceBarMac Demo](docs/demo.gif)

## ✨ Features

- **🚀 Instant Profile Switching**: Change your entire desktop environment with one click
- **⌨️ Global Shortcuts**: Quick switching with ⌘1-9 and ⌘]/[ navigation  
- **🎨 Theme Integration**: VS Code/Cursor settings, extensions, and themes
- **🖼️ Smart Wallpapers**: Auto-detection with multiple format support (PNG, JPG, HEIC)
- **⚡ Terminal Themes**: Automatic Alacritty configuration and live reload
- **📁 Profile Templates**: Dynamic templating with wallpaper color extraction
- **🔄 Auto-Sync**: Live profile updates when you modify files
- **🛡️ Non-Destructive**: Safe overlays with automatic backups
- **🎯 Menu Bar Native**: Clean, minimal interface that stays out of your way

## 🔧 Quick Start

### Requirements
- macOS Sonoma (14+) or later
- Xcode 15+ for building from source

### Installation

1. **Clone and build:**
```bash
git clone https://github.com/MateoCerquetella/RiceBarMac.git
cd RiceBarMac
brew install xcodegen
xcodegen generate
open RiceBarMac.xcodeproj
```

2. **Build and run** the project in Xcode (⌘R)

3. **Grant permissions** when prompted:
   - Desktop folder access (for wallpaper changes)
   - Apple Events (for terminal integration)

The app will appear in your menu bar with a rice bowl icon 🍚.

## 📁 Profile Structure

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

### Core Components

- **`home/`**: Files that overlay your home directory (non-destructive)
- **`vscode/` & `cursor/`**: IDE settings, themes, and extension lists
- **`wallpaper.*`**: Desktop background (PNG, JPG, HEIC, GIF, BMP, TIFF)
- **`profile.json`**: Configuration metadata
- **`hotkey.txt`**: Custom keyboard shortcuts
- **`startup.sh`**: Post-application scripts

## 🎮 Usage

### Creating Profiles

**From Menu:**
- **"Create Profile" → "Empty Profile"**: Start with a blank slate
- **"Create Profile" → "From Current Setup"**: Capture your current configuration

**Manual Creation:**
```bash
mkdir -p ~/.ricebar/profiles/MyProfile/home/.config
# Add your configs...
echo "cmd+shift+1" > ~/.ricebar/profiles/MyProfile/hotkey.txt
```

### Switching Profiles

**Multiple Ways:**
- **Menu**: Click the profile name
- **Keyboard**: ⌘1-9 for first 9 profiles
- **Navigation**: ⌘] (next) / ⌘[ (previous)
- **Hotkeys**: Custom shortcuts from `hotkey.txt`

### Profile Configuration

**profile.json example:**
```json
{
  "name": "Work Setup",
  "order": 1,
  "wallpaper": "wallpaper.jpg",
  "hotkey": "cmd+shift+1",
  "startupScript": "startup.sh",
  "terminal": {
    "kind": "alacritty",
    "theme": "tokyo-night.yml"
  },
  "ide": {
    "kind": "vscode",
    "theme": "@id:Tokyo Night",
    "extensions": ["ms-python.python", "rust-lang.rust-analyzer"]
  }
}
```

## 🎨 Advanced Features

### Theme Integration

**Automatic VS Code/Cursor Setup:**
- Settings and keybindings synchronization
- Extension management and installation
- Theme detection and application
- Snippet library preservation

**Terminal Theming:**
- Alacritty configuration with live reload
- Color scheme extraction from wallpapers
- Template-based configuration generation

### Dynamic Templates

Create templates in `templates/home/` with color variables:

```yaml
# templates/home/.config/alacritty/alacritty.yml
colors:
  primary:
    background: "{{palette0}}"
    foreground: "{{palette1}}"
  normal:
    black: "{{palette2}}"
    red: "{{palette3}}"
```

Colors are automatically extracted from your wallpaper!

### Auto-Sync & Live Updates

RiceBarMac watches your active profile folder and automatically reapplies changes:
- Edit a config file → instant update
- Change wallpaper → automatic desktop refresh
- Modify scripts → immediate execution

## 🔧 App Distribution

### Creating a Logo

1. **Design Requirements:**
   - 1024x1024px base resolution
   - Simple, recognizable icon (rice bowl, grain, or abstract shape)
   - Good contrast for menu bar display
   - Scalable vector design

2. **Tools:**
   - **Free**: GIMP, Canva, or Figma
   - **Paid**: Adobe Illustrator, Sketch
   - **AI**: Midjourney, DALL-E for concepts

3. **Icon Generation:**
   - Use Xcode's Asset Catalog
   - Generate all required sizes automatically
   - Include @1x, @2x, @3x variants

### Building for Distribution

**Development Build:**
```bash
xcodebuild -project RiceBarMac.xcodeproj -scheme RiceBarMac -configuration Debug
```

**Release Build:**
```bash
xcodebuild -project RiceBarMac.xcodeproj -scheme RiceBarMac -configuration Release -archivePath RiceBarMac.xcarchive archive
```

**Notarization (for public distribution):**
1. Enable Hardened Runtime in Release configuration
2. Add Developer ID certificate
3. Submit for notarization via Xcode or `xcrun notarytool`
4. Staple the notarization to your app

### Distribution Options

**Direct Download:**
1. Export as app bundle from Xcode
2. Create DMG with utilities like `create-dmg`
3. Host on GitHub Releases or your website

**Mac App Store:**
1. Add App Store entitlements
2. Enable sandbox (already configured)
3. Submit via App Store Connect

**Package Managers:**
```bash
# Homebrew Cask example
brew install --cask ricebarmac
```

## ⌨️ Keyboard Shortcuts

- **⌘1-9**: Switch to profiles 1-9
- **⌘]**: Next profile
- **⌘[**: Previous profile  
- **⌘E**: Create empty profile
- **⌘N**: Create from current setup
- **⌘R**: Reload profiles
- **⌘O**: Open profiles folder
- **⌘Q**: Quit RiceBarMac

## 🛠️ Troubleshooting

### Common Issues

**Wallpaper not changing:**
- Check file format (PNG, JPG, HEIC supported)
- Verify file permissions
- Try "Reload Profiles" from menu

**Terminal not updating:**
- Ensure Alacritty is installed
- Check config file syntax
- Restart terminal application

**Hotkeys not working:**
- Verify format in `hotkey.txt` (e.g., "cmd+shift+1")
- Check for conflicting system shortcuts
- Restart RiceBarMac

### Permissions

Grant these permissions in System Preferences → Security & Privacy:

- **Desktop Folder**: Required for wallpaper changes
- **Apple Events**: Required for terminal integration
- **Full Disk Access**: Required for some system configurations (optional)

## 🤝 Contributing

Contributions are welcome! Please read our [Contributing Guidelines](CONTRIBUTING.md) before submitting PRs.

### Development Setup

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Test thoroughly
5. Submit a pull request

### Code Style

- Swift code follows standard conventions
- Use SwiftUI for UI components
- Maintain backward compatibility with macOS 14+
- Include tests for new features

## 📄 License

MIT License - see [LICENSE](LICENSE) file for details.

## 🙏 Acknowledgments

- Inspired by the Unix "rice" culture
- Built with SwiftUI and AppKit
- Uses modern macOS APIs for seamless integration

---

**Made with ❤️ by Mateo Cerquetella**

⭐ Star this repo if RiceBarMac helps streamline your workflow!