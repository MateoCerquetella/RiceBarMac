# Design: RiceBarMac v1.2.0 Safety, Reliability, and Release Integrity

## Design Objective

Introduce a narrow transactional core between user intent and the existing profile-management services. Preserve current profile files and supported integrations while removing all implicit Apply paths, making reversible mutations deterministic, and making the downloadable v1.2.0 artifact mechanically verifiable from source through Homebrew.

The change is incremental: profile discovery, creation, capture, and most integration-specific parsing remain recognizable. Existing synchronous and asynchronous Apply implementations become compatibility wrappers over one coordinator and are removed once all call sites use the new API.

## Current Constraints

- `ProfileService` combines scanning, lifecycle, mutation, integration behavior, watchers, persistence, and two Apply implementations in one large observable singleton.
- `FileSystemService` exposes backup parameters but removes destinations directly. It also combines filesystem primitives with templates, palette work, process execution, and watchers.
- `StatusBarViewModel` performs work from construction and refresh, and independent UI surfaces instantiate it more than once.
- Configuration models use synthesized strict decoding; `ConfigService` defaults on error and writes non-atomically.
- The app is XcodeGen-generated, targets macOS 14, and currently has no test targets.
- The current host is Linux. Native compilation, XCUITest, signing, notarization, Gatekeeper, and Homebrew launch evidence must run on macOS CI.

## Target Architecture

```text
Menu bar / Settings / Hotkeys
             |
             v
  @MainActor ApplicationModel
             |
             v
  ProfileApplicationCoordinator (actor)
       |              |              |
       v              v              v
 ProfilePlanner   TransactionStore   ExternalEffectClient
       |              |
       +-------> FileSystemClient
```

`ApplicationModel` is the only observable application state. `ProfileApplicationCoordinator` is the only owner of profile mutation. `ProfilePlanner` is read-only. `FileSystemClient` and `ExternalEffectClient` make destructive and platform effects injectable. `TransactionStore` atomically persists journals through the same filesystem boundary.

## Core Types

### ProfileApplyPlan

Add `App/Sources/Models/ProfileApplyPlan.swift` with immutable `Sendable`, `Codable`, and identifiable value types:

- `ProfileApplyPlan`: transaction UUID, creation date, profile identity and source path, former active-profile path, root/home identity, ordered reversible actions, ordered external effects, warnings, and validation fingerprints.
- `PlannedFileAction`: stable action UUID and index, action kind, optional source, destination, deterministic adjacent staging and backup paths, captured before-state, and parent-component fingerprints.
- `PlannedFileAction.Kind`: `createDirectory`, `replaceWithSymlink`, `replaceWithCopy`, and `writeData`.
- `FileObjectState`: `absent`, `regularFile`, `directory`, or `symbolicLink(target:)`, plus supported POSIX permissions, size, and a lightweight identity fingerprint. File contents are preserved by backup rather than embedded in the plan.
- `ExternalEffect`: supported wallpaper update, Alacritty reload, VS Code/Cursor extension installation, and startup script invocation. Unsupported Terminal.app, iTerm2, and system-theme declarations become explicit preview warnings rather than unstructured calls.
- `PlanWarning` and `PlanValidationIssue`: stable codes, human-readable text, and affected paths/effects for UI and tests.

The transaction UUID and action index derive hidden sibling names such as `.<name>.ricebarmac-backup-<transaction>-<index>` and `.<name>.ricebarmac-stage-<transaction>-<index>`. Preview can therefore show the exact locations without creating them. Existing sibling collisions invalidate the plan rather than being overwritten.

### ApplyTransaction

Replace the lossy `ApplyRecord` model with `App/Sources/Models/ApplyTransaction.swift`:

- Lifecycle: `planned`, `executing`, `rollingBack`, `rolledBack`, `committed`, `committedWithWarnings`, `undoing`, `undone`, or `recoveryRequired`.
- Per-action lifecycle: `pending`, `intentRecorded`, `backupCreated`, `replacementInstalled`, `rolledBack`, or `restored`.
- Each action records its exact before-state, backup/staging paths, installed-state fingerprint, timestamps, and any sanitized error description.
- The journal also records former/new active profile, external-effect outcomes, and unresolved recovery paths.

Journals live in `~/.ricebarmac/transactions/<UUID>.json`. Each update is encoded and validated in memory, written to a unique sibling temporary file, synchronized, and atomically renamed. Recovery-required journals and their backups are never automatically cleaned. v1.2.0 retains completed backup material as well; future retention policy is outside this change and cannot silently remove recoverable user data.

## Planning and Validation

Add `App/Sources/Services/ProfilePlanner.swift`. Planning performs no writes and no external calls.

