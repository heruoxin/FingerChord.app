# Changelog

## 1.3.0 — 2026-11-23

- New icon: a frosted glass hand on a trackpad, the middle finger tapping.
- Redesigned settings: one column, a fingertip diagram per gesture, no descriptions. Gestures are previewed instead of sent while the window is in front, which replaces test mode.
- Rewritten copy in all three languages, using the system’s own terms for click and tap.
- Scrolls are no longer tapped, drags only while a click is held, and single-finger pointer frames are dropped before Swift. Middle taps detect a moving pair from contact motion.
- Closing settings hands over to a fresh background process, returning to about 10 MB instead of keeping ~28 MB.
- Monitoring stops entirely when every gesture is off.
- `install.sh` moves the build into Applications, so no second copy stays in `dist` for Spotlight to list.
- Downloads as a notarized DMG. The website runs on GitHub Pages in three languages.

## 1.2.0 — 2026-11-23

- One and two finger trackpad clicks are no longer delayed; only clicks with three or more contacts wait for the physical button.
- A physical press whose system click already reached an app stays a plain click and no longer also sends ⌘W / ⌘Q.
- No polling: monitoring reacts to leaving System Settings, screen lock, sleep / wake, session and multitouch device notifications. Trackpads connected while running are picked up immediately.
- Scrolls are observed through a listen-only tap and never wait for the app.
- The live preview is pushed on change while settings are visible and redraws only the preview.
- Diagnostics are written once when a recording ends.

## 1.1.2 — 2026-11-23

- Fixed an occasional stuck button where every click acted like press-and-hold until FingerChord restarted. After a delayed click is released, its drag and up events follow it in order, so the up can no longer reach an app before its down.
- An unfinished click held when monitoring stops, or any click held when the event tap is disabled, is dropped instead of replayed late.

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
