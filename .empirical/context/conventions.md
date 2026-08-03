# Conventions

## Code and structure

- Treat `project.yml` as the Xcode project source and regenerate with XcodeGen; do not hand-edit generated `RiceBarMac.xcodeproj` files.
- Swift source is grouped under `App/Sources` by App, Models, Services, Utils, and ViewModels, with assets, plists, and entitlements under `App`.
- Preserve backward compatibility for existing JSON/YAML profiles and the on-disk `~/.ricebarmac` layout.
- Keep dependencies minimal and isolate filesystem and macOS side effects behind injectable boundaries when they need deterministic testing.

## Testing and delivery

- Use temporary home directories, deterministic fixtures, and injected fault boundaries for destructive-path tests; tests must never target a developer's real home configuration.
- Build, analyze, and test both Debug and Release on macOS and verify native UI behavior with XCUITest and accessibility identifiers.
- Release version, build number, tag, plist, About UI, archive, GitHub metadata, and Homebrew cask must be mechanically consistent.
- Public artifacts must be Developer ID signed with hardened runtime, notarized, stapled, Gatekeeper-assessed, and checksum-verified before the cask update.

## Repository-specific constraints

- Launch and metadata refresh are read-only; only explicit user intent authorizes a profile mutation or legacy migration.
- Never remove or replace user configuration without a unique restorable backup and durable transaction evidence.
- Keep `.ricebar` migration non-destructive and conflict-aware; preserve the original until a staged migration succeeds.
- Preserve unrelated user changes in the worktree. `README.md` and untracked `CLAUDE.md` predated the current enhancement work.
- The app targets macOS 14 or later and the release must retain both Apple-silicon and Intel slices.
- Missing signing, notarization, native test, or cask credentials/evidence blocks release rather than permitting an unsigned fallback.
