# RiceBarMac 1.2.0 release readiness

## Candidate

- Branch: `release/v1.2.0`
- Commit: `aef08e90f40931aea4d00d6d73f31485828e0fc1`
- Version: `1.2.0` (build `120`)
- Pull request CI: <https://github.com/MateoCerquetella/RiceBarMac/actions/runs/30784824071>
- Push CI: <https://github.com/MateoCerquetella/RiceBarMac/actions/runs/30784821565>

## Verification result

The exact candidate passed generated-project drift detection, Debug build and analysis, 38 unit/integration tests, 3 real-process XCUITests, Release build and analysis, version verification, and the universal `arm64`/`x86_64` archive gate on macOS 14. Targeted log inspection found no compiler, analyzer, or archive warnings or errors. The runner emitted one unrelated Homebrew annotation for a preinstalled untrusted `aws/tap`.

Seven 1920x1080 native screenshots were extracted from the exact-head XCUITest result and visually inspected: idle, Preview, applying, success, invalid-profile failure, recovery-required, and Undo.

Local static verification also passed `git diff --check`, shell syntax checks for both release scripts, and `EXPECTED_TAG=v1.2.0 scripts/verify-version.sh`.

## Independent review

The final implementation and release diff were reviewed against AC-1 through AC-18, AC-UI-1, AC-UI-2, accepted decisions D-001 through D-005, and all four capability deltas. No blocking code or documentation finding remains. The review specifically covered transaction ownership and race boundaries, rollback/recovery preservation, configuration optimistic locking, external-process pipe handling, accessible native states, generated version metadata, fail-closed Apple verification, and idempotent Homebrew synchronization.

## Publication gate

Publication is intentionally stopped before creating `v1.2.0`. The repository has `HOMEBREW_GITHUB_TOKEN`, but it does not have these required Apple signing/notarization secrets:

- `DEVELOPER_ID_CERTIFICATE_BASE64`
- `DEVELOPER_ID_CERTIFICATE_PASSWORD`
- `KEYCHAIN_PASSWORD`
- `APPLE_TEAM_ID`
- `APPLE_API_KEY_ID`
- `APPLE_API_ISSUER_ID`
- `APPLE_API_PRIVATE_KEY_BASE64`

No unsigned release asset or misleading tag was created. Once those secrets are configured, the release workflow can create and verify the signed, notarized, stapled artifact and synchronize the Homebrew cask.
