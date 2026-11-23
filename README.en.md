<p align="center"><img src="docs/media/icon.png" width="128" alt="FingerChord icon"></p>

# FingerChord · 指间

Trackpad gestures for macOS 27 that turn finger chords into shortcuts. It runs in the background with no Dock or menu bar icon.

[简体中文](README.md) · [Changelog](CHANGELOG.md) · [GPLv3](LICENSE)

## Gestures

| Gesture | How | Sends |
| --- | --- | --- |
| Tap between | Rest index and ring fingers; tap the middle finger between them | ⌘-click |
| Three finger click | Press the trackpad with three fingers | ⌘W |
| Four finger click | Press the trackpad with four fingers | ⌘Q |

Each gesture can be turned off. Taps give one haptic pulse; clicks keep the trackpad’s own click feel. The resting fingers can stay down for repeated taps.

<img src="docs/media/settings-en.png" width="460" alt="FingerChord settings window">

## Use

1. Build, move `FingerChord.app` to Applications and open it.
2. Click **Allow…** and turn on Accessibility and Input Monitoring in System Settings → Privacy & Security.
3. While the settings window is in front, gestures only show in the trackpad preview. Switch to another app and they work normally.
4. Click **Hide** or close the window; FingerChord keeps running. Open the app again to return to settings.

## Limits

- ⌘-click acts at the pointer; shortcuts go to the frontmost app. Keys are sent by US layout position, so other layouts may produce different characters.
- Uses the private MultitouchSupport interface and supports macOS 27 only; OS updates may need changes. Tested on macOS 27.2.1 with the built-in Force Touch trackpad on Apple Silicon. External trackpads are untested.
- One and two finger clicks are never delayed. A click with three or more fingers, which might become a gesture, waits at most 80 ms and then passes through.

## Footprint

Everything is event-driven; nothing polls. Idle in the background it uses 0% CPU, 0 wakeups and about 10 MB of memory (an empty AppKit process takes about 8 MB).

- Frames of a single finger moving the pointer are dropped in C and never reach Swift.
- Scrolls and drags bypass FingerChord. Drags are watched only while a click is held or swallowed.
- Closing settings hands over to a fresh background process, so the ~18 MB SwiftUI leaves behind goes away with the old one.
- With every gesture off, trackpad and event monitoring stop entirely.

## Build

Requires macOS 27, Xcode with the macOS 27 SDK, and Swift 6.2+.

```sh
./scripts/test.sh             # unit tests
./scripts/build.sh            # build and sign dist/FingerChord.app
./scripts/install.sh          # build, move into /Applications, open settings
./scripts/package-release.sh  # ZIP and SHA-256
```

The build signs with a local Developer ID / Apple Development certificate when one exists, otherwise ad-hoc. Set `FINGERCHORD_SIGN_IDENTITY` to choose one; `-` forces ad-hoc. Builds signed with the same certificate keep their system permissions; ad-hoc rebuilds may need them granted again. Local builds are not notarized.

See [development notes](docs/DEVELOPMENT.md) for architecture, diagnostics and verification, and [CONTRIBUTING](CONTRIBUTING.md) to take part.

## Privacy

Gestures are recognized on this Mac only. No network access, no keyboard input or window content is read. Settings live in local UserDefaults. Diagnostics are off by default; a manual recording keeps at most 3 minutes or 10,000 touch and button events in `~/Library/Application Support/FingerChord/diagnostic.json` and is never uploaded.

## Origin and license

The first version was built one-shot by GPT 6 Astra from the [original prompt](docs/ORIGINAL_PROMPT.md), written after BetterTouchTool stopped working on macOS 27. Code, icon and documentation are released under [GPL-3.0-only](LICENSE); interface references and their licenses are in [Acknowledgments](ACKNOWLEDGMENTS.md).
