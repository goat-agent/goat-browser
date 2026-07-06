# Goat Browser

A native macOS browser built with SwiftUI/AppKit and Chromium (CEF), with a Liquid Glass interface. Part of the goat ecosystem.

## Requirements

- macOS 26+
- Xcode 26+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) — `brew install xcodegen`

## Build & Run

```sh
scripts/fetch-cef.sh       # download the pinned CEF distribution
scripts/build-wrapper.sh   # build libcef_dll_wrapper
xcodegen generate
xcodebuild -project GoatBrowser.xcodeproj -scheme GoatBrowser \
  -configuration Debug -destination 'platform=macOS,arch=arm64' \
  SYMROOT="$PWD/build" build
open "build/Debug/Goat Browser.app"
```

## License

MIT — see [LICENSE](LICENSE).
