# Correct The Just Published Public Release By Changing The Marketing

## Request

> Correct the just-published public release by changing the marketing version from 1.2.0 to the literal version 0.20 with tag v0.20, keeping build 120 unless repository evidence requires a different monotonic build; remove the quoted unsigned security-notice paragraph from repository release documentation and the published GitHub release notes; remove emoji characters from every tracked text file including README without changing binary assets or program semantics; run all existing validation; publish and publicly verify the corrected unsigned v0.20 release and checksum; only after that succeeds, delete the mistaken v1.2.0 GitHub release and tag. Leave Homebrew and the normal signed release workflow untouched, and preserve the pre-existing untracked CLAUDE.md.

## Goal

Replace the mistaken public v1.2.0 release with a fully verified v0.20 release,
make every current product and release surface report the literal marketing
version `0.20`, remove the requested unsigned-warning copy, and eliminate emoji
characters from tracked text without regressing application behavior or release
integrity.

## Acceptance Criteria

- [ ] [AC-1] `project.yml` is the canonical source for marketing version `0.20`
  and build `120`; the generated Xcode project, plist substitutions, About UI,
  verification scripts, release archive, and tag-derived version all agree.
- [ ] [AC-2] Current user-facing source and documentation use version `0.20` and
  do not present v1.2.0 as the current version. Historical Empirical event and
  evidence records remain intact as audit history.
- [ ] [AC-3] The quoted `Security notice` paragraph and the equivalent README
  warning paragraph are absent from tracked release documentation and from the
  public v0.20 GitHub release body. No surface falsely claims that the artifact
  is signed, notarized, or Gatekeeper-approved.
- [ ] [AC-4] A deterministic scan of every Git-tracked text file reports no emoji
  characters. Existing source emoji defaults, menus, alerts, and settings choices
  use clear ASCII wording or symbols instead, while user-supplied configuration
  values remain backward compatible.
- [ ] [AC-5] The explicit unsigned workflow defaults to `v0.20`, reads v0.20
  notes, validates exact-head version metadata, and still requires the manual
  unsigned acknowledgement. The normal signed workflow retains its signing,
  notarization, Gatekeeper, checksum, and Homebrew gates; only version-dependent
  release-note references may change.
- [ ] [AC-6] Generated-project drift checks, version verification, workflow lint,
  shell syntax checks, Debug build and analysis, 38 unit tests, 3 UI tests,
  Release analysis, and universal archive verification pass for the exact commit.
- [ ] [AC-7] A public, non-draft, non-prerelease `v0.20` release targets the exact
  verified main commit and contains `RiceBarMac-0.20-unsigned.zip` plus its
  checksum file. An unauthenticated download passes the attached SHA-256 and ZIP
  integrity checks and contains version `0.20`, build `120`, macOS 14 minimum,
  and both `arm64` and `x86_64` slices.
- [ ] [AC-8] The mistaken v1.2.0 GitHub release and remote tag are deleted only
  after AC-7 succeeds. Failure before that point leaves v1.2.0 recoverable.
- [ ] [AC-9] Homebrew is not updated to the unsigned artifact, no signed release
  is triggered accidentally, and the pre-existing untracked `CLAUDE.md` remains
  untouched.

## Scope

- Canonical and generated version metadata, current-version source strings,
  README, release notes, and version-dependent workflow inputs.
- Emoji removal from every tracked text file, including application defaults,
  UI strings, tests, and contributor documentation.
- Native CI validation, explicit unsigned v0.20 publication, public artifact
  verification, and ordered retirement of the mistaken v1.2.0 release and tag.
- Durable Empirical contract, evidence, review, and capability updates for the
  corrected release behavior.

## Non-goals

- Product feature, profile format, filesystem transaction, or migration changes.
- Apple Developer ID enrollment, signing, notarization, or distribution through
  Homebrew for this owner-authorized unsigned artifact.
- Rewriting archived Empirical events or evidence that truthfully record the
  earlier v1.2.0 work and mistaken publication.
- Rejecting or rewriting emoji characters supplied by users in existing config;
  the repository itself and built-in choices are the removal boundary.

## Verification

- Enumerate tracked files and run a Unicode-aware emoji scan over files detected
  as text; separately inspect current-version references outside archived
  Empirical audit records.
- Run `EXPECTED_TAG=v0.20 scripts/verify-version.sh`, XcodeGen regeneration and
  drift comparison, Actionlint, shell syntax validation, and `git diff --check`.
- Require green pull-request and exact-main macOS CI evidence for all native build,
  analysis, test, UI-test, and universal-archive gates.
- Dispatch the explicit unsigned workflow at the exact main commit; inspect its
  evidence JSON and test logs, GitHub release metadata, tag target, assets, and
  absence of an unexpected normal signed-release run.
- Download both public assets without authentication, verify SHA-256 and ZIP
  integrity, inspect embedded plist metadata and Mach-O slices, then verify the
  v1.2.0 release and tag no longer exist.
- Confirm final worktree status contains no change to the user-owned untracked
  `CLAUDE.md`.

## Capability Deltas

- `deltas/release-integrity.md` modifies canonical version, documentation,
  explicit unsigned exception, and correction-order requirements.
- `deltas/application-experience.md` adds an emoji-free built-in presentation
  requirement while preserving user configuration compatibility.
