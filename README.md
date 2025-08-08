# RiceBarMac

A super-simple macOS menu bar app to switch between desktop profiles by overlaying your `~/.config`, setting a wallpaper, and optionally running a startup script. Uses SwiftUI + AppKit.

## Install & Build

-   Requires macOS Sonoma (14+) and Xcode.
-   Dependencies are managed by Swift Package Manager via XcodeGen.

```bash
brew install xcodegen
xcodegen generate
open RiceBarMac.xcodeproj
```

Run the app (Debug). It appears in the menu bar only.

## Profiles

Profiles live at:

```
~/.ricebar/profiles/<ProfileName>/
```

Each profile can contain:

-   `home/.config/**` → files that overlay your `~/.config` on apply (non-destructive, existing files are backed up with `.bak` before replacement)
-   `wallpaper.jpg|png|heic` → optional wallpaper (auto-detected if present). You can also pick one via the menu: Active Profile → Set Wallpaper…
-   `profile.json` or `profile.yml` → optional explicit config (fields: `name`, `hotkey`, `wallpaper`, `startupScript`, `terminal`)
-   `hotkey.txt` → optional shortcut like `ctrl+cmd+1`

You can create profiles from the menu:

-   Create Empty Profile… → scaffolds a new profile with an empty `home/`
-   Create Profile From Current… → snapshots your current `~/.config` into `home/.config`

## Applying a Profile

-   Click a profile name in the menu. RiceBar will:
    1. Render templates (if any) from `templates/home/**` into `home/**` using variables and a color palette extracted from the profile’s wallpaper
    2. Overlay `home/**` into your home directory (non-destructive: existing destination files are backed up as `.bak` and replaced)
    3. Set the wallpaper (AppKit first, AppleScript fallback)
    4. Apply terminal theme for Alacritty when configured (supports `alacritty.yml` or `alacritty.toml` and triggers a reload)
    5. Optionally run `startupScript` if specified

Global hotkeys from `hotkey.txt` are supported (e.g., `ctrl+cmd+1`).

## Notes

-   Debug builds are not sandboxed. For App Store/Notarization, enable sandbox (already configured in Release entitlements).
-   Alacritty reload: the app touches `alacritty.yml`/`alacritty.toml` and attempts `alacritty msg config reload` (with common PATHs and a USR1 fallback).
-   Templating: If you create templates under `templates/home/**` with `{{palette0}}..{{palette5}}`, RiceBar renders them into `home/**` using a palette extracted from the profile’s wallpaper.
-   Auto-apply: edits under the active profile folder trigger a debounced re-apply.

## Minimal Example

```
~/.ricebar/profiles/Work/
  home/
    .config/
      alacritty/alacritty.yml  # or alacritty.toml
      htop/htoprc
  wallpaper.jpg
  hotkey.txt  # ctrl+cmd+1
```

Choose “Reload Profiles” from the menu to pick it up (or restart the app).
