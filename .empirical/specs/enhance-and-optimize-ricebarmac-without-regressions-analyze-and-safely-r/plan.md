# Execution Plan: RiceBarMac v1.2.0

## Strategy

Implement from the lowest-risk injectable core outward. Establish tests and compatibility models before routing any UI intent through new mutation code. Keep the old Apply entry points only as temporary adapters, then remove their bodies once every call site uses the coordinator. Do not tag, publish, or update Homebrew until all implementation, native evidence, review, signing, and notarization gates pass for the same commit.

## Work Packages

### P-01: Preserve baseline and introduce test seams

**Dependencies:** approved specification and design.

**Changes:**

- Record the restored upstream baseline and preserve the user's existing `README.md` and `CLAUDE.md` work without overwriting unrelated edits.
- Add XcodeGen unit and UI test target directories and initial smoke tests.
- Add injected RiceBar root, user home, clock, UUID generator, user defaults, filesystem, and external-effect abstractions suitable for temporary test homes.
- Keep production defaults rooted at the existing `~/.ricebarmac` paths.

**Files:** `project.yml`, new `App/Tests/**`, new `App/UITests/**`, new dependency/client types under `App/Sources`.

**Verification:** XcodeGen structure inspection on Linux; project generation/build/test on macOS CI. Confirm no test references the real home directory.

**Criteria:** AC-14 foundation; enables AC-1 through AC-13 tests.

### P-02: Add compatible data and error models

**Dependencies:** P-01.

**Changes:**

- Add explicit defaulted decoding for `RiceBarConfig`, nested settings, and `Profile` while retaining current JSON/YAML keys.
- Add `ProfileLoadItem`, typed configuration load state, validation issue codes, `ProfileApplyPlan`, file-object state/fingerprints, external effects, transaction journal, and operation-state models.
- Replace swallowed journal encoding/decoding errors with typed surfaced errors.
- Add fixture matrices for older, current, unknown-field, malformed, JSON, and YAML inputs.

**Files:** `App/Sources/Models/**`, `App/Sources/Profile.swift`, `App/Tests/Fixtures/**`, model tests.

**Verification:** Codable round trips, byte-preservation assertions for invalid input, and legacy profile semantic comparisons.

**Criteria:** AC-2, AC-4, AC-6, AC-9, AC-10, AC-11.

### P-03: Implement the safe filesystem boundary

**Dependencies:** P-01, P-02.

**Changes:**

- Introduce `FileSystemClient` using `lstat`-equivalent inspection for files, directories, valid symlinks, and broken symlinks.
- Implement standardized path containment, parent-chain resolution with loop detection, parent fingerprints, adjacent unique staging/backup paths, atomic move/write, and supported permission restoration.
- Add fault-injecting and recording clients for every primitive boundary.
- Route new work away from destructive `FileSystemService` helpers; retain unrelated read/capture helpers temporarily.

**Files:** new filesystem client and path-safety files, focused adaptations in `FileSystemService.swift`, exhaustive filesystem tests.

**Verification:** temporary-tree tests for all object types, escape/loop/prefix-confusion cases, collisions, permissions, and injected failures.

**Criteria:** AC-3, AC-4, AC-6, AC-7.

### P-04: Build deterministic profile planning

**Dependencies:** P-02, P-03.

**Changes:**

- Implement a read-only planner for conventional `home/` overlays, explicit replacements, rendered templates, Alacritty, VS Code, Cursor, wallpaper, extension commands, and startup scripts.
- Sort actions deterministically and detect missing sources, recursive mappings, duplicate/ancestor conflicts, unsafe paths, and unsupported integration warnings before writes.
- Ensure preview and Apply share the same plan value and revalidate fingerprints before execution.

**Files:** new `ProfilePlanner.swift` and planner helpers/tests; small extraction from `ProfileService.swift` and template helpers.

**Verification:** golden ordered plans, zero-mutation recording-client assertions, invalid-plan aggregation, and preview/Apply identity tests.

**Criteria:** AC-2, AC-3, AC-11.

### P-05: Implement journals, Apply, rollback, recovery, and Undo

**Dependencies:** P-03, P-04.

**Changes:**

- Implement atomic transaction storage and lifecycle transitions.
- Execute each action through intent, stage, backup, install, fingerprint, and completion records.
- Roll back in reverse order; refuse to overwrite post-apply user changes; retain unresolved journal/backups in recovery-required state.
- Persist active profile only after commit and restore the former value only after successful rollback/Undo.
- Run non-reversible effects after commit and record distinct warnings.
- Implement exact, idempotent latest-transaction Undo and incomplete-journal recovery inspection.

