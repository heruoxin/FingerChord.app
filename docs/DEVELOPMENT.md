# Development

## Architecture

| Component | Responsibility |
| --- | --- |
| `GestureCore` | Pure Swift recognition: middle taps, physical presses, click gating |
| `TouchBridge` | MultitouchSupport loading, ABI boundary, contact filtering and device ownership |
| `InputMonitor` | Per-device state, event taps, short click buffering, live preview and action delivery |
| `HardwareButtonMonitor` | Physical button values from IOHIDManager, matched to the exact trackpad |
| `DeviceWatcher` | IOKit arrival / termination notifications for multitouch devices |
| `AppModel` / `AppDelegate` | Preferences, permissions, login item, single instance, settings window, session events |
| `SettingsView` / `Localization` | SwiftUI settings and three string tables |

The private touch ABI was checked against macOS 27.0 (26A428): a 96-byte contact with normalized coordinates at offset 32, enforced by C static assertions. Physical presses come from HID usage page 9 / usage 1; tap-to-click and three finger dragging never change that value. The legacy MultitouchSupport button callback stays registered but this Mac’s MTHID device does not deliver it.

## Recognition

- **Middle tap.** Two contacts must stay within 0.015 of their snapshot for 80 ms before a third finger counts, so a scrolling pair keeps restarting its clock. The third finger must land between the pair, lift within 25–260 ms and move less than 0.04; the pair may drift at most 0.045.
- **Presses.** Three or four fresh contacts (under 180 ms old) when the hardware button goes down.
- Every gesture passes the click gate: a system click produced by the same touch is swallowed, and a gesture whose system click already reached an app stays a plain click.

## Runtime

- Nothing polls. Monitoring is reconciled on launch, settings display, preference changes, System Settings losing focus, screen lock / unlock, sleep / wake, session switches and multitouch device arrival or removal. A failed start retries once after two seconds.
- `TouchBridge` copies only touching contacts and drops frames whose count is unchanged at zero or one, unless the preview is streaming. Moving the pointer never enters Swift.
- One filtering tap sees mouse downs and ups. A second tap for drags is enabled only while a click is buffered or swallowed. Scrolls are not tapped at all.
- A click is held only while three or more fresh contacts could turn it into a gesture, or while an earlier click for the same button is being reposted; at most 80 ms. A released click reposts its remaining drag and up events behind the down. A disabled tap drops held clicks because newer events already bypassed it.
- Closing settings (close button, ⌘W, Hide) spawns the same binary as a helper with `--relaunch-after <pid>` and quits. The helper waits for that pid with a kqueue `NOTE_EXIT`, then asks LaunchServices for an ordinary background launch with `--relaunch`, which never opens settings by itself. The handover starts in `windowShouldClose`, which quitting and logging out do not call, so they never relaunch.
- With every gesture off, or while paused, locked or asleep, all taps, devices and HID callbacks are released.

### Threading and ownership

- App model, start / stop, HID manager, device notifications and event taps run on the main run loop.
- Multitouch callbacks arrive on framework threads. One lock protects recognition state and the session generation; dispatched actions check the generation, so stopping invalidates queued work.
- `FCStop` clears and drains the callback sinks before unregistering devices. The framework stays loaded for the process lifetime.
- Diagnostic fields are evaluated outside the trace lock, keeping the monitor → trace lock order.

## Checks

```sh
./scripts/test.sh
swift test --sanitize=address
./scripts/test-core.sh        # recognition only, for hosted CI on older macOS
xcrun swift-format lint -r Sources Tests Package.swift
./scripts/build.sh
```

Hosted CI runs the core package. The full app workflow is manual and needs a self-hosted runner labelled `macOS-27`; neither grants input permissions or sends events.

## Diagnostics

Quit the normal app before hardware self-tests.

