## Purpose

Define non-destructive configuration loading, saving, profile compatibility, and legacy migration behavior.

## ADDED Requirements

### Requirement: Read-only startup

Startup MUST inspect configuration, profiles, legacy state, and incomplete journals without applying a profile or changing user files and external-system state. A saved active-profile identifier is display state, not authorization to apply.

#### Scenario: Previously active profile exists

- **WHEN** RiceBarMac launches with a saved active-profile identifier
- **THEN** it may display the saved selection after validation
- **AND** it performs no profile action until the user explicitly applies one

#### Scenario: Configuration is absent or malformed

- **WHEN** configuration is missing or cannot be decoded
- **THEN** startup remains read-only
- **AND** missing state receives in-memory defaults while malformed source bytes remain untouched and an actionable error is shown

### Requirement: Explicit staged legacy migration

The system MUST detect `.ricebar` data without mutating it, obtain explicit user confirmation, stage the migration, and commit it through recoverable operations. It MUST preserve the legacy source until success and MUST NOT silently merge into or overwrite existing `.ricebarmac` data.

#### Scenario: Legacy-only configuration migrates successfully

- **WHEN** the user confirms migration and no destination conflict exists
- **THEN** the system validates and stages all migrated data before committing it
- **AND** current-format data is available after commit while the legacy source remains recoverable according to the documented retention rule

#### Scenario: Current and legacy configuration conflict

- **WHEN** both locations contain data that would target the same destination
- **THEN** migration stops without changing either location
- **AND** the user receives a conflict explanation and non-destructive choices

#### Scenario: Migration fails partway

- **WHEN** an injected failure occurs during staged migration
- **THEN** partial current-format output is rolled back
- **AND** the original legacy bytes remain unchanged

### Requirement: Tolerant decode and atomic save

Configuration decoding MUST provide documented defaults for absent known fields and tolerate unknown fields. It MUST NOT replace malformed data with defaults on disk. A successful save MUST create a unique pre-write backup and atomically replace the destination only after encoding and validation succeed.

#### Scenario: Older configuration omits a field

- **WHEN** a valid older configuration lacks a newly introduced optional field
- **THEN** the documented default is used without rejecting or eagerly rewriting the file

#### Scenario: Future configuration has unknown fields

- **WHEN** otherwise valid configuration contains unknown fields
- **THEN** known settings load and the unknown fields do not prevent startup

#### Scenario: Save encoding or replacement fails

- **WHEN** encoding, staging, or atomic replacement fails
- **THEN** the prior configuration remains readable at its original path or recorded backup
- **AND** the failure is surfaced rather than followed by a default overwrite

### Requirement: Existing profile-format compatibility

The system MUST continue to load valid existing JSON and YAML profiles and their intended wallpaper, Alacritty, VS Code, Cursor, replacement, symlink, and startup-script declarations. Invalid profiles MUST remain identifiable with validation errors and MUST NOT be silently converted to default profiles.

#### Scenario: Existing JSON and YAML fixtures load

- **WHEN** representative profiles accepted by the previous release are scanned
- **THEN** their identifiers, metadata, and supported action semantics remain equivalent

#### Scenario: One profile is invalid

- **WHEN** a profile file is malformed or declares an unsupported or unsafe action
- **THEN** other valid profiles remain available
- **AND** the invalid profile is shown as invalid with its source path and actionable reason
