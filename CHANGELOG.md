# Changelog

## 1.3.0 — 2026-11-23

- New icon: a frosted-glass hand on a trackpad, tapping with the middle finger.
- Redesigned settings: one column with a fingertip diagram for each gesture and no descriptions. While the window is in front, gestures are previewed instead of sent, which replaces test mode.
- Rewrote the copy in all three languages, using each system’s own terms for click and tap.
- Removed the scroll event tap; tap between fingers now recognizes a scrolling pair from touch motion. The drag event tap stays off unless a click is buffered or swallowed, and single-finger pointer frames are dropped in C before reaching Swift.
- Closing settings hands off to a fresh background process, bringing memory back to about 10 MB instead of keeping ~28 MB.
- Trackpad and event monitoring stop completely when every gesture is off.
- `install.sh` moves the build into Applications instead of copying it, so Spotlight no longer finds a second copy in `dist`.
- Releases ship as a notarized DMG, and the website is live in three languages.

## 1.2.0 — 2026-11-23

- One- and two-finger trackpad clicks are no longer delayed; only clicks with three or more contacts wait for the physical button.
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
