# Decisions: Correct The Just Published Public Release By Changing The Marketing

Record concise, externally reviewable evidence and choices here. Do not store
private chain-of-thought, prompts, credentials, secrets, or scratchpad text.

## D-001: Use literal marketing version 0.20 and retain build 120

Status: Accepted

### Evidence

- The user explicitly requested version `0.20`, not `0.20.0`.
- `project.yml` is canonical and currently uses marketing version `1.2.0` with
  build `120`; the verification script derives tags directly as `v<version>`.
- Lowering the build number would create unnecessary downgrade ambiguity.

### Options

1. Use marketing version `0.20` and retain build `120`.
2. Normalize to `0.20.0` and retain build `120`.
3. Use `0.20` and lower the build to `20`.

### Chosen approach

Use literal marketing version `0.20`, tag `v0.20`, and build `120` everywhere.

### Trade-offs and risks

Two-component marketing versions are less common than three-component semantic
versions but match the explicit request and are valid for the existing metadata
flow. Retaining build `120` avoids a backward build identifier. Exact tag and
archive checks prevent accidental normalization or drift.

### Verification

Run version verification with `EXPECTED_TAG=v0.20`, regenerate the project, and
inspect the published app plist, title, tag, asset name, and evidence JSON.

## D-002: Replace repository emojis with ASCII while preserving user data

Status: Accepted

### Evidence

- Emoji characters occur in contributor headings, built-in menu/settings strings,
  a warning alert, About copy, default configuration, and compatibility tests.
- `menuBarIcon` is user-controlled string data, so rejecting or rewriting loaded
  custom values would be an unrelated compatibility break.

### Options

1. Remove only documentation emojis.
2. Replace every tracked built-in emoji with ASCII and preserve loaded user data.
3. Strip emoji dynamically from both built-in and user-provided values.

### Chosen approach

Replace every tracked emoji occurrence with readable ASCII equivalents, make the
fresh-config default `RB`, offer ASCII icon choices, and keep decoding arbitrary
existing user strings unchanged. Add a tracked-text emoji verification script.

### Trade-offs and risks

The menu-bar appearance changes for fresh/default configuration. Existing configs
that explicitly stored the former icon continue displaying their stored value.
A broad Unicode scan can flag text-style pictographs; that strictness matches the
request and is enforced consistently in CI.

### Verification

Run the emoji gate across `git ls-files`, update and run compatibility tests, and
run native UI tests to confirm menu, alerts, and settings remain usable.

## D-003: Publish v0.20 before deleting v1.2.0

Status: Accepted

### Evidence

- v1.2.0 is currently public and verified, but its requested version and release
  presentation are wrong.
- GitHub release and tag deletion is externally destructive and can remove the
  only downloadable release if done before the replacement is proven.

### Options

1. Delete v1.2.0 first, then build and publish v0.20.
2. Publish and independently verify v0.20, then delete v1.2.0 release and tag.
3. Keep both releases permanently.

### Chosen approach

Keep v1.2.0 as rollback until v0.20 passes exact-head CI, publication, metadata,
checksum, archive, and unauthenticated-download verification. Delete the release
first and its tag second only after success.

### Trade-offs and risks

Both versions coexist briefly during correction. This is preferable to a period
with no valid asset. Explicit remote checks before and after deletion prevent
target ambiguity.

### Verification

Record the v0.20 release URL, tag commit, asset digest, workflow evidence, and
public download checks before running and verifying the v1.2.0 deletions.

## D-004: Remove the requested warning without making a false signing claim

Status: Accepted

### Evidence

- The user explicitly identified the Security notice paragraph for removal and
  also objected to the equivalent README warning.
- The produced artifact is technically unsigned and unnotarized.

### Options

1. Keep the warning unchanged.
2. Remove the requested warning copy while retaining factual `Unsigned` labeling.
3. Remove all unsigned labeling or claim that the artifact is signed.

### Chosen approach

Remove the quoted notice, its README equivalent, and the longer warning/install
copy from current notes. Retain `Unsigned` in the release title and asset name and
make no signed, notarized, or Gatekeeper claim.

### Trade-offs and risks

The release body provides less installation-risk guidance. Retaining factual
artifact labeling avoids misleading users while honoring the requested copy
removal.

### Verification

Scan repository documentation and the public v0.20 body for the removed text and
for contradictory signing claims; inspect the actual asset evidence as unsigned.
