# Decisions: Enhance And Optimize Ricebarmac Without Regressions Analyze And Safely R

Record concise, externally reviewable evidence and choices here. Do not store
private chain-of-thought, prompts, credentials, secrets, or scratchpad text.

## D-001: Model profile application as a journaled transaction

Status: Accepted

### Evidence

`FileSystemService` and `ProfileService` currently remove existing destinations even when their public methods receive `createBackup`, while the existing revert path deletes applied destinations rather than restoring the displaced state. Apply behavior is also duplicated across synchronous and asynchronous implementations.

### Options

1. Patch each mutation helper to create a backup and retain the existing orchestration.
2. Snapshot the entire managed home subtree before every apply.
3. Build one immutable plan and execute per-action adjacent backups through an atomic transaction journal.

### Chosen approach

Use option 3. Preflight produces a complete immutable plan. The executor records intent and completion for each action, moves displaced destinations to unique adjacent same-volume backups, rolls completed actions back in reverse order, and retains ambiguous journals for explicit recovery. Decompose the current services incrementally behind injectable boundaries so existing profile formats remain compatible.

### Trade-offs and risks

The journal and recovery state machine add code and on-disk metadata, and adjacent backups remain until their retention rule permits cleanup. In exchange, the system can restore exact file, directory, and symlink state without copying an unrelated home subtree. Crash windows are mitigated by separate intent and completion records and fail-closed recovery.

### Verification

Inject a failure before and after every mutation boundary, compare complete temporary filesystem trees, test crashes from persisted journal fixtures, and prove that success, rollback, recovery-required, and Undo are mutually consistent.

## D-002: Serialize mutations with one actor-owned coordinator

Status: Accepted

### Evidence

The current app constructs multiple view models over singleton services, has duplicated apply entry points, global apply activity, polling sleeps, weak cancellation, and repeated hotkey registration. Those paths can race or report state independently.

### Options

1. Protect current entry points with locks and disable controls while one call runs.
2. Introduce one actor-owned coordinator and one shared application model with explicit queued and terminal states.

### Chosen approach

Use option 2. All Preview, Apply, recovery, and Undo requests pass through the coordinator. It owns the current operation, supported cancellation boundaries, queue policy, and published state; UI surfaces observe one shared model.

### Trade-offs and risks

Adopting actor isolation requires careful bridging to the main actor and dependency protocols. It removes ambiguous global flags and makes serialization testable. Queue and cancellation semantics must be explicit rather than inferred from disabled buttons.

### Verification

Run concurrent request tests with deterministic barriers, cancellation at every supported boundary, main-actor responsiveness checks, and hotkey registration-count assertions.

## D-003: Make configuration and legacy migration explicit and non-destructive

Status: Accepted

### Evidence

Malformed configuration currently falls back to defaults and can then be overwritten, saves are non-atomic, and the documented `.ricebar` to `.ricebarmac` migration does not exist.

### Options

1. Automatically move or merge legacy data during launch and retain strict decoding.
2. Leave legacy data unsupported and document a manual move.
3. Detect legacy data read-only, ask for explicit migration, stage and journal it, and use tolerant decoding plus atomic backed-up saves.

### Chosen approach

Use option 3. Launch may detect and explain but cannot mutate. Migration preserves the source until the staged destination commits, refuses silent conflicts, and rolls back partial output. Missing known fields receive documented defaults, unknown fields are tolerated, and malformed bytes remain untouched for recovery.

### Trade-offs and risks

Users must make one explicit migration choice, and tolerant decoding requires custom model handling and compatibility fixtures. The approach avoids silent loss and preserves forward compatibility.

### Verification

Exercise absent, older, current, future-field, malformed, conflict, and injected migration-failure fixtures for both JSON and YAML profiles and compare original bytes after every rejected operation.

## D-004: Distribute a hardened Developer ID application outside the App Sandbox

Status: Accepted

### Evidence

RiceBarMac intentionally manages arbitrary files under the user's home directory. The current release build is unsigned and the release entitlements enable App Sandbox despite that access model. App Store distribution is outside scope.

### Options

1. Redesign the product around App Sandbox security-scoped bookmarks.
2. Continue publishing unsigned or ad-hoc signed artifacts.
3. Use hardened-runtime Developer ID distribution with only the minimum required non-sandbox entitlements and notarization.

### Chosen approach

Use option 3. Remove App Sandbox and application-group entitlements that do not match the direct-distribution architecture, retain only entitlements justified by implemented behavior, sign the exact archive with Developer ID, notarize, staple, and assess it before publishing.

### Trade-offs and risks

Developer ID and notarization credentials become mandatory release prerequisites, and direct distribution does not provide App Store sandbox guarantees. Failing closed prevents an unverifiable artifact from being labeled a release.

### Verification

Inspect final entitlements, run strict deep signature verification, validate hardened runtime and identities, submit to notarization, staple and validate the ticket, and pass Gatekeeper assessment on the exact downloadable artifact.

## D-005: Use native macOS UI evidence instead of browser evidence

Status: Accepted

### Evidence

RiceBarMac is an AppKit/SwiftUI menu-bar application with no browser-delivered surface. The approved verification still requires real interaction evidence for visible behavior and accessibility.

### Options

1. Omit UI automation because the product is not web-based.
2. Build an unrelated browser harness solely to satisfy a browser-oriented gate.
3. Use XCUITest against the real application and archive screenshots and accessibility assertions.

### Chosen approach

Use option 3. Mark browser testing not applicable and require equivalent native macOS interaction evidence for every specified visible state.

### Trade-offs and risks

XCUITest for a menu-bar application can require stable launch arguments and accessibility identifiers and may be slower than unit tests. It provides evidence against the actual product rather than a substitute UI.

### Verification

Run XCUITest on macOS for idle, preview, applying, success, failure, recovery, and Undo states; assert keyboard reachability and meaningful accessibility labels and retain screenshot attachments.
