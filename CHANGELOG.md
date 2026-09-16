# Changelog

## 1.1.1 — 2026-09-16

- Three / four finger presses use the trackpad's native click feedback, without an additional delayed app haptic.
- Middle finger taps retain one immediate haptic per recognized tap, including in test mode.

## 1.1.0 — 2026-09-16

- Original SVG icon, native app icon resources, and GPL-3.0-only licensing.
- English, Simplified Chinese and Traditional Chinese; live language switching.
- Improved dark appearance and a scrollable settings window for smaller screens.
- Removed a potential lock-order deadlock while collecting diagnostic fields.
- Invalidated pending callbacks across reconnects; bounded copied mouse events and diagnostic snapshots.
- Explicit teardown of HID callbacks, event taps, timers and framework device references.
- Diagnostic buffers release after stopping or reaching their duration / size limit.
- Ignored duplicate hardware press edges and stale presses after changing gesture options.
- Repeatable app packaging, ad-hoc signing fallback, CI, regression and lifecycle checks.
- Screenshots, a compact demo, bilingual documentation and the original development prompt.

## 1.0.0 — 2026-09-15–16

- Three trackpad gestures: middle finger tap → ⌘ click, three finger press → ⌘W, four finger press → ⌘Q.
- Physical presses detected through HID input values on macOS 27.
- Stable repeated middle finger taps without lifting the resting fingers.
- Haptic feedback, individual switches, test mode and launch at login.
- Background operation without Dock or menu bar icons; reopen for settings.
