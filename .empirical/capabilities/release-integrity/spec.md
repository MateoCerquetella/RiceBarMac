# Release Integrity Specification

## Purpose

Define reproducible build, version, signing, notarization, publication, Homebrew, and documentation gates for v1.2.0.

## Requirements

### Requirement: Required macOS verification pipeline

XcodeGen MUST define unit and UI test targets. macOS CI MUST regenerate the project from `project.yml`, build, analyze, and test Debug and Release, and verify the macOS 14 deployment target plus `arm64` and `x86_64` slices before a release job can run.

#### Scenario: A required check fails

- **WHEN** generation, build, analysis, tests, deployment inspection, architecture inspection, or required evidence fails or is missing
- **THEN** the release workflow stops before signing, tagging, asset publication, or cask update

### Requirement: One canonical version for v1.2.0

`project.yml` MUST be the canonical source for marketing and build versions. The v1.2.0 tag, monotonically increased build number, generated plist, About display, archive, release title, and asset naming MUST agree, and CI MUST reject drift.

#### Scenario: Version metadata disagrees

- **WHEN** any checked source, generated artifact, tag, or release field reports a different marketing or build version
- **THEN** publication stops with the mismatched values identified

### Requirement: Fail-closed Developer ID and notarization gate

The exact distributed application MUST be signed with a Developer ID Application identity, use hardened runtime and only justified minimum entitlements, receive accepted Apple notarization, have its ticket stapled and validated, and pass Gatekeeper assessment. Missing credentials or any failed check MUST block release publication.

#### Scenario: Signing credentials are unavailable

- **WHEN** the Developer ID certificate, team information, or notarization credentials are missing
- **THEN** the workflow fails before creating a public release and does not fall back to unsigned or ad-hoc signing

#### Scenario: Distributed archive is verified

- **WHEN** notarization succeeds
- **THEN** the ticket is stapled to the same application that is archived for download
- **AND** strict signature, entitlement, notarization, Gatekeeper, archive-content, and architecture checks pass against that artifact

### Requirement: Homebrew cask matches the immutable release asset

The cask MUST be updated only after the final release asset exists. Its version, URL, SHA-256, and macOS 14 minimum MUST match that asset, and clean-environment audit, install, launch, and upgrade tests MUST pass without removing user configuration.

#### Scenario: Asset and cask are synchronized

- **WHEN** the v1.2.0 asset is final
- **THEN** automation downloads it, independently computes SHA-256, updates the cask to that exact immutable URL and checksum, and passes all required Homebrew checks

#### Scenario: Cask verification fails

- **WHEN** checksum, metadata, audit, install, launch, or upgrade verification fails
- **THEN** the cask change is not published as complete and the release process reports the failed gate

### Requirement: Documentation is truthful and operational

README and release notes MUST describe implemented integrations and accurate macOS requirements and MUST explain Preview, backups, Undo, migration, recovery, signature verification, and Homebrew installation. They MUST NOT claim currently stubbed Terminal.app, iTerm2, or system-theme behavior.

#### Scenario: Release documentation is reviewed

- **WHEN** v1.2.0 is ready to tag
- **THEN** every product and compatibility claim maps to tested implemented behavior
- **AND** recovery and verification instructions are sufficient for a user to act without hidden repository knowledge