1. Validate the descriptor and locate the first supported profile document using the existing JSON/YAML candidate order.
2. Standardize the injected user home and profile root. Expand `~` against the injected home, not the process-global home.
3. Require every profile source and resolved source target to remain under the canonical home and the selected profile directory as appropriate.
4. Require every destination to be a strict descendant of the canonical home. Reject the home root and protected system paths.
5. Walk every existing destination parent with `lstat`. Resolve symlink chains with loop detection; reject links that escape home or cannot be resolved safely. Record device, inode, type, and literal link target fingerprints and revalidate them immediately before execution to reduce time-of-check/time-of-use risk.
6. Reject recursive source/destination mappings, duplicate destinations, ancestor/descendant conflicts that imply incompatible object types, missing sources, unreadable objects, and existing stage/backup collisions.
7. Render at most the documented template limit in memory. Changed rendered profile outputs become journaled `writeData` actions before actions that link those outputs.
8. For explicit replacements, plan a whole-file or whole-directory symlink. For the conventional `home/` overlay, enumerate deterministically by standardized relative path, plan needed parent directories, and then plan file symlinks. No executor fallback is allowed to change plan semantics after preview.
9. Convert Alacritty, VS Code, and Cursor configuration changes to reversible symlink/copy/write actions. Treat editor extension installation, wallpaper, reload signals, and startup scripts as post-commit external effects.
10. Return all deterministically discoverable issues together. Only a plan with no blocking issues can be applied.

`ProfileApplyPlan` is a short-lived capability. Immediately before the first journal write and before each action, the executor revalidates sources, parent fingerprints, destination before-state, and absence of staging/backup collisions. A changed environment produces a stale-plan failure before that action and triggers rollback if earlier actions completed.

## Filesystem Boundary and Transaction Algorithm

Add a focused `FileSystemClient` protocol and `LiveFileSystemClient` implementation in `App/Sources/Services/FileSystemClient.swift`. Required operations use `lstat` semantics so broken symlinks remain visible: enumerate, inspect, read data/link, create directory, copy without following links, create symlink, move, remove, set supported permissions, atomic data replacement, and directory synchronization. Tests use `FaultInjectingFileSystemClient` and `InMemoryExternalEffectClient`.

Execution for each reversible action is:

1. Persist `intentRecorded` with the expected before-state and parent fingerprints.
2. Create missing parent directories one component at a time as their own actions.
3. Build the replacement at the unique adjacent staging path and validate its object type.
4. If the destination exists by `lstat`, atomically move it to the unique adjacent backup and persist `backupCreated`.
5. Atomically move the staged replacement into the destination and persist `replacementInstalled` with its installed fingerprint.
6. Continue only after the journal update succeeds.

If any reversible action fails, rollback walks installed actions in reverse order. It removes a transaction-created destination only when its current fingerprint still matches the installed fingerprint, then atomically restores the recorded backup. A mismatch is never overwritten; it produces `recoveryRequired` with the conflicting path. Parent directories created by the transaction are removed only when empty and fingerprint-compatible.

After reversible commit, persist the new active-profile identifier, suppress watcher feedback for the transaction's touched profile paths, and run external effects serially. External failures produce `committedWithWarnings`; they do not invoke filesystem rollback. Cancellation before mutation exits cleanly. Cancellation between reversible actions rolls back. Cancellation after commit stops remaining external effects and records warnings.

Undo selects the newest `committed` or `committedWithWarnings` non-undone journal. It first verifies that each current destination still matches the installed fingerprint. It then restores actions in reverse order, persists the former active profile after filesystem restoration, and marks the journal `undone`. A second Undo is a no-op. A conflict retains evidence and enters recovery-required state.

## Coordinator and Application State

Add `App/Sources/Services/ProfileApplicationCoordinator.swift` as an actor. It owns one active operation plus a bounded FIFO queue. Each request has an ID and visible queue position. The worker never relies on actor reentrancy for exclusion: one explicit drain loop executes requests to a terminal state before starting the next. Duplicate requests for the same unchanged profile coalesce while pending.

Replace constructor side effects in `StatusBarViewModel` with a single `@MainActor ApplicationModel` (the existing type may be renamed or incrementally adapted). It is created once at the application composition root and injected into the status-bar controller and every SwiftUI settings surface. Published state includes:

- Valid and invalid profile rows.
- Persisted last committed active profile without applying it.
- Current operation and progress, queued requests, preview plan, last completed transaction eligible for Undo, warnings, validation errors, configuration errors, migration offer/conflict, and recovery-required details.

Startup explicitly calls `load()` once. `load()` reads configuration, profile metadata, active-profile persistence, migration availability, and incomplete journals. It never calls Apply. Hotkeys are registered once from current valid profiles and configuration and are replaced as one registry when inputs change.

