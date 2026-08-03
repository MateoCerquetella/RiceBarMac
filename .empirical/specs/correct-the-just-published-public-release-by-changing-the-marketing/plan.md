# Execution Plan: RiceBarMac v0.20 Release Correction

## P-01: Establish correction branch and immutable baselines

Dependencies: none

Work:

- Confirm `main`, `origin/main`, public v1.2.0 tag/release target, asset digest,
  release body, workflow history, and the pre-existing untracked `CLAUDE.md`.
- Create a focused correction branch from exact `origin/main` without staging or
  modifying `CLAUDE.md`; retain the Empirical contract/context updates.
- Record the files with current-version references and emoji characters before
  editing so removal scope is reviewable.

Checks:

- `git status --short --branch`
- `git rev-parse origin/main`
- GitHub release/tag metadata for v1.2.0
- Unicode-aware baseline scan

Acceptance: AC-2, AC-4, AC-8, AC-9

Stop conditions: unexpected tracked user changes, v1.2.0 already missing, or a
v0.20 tag/release targeting an unknown commit.

## P-02: Correct canonical version and current release documentation

Dependencies: P-01

Work:

- Set `MARKETING_VERSION` to literal `0.20` and retain build `120` in
  `project.yml`; update current application copy that names v1.2.0.
- Rename signed and unsigned release notes to v0.20, update version/build copy,
  remove the quoted Security notice and longer equivalent warning copy, and keep
  only factual unsigned labeling.
- Update README current-version text, remove its unsigned warning paragraph, and
  keep accurate supported-integration and macOS requirements.
- Update workflow defaults and version-dependent notes filenames; preserve normal
  signing/notarization/Gatekeeper/Homebrew logic and manual acknowledgement.

Checks:

- Targeted `rg` scan for current v1.2.0 references outside archived Empirical
  history
- Targeted scan for the removed warning copy and false signed claims
- Review `.github/workflows/release.yml` diff to ensure only notes/gate wiring
  changed

Acceptance: AC-1, AC-2, AC-3, AC-5

Stop conditions: any required runtime/profile behavior change or any weakening of
the signed release gates.

## P-03: Remove built-in emojis and add a regression gate

Dependencies: P-01

Work:

- Replace default `menuBarIcon` with `RB`, replace built-in icon choices with
  ASCII alternatives, replace warning/unavailable glyphs with clear words, and
  change copyright copy to `(c)`.
- Update configuration compatibility expectations while leaving decoder behavior
  unchanged for arbitrary user-provided strings.
- Remove emoji prefixes and trailing glyphs from contributor documentation.
- Add `scripts/verify-no-emoji.sh` and invoke it from CI plus both release
  workflows after checkout/toolchain availability.

Checks:

- Run the gate across every `git ls-files` text file
- Focused source/test diff confirms decoder preservation
- Shell syntax and Actionlint pass

Acceptance: AC-4, AC-5, AC-6

Stop conditions: scan excludes a tracked text class, changes rewrite loaded user
data, or UI copy becomes ambiguous.

## P-04: Regenerate and perform static verification

Dependencies: P-02, P-03

Work:

- Regenerate `RiceBarMac.xcodeproj` from `project.yml` with XcodeGen.
- Run exact tag/version verification, emoji gate, workflow lint, shell syntax,
  generated-project drift verification, JSON validation, and diff hygiene.
- Review the full change set for scope, historical-record preservation, and
  absence of `CLAUDE.md` staging.

Checks:

- `EXPECTED_TAG=v0.20 scripts/verify-version.sh`
- `scripts/verify-no-emoji.sh`
- Actionlint for every workflow
- `bash -n scripts/*.sh`
- clean second XcodeGen generation/diff
- `git diff --check`

Acceptance: AC-1 through AC-6, AC-9

Stop conditions: generated drift, emoji match, version mismatch, workflow lint
failure, or unrelated tracked changes.

## P-05: Review, merge, and verify exact main commit

Dependencies: P-04

Work:

- Commit intentionally, push the correction branch, and open a draft pull request
  describing version, warning, emoji, compatibility, and release effects.
- Require green PR macOS CI, promote only after checks, verify clean mergeability,
  merge, and require green exact-main CI for the resulting merge commit.
- Inspect native evidence for 38 unit tests, 3 UI tests, Debug/Release analysis,
  generated-project consistency, and universal archive metadata.

Checks:

- PR status/check rollup and exact head SHA
- main CI run exact merge SHA and native evidence

Acceptance: AC-1, AC-4, AC-5, AC-6, AC-9

Stop conditions: failed/flaky native gate, merge conflict, or main advancing away
from the reviewed commit without revalidation.

## P-06: Publish and independently verify v0.20

Dependencies: P-05

Work:

- Dispatch `unsigned-release.yml` from exact `main` with tag `v0.20` and explicit
  acknowledgement.
- Require the workflow to validate exact main, version, no-emoji gate, tests,
  Release analysis, unsigned universal archive, and public checksum.
- Inspect release metadata and workflow artifacts; download the ZIP and checksum
  both through GitHub tooling and an unauthenticated public URL.
- Verify SHA-256, ZIP integrity, version `0.20`, build `120`, macOS `14.0`, both
  architectures, unsigned evidence, exact tag target, and current release body.

Checks:

- Exact workflow run and evidence JSON/logs
- GitHub release API and `git ls-remote --tags`
- `sha256sum -c`, `unzip -t`, plist and Mach-O inspection
- unauthenticated public download checksum

Acceptance: AC-1, AC-3, AC-5, AC-6, AC-7, AC-9

Stop conditions: any failure leaves v1.2.0 unchanged and routes to a reviewed
repair rather than overwriting an unverified asset.

## P-07: Retire v1.2.0 and close durable evidence

Dependencies: P-06 successful in full

Work:

- Delete the mistaken v1.2.0 GitHub release, verify release absence, then delete
  the remote v1.2.0 tag and verify tag absence.
- Reconfirm v0.20 is the latest public release, remains downloadable with the
  verified digest, and no normal signed workflow or Homebrew update ran.
- Complete Empirical evidence, independent review, capability archive, final
  local `main` synchronization, and worktree status check.

Checks:

- v1.2.0 release API returns not found and `git ls-remote` has no v1.2.0 tag
- v0.20 release/tag/assets remain exact and public
- GitHub workflow history contains only expected CI/manual publisher runs
- final `git status --short --branch` shows only untouched `CLAUDE.md`

Acceptance: AC-7, AC-8, AC-9

Stop conditions: do not delete the tag until release deletion is confirmed; any
v0.20 regression stops retirement and preserves remaining recovery state.

## Completion condition

All nine acceptance criteria have exact-commit evidence, v0.20 is the sole current
public release and verified from an unauthenticated download, v1.2.0 release/tag
are absent, capability deltas are reviewed and archived, normal signing/Homebrew
behavior is preserved, and `CLAUDE.md` is untouched.
