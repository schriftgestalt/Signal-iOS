# Signal Mac Catalyst Development

These instructions apply to the entire repository.

## Supported Catalyst configuration

- Build the `Signal-Catalyst` scheme for Apple Silicon (`arm64`) only.
- MobileCoin is intentionally disabled for the Catalyst target.
- Catalyst uses locally built LibSignal, RingRTC, and WebRTC artifacts. Do not add Intel slices unless explicitly requested.

## Dependency preparation

Routine source validation does not require running the preparation script again. `Scripts/prepare-catalyst` runs CocoaPods and may download dependencies, so run it only when the workspace has not been prepared, native artifacts are missing or stale, or dependency configuration changed.

The default local checkouts are sibling directories of this repository:

- `../libsignal`
- `../ringrtc`

If their Catalyst artifacts are missing, build them first:

```sh
Scripts/build-libsignal-catalyst
Scripts/build-ringrtc-catalyst
```

Then prepare the workspace:

```sh
Scripts/prepare-catalyst
```

The paths can be overridden with `LIBSIGNAL_DIR` and `RINGRTC_DIR` when invoking the scripts.

## Standard validation build

For normal code changes, validate with this command from the repository root:

```sh
xcodebuild \
  -workspace Signal.xcworkspace \
  -scheme Signal-Catalyst \
  -configuration Debug \
  -destination 'platform=macOS,variant=Mac Catalyst,arch=arm64' \
  -derivedDataPath /private/tmp/Signal-Catalyst-XcodeUI-DerivedData \
  ONLY_ACTIVE_ARCH=YES \
  CODE_SIGN_STYLE=Automatic \
  -quiet \
  build
```

A successful command exit is the compile/link validation milestone. Warnings about the missing optional Metal toolchain search path, linking macOS system framework stubs into Catalyst, and the LibSignal download build phase running every time are currently known and non-fatal.

For interactive runtime validation, open `Signal.xcworkspace`, select `Signal-Catalyst` and `My Mac (Mac Catalyst)`, then run. If Xcode previously built a different pod graph, use **Product > Clean Build Folder** once.

## Working tree and commit hygiene

- Preserve all pre-existing and unrelated user changes.
- Workspace preparation commonly changes `Podfile.lock`, `Pods`, `Signal.xcodeproj/project.pbxproj`, and `Signal/Settings.bundle/Acknowledgements.plist`. Treat these as generated local state and do not stage them unless the task explicitly changes dependency configuration.
- `Config/User.xcconfig` is ignored local signing configuration. Never commit it, a personal development team, bundle-prefix customization, signing identity, or provisioning profile.
- Stage explicit source paths rather than using `git add .` or `git add -A`.
- Before every commit, run `git diff --cached --check`, review `git diff --cached`, and verify the staged diff contains no signing settings or personal identifiers.
- After each independently useful Catalyst milestone passes the standard arm64 build, create a focused commit containing only that milestone.