Filesystem observation is enabled or disabled from `autoReloadProfiles`. Events debounce into metadata-only `reloadProfiles()` and never call Apply. Paths touched by the current transaction are suppressed by transaction identity/generation rather than a time-window global flag.

## Configuration and Profile Compatibility

Refactor `RiceBarConfig` and nested models with explicit `CodingKeys` and custom `init(from:)` methods using `decodeIfPresent` defaults. Unknown keys remain tolerated by JSONDecoder. Loading returns a typed result:

- `.missing(defaults)` uses defaults in memory without writing.
- `.loaded(config)` publishes decoded state.
- `.invalid(originalData, error)` preserves the file byte-for-byte and exposes an actionable UI error.

`ConfigService` accepts an injected root and filesystem client. Save encodes and decodes the proposed value before touching disk, moves an existing config to a unique adjacent backup, atomically installs the staged file, and restores the backup on failure. Setting methods surface errors instead of swallowing them.

Add `ProfileLoadItem` with valid descriptor or invalid source path/error variants. Scanning retains invalid directories as disabled, inspectable rows instead of manufacturing default profiles. Add explicit defaulted decoding to `Profile` for optional/previously defaulted fields so older JSON and YAML fixtures remain readable.

Add `LegacyMigrationService` for `~/.ricebar` to `~/.ricebarmac`:

1. Detection is read-only and produces an offer only when legacy data exists.
2. Confirmation builds a migration plan under a unique staging root next to `.ricebarmac`.
3. Any existing destination conflict blocks before writes and lists conflicts.
4. Copy legacy data without following unsafe links, validate migrated configuration and profiles from the stage, then atomically install the current root only when it was absent.
5. Preserve `.ricebar` after success and record migration metadata. On failure remove only the identified stage and retain the source.

## Native UI

The profile menu initiates Preview, not immediate mutation. Preview presents an accessible sheet/window with ordered actions, backup destinations, warnings, and explicit Apply/Cancel buttons. The menu also exposes Undo when a transaction is eligible, operation/queue status, invalid profile diagnostics, legacy migration, and recovery actions.

Settings observes the same application model and provides the detailed preview/recovery view. Error presentation distinguishes validation failure, failed-and-rolled-back, committed-with-warning, migration conflict, and recovery-required. Stable accessibility identifiers cover the status item, profile rows, Preview, Apply, Cancel, progress, queue, Undo, migration, recovery, and alerts. All controls have keyboard equivalents or standard focus behavior.

For XCUITest, launch arguments inject a temporary RiceBar root and deterministic fake external-effect client, disable global hotkeys, and optionally open a normal test host window that contains the same production controls. This does not replace menu-bar coverage; it makes terminal states and screenshots deterministic while the suite also exercises the real status item and settings command.

## Version and Build Configuration

Make `project.yml` canonical:

- `MARKETING_VERSION: 1.2.0`
- `CURRENT_PROJECT_VERSION: 120`
- `App/Info.plist` uses `$(MARKETING_VERSION)` and `$(CURRENT_PROJECT_VERSION)`.
- XcodeGen adds `RiceBarMacTests` and `RiceBarMacUITests` targets and includes them in the shared scheme.
- Release retains macOS 14, `arm64 x86_64`, and hardened runtime.
- Release entitlements remove App Sandbox and the unrelated application group. Only implemented, justified automation entitlement remains; direct home-directory access relies on the explicitly non-sandboxed Developer ID distribution model.

Add `scripts/verify-version.sh` to compare project settings, plist substitutions, a provided tag, archive bundle metadata, and expected asset naming. Add `scripts/verify-release.sh` for architectures, strict signature, hardened runtime/entitlements, stapling, Gatekeeper, archive contents, and checksum output. Shell scripts fail on unset inputs and never print secrets.

## CI and Release Flow

Add required macOS CI for pull requests and `main`:

1. Install a pinned compatible XcodeGen release and regenerate the project.
2. Fail on generated-project drift.
3. Build and analyze Debug and Release.
4. Run unit/integration tests and XCUITest, upload result bundles and screenshot attachments.
5. Archive an unsigned verification build only for architecture and metadata inspection; this is not a release artifact.

Replace the tag release workflow with a fail-closed Developer ID pipeline:

