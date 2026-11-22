# Development and verification

## Architecture

| Component | Responsibility |
| --- | --- |
| `GestureCore` | Pure Swift contact recognition, physical button coordination and paired click suppression |
| `TouchBridge` | Runtime MultitouchSupport loading, ABI boundary and device ownership |
| `InputMonitor` | Per-device state, CoreGraphics event taps, short click buffering, live preview and action delivery |
| `HardwareButtonMonitor` | Public IOHIDManager physical switch values and exact trackpad matching |
| `DeviceWatcher` | IOKit arrival / termination notifications for multitouch devices |
| `AppModel` / `AppDelegate` | Preferences, permissions, login service, single instance, window and session lifecycle |
| `SettingsView` / `Localization` | SwiftUI settings and three localized resource bundles |

The private touch ABI was checked against macOS 27.0 (26A428). A touch has a 96-byte layout with normalized coordinates at offset 32; compile-time C assertions enforce these assumptions. The legacy button callback is retained, but this Mac's MTHID device does not deliver it. Physical presses use HID Usage Page 9 / Usage 1 instead. Tap-to-click and three finger dragging do not produce that switch value.

### Threading and ownership

- App model, start/stop operations, HID manager, device notifications and event taps run on the main run loop.
- Nothing polls. Monitoring is reconciled on launch, settings display, preference changes, System Settings losing focus (permissions and login items), screen lock / unlock, sleep / wake, session switches and multitouch device arrival or removal. Each reconciliation reads the current lock state and restarts a monitor whose tap or device is no longer healthy. A failed start is retried once after two seconds, for devices still settling after wake or pairing.
- Only clicks and drags pass through the filtering event tap. Scrolls use a separate listen-only tap, so system scrolling never waits for this process. A click is held only while three or more fresh contacts could turn it into a gesture, or while an earlier click for the same button is still being reposted; other one and two finger clicks pass immediately. If a press resolves after its system click already reached an app, it stays a plain click and sends no shortcut.
- The live preview is pushed only while settings are visible. Frames coalesce into at most one pending main-queue update, and only the preview views observe it.
- Multitouch callbacks can run on framework threads. A lock protects recognition state and the session generation. Dispatched actions verify their generation before execution, so stopping/reconnecting invalidates old work.
- `FCStop` disconnects and drains callback sinks before unregistering callbacks, stopping devices and releasing the owned device array. The dynamic framework handles intentionally remain loaded for the process lifetime.
- HID value callbacks are explicitly unregistered before unscheduling and closing their manager. CF event tap and run-loop source references are invalidated and released on stop.
- Each pending click is keyed by a known trackpad and button. Each batch has its own token so an old timeout cannot resolve a later click. Unknown mouse senders do not grow the gate cache.
- Once a pending click is released, its remaining drag and up events are reposted in order until the up. A real up already queued at the tap therefore cannot overtake the reposted down and leave the target app holding the button. Stopping the monitor replays only completed clicks. A disabled tap drops held clicks because newer events already bypassed it.
- Diagnostic fields are evaluated outside the trace lock to avoid reversing the monitor/trace lock order. A session generation rejects records still being prepared when a recording is stopped.
- Timers and UI callbacks capture models weakly. Preview models do not start hardware monitoring or change stored preferences. Stopped diagnostics release their entries after a single write.

## Local checks

```sh
./scripts/test.sh
swift test --sanitize=address
./scripts/build.sh
xcrun swift-format lint -r Sources Tests Package.swift
```

The full package requires macOS 27. `./scripts/test-core.sh` copies the platform-independent recognition code and tests to a temporary Swift package, for hosted CI on earlier macOS versions. Temporary files are removed automatically.

GitHub's [runner inventory](https://github.com/actions/runner-images#available-images) lists macOS 26 as the current hosted image at preparation time. Therefore hosted CI checks the gesture core. The full app workflow is manual and requires a self-hosted runner with the custom `macOS-27` label. It does not run untrusted pull requests on a personal Mac. Neither workflow grants input permissions or runs hardware shortcuts on CI.

## Diagnostics

Quit the normal app before running hardware self-tests. A second normal launch reopens settings in the existing instance. Command-line permission attribution can differ from Launch Services; prefer launching the installed app when testing actual input.

```sh
# Permission, device and raw frame counts; --observe watches for 15 seconds.
/Applications/FingerChord.app/Contents/MacOS/FingerChord --probe --observe

# Show settings, enable test mode and record a bounded trace.
open /Applications/FingerChord.app --args --settings --diagnose

# Start a fresh trace in the already-running app.
/Applications/FingerChord.app/Contents/MacOS/FingerChord --start-diagnostics

# With the normal app quit: 100 real input lifecycle cycles, then hold for 45 seconds.
open /Applications/FingerChord.app --args --self-test-lifecycle --hold-for-leaks
cat "$HOME/Library/Application Support/FingerChord/lifecycle-test.json"
leaks FingerChord
```

Lifecycle tests disable every gesture during restart cycles and verify that monitor objects deallocate. They also fill and release the diagnostic buffer ten times. Finally, the event self-test sends three ⌘ click pairs, ⌘W and ⌘Q through an absorbing event tap; all ten synthetic events are intercepted before reaching other applications. The test refuses to send if required permissions or the absorbing tap are unavailable. It leaves login and gesture preferences unchanged and exits automatically. Check `passed: true` in the report; `open`'s exit status only reports launch success.

