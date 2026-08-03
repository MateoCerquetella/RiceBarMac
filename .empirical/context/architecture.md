# Architecture

## Components and ownership

- `RiceBarMacApp.swift` and `StatusBarController.swift` own the application lifecycle, menu-bar presentation, windows, and AppKit/SwiftUI integration.
- `StatusBarViewModel.swift` exposes profiles and apply state to UI surfaces. Multiple constructions currently share singleton services and can repeat refresh, watcher, and hotkey side effects.
- `ProfileService.swift` discovers, parses, creates, deletes, and applies profiles. It currently contains duplicated synchronous/asynchronous orchestration.
- `FileSystemService.swift` performs replacement, copy, symlink, directory-tree, watcher, and backup-related operations.
- `ConfigService.swift` loads and saves `RiceBarConfig`; `SystemService.swift` and `ThemeService.swift` perform external macOS and application effects.
- `ApplyRecord.swift` and `ApplyActivity.swift` represent limited apply history/global activity but do not currently provide an exact durable transaction journal.

## Data and control flow

1. The app resolves the configuration and profiles roots through `Constants.swift` under `~/.ricebarmac/`.
2. App and menu construction instantiate view-model/service paths, load configuration and profiles, register hotkeys, and observe changes.
3. A profile selection reaches `ProfileService`, which maps profile declarations to filesystem operations and external system/theme operations.
4. `FileSystemService` mutates destinations while `SystemService` and `ThemeService` invoke macOS or third-party behavior.
5. UI state is published back through view models and status-bar views. Current launch refresh can apply the saved active profile, and failure/cancellation state is not transactionally unified.

The approved target architecture inserts an immutable plan and actor-owned transaction coordinator between UI intent and injectable filesystem/external-effect boundaries. Active UI state changes after commit; a durable journal drives rollback, recovery, and Undo.

## External dependencies

- Swift packages are declared in `project.yml`; the generated workspace pins them in `Package.resolved`.
- macOS frameworks provide AppKit/SwiftUI, wallpaper/appearance APIs, login-item behavior, and accessibility/UI-test integration.
- XcodeGen generates `RiceBarMac.xcodeproj`; the project file is derived output rather than the source of truth.
- GitHub Actions currently archives and publishes releases and updates the separate Homebrew cask repository.
- Apple Developer ID signing, App Store Connect notarization, Gatekeeper, and Homebrew require macOS tooling and credentials unavailable on the current Linux host.