1. Verify the `v1.2.0` tag matches canonical version metadata and that required CI passed for the same commit.
2. Validate required certificate, keychain, team, notarization API, and Homebrew token secret names before build.
3. Import the Developer ID certificate into an ephemeral keychain without logging secret material.
4. Regenerate, test, analyze, and archive the universal app with hardened runtime and Release entitlements.
5. Verify the archive signature and entitlements, submit the exact app for notarization with `notarytool --wait`, staple and validate, and run Gatekeeper assessment.
6. Package the stapled app with metadata-preserving tooling, download/reinspect the produced archive, and compute SHA-256.
7. Publish GitHub release notes and the immutable `RiceBarMac-1.2.0.zip` asset only after all prior gates pass.
8. Check out the Homebrew tap, update its cask to version 1.2.0, the immutable release URL, computed checksum, and `depends_on macos: ">= :sonoma"`; preserve user configuration on upgrade.
9. Run cask syntax/audit, download/checksum, install, launch, and upgrade-preservation checks before committing and pushing the tap update.

If Apple credentials or macOS evidence are unavailable, implementation may complete but tagging/publication remains blocked. The workflow never falls back to unsigned, ad-hoc, unstapled, or unverified output.

## Tests and Evidence

### Unit and integration tests

- Read-only launch matrices for absent, current, malformed, legacy, and persisted-active state.
- JSON/YAML compatibility fixtures for missing and unknown fields plus invalid-profile retention.
- Plan ordering, exact preview, duplicate/recursive/missing/escaping path rejection, safe and unsafe parent symlinks, and stage/backup collision tests.
- Files, directories, valid symlinks, broken symlinks, permissions, absent destinations, and same-source no-op tests.
- Fault injection before and after every journal and filesystem boundary; exact tree comparison after rollback.
- Persisted crash-state recovery fixtures and rollback-conflict behavior.
- Exact one-time Undo and user-modified-after-commit conflict protection.
- Concurrent Apply FIFO/coalescing and cancellation boundary tests.
- Watcher enabled/disabled and self-event suppression tests.
- A delayed 1,000-file fixture with a main-actor heartbeat and progress assertions.

### Native UI tests

- Launch without Apply, invalid/migration/recovery rows, Preview details, keyboard confirmation, progress/queue, success, post-commit warning, failed rollback, recovery-required, Undo, and second-Undo state.
- Accessibility roles, labels, values, focus order, and stable identifiers.
- Screenshot attachments for idle, preview, applying, success, failure, recovery, and Undo.

### Release evidence

- XcodeGen drift output; Debug/Release build, analyze, test, and result bundles.
- `lipo`, bundle metadata, `codesign`, entitlement, notarization, stapling, `spctl`, archive listing, and SHA-256 outputs.
- Homebrew audit/install/launch/upgrade output and the final cask diff.
- Acceptance-criterion evidence matrix and independent final diff review before tagging.

## Implementation Sequence

1. Add defaulted models, load-result types, filesystem protocol, plan/journal models, and exhaustive unit fixtures without changing UI entry points.
2. Implement planner, transaction store/executor, recovery, Undo, and actor coordinator; route `ProfileService` Apply compatibility calls through it and delete duplicate mutation logic.
3. Refactor configuration save/load and explicit legacy migration; retain invalid profile rows and make watchers metadata-only.
4. Create one application model and inject it into AppKit/SwiftUI surfaces; implement Preview, state/error UI, migration, recovery, Undo, settings behavior, hotkey lifecycle, and accessibility identifiers.
5. Add integration/performance and XCUITest targets, fixtures, and macOS CI.
6. Align version/plist/entitlements, replace release automation, and correct documentation/release notes.
7. Run macOS evidence gates, conduct independent review, repair failures, archive capability deltas, then tag and publish only when Apple and Homebrew prerequisites are satisfied.

## Acceptance-Criterion Traceability

| Concern | Acceptance criteria | Primary implementation | Primary evidence |
| --- | --- | --- | --- |
| Read-only launch and compatibility | AC-1, AC-9, AC-10, AC-11 | Config/Profile loaders, migration service | Fixture integration tests |
| Exact plan and path safety | AC-2, AC-3 | ProfilePlanner, fingerprints | Planner/path tests |
| Backup, journal, rollback, recovery, Undo | AC-4, AC-5, AC-6, AC-7 | Transaction store/executor | Fault-injection tree tests |
| Serialization and responsiveness | AC-8, AC-13 | Actor coordinator, async clients | Concurrency and heartbeat tests |
| Watchers, shared state, hotkeys | AC-12 | ApplicationModel and watcher controller | Lifecycle/registration tests |
| Visible and accessible state | AC-UI-1, AC-UI-2 | Menu/settings preview and recovery UI | XCUITest screenshots/assertions |
| Build and version integrity | AC-14, AC-15 | XcodeGen, CI, version script | macOS logs and artifact inspection |
| Signed release and cask | AC-16, AC-17 | Release workflow and tap update | Apple/Gatekeeper/Homebrew logs |
| Truthful documentation | AC-18 | README and release notes | Claim-to-test review |