**Files:** new `TransactionStore.swift`, `ProfileTransactionExecutor.swift`, `RecoveryService.swift`, external-effect client; retire `ApplyRecord.swift` behavior.

**Verification:** failure before/after every boundary, full tree snapshots, crash journal fixtures, external-effect failures, active-profile assertions, conflicts, and repeated Undo.

**Criteria:** AC-4, AC-5, AC-6, AC-7.

### P-06: Serialize operations and eliminate duplicated Apply paths

**Dependencies:** P-05.

**Changes:**

- Add the actor-owned bounded FIFO coordinator with visible queue position, duplicate coalescing, structured cancellation, and progress events.
- Replace synchronous polling, `ApplyActivity`, detached/background continuations, unstructured theme tasks, and `Thread.sleep` in the Apply path.
- Route hotkeys, menus, profile navigation, reapply, and compatibility calls through Preview/Apply coordinator requests.
- Delete the duplicated Apply implementations and destructive revert implementation after call-site migration.

**Files:** new coordinator; `ProfileService.swift`, `StatusBarViewModel.swift`, `ApplyActivity.swift`, integration tests.

**Verification:** deterministic concurrent barriers, FIFO/coalescing tests, cancellation at each supported boundary, no-overlap recording, source scan for forbidden Apply polling, and 1,000-file heartbeat test.

**Criteria:** AC-5, AC-7, AC-8, AC-13.

### P-07: Make loading, saving, migration, and watchers non-destructive

**Dependencies:** P-03, P-05.

**Changes:**

- Make configuration startup read-only, expose malformed state, and implement atomic backed-up save with rollback.
- Scan profiles into valid and invalid rows without synthetic defaults for broken definitions.
- Detect `.ricebar` read-only and implement explicit conflict-aware staged migration that preserves the source.
- Make `autoReloadProfiles` start/stop one watcher, debounce metadata reload only, and suppress app-originated events without time-based reapply logic.
- Remove automatic first-profile persistence and every refresh-triggered Apply.

**Files:** `ConfigService.swift`, `ProfileService.swift`, new migration/watcher helpers, configuration/migration/watcher tests.

**Verification:** launch matrix, byte/tree preservation, save failure injection, migration conflict/failure fixtures, watcher registration counts, and no-Apply event assertions.

**Criteria:** AC-1, AC-9, AC-10, AC-11, AC-12.

### P-08: Consolidate application state and implement safety UI

**Dependencies:** P-06, P-07.

**Changes:**

- Create one composition-root `ApplicationModel` and inject it into `StatusBarController`, settings, and profile-management surfaces.
- Remove constructor-triggered refresh/apply and duplicate hotkey registration.
- Change profile selection to accessible Preview with exact actions/warnings and Apply/Cancel.
- Add progress/queue, committed warning, failed-and-rolled-back, migration conflict, recovery-required, and Undo states/actions.
- Respect notifications and visible appearance/general settings or remove unsupported controls/claims.
- Add stable accessibility identifiers and keyboard behavior.

**Files:** `RiceBarMacApp.swift`, `StatusBarController.swift`, `StatusBarViewModel.swift` or replacement model, focused SwiftUI components.

**Verification:** model state tests and XCUITest fixtures/screenshots for every required state and keyboard/accessibility flow.

**Criteria:** AC-1, AC-5, AC-6, AC-7, AC-8, AC-12, AC-UI-1, AC-UI-2.

### P-09: Complete native automated verification

**Dependencies:** P-02 through P-08.

**Changes:**

- Finish unit/integration suites and deterministic temporary-root fixtures.
- Add UI-test launch arguments, fake external effects, and screenshot attachments without weakening production behavior.
- Add macOS CI that installs XcodeGen, checks generated-project drift, builds, analyzes, tests Debug/Release, archives results, and inspects deployment target and universal slices.

**Files:** `App/Tests/**`, `App/UITests/**`, `project.yml`, new `.github/workflows/ci.yml`.

**Verification:** green required CI for the exact candidate commit with test/result/screenshot artifacts.

**Criteria:** AC-1 through AC-15, AC-UI-1, AC-UI-2.

### P-10: Align version, entitlements, documentation, and release automation

**Dependencies:** P-09 implementation complete; CI configuration may be drafted earlier.

**Changes:**

