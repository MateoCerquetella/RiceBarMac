# Design: v0.20 Release Correction and Emoji-Free Repository

## Overview

Apply a narrow metadata, presentation, documentation, and delivery correction on
top of the completed transactional profile work. Keep build `120` and all product
behavior intact while changing the canonical marketing version to the literal
`0.20`, regenerating the Xcode project, replacing built-in emoji strings with
ASCII presentation, and publishing a new exact-head v0.20 unsigned asset. Treat
the existing v1.2.0 release as a rollback point until v0.20 passes independent
public verification.

## Version and documentation flow

1. Change only the canonical `MARKETING_VERSION` in `project.yml` from `1.2.0`
   to `0.20`; retain `CURRENT_PROJECT_VERSION` `120` so the build identifier does
   not move backward.
2. Regenerate `RiceBarMac.xcodeproj` with XcodeGen rather than editing it by hand.
3. Change current-version application copy, README, release-note filenames and
   content, and workflow defaults/references to v0.20. Archived Empirical events
   and evidence continue to record v1.2.0 as history.
4. Remove the quoted Security notice and the equivalent README warning paragraph.
   Keep the asset and release title factually labeled `Unsigned`; do not add a
   signed, notarized, or Gatekeeper claim.

## Emoji-removal boundary

The repository boundary is every Git-tracked file that is valid text. Replace
built-in menu icons and settings options with concise ASCII choices, replace
warning/status glyphs with words, strip emoji from contributor headings, and use
`(c)` for copyright copy. Continue accepting arbitrary strings from existing
configuration so a user-owned custom emoji remains backward compatible and is
not rewritten by loading the app.

Add `scripts/verify-no-emoji.sh` as a deterministic gate. It enumerates tracked
files, skips binary content, and uses a Unicode-aware Extended Pictographic plus
emoji-sequence scan. CI and both release workflows run the same script after
checkout. This prevents a clean local scan from drifting before publication.

## Release workflow

The manual unsigned workflow keeps its explicit acknowledgement, exact-main
check, canonical tag check, generated-project gate, 38 unit tests, 3 UI tests,
Release analysis, unsigned universal archive checks, checksum generation, and
public re-download validation. Its default tag and notes file change to v0.20.

The normal tag workflow keeps every secret, Developer ID, hardened-runtime,
notarization, stapling, Gatekeeper, checksum, and Homebrew gate. Its only release
logic change is the version-dependent notes filename plus the shared no-emoji
gate. The `GITHUB_TOKEN`-created v0.20 tag from the manual workflow is not expected
to trigger the normal tag workflow; run history is checked after publication.

## Safe publication sequence

1. Commit the correction on a branch and require pull-request macOS CI.
2. Merge only a green, clean, exact-head pull request.
3. Require the resulting exact `main` commit to pass macOS CI again.
4. Dispatch the explicit unsigned workflow for `v0.20` with acknowledgement.
5. Verify release metadata, exact tag commit, workflow evidence, tests, embedded
   version/build, deployment target, architectures, attached checksum, ZIP
   integrity, and an unauthenticated public download.
6. Only after step 5 succeeds, delete the v1.2.0 GitHub release and then delete
   the remote v1.2.0 tag. Recheck that v0.20 is the latest public release and that
   no normal signed release or Homebrew update ran.

## Failure handling

- Any static, native CI, workflow, archive, checksum, metadata, or public-access
  failure stops correction before v1.2.0 deletion.
- A v0.20 tag already targeting another commit blocks publication.
- A v0.20 release with different assets is not overwritten silently; inspect and
  repair through a reviewed commit or explicit release correction.
- The untracked `CLAUDE.md` is never staged or edited.

## Verification mapping

- AC-1/2: canonical version script, generated-project diff, targeted current-copy
  scan, archive plist, and tag/release metadata.
- AC-3: exact warning-text and false-signing-claim scans plus public release body.
- AC-4: tracked-text emoji gate, focused config compatibility tests, and native UI
  tests after ASCII presentation replacements.
- AC-5/6: Actionlint, shell syntax, PR CI, exact-main CI, and workflow inspection.
- AC-7: unsigned workflow evidence, unauthenticated download, SHA-256, ZIP, plist,
  and Mach-O inspection.
- AC-8/9: post-verification GitHub release/tag absence, run history, Homebrew
  non-update evidence, and final worktree status.
