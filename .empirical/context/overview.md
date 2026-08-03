# Project Overview

## Purpose

- RiceBarMac is a native macOS menu-bar application for developers and power users who switch groups of desktop configuration files, editor settings, terminal settings, and wallpaper state.
- Profiles live below `~/.ricebarmac/profiles/` and describe filesystem mappings plus supported external effects. Global shortcuts and menu commands select profiles.
- The safety boundary is unusually important: the application mutates configuration under the user's home directory, so replacement, backup, rollback, migration, and release authenticity are product behavior rather than internal details.

## Boundaries

- The current project targets macOS 14 or later and is generated with XcodeGen from `project.yml`.
- Intended existing integrations include file replacement and symlinks, wallpaper, Alacritty, VS Code, Cursor, and startup scripts.
- Terminal.app, iTerm2, and broader system-theme behavior are present as incomplete or stubbed claims and must not be documented as supported until implemented and verified.
- Release delivery spans this repository's GitHub artifact and the separate `homebrew-ricebarmac` cask repository.

## Evidence

- Product and setup descriptions: `README.md`, `CONTRIBUTING.md`, and `CLAUDE.md`.
- Build and delivery sources: `project.yml`, `App/Info.plist`, and `.github/workflows/release.yml`.
- Entrypoints and paths: `App/Sources/App/RiceBarMacApp.swift`, `App/Sources/App/StatusBarController.swift`, and `App/Sources/Utils/Constants.swift`.
- The complete inspected-file inventory and digests are recorded in `manifest.json`.
