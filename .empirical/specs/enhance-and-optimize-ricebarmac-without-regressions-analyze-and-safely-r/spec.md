# Enhance And Optimize Ricebarmac Without Regressions Analyze And Safely R

## Request

> Enhance and optimize RiceBarMac without regressions: analyze and safely refactor the app, fix discovered bugs, improve reliability and performance, add verification, and publish a new signed and notarized release with the Homebrew cask synchronized.
>
> Approved Socratic discovery:
> - Primary user and problem: Primary users are macOS developers and power users who rely on RiceBarMac to switch desktop, terminal, IDE, wallpaper, and system profiles. Today they face silent or destructive behavior: existing configuration can be removed without usable backups, profiles may auto-apply, failures are swallowed, settings can be overwritten, and the published version and cask may not match the source. This matters because the app modifies valuable user configuration; users need to trust that every switch is predictable, recoverable, responsive, and distributed as a legitimate signed application.
> - Smallest observable outcome: Launching RiceBarMac must never alter user files. When a user explicitly selects a valid profile, the app validates a deterministic change plan, applies only one profile operation at a time, backs up every replaced item, updates the active-profile UI only after success, and offers a working undo that restores the prior state. If any step fails, the user sees a clear error and the filesystem is rolled back instead of being left partially changed. Existing profiles and legacy configuration remain usable, and the finished version installs from a signed and notarized GitHub artifact whose version and checksum match the Homebrew cask.
> - Scope, non-goals, and constraints: The first release covers the existing menu-bar profile picker, apply progress and failure states, settings, profile creation and deletion, hotkeys, launch at login, configuration migration, backup, dry-run planning, and undo. It must preserve current JSON and YAML profiles and intended wallpaper, Alacritty, VS Code, Cursor, replacement, and startup-script behavior on macOS 14 or newer for both Apple silicon and Intel. User-facing controls and alerts must remain keyboard usable, have meaningful accessibility labels, and never claim success before work completes. Constraints include XcodeGen as the project source, no direct project-file edits, backward-compatible on-disk data, minimal dependencies, and synchronized app and Homebrew repositories. Out of scope are a broad visual redesign, cloud sync, App Store distribution, new profile formats, support below macOS 14, and implementing currently stubbed Terminal.app, iTerm2, or system-theme features; unsupported claims should instead be corrected in documentation.
> - Failure cases and risks: The unacceptable failures are lost or overwritten configuration, an apply operation stopping halfway, two profile applications racing, cancellation leaving mixed state, unsafe destinations escaping the user home, symlink loops, corrupt or older config being replaced, watcher feedback repeatedly reapplying, permission denial, a startup script or external editor command failing, UI success reported before completion, and a release artifact, version, signature, notarization ticket, checksum, or cask becoming inconsistent. Preflight validation must reject invalid plans before writes. File mutations must use unique backups and a transaction journal, restore the previous active profile and filesystem on recoverable errors, retain recovery data if rollback itself fails, and show an actionable error without automatic destructive retry. External side effects that cannot be rolled back must run after reversible filesystem work and be reported separately. Scanning and apply work must stay off the main thread without busy waits. Release automation must fail closed before publishing or updating Homebrew when tests, signing, notarization, stapling, version checks, or credentials are missing.
> - Required verification: Automated XCTest unit and integration suites will run against temporary home directories and injected filesystem/system adapters to assert plan validation, safe-path rejection, tolerant decoding, legacy migration, backup uniqueness, successful apply, forced mid-transaction failure and rollback, exact undo restoration, watcher suppression, and serialization of concurrent requests. A macOS CI workflow will regenerate the Xcode project, build, analyze, and test Debug and Release configurations, verify both arm64 and x86_64 slices, and fail on version drift. Native XCUITest interaction checks will cover launch-without-apply, explicit profile selection, progress, success, failure, dry-run, and undo, with screenshot artifacts and accessibility assertions for visible states; the real-browser gate is not applicable because RiceBarMac has no browser surface, so equivalent real macOS application evidence is required. Release checks will verify codesign, hardened runtime entitlements, notarization acceptance, stapling, Gatekeeper assessment, archive contents, tag and bundle version equality, SHA-256 equality with the cask, Homebrew audit, installation, launch, and upgrade preservation. Each acceptance criterion also requires recorded command output and an independent diff review before tagging.

## Goal

Ship RiceBarMac v1.2.0 as a predictable and recoverable profile switcher. Launch is read-only, every explicit apply is derived from a validated immutable plan, reversible filesystem changes are backed up and journaled, failures roll back safely, and the published application is the same signed and notarized build referenced by the Homebrew cask.

## Acceptance Criteria

