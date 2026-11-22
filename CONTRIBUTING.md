# Contributing

FingerChord currently targets macOS 27 and Apple trackpads. Use Xcode with the macOS 27 SDK and Swift 6.2 or newer. Start with [README](README.md) and [development notes](docs/DEVELOPMENT.md).

## Changes

1. Describe the behavior you want to change, with a reproducible example.
2. Keep recognition logic in `GestureCore` and hardware / UI code in `FingerChord` or `TouchBridge`.
3. Add a regression test for a recognition or lifecycle bug. Run `./scripts/test.sh` and `./scripts/build.sh`.
4. For UI changes, check all languages, dark appearance and the permission rows.
5. Format Swift with `xcrun swift-format format -i -r Sources Tests Package.swift`.

The tests do not replace physical trackpad testing. Repeat chord taps without lifting the resting pair, and check the three finger tap, three / four finger presses, three finger dragging, scrolling, an external mouse and sleep / wake. With the settings window in front, gestures are only previewed, so nothing reaches other apps.

## Translations and artwork

Translations live in `Sources/FingerChord/Resources/*.lproj/Localizable.strings`; every gesture needs a `gesture.<name>` and an `action.<name>` key. Keep keys and printf placeholders in sync. Use the system’s own words: click / 点按 / 按一下 for a physical press, tap / 轻点 / 點一下 for a light touch. Add a language to `AppLanguage`, `L10n`, the build script and the translation test when introducing a new locale. System display names live in `Resources/*.lproj/InfoPlist.strings`.

The icon is the Icon Composer document `Resources/AppIcon.icon`; `build.sh` compiles it. After editing, export `docs/media/icon.png` with `ictool` as shown in the [development notes](docs/DEVELOPMENT.md#icon-and-media).

## License

Original code, documentation and artwork use **GPL-3.0-only**. Contributions must be compatible with that license. Keep relevant copyright and third-party license notices. See [LICENSE](LICENSE) and [ACKNOWLEDGMENTS](ACKNOWLEDGMENTS.md).
