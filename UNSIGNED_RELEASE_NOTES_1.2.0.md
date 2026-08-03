# RiceBarMac 1.2.0 — Unsigned build

> **Security notice:** `RiceBarMac-1.2.0-unsigned.zip` is intentionally unsigned and unnotarized. It does not have an Apple Developer ID signature, notarization ticket, or Gatekeeper approval. macOS may block it. Install it only if you trust this repository and accept that risk.

This one-time unsigned publication was explicitly authorized by the project owner because Apple signing credentials are not configured. The normal tag-triggered release workflow remains fail-closed and will publish only a Developer ID signed, hardened, notarized, stapled, and Gatekeeper-verified build.

The Homebrew cask is not updated to this unsigned build. Download the explicitly labeled asset from this release, verify it against the attached `.sha256` file, extract it, and move `RiceBarMac.app` to `/Applications`. If macOS blocks the first launch, review the warning in **System Settings → Privacy & Security** and use **Open Anyway** only if you choose to trust the app.

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

- Version `1.2.0`, build `120`
- macOS 14 Sonoma or later
- Universal `arm64` and `x86_64` application
- Debug and Release analysis, 38 unit/integration tests, and 3 native UI tests run before publication
- Public asset checksum re-downloaded and verified before workflow completion

Supported integrations are wallpaper, Alacritty, VS Code, Cursor, filesystem replacements, and startup scripts. Terminal.app, iTerm2, and system-theme automation remain unsupported.