- [ ] [AC-1] Launching with no configuration, a valid current configuration, a legacy `.ricebar` configuration, a malformed configuration, or a previously active profile performs no profile application and makes no filesystem or external-system change until the user explicitly requests one.
- [ ] [AC-2] Previewing a profile produces the exact ordered immutable plan later used by Apply, including creates, replacements, backup locations, external effects, and warnings, without mutating user state.
- [ ] [AC-3] Preflight validation rejects the complete plan before its first mutation when a source is missing, a source or destination escapes the canonical user home, a destination traverses an unsafe parent symlink, a directory maps recursively into itself, or two actions conflict with the same destination.
- [ ] [AC-4] Before replacing a regular file, directory, valid symlink, or broken symlink, Apply preserves its exact prior type, contents, permissions where supported, and symlink target at a unique non-overwriting backup path and records the intent and result in an atomically persisted transaction journal.
- [ ] [AC-5] A successful explicit Apply executes exactly once, marks the journal complete, suppresses feedback from its own filesystem changes, and changes the active-profile state only after all reversible work commits.
- [ ] [AC-6] A forced failure at every reversible mutation boundary rolls completed actions back in reverse order and preserves the former active profile; if rollback cannot finish, RiceBarMac retains the journal and backups, enters a visible recovery-required state, reports the unresolved paths, and neither reports success nor retries destructively.
- [ ] [AC-7] Undo restores the exact pre-apply file, directory, and symlink state, removes only items created by that apply, restores the former active-profile state, and becomes a safe no-op after the transaction has already been undone.
- [ ] [AC-8] One asynchronous coordinator serializes Preview, Apply, recovery, and Undo so two mutations cannot overlap; queued requests and cancellation at supported boundaries leave a deterministic state without polling or mixed profile contents.
- [ ] [AC-9] Legacy `.ricebar` data migrates only after explicit confirmation through a staged, journaled operation: the original remains untouched until success, existing `.ricebarmac` data is never silently overwritten, and a failed migration removes its partial destination while preserving the source.
- [ ] [AC-10] Configuration loading supplies documented defaults for missing known fields, tolerates unknown fields, preserves malformed source bytes while showing an actionable error, and uses an atomic replace plus a pre-write backup for every successful save.
- [ ] [AC-11] Existing valid JSON and YAML profiles continue to load with the supported wallpaper, Alacritty, VS Code, Cursor, file replacement, symlink, and startup-script behaviors; invalid profiles remain visible with validation errors instead of being silently replaced by defaults.
- [ ] [AC-12] Auto-reload, when enabled, refreshes profile metadata only and never applies a profile; disabling it stops observation, one shared application model owns service state, and hotkey registration is updated without duplicate handlers.
- [ ] [AC-13] During a deliberately slow apply over a 1,000-file fixture, a main-actor heartbeat continues to advance and the implementation uses structured asynchronous work rather than `Thread.sleep`, busy waits, or an unstructured apply task.
- [ ] [AC-UI-1] [UI] The menu and settings expose Preview and Undo when valid, show applying and queued states, mark a profile active only after success, and present distinct actionable warning, apply-failure, rollback-failure, migration-conflict, and recovery-required messages.
- [ ] [AC-UI-2] [UI] All user-facing controls and alerts are keyboard operable and have meaningful accessibility labels; native UI evidence captures idle, preview, applying, success, failure, recovery, and undo states.
- [ ] [AC-14] XcodeGen defines unit and UI test targets, and macOS CI regenerates the project, builds, analyzes, and tests Debug and Release while verifying the deployment target and both `arm64` and `x86_64` slices of the release application.
- [ ] [AC-15] `project.yml` is the canonical version source, and the v1.2.0 tag, marketing version, monotonically increased build number, generated plist, About UI, archive, and release metadata agree; CI rejects any drift before publication.
- [ ] [AC-16] Release automation fails closed unless the exact archived application has a valid Developer ID signature, hardened runtime, the intended minimum entitlements, accepted notarization, a stapled ticket, and a passing Gatekeeper assessment.
- [ ] [AC-17] The Homebrew cask is updated only after the final asset exists; its version, URL, SHA-256, and macOS 14 minimum match that asset, and automated `brew audit`, install, launch, and upgrade checks preserve user configuration.
- [ ] [AC-18] README and release notes describe only implemented behavior and accurately document Preview, backup placement, Undo, legacy migration, failure recovery, supported integrations, macOS requirements, and release verification without claiming stubbed Terminal.app, iTerm2, or system-theme support.

## Scope

- Introduce an immutable apply plan, adjacent unique backups, an atomic transaction journal, reverse-order rollback, recovery guidance, and exact Undo for reversible filesystem actions.
- Separate filesystem and external-system boundaries behind injectable interfaces and consolidate all mutations under one asynchronous coordinator.
- Make configuration decoding, saving, profile validation, and `.ricebar` migration backward-compatible and non-destructive.
- Consolidate duplicated view-model/service ownership, make settings and watchers effective, and add explicit Preview, progress, warning, failure, recovery, and Undo UI states.
- Add XcodeGen-managed XCTest and XCUITest targets, deterministic fixtures and fault injection, macOS CI, version-consistency checks, and recorded native UI evidence.
- Prepare and publish v1.2.0 as a universal Developer ID signed, notarized, stapled release, then synchronize and verify its Homebrew cask.
- Correct documentation to match the supported product surface.

