# Commands

## Setup

- Install XcodeGen on macOS: `brew install xcodegen`.
- Regenerate the project from its canonical source: `xcodegen generate`.
- Resolve packages through the generated Xcode project/workspace as part of `xcodebuild` or Xcode.

## Run, test, and build

- Release build documented by the repository: `xcodebuild -project RiceBarMac.xcodeproj -scheme RiceBarMac -configuration Release build`.
- The current release workflow runs `xcodegen generate`, archives with `xcodebuild -project RiceBarMac.xcodeproj -scheme RiceBarMac -configuration Release archive`, and exports the archive.
- No XCTest or XCUITest target is currently declared in `project.yml`; adding and running those targets is part of the approved specification.
- Xcode can run the generated `RiceBarMac` scheme interactively on a macOS development host.

## Verification evidence

- On a macOS runner, verification must cover project generation, Debug and Release build, static analysis, XCTest/XCUITest, deployment target, and universal binary slices.
- Release verification must include `codesign`, notarization submission/status, `stapler`, `spctl`, archive inspection, SHA-256 calculation, and Homebrew audit/install/launch/upgrade checks.
- The present environment is Linux and does not provide `xcodebuild`, Swift/Xcode SDKs, `codesign`, `stapler`, or `spctl`; native build, UI, signing, and release evidence must therefore come from macOS CI.
