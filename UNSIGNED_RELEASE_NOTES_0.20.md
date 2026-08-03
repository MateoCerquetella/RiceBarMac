# RiceBarMac 0.20

RiceBarMac 0.20 focuses on predictable and recoverable profile changes. The
manually published asset is identified as unsigned in its release title and
filename. The Homebrew cask is unchanged.

## Highlights

- Launch and profile reload are read-only; profiles are never reapplied automatically.
- Every profile selection opens an exact Preview before Apply.
- Replaced files, directories, and symbolic links move to unique adjacent backups.
- Apply uses an atomic transaction journal with reverse-order rollback and explicit recovery details.
- Undo restores the exact state from the most recent successful Apply without overwriting later user changes.
- Profile mutations are serialized, with visible progress and deterministic cancellation behavior.
- Malformed configuration is preserved instead of being replaced with defaults.
- Legacy `~/.ricebar` migration is explicit, staged, and conflict-aware.
- Existing JSON and YAML profiles remain supported; invalid profiles stay visible with their errors.

## Build verification

- Version `0.20`, build `120`
- macOS 14 Sonoma or later
- Universal `arm64` and `x86_64` application
- Debug and Release analysis, 38 unit/integration tests, and 3 native UI tests run before publication
- Public asset checksum re-downloaded and verified before workflow completion

Supported integrations are wallpaper, Alacritty, VS Code, Cursor, filesystem replacements, and startup scripts. Terminal.app, iTerm2, and system-theme automation remain unsupported.
