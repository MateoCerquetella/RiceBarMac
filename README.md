<div align="center">

  <img src="docs/assets/ricebarmac-icon.png" alt="RiceBarMac Icon" width="128" height="128">

  # RiceBarMac

  ### Safe, reversible macOS desktop-profile switching from the menu bar

  [![macOS](https://img.shields.io/badge/macOS-14.0+-blue.svg)](https://www.apple.com/macos/)
  [![Swift](https://img.shields.io/badge/Swift-5.9+-orange.svg)](https://swift.org/)
  [![Xcode](https://img.shields.io/badge/Xcode-15.0+-blue.svg)](https://developer.apple.com/xcode/)
  [![License](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)

</div>

RiceBarMac is a menu bar app for switching developer and desktop configurations. Profiles live under `~/.ricebarmac/profiles/` and map files from a profile into locations inside your home directory.

Version 0.20 makes profile changes previewable, transactional, and reversible. Launching the app or reloading the profile list never applies a profile automatically.

## What v0.20 supports

- Read-only Preview with every destination, source, backup, warning, and post-commit effect.
- Explicit Apply confirmation from the menu bar or Settings.
- Serialized profile operations with visible progress and queue depth.
- Unique adjacent backups for replaced files, directories, and symbolic links.
- Reverse-order rollback when a filesystem action fails.
- Undo that restores the previous object and refuses to overwrite later user changes.
- Persistent transaction journals and explicit recovery controls after an interrupted operation.
- JSON and YAML profiles; malformed profiles stay visible with their validation error.
- Home overlays and explicit replacement mappings.
- Wallpaper, Alacritty, VS Code, Cursor, extension installation, and startup-script integrations.
- Explicit, staged migration from legacy `~/.ricebar` data without deleting the original.
- Config compatibility: missing fields receive defaults, unknown fields are ignored, and malformed `config.json` is never silently replaced.
- Configurable global shortcuts and launch-at-login support.

Terminal.app, iTerm2, and `systemTheme` declarations are accepted for profile compatibility but are not applied in v0.20; Preview reports them as unsupported. Kitty, WezTerm, remote theme downloads, palette extraction, and template substitution are not implemented.

## Safety model

Selecting a profile follows this sequence:

1. RiceBarMac validates the profile and builds a plan without writing to disk.
2. Preview shows the exact plan and requires Apply or Cancel.
3. Apply enters a single FIFO operation queue.
4. Each action records intent, stages its replacement, preserves the existing object at the displayed backup path, and installs the replacement.
5. A failure triggers reverse-order rollback. Any path that cannot be restored is shown in Recovery.
6. Wallpaper changes, editor extension installation, Alacritty reload, and startup scripts run only after the reversible filesystem commit. Their failures are warnings and do not undo committed files.
7. Undo verifies fingerprints before restoring backups, so a file changed after Apply is left untouched.

Destinations must be strictly inside the current user’s home directory. RiceBarMac rejects unsafe parent symlinks, recursive mappings, duplicate or conflicting destinations, collisions with reserved staging paths, and changes to its own `.ricebar`/`.ricebarmac` storage.

Transaction journals are stored in `~/.ricebarmac/transactions/`. Backups use unique `.ricebarmac-backup-…` names beside the affected path. If Recovery is shown, keep both the journal and backups until the issue is resolved.

## Profile layout

Each profile contains `profile.json`, `profile.yml`, or `profile.yaml`:

```text
~/.ricebarmac/profiles/
├── Work/
│   ├── home/
│   │   └── .config/
│   │       ├── nvim/
│   │       └── tmux/
│   ├── vscode/
│   │   ├── settings.json
│   │   ├── keybindings.json
│   │   └── snippets/
│   ├── alacritty.toml
│   ├── wallpaper.jpg
│   ├── startup.sh
│   └── profile.json
└── Minimal/
    ├── home/.config/...
    └── profile.yml
```

When `replacements` is absent or empty, files below the profile’s `home/` directory overlay the corresponding paths below `~`. Explicit replacements take precedence when present.

### Example profile

```json
{
  "name": "Work Setup",
  "order": 1,
  "hotkey": "cmd+1",
  "wallpaper": "wallpaper.jpg",
  "terminal": {
    "kind": "alacritty",
    "theme": "alacritty.toml",
    "themeSource": "file",
    "fontSize": 14,
    "fontFamily": "JetBrains Mono",
    "opacity": 0.95
  },
  "ide": {
    "kind": "vscode",
    "theme": "@id:Default Dark Modern",
    "themeSource": "builtin",
    "extensions": ["ms-vscode.vscode-typescript-next"],
    "fontSize": 14,
    "fontFamily": "JetBrains Mono",
    "wordWrap": true
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

Replacement sources are relative to the profile directory. Destinations may be absolute paths or start with `~/`, but must resolve safely inside the user’s home directory.

For VS Code or Cursor, a theme beginning with `@id:` updates `workbench.colorTheme` while preserving the rest of `settings.json`. A relative theme path is treated as profile content. Recognized editor directories can contain `settings.json`, `keybindings.json`, and `snippets/`.

## Installation

RiceBarMac 0.20 requires macOS 14 Sonoma or later and ships as a universal Intel/Apple Silicon app.

### Homebrew

```bash
brew tap mateocerquetella/ricebarmac
brew install --cask ricebarmac
```

The Homebrew cask tracks signed releases and is not changed by the manual v0.20 publisher.

### Download

Download the versioned asset from [GitHub Releases](https://github.com/MateoCerquetella/RiceBarMac/releases), verify its attached SHA-256 checksum, extract it, and move `RiceBarMac.app` to `/Applications`.

## Build and test

Development requires Xcode 15 or later and XcodeGen.

```bash
brew install xcodegen
xcodegen generate
xcodebuild -project RiceBarMac.xcodeproj -scheme RiceBarMac \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO build
xcodebuild -project RiceBarMac.xcodeproj -scheme RiceBarMac \
  -destination 'platform=macOS' CODE_SIGNING_ALLOWED=NO \
  -only-testing:RiceBarMacTests test
```

CI additionally runs static analysis, UI tests against an isolated temporary home, a Release build, and a universal archive check. `project.yml` is the source of truth for the generated Xcode project.

## Configuration and migration

Global settings are stored at `~/.ricebarmac/config.json`. Editing settings uses a staged write and preserves the previous file at a unique backup path. If the file is malformed, RiceBarMac keeps its bytes unchanged and shows the parse error.

If `~/.ricebar` exists and `~/.ricebarmac` is not already populated, Settings offers an explicit migration. Migration validates links, copies into a staging directory, journals the operation, and leaves `~/.ricebar` intact. If both roots contain data, RiceBarMac reports a conflict instead of merging them automatically.

## Troubleshooting

### A profile cannot be applied

Open Preview and read the “Cannot apply” section. Common causes are a missing source, an invalid destination, a parent symlink that escapes the home directory, or two mappings targeting the same path. Invalid profiles remain listed with their parsing or validation error.

### Undo reports a changed path

RiceBarMac detected a post-Apply user change and intentionally did not overwrite it. Preserve the displayed backup and transaction journal, then reconcile the current file manually.

### Recovery is required

Do not rename or delete affected paths, `.ricebarmac-backup-…` files, or the transaction journal. Open Settings, inspect the recovery entry, and retry recovery after resolving permissions or filesystem availability.

### Global shortcuts do not work

Check for conflicts with other apps and review the shortcuts in Settings. macOS may require Accessibility approval for global interaction.

### Launch at Login requires approval

Open System Settings → General → Login Items and approve RiceBarMac. The app does not silently change this setting during launch.

## Demo

- [Terminal configuration switching](https://github.com/user-attachments/assets/551ad0a6-b659-47d8-8258-45d515670210)
- [VS Code and Cursor integration](https://github.com/user-attachments/assets/cbc52f71-27c8-44df-b107-6598f8562a0f)

## Contributing and support

See [CONTRIBUTING.md](CONTRIBUTING.md) for development and pull-request guidance.

- [GitHub Issues](https://github.com/MateoCerquetella/RiceBarMac/issues)
- [GitHub Discussions](https://github.com/MateoCerquetella/RiceBarMac/discussions)

RiceBarMac is licensed under the [MIT License](LICENSE).
