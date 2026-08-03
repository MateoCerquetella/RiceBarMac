# Profile Application Safety Specification

## Purpose

Define the safety, transaction, recovery, and concurrency guarantees for previewing and applying a profile.

## Requirements

### Requirement: Immutable validated apply plan

The system MUST resolve an explicit profile request into one immutable ordered plan before mutation. The plan MUST identify every reversible filesystem action, displaced destination, unique backup location, non-reversible external effect, and warning. Apply MUST execute the validated plan model and MUST NOT silently recompute a different action set.

#### Scenario: Preview is read-only and exact

- **WHEN** a user previews a valid profile
- **THEN** the application shows the same ordered actions and backup locations that a subsequent unchanged Apply will consume
- **AND** no user file, active-profile value, external application, wallpaper, or startup script is changed

#### Scenario: Unsafe plan is rejected before writes

- **WHEN** any source is missing, any resolved path escapes the canonical user home, an existing parent is an unsafe symlink, a directory maps into itself, or actions conflict at one destination
- **THEN** validation rejects the entire plan before the first filesystem mutation
- **AND** reports every deterministically discoverable validation error

### Requirement: Exact backups and durable journal

Before replacing a regular file, directory, valid symlink, or broken symlink, the system MUST preserve its exact restorable state at a unique non-overwriting adjacent backup path. The system MUST atomically persist transaction identity, former active profile, planned actions, action intent, completion state, and backup metadata.

#### Scenario: Existing destination is displaced safely

- **WHEN** Apply replaces an existing destination
- **THEN** the former object is moved to its recorded unique same-volume backup before the replacement is installed
- **AND** its original type, contents, supported permissions, and literal symlink target can be restored

#### Scenario: Destination did not exist

- **WHEN** Apply creates an item at a previously absent destination
- **THEN** the journal records that absence without inventing a backup
- **AND** rollback or Undo removes only the item created by that transaction

### Requirement: Rollback and crash recovery

On a reversible failure, the system MUST roll completed actions back in reverse order and MUST preserve the former active-profile state. It MUST NOT claim success or automatically retry a destructive action. If a journal is incomplete or rollback fails, the system MUST retain all recovery material and enter an explicit recovery-required state.

#### Scenario: Mid-transaction failure rolls back

- **WHEN** an injected error occurs after any reversible action has completed
- **THEN** completed actions are reversed in last-in-first-out order
- **AND** the resulting filesystem and active-profile state equal their exact pre-apply state

#### Scenario: Rollback cannot finish

- **WHEN** restoring one or more actions fails
- **THEN** the journal and backups remain intact
- **AND** the user sees the unresolved paths and available recovery action without a success indication or destructive retry

#### Scenario: Launch finds an ambiguous journal

- **WHEN** startup finds intent recorded without an unambiguous completion state
- **THEN** startup remains read-only and enters recovery-required state
- **AND** does not guess whether to delete, replace, or restore the affected destination

### Requirement: Exact one-time Undo

The system MUST allow the most recent completed, non-undone transaction to restore its exact before-state and former active profile. Undo MUST be idempotent and MUST retain recovery evidence if it cannot complete.

#### Scenario: Undo a successful apply

- **WHEN** the user invokes Undo for the latest completed Apply
- **THEN** displaced files, directories, valid symlinks, and broken symlinks are restored exactly
- **AND** only destinations newly created by that Apply are removed
- **AND** the former active profile becomes active after restoration commits

#### Scenario: Undo is invoked twice

- **WHEN** an already undone transaction receives another Undo request
- **THEN** the request is a safe no-op and no restored user data is removed

### Requirement: Serialized structured mutations

One asynchronous coordinator MUST serialize Preview, Apply, recovery, and Undo requests. It MUST expose deterministic queued, executing, committed, warning, failed, and recovery-required states and support cancellation only at boundaries that preserve a known state. It MUST NOT use polling sleeps or unstructured fire-and-forget apply work.

#### Scenario: Two profiles are requested concurrently

- **WHEN** a second Apply arrives while another mutation is executing
- **THEN** the requests never mutate the filesystem concurrently
- **AND** the configured queue policy is visible and deterministic

#### Scenario: Cancellation is requested

- **WHEN** cancellation arrives at a supported boundary
- **THEN** the current transaction either stops before mutation or rolls back completed reversible work
- **AND** no mixed profile state is reported as successful

### Requirement: External effects follow the reversible commit

Startup scripts and third-party application or wallpaper commands that cannot be transactionally reversed MUST run only after reversible filesystem work commits. Their failures MUST be reported as post-commit warnings and MUST NOT misrepresent the committed filesystem state as rolled back.

#### Scenario: Startup script fails after commit

- **WHEN** reversible actions commit and the profile startup script exits unsuccessfully
- **THEN** the committed transaction remains recorded as applied
- **AND** the UI reports the script failure as a distinct post-commit warning with captured context
