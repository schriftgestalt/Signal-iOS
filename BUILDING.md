# Building

We typically develop against the latest stable version of Xcode.

## 1. Clone

Clone the repo to a working directory:

```
git clone --recurse-submodules https://github.com/signalapp/Signal-iOS
```

Since we make use of sub-modules, you must use `git clone`, rather than
downloading a prepared zip file from Github.

We recommend you fork the repo on GitHub, then clone your fork:

```
git clone --recurse-submodules https://github.com/<USERNAME>/Signal-iOS.git
```

You can then add the Signal repo to sync with upstream changes:

```
git remote add upstream https://github.com/signalapp/Signal-iOS
```

## 2. Dependencies

To build and configure the libraries Signal uses, just run:

```
make dependencies
```

## 3. Xcode

Open the `Signal.xcworkspace` in Xcode.

```
open Signal.xcworkspace
```

In the TARGETS area of the General tab, change the Team drop down to
your own. You will need to do that for all the listed targets, for ex.
Signal, SignalShareExtension, and SignalNSE. You will need an Apple
Developer account for this.

On the Capabilities tab, turn off Push Notifications, Apple Pay,
Communication Notifications, and Data Protection, while keeping Background Modes
on. The App Groups capability will need to remain on in order to access the
shared data storage. The best way to change the bundle ID for the app groups is
setting `SIGNAL_BUNDLEID_PREFIX` in the project's settings.

If you wish to test the Documents API, the iCloud capability will need to
be on with the iCloud Documents option selected.

Build and Run and you are ready to go!

## Mac Catalyst (experimental)

The `Signal-Catalyst` scheme builds the existing Signal app target for the
Mac Catalyst destination, so the iOS and Mac variants continue to share their
source and resource membership. In Xcode, select `Signal-Catalyst` and a
`My Mac (Mac Catalyst)` destination. The equivalent command-line build is:

```
xcodebuild \
    -workspace Signal.xcworkspace \
    -scheme Signal-Catalyst \
    -configuration Debug \
    -destination 'platform=macOS,variant=Mac Catalyst' \
    build
```

The application, `SignalUI`, and `SignalServiceKit` targets advertise Catalyst
support. The notification service and share extensions remain iOS-only and are
excluded from the Catalyst dependency graph. The Mac variant uses the distinct
bundle identifier `$(SIGNAL_BUNDLEID_PREFIX).signal.catalyst` and does not load
the iOS app's entitlement file.

The published libsignal archive does not include Catalyst libraries. Build the
pinned source locally and tell CocoaPods to use that checkout instead:

```
brew install protobuf
Scripts/build-libsignal-catalyst
LIBSIGNAL_LOCAL_PATH=../libsignal bundle exec pod install
```

The build script creates sibling `libsignal` and `boring-catalyst` checkouts as
needed, verifies their pinned commits, and builds arm64 and x86_64 Catalyst
archives. Its small BoringSSL build-system patch enables the existing Catalyst
targets without changing cryptographic code.

The published RingRTC and WebRTC archives also lack Catalyst slices. Build the
pinned sources locally (the WebRTC build is large and can take a while), then
install both source-built dependencies:

```
brew install coreutils protobuf
cargo install cbindgen
Scripts/build-ringrtc-catalyst
LIBSIGNAL_LOCAL_PATH=../libsignal \
    RINGRTC_LOCAL_PATH=../ringrtc \
    bundle exec pod install
```

The RingRTC workflow currently builds Apple Silicon (`arm64`) only. It pins the
RingRTC and WebRTC revisions, uses WebRTC's upstream Catalyst build support, and
validates both resulting binaries as `MACCATALYST` before CocoaPods consumes
them. Its source patch skips an iPad-only camera option that AVFoundation marks
unavailable on Catalyst. The native Apple linker is used because Chromium's LLD
cannot link the Catalyst system stubs shipped with current Xcode versions.

The pinned MobileCoin artifacts only contain iOS device and simulator slices.
Payments can be omitted from the experimental Catalyst build while leaving the
iOS dependency graph unchanged:

```
SIGNAL_DISABLE_MOBILECOIN=1 \
    LIBSIGNAL_LOCAL_PATH=../libsignal \
    RINGRTC_LOCAL_PATH=../ringrtc \
    bundle exec pod install
```

Without the MobileCoin modules, SignalUI selects its disabled payments
implementation and does not expose payments UI. Payment protobufs and storage
models remain available because they do not depend on the MobileCoin SDK.

## Known issues

Features related to push notifications are known to be not working for
third-party contributors since Apple's Push Notification service pushes
will only work with Open Whisper Systems production code signing
certificate.

Turn on Push Notifications on the Capabilities tab if you want to register a new Signal account using the application installed via XCode.

If you have any other issues, please ask on the [community forum](https://community.signalusers.org/).
