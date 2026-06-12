# EarGuard — macOS Earphone Listening-Time Tracker

A menu-bar app for macOS, written in Swift, that tracks how much time you spend listening to audio through earphones/headphones each day, and how loud, with warnings for sustained loud listening — similar in spirit to iOS "Headphone Safety", which macOS lacks entirely.

---

## 1. Goal and non-goals

### Goal

- Count listening time **only while audio is actually being played to a headphone-class output device** (Bluetooth earbuds like your Redmi, or wired headphones in the jack). Connected-but-silent does not count.
- Track **volume exposure**: time-weighted volume level while listening, and warn when you listen loud for a sustained period.
- Show everything in a lightweight **menu-bar app**: today's total at a glance, last 7 days, average volume.
- Persist daily history locally so trends survive restarts.

### Non-goals (stated plainly)

- **No in-ear detection for third-party earbuds.** AirPods expose an in-ear sensor; Redmi and other third-party buds do not expose anything like it to macOS. There is no API for it. Consequence: if audio is *actively playing* while your buds sit on the table, that time **will** be counted. The "device is running" check covers the common case (connected but idle = not counted), but not the "playing into the void" case. This is a hard platform limit, not a solvable bug.
- **No real dB SPL measurement.** System volume % is a proxy. Two different earbuds at 70% volume produce different real-world loudness. We track exposure in volume-% terms and are honest about that in the UI.
- No iOS companion, no cloud sync, no per-app attribution of audio (macOS doesn't expose which app is rendering to the device without much heavier machinery).
- No idle-input heuristic (decided with user: counting is purely "audio playing to headphones", predictable and simple).

---

## 2. Technical approach

### CoreAudio APIs

All of this is public, non-deprecated CoreAudio / AudioObject API. No private APIs, no special entitlements, no TCC permission prompts.

| What we need | API |
|---|---|
| Current default output device | `kAudioHardwarePropertyDefaultOutputDevice` on `AudioObjectSystemObject` |
| Device transport type | `kAudioDevicePropertyTransportType` → `Bluetooth`, `BluetoothLE`, `BuiltIn`, `USB`, `AirPlay`, … |
| Built-in jack: headphones vs speakers | `kAudioDevicePropertyDataSource` (output scope) → `'hdpn'` when headphones are plugged into the jack |
| Is audio actively rendering | `kAudioDevicePropertyDeviceIsRunningSomewhere` — true while *any* process has an active IO proc on the device. This is the listening proxy. |
| Volume | `kAudioDevicePropertyVolumeScalar` (output scope, main element; fall back to channel 1/2 average), with `kAudioDevicePropertyVirtualMainVolume` as fallback |
| Device name (for heuristics/UI) | `kAudioObjectPropertyName` |

### Listeners vs polling: both, deliberately

- **Property listeners** (`AudioObjectAddPropertyListenerBlock`) on: default output device changes, `DeviceIsRunningSomewhere`, data source changes, and device volume. These give instant, battery-cheap state transitions (start/stop of listening sessions, device switches).
- **A light polling timer (every 5 s)** while a listening session is active, for two jobs:
  1. Accumulate elapsed time and sample volume for the time-weighted exposure model.
  2. Safety net — CoreAudio listeners occasionally miss transitions across device hot-swaps; a poll reconciles state.
- When no headphone device is the default output, the timer is stopped entirely; the app sits idle on listeners only. CPU cost ~zero.

### Classifying a device as "headphones"

In priority order:

1. **Transport type is Bluetooth or BluetoothLE** → headphones. (Edge case: Bluetooth *speakers* exist. Mitigation: name heuristic below can demote, and a manual override exists — see open questions.)
2. **Transport type is BuiltIn and data source is `'hdpn'`** → wired headphones in the jack.
3. **Name heuristic** as a tiebreaker for USB/other transports: name contains `headphone`, `earbud`, `buds`, `airpods`, `headset`, `arctis`, etc. → headphones; contains `speaker`, `display`, `monitor`, `TV` → not headphones.
4. Anything else (USB DAC with neutral name, HDMI, AirPlay) → **not counted** by default. Better to undercount than to count your monitor's speakers.

### Listening state machine

```
counting = (default output is headphone-class) AND (DeviceIsRunningSomewhere == true)
```

- Transition to `counting` opens a session (timestamp, device name).
- Transition out (audio stops, device switches to speakers, device disconnects, machine sleeps) closes the session and flushes to disk.
- Note: `DeviceIsRunningSomewhere` goes false a few seconds after playback stops (apps release the IO proc lazily — e.g. Spotify holds it ~30 s after pause). Accept the slight overcount; it's bounded and consistent.

### Volume exposure model

- Every 5 s tick while counting: sample volume scalar `v ∈ [0,1]`, add to the day's `volumeWeightedSeconds += v * 5` and `loudSeconds += 5 if v ≥ 0.75`.
- **Day metric: average listening volume** = `volumeWeightedSeconds / totalSeconds`, shown as %.
- **Loud-listening warning**: if the rolling window of the last 30 minutes contains ≥ 25 minutes of loud (≥75% volume) listening, fire a notification ("You've been listening loud for 25 of the last 30 minutes — consider turning it down"), at most once per hour. Thresholds (75%, 25/30 min, cooldown) live as named constants, easy to tune later.
- UI always labels this as **volume %, not decibels** — e.g. "avg volume 62%". No fake dB numbers.
- Fallback: if a Bluetooth device exposes no volume property (some don't), duration still counts; volume shows as "n/a" and the warning system is disabled for that device.

---

## 3. App architecture

Small, boring, single-process. ~7 source files in one SwiftPM target.

```
Sources/EarGuard/
  main.swift                 — app bootstrap, NSApplication, AppDelegate (LSUIElement agent app)
  AudioDeviceMonitor.swift   — CoreAudio wrapper: current device, transport, data source,
                               isRunningSomewhere, volume; owns property listeners; emits
                               plain Swift events (deviceChanged, runningChanged, volumeChanged)
  HeadphoneClassifier.swift  — pure function: (transport, dataSource, name) → isHeadphone
  ListeningTracker.swift     — the state machine + 5 s tick; owns the current session;
                               produces per-tick samples (elapsed, volume)
  ExposureModel.swift        — rolling 30-min loudness window, warning decisions
  Store.swift                — persistence: daily aggregates, day rollover, atomic JSON writes
  StatusItemController.swift — NSStatusItem icon + menu construction/refresh
  Notifier.swift             — UNUserNotificationCenter wrapper (loud-listening warnings)
```

**Data flow:** `AudioDeviceMonitor` events → `ListeningTracker` decides counting on/off and ticks → samples go to `Store` (durations) and `ExposureModel` (loudness window) → `ExposureModel` may trigger `Notifier` → `StatusItemController` reads `Store` + tracker state to render the menu. Everything on the main queue except CoreAudio callbacks, which hop to main immediately. No Combine, no reactive framework — direct delegate/closure wiring.

### Persistence

- Location: `~/Library/Application Support/EarGuard/history.json`
- Format — one record per calendar day (local timezone):

```json
{
  "days": {
    "2026-06-12": {
      "seconds": 9840,
      "volumeWeightedSeconds": 6120.5,
      "loudSeconds": 1800,
      "byDevice": { "Redmi Buds 4 Active": 9840 }
    }
  }
}
```

- Write strategy: flush on session close, on day rollover, on app quit, and at most every 60 s during a long session (so a crash loses ≤ 1 min). Atomic write (temp file + rename).
- **Day rollover at midnight:** a session spanning midnight is split — seconds before 00:00 go to the old day, the rest to the new day. A timer scheduled for next midnight handles rollover even mid-session.
- Sessions themselves are not persisted long-term in v1 (daily aggregates only); the session model exists in memory for correctness, not reporting.

### Sleep/wake & lifecycle

- Observe `NSWorkspace.willSleepNotification` / `didWakeNotification`: close any open session on sleep, re-evaluate state from scratch on wake (don't trust pre-sleep listener state).
- On quit (`applicationWillTerminate`), close session and flush.

---

## 4. UI

### Menu-bar item

- Icon: SF Symbol headphones glyph; title text next to it shows today's time, e.g. `🎧 2h 41m` (compact `2:41` style configurable later). Updates once a minute while counting.
- Warning state: icon switches to `headphones.exclamationmark` (tinted) while the loud-listening condition is active.

### Dropdown menu (plain NSMenu, no SwiftUI popover in v1)

```
Today: 2h 41m  ·  avg volume 63%
Now: Redmi Buds 4 Active (playing)        ← or "(connected, silent)" / "No headphones"
──────────────────────────────
Last 7 days
  Thu Jun 11      3h 12m   ▍▍▍▍▍▍
  Wed Jun 10      1h 05m   ▍▍
  ... (text rows with simple unicode bars; real charts are a later nicety)
──────────────────────────────
⚠ Loud listening: 25m at ≥75% in the last 30m   ← only when active
──────────────────────────────
Launch at Login   [✓]
Quit EarGuard
```

### Notifications

- `UNUserNotificationCenter` for the loud-listening warning. **This requires a real `.app` bundle with a bundle identifier** — a bare SwiftPM executable can't register with the notification system. That constraint drives the packaging approach below.
- Permission requested on first launch; if denied, the warning falls back to the menu-bar icon state only.

---

## 5. Build & packaging

- **SwiftPM executable** (no `.xcodeproj`): `swift build -c release` produces the binary. Everything editable/buildable from the command line.
- **`make app`** script assembles `EarGuard.app`:
  1. `swift build -c release`
  2. Create `EarGuard.app/Contents/{MacOS,Resources}`, copy binary
  3. Generate `Info.plist` with `CFBundleIdentifier=dev.anish.earguard`, **`LSUIElement=true`** (menu-bar agent: no Dock icon, no app switcher entry)
  4. Ad-hoc codesign (`codesign --force --sign -`) so notifications and login-item registration behave
- **Install/run:** `make install` copies to `/Applications`; `open /Applications/EarGuard.app`. First run asks for notification permission, then it just lives in the menu bar.
- **Launch at login:** `SMAppService.mainApp.register()` (macOS 13+), toggled from the menu. No helper app needed.

---

## 6. Milestones

Each milestone is independently runnable and verifiable — you can stop me and inspect at any point.

- **M1 — CoreAudio proof (CLI).** A throwaway command-line mode that prints, live: default output device, transport type, headphone classification, `isRunningSomewhere`, volume. **Verify with your actual Redmi buds**: connect, play, pause, take out, plug wired headphones. This de-risks the entire project before any UI exists.
- **M2 — Tracking + persistence.** State machine, 5 s tick, daily aggregates, midnight rollover, sleep/wake handling, atomic JSON writes. Still CLI-observable.
- **M3 — Menu-bar UI.** NSStatusItem with live today-total, dropdown with last 7 days, Quit. App is now daily-usable.
- **M4 — Volume exposure + warnings.** Time-weighted volume, rolling loudness window, notification + icon warning state.
- **M5 — Packaging & polish.** `.app` bundle script, ad-hoc signing, launch-at-login toggle, README.

---

## 7. Open questions & risks

| Risk / question | Plan |
|---|---|
| **Bluetooth speakers misclassified as headphones** | Name heuristic demotes obvious speakers; if you own a BT speaker this gets wrong, v1.1 adds a per-device "ignore this device" menu toggle. Acceptable for v1? |
| **BT devices that don't report volume** | Duration still tracked; volume shows "n/a", warnings disabled for that device. Verified in M1 against the Redmi buds specifically. |
| **`isRunningSomewhere` lag after pause** | Apps hold the audio device ~5–30 s after pausing. Slight overcount, bounded and consistent. Not fixable without per-app audio taps; accepted. |
| **Multi-output / aggregate devices** | If the default output is an aggregate containing a headphone sub-device, v1 classifies by the aggregate's name only (likely "not headphones"). Rare setup; documented limitation. |
| **AirPlay** | Not counted (could be speakers or a TV). Could add as opt-in later. |
| **Sleep/wake edge cases** | Sessions force-closed on sleep, state rebuilt on wake. M2 includes a manual sleep test. |
| **Midnight rollover during playback** | Session split across days via a scheduled midnight timer. M2 includes a clock-change test (set clock forward manually). |
| **Loudness thresholds (75%, 25/30 min)** | Reasonable defaults inspired by WHO/iOS behavior but ultimately arbitrary in volume-% space. Shipped as constants; tune after a week of your real data. |

---

*Stack: Swift 6.1, AppKit + CoreAudio + UserNotifications + ServiceManagement. Min target macOS 13. No third-party dependencies.*
