# Application Experience Specification

## Purpose

Define coherent application state, settings behavior, responsiveness, and accessible native UI evidence.

## Requirements

### Requirement: One shared observable application model

The menu bar, settings windows, hotkeys, and application lifecycle MUST observe one shared model backed by one mutation coordinator. Construction or refresh MUST NOT register duplicate hotkey handlers, start duplicate watchers, or trigger profile application.

#### Scenario: Multiple windows are opened

- **WHEN** the user opens and closes settings and profile-management windows repeatedly
- **THEN** every surface shows the same profile and operation state
- **AND** exactly one configured handler exists for each hotkey and one watcher exists for each watched location

### Requirement: Explicit operation state and controls

The UI MUST expose Preview before Apply, enable Undo only for an eligible completed transaction, and distinguish idle, queued, validating, applying, committed, committed-with-warning, failed-and-rolled-back, and recovery-required states. A profile MUST be marked active only after the reversible transaction commits.

#### Scenario: Apply succeeds

- **WHEN** the requested profile commits successfully
- **THEN** progress ends, the selected profile becomes active, and Undo becomes available
- **AND** success is not displayed before commit

#### Scenario: Apply or rollback fails

- **WHEN** Apply rolls back successfully or requires recovery
- **THEN** the former profile remains active
- **AND** the UI presents a distinct actionable message appropriate to rollback success or unresolved recovery

#### Scenario: Preview contains warnings

- **WHEN** a valid plan includes replacement, backup, or non-reversible external-effect warnings
- **THEN** the preview identifies the affected paths or effects before Apply can be confirmed

### Requirement: Watcher and setting behavior is effective

When auto-reload is enabled, filesystem observation MUST refresh profile metadata only and MUST suppress feedback caused by the app's own transaction. When disabled, observation MUST stop. Every persisted user-facing setting MUST either affect documented behavior or be removed from the visible interface.

#### Scenario: Profile metadata changes externally

- **WHEN** auto-reload is enabled and a profile definition changes outside the app
- **THEN** the available profile metadata refreshes without applying any profile

#### Scenario: Auto-reload is disabled

- **WHEN** the user disables auto-reload
- **THEN** the observer stops and subsequent filesystem events do not refresh or apply state until explicitly requested

### Requirement: Responsive structured work

Profile scanning, planning, mutation, backup, rollback, and external commands MUST avoid blocking the main actor. The application MUST remain observably responsive during a deliberately slow 1,000-file operation and MUST NOT coordinate progress through busy waits or `Thread.sleep`.

#### Scenario: Large apply runs slowly

- **WHEN** a test adapter delays an Apply across a 1,000-file fixture
- **THEN** a scheduled main-actor heartbeat continues to advance within the test threshold
- **AND** progress and cancellation state continue to update coherently

### Requirement: Keyboard and accessibility-complete native interface

Every user-facing control and alert in the menu and settings MUST be keyboard operable and expose a meaningful accessibility role, label, value, and state where applicable. Stable identifiers MUST support native UI tests.

#### Scenario: User completes a safety flow by keyboard

- **WHEN** a keyboard-only user previews, confirms, observes, and undoes an Apply
- **THEN** focus order reaches every required control and the operation completes without pointer input

#### Scenario: Native UI evidence is captured

- **WHEN** XCUITest exercises idle, preview, applying, success, failure, recovery, and Undo fixtures
- **THEN** accessibility assertions pass and screenshot attachments record each visible state
