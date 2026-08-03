# Release Integrity Delta

## REMOVED Requirements

### Requirement: One canonical version for v1.2.0

The v1.2.0-specific canonical-version requirement is superseded by the corrected
v0.20 requirement below.

#### Scenario: Mistaken version is retired

- **WHEN** the corrected version contract is archived
- **THEN** v1.2.0 is no longer the canonical current release version

## MODIFIED Requirements

### Requirement: Fail-closed Developer ID and notarization gate

The normal tag-triggered workflow MUST continue to require Developer ID signing,
hardened runtime, Apple notarization, stapling, Gatekeeper acceptance, checksum
verification, and Homebrew gates. A separate manual workflow MAY publish an
owner-authorized unsigned artifact only after an explicit acknowledgement and
the same version, native-test, Release-analysis, universal-archive, and public
checksum checks pass. It MUST NOT update Homebrew or claim signed status.

#### Scenario: Normal signing credentials are unavailable

- **WHEN** the normal release workflow lacks any signing or notarization secret
- **THEN** that workflow fails before publication and does not fall back to the
  manual unsigned path

#### Scenario: Owner authorizes the manual exception

- **WHEN** the manual publisher is dispatched from exact `main` with the required
  acknowledgement for v0.20
- **THEN** it may publish only the explicitly unsigned asset after every native
  and public-integrity check passes
- **AND** it does not update Homebrew

### Requirement: Documentation is truthful and operational

Current README and release notes MUST report version `0.20`, implemented
integrations, and accurate macOS requirements without emoji characters. The
owner-requested security-notice paragraphs MUST be absent. Documentation MUST
NOT claim that an unsigned artifact is signed, notarized, or Gatekeeper-approved,
and MUST NOT claim unsupported Terminal.app, iTerm2, or system-theme behavior.

#### Scenario: Current release documentation is reviewed

- **WHEN** v0.20 is ready to publish
- **THEN** the exact requested warning copy is absent, the remaining claims map
  to tested behavior, and a Unicode-aware tracked-text scan finds no emojis

## ADDED Requirements

### Requirement: One canonical version for v0.20

`project.yml` MUST be the canonical source for marketing version `0.20` and build
`120`. The v0.20 tag, generated plist, About display, archive, release title, and
asset naming MUST agree, and CI MUST reject drift before publication.

#### Scenario: Version metadata disagrees

- **WHEN** any checked source, generated artifact, tag, or release field reports
  a marketing version other than `0.20` or a build other than `120`
- **THEN** publication stops with the mismatched values identified

### Requirement: Corrected release replaces the mistaken release safely

The v0.20 release MUST be published and independently verified before the
mistaken v1.2.0 release or tag is deleted.

#### Scenario: Corrected release verification fails

- **WHEN** v0.20 publication, metadata, checksum, archive, or public-download
  verification fails
- **THEN** v1.2.0 remains available and the correction stops for repair

#### Scenario: Corrected release verification succeeds

- **WHEN** the public v0.20 tag, metadata, assets, checksum, embedded version,
  deployment target, and architectures all pass verification
- **THEN** the v1.2.0 release is deleted followed by its remote tag
- **AND** v0.20 remains the repository's current public release