`--self-test-events` runs the event test alone. `--self-test-login` registers and unregisters the login item only when it was initially unregistered; existing login preferences are preserved. Do not run the login test while relying on login startup.

Opt-in traces live at `~/Library/Application Support/FingerChord/diagnostic.json`. They contain touch coordinates, timestamps, button and status events; inspect before sharing. Normal operation does not write them. The trace stops and is written once after 180 seconds or 10,000 entries, whichever comes first. The lifecycle self-test overwrites this file with its capacity check.

## Screenshots and media

```sh
app=dist/FingerChord.app/Contents/MacOS/FingerChord
"$app" --render-settings docs/media/settings-zh-Hans.png --language zh-Hans
"$app" --render-settings docs/media/settings-en.png --language en
"$app" --render-settings .build/settings-dark.png --language zh-Hant --dark
"$app" --render-settings .build/settings-permissions.png --language en --permissions
```

The renderer uses the real settings view with a deterministic preview model. It does not acquire input monitoring, register login items or send shortcuts. These are interface renders, not evidence of a live hardware state. Language flags apply only to that rendering process.

The supplied demonstration was renamed to `fingerchord-demo.mp4` and converted to H.264/YUV420p with fast-start metadata. A compact GIF provides an inline README preview. The original desktop MOV was preserved; the recording depicts the initial UI.

## Verification — 2026-09-16

Environment: macOS 27.0 (26A428), Apple Silicon, Swift 6.4, built-in Force Touch trackpad.

| Check | Result |
| --- | --- |
| Gesture regression tests | 44 passed |
| App resource / localization / object-release tests | 3 passed |
| Address Sanitizer | Both test suites passed; no reported memory-access errors |
| C static analyzer | No diagnostics for TouchBridge |
| Release build and code signature | Passed |
| Real hardware lifecycle stress | 100 / 100 starts and 100 / 100 monitor releases |
| Diagnostic capacity / release stress | 10 full buffers bounded and released |
| Event emission | 10 / 10 synthetic events, intercepted before other apps |
| `leaks` after lifecycle stress | 0 leaks / 0 bytes; physical footprint 22.8 MB, peak 23.0 MB |
| `leaks` with live settings and language switching | 0 leaks / 0 bytes |
| Settings UI | English, Simplified / Traditional Chinese, light / dark and permission layouts inspected |
| Existing preferences | All three gestures and the user's enabled login preference retained |

Earlier physical acceptance by the user confirmed repeated middle finger taps without lifting the resting pair, three / four finger presses, no false action on three finger dragging, and haptics in foreground and background. This release also received live language-switching checks. These bounded checks cannot prove the absence of every leak or driver issue. External trackpads, alternate keyboard layouts and startup after a fresh login still need separate hardware validation.

## Packaging

`./scripts/package-release.sh` builds a ZIP named with the version and current architecture plus a SHA-256 file. The app includes GPL and attribution notices. It uses the local certificate if available, otherwise ad-hoc signing. These are local artifacts, not notarized distribution releases. Public distribution requires choosing a signing/notarization process and supplying corresponding source under GPLv3.

## Physical press feedback — 1.1.1

The app no longer adds a haptic after a three / four finger physical press; it uses the trackpad's native click feedback. Middle finger taps still request one immediate haptic each. This removes the delayed second bump caused by requesting feedback after the hardware press had already occurred.

Validation on 2026-09-16: all 49 tests passed. The installed app's event self-test passed. The physical acceptance trace contained two three finger presses and two four finger presses, all without an app-generated haptic, plus three middle finger taps with exactly three haptic requests. The user confirmed that the resulting press feel was very good. Trace files remain local and are not included in the repository.

## Click ordering — 1.1.2

Occasionally every click acted like press-and-hold until the app restarted. A deferred trackpad down was released by the 80 ms timeout and reposted at the HID tap, but a real up already queued at the tap could pass first; an earlier trace shows a physical up 9 ms after such a release. The target app then received the up before its down. A released click now reposts its remaining drag and up events behind the down.

Validation on 2026-11-23 (macOS 27.2.1, 26B131): all 49 tests passed, also with Address Sanitizer, and swift-format lint was clean. The Developer ID release build was installed. The installed app's lifecycle self-test passed: 100 / 100 starts and releases, plus the event self-test. The race depends on hardware timing, so these checks cannot reproduce it directly; confirm through normal trackpad use.

## Event-driven monitoring — 1.2.0

The 2 s status poll, the 60 ms preview poll and the 2 s diagnostic flush were removed. Monitoring now follows system notifications and multitouch device arrival / removal. One and two finger clicks are no longer held. Scrolls leave the filtering tap. Contact updates redraw only the preview.

Validation on 2026-11-23 (macOS 27.2.1, 26B131): all 55 tests passed, also with Address Sanitizer; the core-only package, swift-format lint and a warning-free build passed. The installed Developer ID build passed the lifecycle self-test (100 / 100 starts and releases with both taps) and the event self-test. `leaks` reported 0 leaks after the stress run (22.7 MB footprint) and in the running app (10.6 MB). A 5 s `sample` of the idle app showed every thread blocked in `mach_msg`; settled idle CPU time was 0.00 s over 28 s, versus 0.02 s per 25 s for 1.1.2. 100 monitor restarts left the `AppleMultitouchDevice` registry entry unchanged, so restarts cannot retrigger the device watcher. Physical checks remain: 3 / 4 finger presses, middle taps, click latency, sleep / wake, lock / unlock and connecting a Bluetooth trackpad.
