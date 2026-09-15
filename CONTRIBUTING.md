# Contributing

FingerChord currently targets macOS 27 and Apple trackpads. Use Xcode with the macOS 27 SDK and Swift 6.2 or newer. Start with [README](README.md) and [development notes](docs/DEVELOPMENT.md).

## Changes

1. Describe the behavior you want to change, with a reproducible example.
2. Keep recognition logic in `GestureCore` and hardware / UI code in `FingerChord` or `TouchBridge`.
3. Add a regression test for a recognition or lifecycle bug. Run `./scripts/test.sh` and `./scripts/build.sh`.
4. For UI changes, check all languages, dark appearance and the permission panel.
5. Format Swift with `xcrun swift-format format -i -r Sources Tests Package.swift`.

The tests do not replace physical trackpad testing. Test middle taps repeatedly without lifting the resting pair; also check three / four finger presses, three finger dragging, an external mouse, reconnect and sleep / wake. Use the app's test mode before sending shortcuts to other apps.

## Translations and artwork

Translations live in `Sources/FingerChord/Resources/*.lproj/Localizable.strings`. Keep keys and printf format placeholders in sync. Add a language to `AppLanguage`, `L10n`, the build script and the translation test when introducing a new locale. System display names live in `Resources/*.lproj/InfoPlist.strings`.

Edit `Resources/Icon/FingerChord.svg`, then run `./scripts/make-icon.sh`. Commit the SVG, PNG and ICNS together. The renderer uses AppKit, `sips` and `iconutil`; no third-party graphics package is required.

## License

Original code, documentation and artwork use **GPL-3.0-only**. Contributions must be compatible with that license. Keep relevant copyright and third-party license notices. See [LICENSE](LICENSE) and [ACKNOWLEDGMENTS](ACKNOWLEDGMENTS.md).
