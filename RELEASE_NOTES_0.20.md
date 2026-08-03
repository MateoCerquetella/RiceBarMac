# RiceBarMac 0.20

RiceBarMac 0.20 focuses on making profile changes predictable and recoverable.

## Highlights

- Launch and profile reload are read-only. RiceBarMac never reapplies a saved profile automatically.
- Every profile selection opens an exact Preview before Apply.
- Replaced files, directories, and symbolic links move to unique adjacent backups.
- Apply uses an atomic transaction journal with reverse-order rollback and explicit recovery details.
- Undo restores the exact state from the most recent successful Apply and will not overwrite later user changes.
- Profile mutations are serialized; queued operations and progress are visible without polling.
- Malformed configuration is preserved instead of being overwritten with defaults.
- Legacy `~/.ricebar` migration is explicit, staged, conflict-aware, and preserves the original.
- Existing JSON and YAML profiles remain supported. Invalid profiles remain visible with their errors.
- Supported integrations are wallpaper, Alacritty, VS Code, Cursor, filesystem replacements, and startup scripts. Terminal.app, iTerm2, and system-theme automation remain unsupported.

## Distribution integrity

The normal release workflow requires a universal `arm64`/`x86_64` build, Developer ID signature, hardened runtime, Apple notarization, a stapled ticket, Gatekeeper acceptance, and a matching Homebrew checksum. It fails without those gates rather than publishing an unsigned fallback.

## Requirements

- macOS 14 Sonoma or later
- User approval for any macOS permissions required by selected integrations

Backups and transaction journals are retained under or alongside the affected paths and `~/.ricebarmac/transactions`. Keep them when RiceBarMac reports that recovery is required.