```sh
# Permissions, devices and raw frame counts; --observe watches for 15 s.
/Applications/FingerChord.app/Contents/MacOS/FingerChord --probe --observe

# Open settings and record a bounded trace. Closing settings hands over to a new process and ends it.
open /Applications/FingerChord.app --args --diagnose

# Start a trace in the running background app, e.g. after closing settings.
/Applications/FingerChord.app/Contents/MacOS/FingerChord --start-diagnostics

# 100 real monitor start / stop cycles, buffer stress and the event self-test, then hold 45 s for leaks.
open /Applications/FingerChord.app --args --self-test-lifecycle --hold-for-leaks
cat "$HOME/Library/Application Support/FingerChord/lifecycle-test.json"
leaks FingerChord
```

The event self-test sends every gesture’s events and absorbs each tagged one in a session tap before any app sees it; it refuses to send without permissions or that tap. `--self-test-events` runs it alone. `--self-test-login` registers and unregisters the login item only if it was unregistered.

Traces live in `~/Library/Application Support/FingerChord/diagnostic.json` with contact coordinates, timestamps, button and status events. Inspect before sharing. A trace stops and is written once after 180 s or 10,000 entries.

## Icon and media

`Resources/AppIcon.svg` is the icon source: a frosted glass hand on a solid trackpad, the middle finger tapping. The frost is the scene blurred and overlaid with 80% white, clipped to the hand, so the fingers pick up the trackpad colour and fade where they cross its edge. `./scripts/make-icon.sh` renders it with headless Chrome at 2× and writes the PNGs in `Resources/AppIcon.xcassets`, which `build.sh` compiles with `actool`. macOS masks the full-bleed square to its icon shape. `docs/media/icon.png` is the installed icon as `NSWorkspace` draws it.

README screenshots are `screencapture -o -l <window id>` captures of the real settings window. For quick layout checks without touching preferences or input:

```sh
app=/Applications/FingerChord.app/Contents/MacOS/FingerChord
"$app" --render-settings .build/settings.png --language zh-Hant --dark --permissions
```

The offscreen render draws switches in their inactive-window style.

## Verification log

### 1.3.0 — 2026-11-23

macOS 27.2.1 (26B131), Apple Silicon, built-in Force Touch trackpad, Developer ID build.

| Check | Result |
| --- | --- |
| Unit tests | 55 passed, also under Address Sanitizer; core-only package passed |
| swift-format lint, release build, code signature | Clean |
| Lifecycle self-test | 100 / 100 starts and releases; trace buffers bounded and released |
| Event self-test | 6 / 6 events for the three gestures, absorbed before apps |
| `leaks` after stress | 0 leaks |
| Idle | 0.0% CPU, 0 idle wakeups, every thread in `mach_msg`, 0.10 s CPU since launch |
| Memory | 10 MB at launch (empty AppKit process: 8.3 MB); 28 MB with settings open; 11 MB after closing via relaunch |
| Event taps | One enabled tap for downs / ups; drag tap disabled when idle; no scroll tap |
| Recognizer | 113 ns per two-finger frame (0.0014% of a core at 120 Hz) |
| Window close / ⌘W / Hide | Fresh `--relaunch` instance within ~300 ms, one process, click tap live |
| Quit with settings open | Quit button and Apple Event quit exit without relaunching |
| Installed copies | `install.sh` leaves one bundle; Spotlight and LaunchServices list only `/Applications/FingerChord.app` |

Still needs fingers on hardware: middle taps after a scroll with the new stillness rule, presses, sleep / wake, lock / unlock and a Bluetooth trackpad.

### Earlier

- **1.2.0** — Polls removed; 55 tests, lifecycle and event self-tests passed; 0 leaks; idle CPU 0.00 s over 28 s; 100 restarts left the device registry unchanged.
- **1.1.2** — Reposted clicks keep their drag and up behind the down after a trace showed a physical up 9 ms after a timed-out release; 49 tests and lifecycle test passed.
- **1.1.1** — Physical presses keep only the native click feel. An acceptance trace showed two three finger and two four finger presses with no app haptic, and three middle taps with three haptics; the user confirmed the feel.
- **1.0–1.1** — Repeated middle taps without lifting the pair, three / four finger presses and no false action during three finger dragging were accepted on hardware.