- Set canonical v1.2.0/build 120 metadata in `project.yml` and plist substitutions.
- Remove contradictory sandbox/application-group release entitlements and retain only justified direct-distribution entitlements.
- Add strict version and release-verification scripts.
- Replace unsigned release workflow with required test, Developer ID, hardened runtime, notarization, stapling, Gatekeeper, archive, checksum, and cask gates.
- Update README and v1.2.0 release notes to supported behavior, migration, backups, Undo, recovery, macOS 14, signature verification, and accurate integrations.

**Files:** `project.yml`, `App/Info.plist`, release entitlement files, `scripts/**`, `.github/workflows/release.yml`, `README.md`, `CHANGELOG.md` or release-notes file.

**Verification:** shell static checks on Linux; full scripts and workflow on macOS. Review documentation claims against tests and source.

**Criteria:** AC-14, AC-15, AC-16, AC-17, AC-18.

### P-11: Review and repair the release candidate

**Dependencies:** P-09, P-10.

**Changes:**

- Collect an acceptance-criterion evidence matrix from exact command and native UI outputs.
- Review all product, test, CI, release, entitlement, and documentation diffs independently.
- Repair every blocking finding and rerun affected evidence; do not waive data-safety, native-test, signing, or release-integrity failures.
- Archive approved capability deltas only after review passes.

**Files:** Empirical evidence/review artifacts and any repaired implementation files.

**Verification:** no unresolved blocking review findings, every AC mapped to passing evidence, clean candidate commit, and reviewed delta archive.

**Criteria:** AC-1 through AC-18 and AC-UI-1/2.

### P-12: Tag, publish, and synchronize Homebrew

**Dependencies:** P-11 plus available Apple signing/notarization and Homebrew credentials.

**Changes:**

- Confirm candidate commit and v1.2.0 tag/version/build equality.
- Push the reviewed commit/tag and monitor the release workflow to completion.
- Verify the public immutable asset independently, then verify the synchronized Homebrew cask version, URL, checksum, macOS minimum, audit, install, launch, and upgrade preservation.
- Report the release URL, checksum, cask commit, and final evidence. If credentials or any gate are absent, stop before tagging/publication and report the exact prerequisite rather than creating a partial release.

**Verification:** public signed/notarized/stapled asset, matching cask, and passing post-publication checks.

**Criteria:** AC-15, AC-16, AC-17, AC-18.

## Dependency Order

```text
P-01 -> P-02 -> P-03 -> P-04 -> P-05 -> P-06
                    \                    /
                     +------ P-07 ------+
                                      |
                                      v
                                    P-08 -> P-09 -> P-10 -> P-11 -> P-12
```

P-10 workflow and documentation drafting may overlap P-08/P-09, but its verification cannot pass until the implementation and native suites are final.

## Evidence Matrix

| Evidence ID | Required output | Work package |
| --- | --- | --- |
| E-UNIT | XCTest result bundle for models, planning, path safety, transaction, rollback, Undo, migration, watcher, concurrency, and performance | P-02 through P-09 |
| E-UI | XCUITest result bundle and idle/preview/applying/success/failure/recovery/Undo screenshots | P-08, P-09 |
| E-BUILD | XcodeGen drift, Debug/Release build and analyze, deployment target, plist, and universal slice output | P-09, P-10 |
| E-SIGN | Strict codesign, hardened-runtime/entitlement inspection, notarization acceptance, staple validation, and Gatekeeper output | P-10, P-12 |
| E-ASSET | Archive listing, version/build, public download SHA-256, and release metadata comparison | P-10, P-12 |
| E-BREW | Final cask diff, audit, install, launch, checksum, and upgrade-preservation output | P-10, P-12 |
| E-REVIEW | Independent diff findings, repairs, and AC-to-evidence traceability | P-11 |

## Stop Conditions

- Stop mutation work if a test fixture or command resolves to the real user home rather than an explicitly created temporary root.
- Stop release publication if the candidate differs from reviewed evidence, native CI is missing/failing, a version differs, an architecture is absent, Apple credentials are missing, signing/notarization/stapling/Gatekeeper fails, or the cask cannot be verified.
- Preserve journals and backups and stop automatic recovery whenever destination fingerprints show post-transaction user changes.
- Never resolve an implementation difficulty by weakening an approved acceptance criterion.

## Definition of Done

All P-01 through P-11 work is implemented, tested, evidenced, and reviewed; capability deltas are archived; P-12 has produced and independently verified the public v1.2.0 asset and synchronized cask; and the Empirical feature reaches Done. If only external release credentials prevent P-12, the implementation must remain complete and the feature must report the exact publication blocker without claiming a release.