## Non-goals

- A broad visual redesign, cloud sync, telemetry, an auto-updater, or unrelated new product features.
- App Store distribution or the security-scoped bookmark architecture required for a sandboxed arbitrary-home-file workflow.
- Support for macOS versions before 14 or removal of either Intel or Apple-silicon support.
- New profile formats or intentional breaking changes to existing JSON, YAML, or configuration schemas.
- Implementing currently stubbed Terminal.app, iTerm2, or system-theme integrations.
- Pretending arbitrary startup scripts or third-party application commands are reversible; they run only after the filesystem commit and can produce a post-commit warning.
- Direct manual edits to generated Xcode project files.

## Behavioral Model

1. Startup reads and validates state without applying it. An incomplete journal produces a recovery-required state and an explicit recovery choice.
2. Preview resolves and validates one immutable `ProfileApplyPlan`; Apply consumes that same model rather than recomputing a second path.
3. The mutation coordinator records action intent, creates an adjacent same-volume unique backup when needed, performs the action, and records completion before advancing.
4. A reversible error rolls completed actions back in reverse order. Active-profile state changes only after the reversible transaction commits.
5. Non-reversible external effects run after commit and are reported as post-commit warnings without corrupting the committed filesystem transaction.
6. Undo consumes the most recent completed, non-undone journal and restores its exact before-state once.

## Risks and Mitigations

- Large directories may be expensive to copy. Prefer adjacent same-volume moves for displaced destinations, retain backups through verification, and measure the 1,000-file fixture.
- A process crash can occur between mutation and journal completion. Persist intent and completion separately, classify ambiguous actions as recovery-required, and never guess destructively.
- Symlinks create a path-escape trust boundary. Validate standardized and resolved paths, inspect every existing parent component without following an unsafe link, and test valid and broken links explicitly.
- External commands cannot be rolled back. Run them after the reversible commit, capture exit status, and distinguish their warning from a rollback-capable failure.
- Configuration and version metadata can drift. Use tolerant decoding, atomic writes, one generated project source, and mechanical consistency checks.
- The current Linux host cannot execute macOS binaries or Apple signing tools. Require macOS CI evidence and block release publication when that evidence or credentials are unavailable.
- Cross-repository cask updates can point at the wrong asset. Compute the checksum from the final immutable release asset and verify the cask in a clean Homebrew environment before publication completes.

## Verification

- **XCTest unit and integration suites (AC-1 through AC-13):** temporary home directories, JSON/YAML and legacy fixtures, valid and broken symlinks, unsafe path cases, injected failures at each action boundary, crash-journal fixtures, exact before/after tree comparisons, concurrent request tests, watcher tests, and a main-actor heartbeat performance test.
- **XcodeGen and macOS CI (AC-11 through AC-15):** regenerate the project from `project.yml`; build, analyze, and test Debug and Release; inspect deployment targets, bundle metadata, and universal slices; archive command output as evidence.
- **Native XCUITest evidence (AC-UI-1 and AC-UI-2):** drive the real menu-bar application and settings window with accessibility assertions and screenshot attachments for each named state. Browser verification is not applicable because RiceBarMac has no browser surface.
- **Release verification script (AC-15 and AC-16):** compare tag/version/build metadata, inspect archive contents and architectures, run strict `codesign` verification, inspect entitlements, submit and wait for notarization, staple and validate, and run `spctl` against the exact distributed application.
- **Homebrew verification (AC-17):** download the published asset, recompute SHA-256, compare the cask fields, and run audit, install, launch, and upgrade-preservation checks on supported macOS runners.
- **Documentation and independent review (AC-1 through AC-18):** map every acceptance criterion to recorded command or UI evidence, review the final diff independently, and stop before tagging if any item lacks evidence.

## External Prerequisites

- CI secrets for a Developer ID Application certificate and its import password, Apple team identifier, and App Store Connect notarization API key, issuer identifier, and private key.
- A scoped token or approved automation identity able to update the Homebrew cask repository after the GitHub asset is final.
- macOS runners capable of native XCTest/XCUITest, signing, notarization, Gatekeeper, and Homebrew verification. These gates cannot be satisfied on the current Linux host alone, so missing prerequisites block publication rather than weakening the release.

## Capability Deltas

- [Profile application safety](deltas/profile-application-safety.md)
- [Configuration compatibility](deltas/configuration-compatibility.md)
- [Application experience](deltas/application-experience.md)
- [Release integrity](deltas/release-integrity.md)
