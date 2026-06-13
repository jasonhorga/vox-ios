# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Vox Input — an iOS voice-input app (iOS 17+, Swift/SwiftUI) with a custom **keyboard extension**. The user dictates speech; it's transcribed by a cloud ASR (Qwen/DashScope or OpenAI-Whisper-compatible), post-processed, and either copied to the clipboard (main app) or injected into the active text field (keyboard).

> The `README.md`/`ROADMAP.md` describe an early "Sprint 0 planning" state and are **stale** — the app is well past that (shipping to TestFlight, build `beta.60+`). Trust the source, not those docs. The `docs/planning/*` files are historical design notes; `docs/vox-wakeup-flow.md` is the one doc that still maps to current behavior.

## Build / test / release

The Xcode project is **not committed** — `*.xcodeproj` is gitignored and generated from `project.yml` by [XcodeGen]. `project.yml` is the source of truth for targets, bundle IDs, entitlements, Info.plist, and build settings. **Edit `project.yml`, never the generated `.xcodeproj`.** After changing it (or adding/removing source files), regenerate:

```bash
brew install xcodegen          # one-time
xcodegen generate              # or: ./setup.sh   (regenerates VoxInput.xcodeproj)
bundle install                 # fastlane + xcpretty, from Gemfile
```

Building/testing requires **macOS + Xcode** (iOS toolchain). This is normally **not done locally** — it runs in GitHub Actions on `macos-15` runners. Editing Swift, `project.yml`, workflows, and `fastlane/Fastfile` is fully doable on any platform; compiling/simulator is not.

If you do have a Mac, the equivalents of the CI steps:

```bash
# Build (signing disabled, like CI)
xcodebuild build -project VoxInput.xcodeproj -scheme VoxInput \
  -destination 'generic/platform=iOS Simulator' -configuration Debug \
  CODE_SIGNING_ALLOWED=NO | xcpretty

# Run the full test bundle (use any installed simulator, e.g. "iPhone 16")
xcodebuild test -project VoxInput.xcodeproj -scheme VoxInputTests \
  -destination 'platform=iOS Simulator,name=iPhone 16' CODE_SIGNING_ALLOWED=NO | xcpretty

# Run a SINGLE test class or method (placeholder names — check VoxInputTests/ for real ones)
xcodebuild test ... -only-testing:VoxInputTests/TextFormatterTests
xcodebuild test ... -only-testing:VoxInputTests/TextFormatterTests/testMethodName

# Lint (config in .swiftlint.yml; force_unwrapping is opt-in & enforced)
swiftlint lint
```

### CI/CD (this is the real workflow)

- **`.github/workflows/ci.yml`** — on push/PR to `main`: XcodeGen → build app + keyboard → boot a simulator → run `VoxInputTests` → SwiftLint. **Push to `main` to run build+tests.**
- **`.github/workflows/cd.yml`** — on push of a **`v*` tag** (or manual `workflow_dispatch`): runs `bundle exec fastlane beta` → builds Release IPA → uploads to TestFlight. **To ship a build, tag `vX.Y.Z` and push the tag.**
- **`.github/workflows/signing-bootstrap.yml`** — manual only.

### Signing (fastlane match — read before touching CD)

- Code signing uses **fastlane match** with certs/profiles persisted in a **separate private git repo** (the `vox-ios-signing` repo, via `MATCH_GIT_URL`). Secrets `MATCH_*` and `ASC_*` live in GitHub Actions secrets.
- `fastlane beta` is the release lane: it auto-computes the next build number from the latest TestFlight build, increments it, builds Release, and uploads. CI is **intentionally blocked from creating new Distribution certificates** (`ensure_match_env!`).
- `fastlane bootstrap_signing` is a **one-time, run-locally-never-in-CI** lane that creates the signing assets in the match repo.
- App identity is fixed: team `6HB84897DJ`, bundle IDs `com.jasonhorga.vox` (app) + `com.jasonhorga.vox.keyboard` (extension). The app record `com.jasonhorga.vox` must already exist on App Store Connect (`Fastfile` asserts this).

## Architecture — the big picture

Two targets share the `Shared/` directory (compiled into both): main app **`VoxInput`** and keyboard extension **`VoxInputKeyboard`**. iOS keyboard extensions are sandboxed and memory-limited (~60 MB target) and **cannot record audio reliably or switch apps**. The whole design works around that constraint.

### Cross-process IPC (the spine of the app)

The app and keyboard are **separate processes** that coordinate through two channels, both defined in `Shared/`:

1. **App Group shared `UserDefaults`** (`group.com.jasonhorga.vox`, see `Shared/AppGroup.swift`) — a tiny message bus. Keys are `vox.ipc.*`: a command (`start`/`stop`/`cancel`) with a monotonic `command_id`, the daemon `state`, an `error` string, a `result` text with monotonic `result_id`, plus a `heartbeat` timestamp. Writers bump the `*_id` so polling readers detect changes; consumers clear `result` after reading.
2. **Darwin notifications** (`Shared/DarwinIPC.swift`, `CFNotificationCenterGetDarwinNotifyCenter`) — cross-process broadcast for *immediacy*: `wakeUpAndRecord` (keyboard → app) and `daemonStateDidChange` (app → keyboard). These wake the other side instantly instead of waiting for the next poll.

Both sides also poll (~0.2 s timers) as a fallback. The keyboard treats the daemon as **dead if the heartbeat is stale** (`heartbeatTimeout`, 1.5 s) — this defends against a zombie `idle` state left in UserDefaults after the app is force-killed (see `KeyboardState.apply`).

### The "audio daemon" (main app) — `VoxInput/App/AudioDaemonService.swift`

The main app hosts an always-on recorder service (`@MainActor`, owned by `VoxInputApp`, started on launch and on every scenePhase change). It's a state machine: `idle → recording → processing → idle`, plus `sleeping` (idle-timeout standby), `error`, `dead`. It:
- polls App-Group commands and reacts to the `wakeUpAndRecord` Darwin notification;
- keeps an `AVAudioEngine` **primed** (input tap installed) even in the background so background recording can start instantly — "Typeless Always-On" (`beta.40`). `start`/`stop` are soft switches over the primed engine, not engine lifecycle;
- uses `UIBackgroundTask` keep-alives and the `audio` background mode to survive backgrounding;
- on idle timeout, goes `sleeping` (configurable: 3 m / 10 m / never via `DaemonStandbyDuration`);
- has **crash recovery** (`beta.58`): on launch, rescues an orphaned recording left in tmp by a previous crash into history.

### Two recording paths

- **Keyboard path** (`VoxInputKeyboard/KeyboardState.swift` ↔ daemon): the keyboard is a **remote control**. It never records itself — it sends `start`/`stop`/`cancel` over IPC, the daemon records and transcribes, writes the `result`, and the keyboard injects it via `textDocumentProxy.insertText`. `KeyboardState` mirrors the daemon's state machine into a UI `KeyboardPhase` and has watchdog timers (startup-ack, result-timeout) to recover from a non-responsive daemon.
- **Main-app path** (`VoxInput/App/AppState.swift`): direct pipeline — `AudioRecorder` → `ASRFactory.transcribe` → optional `PostProcessor` (translation) → `TextFormatter` → `ClipboardOutput`. This path copies to clipboard rather than injecting.

### The cold-start / wakeup dance (subtle — read `docs/vox-wakeup-flow.md`)

When the user taps record in the keyboard but the daemon is `sleeping`/`dead`, the keyboard can't start audio and **can't switch apps**. Its only lever is to open a URL (`voxinput://record?...`) by walking the `UIResponder` chain for `openURL:` (`KeyboardViewController.autoJumpToMainApp`). That foregrounds the main app, which primes the daemon and then tries to `suspend` itself to bounce back to the previous app.

The critical nuance (`beta.60`): iOS's "return to previous app" transition context expires ~1 s after foregrounding. A **hot wakeup** (daemon already alive) primes in <0.5 s, so `suspend` works and the user is returned automatically. A **cold start** (app was not running) primes too slowly — `suspend` would dump the user to the home screen — so the app detects cold-start (via the "first URL in this process lifetime" flag, *not* the heartbeat — see `AppState.isWakeupColdStart`) and instead shows a "ready, please go back" message without suspending.

### ASR providers — `Shared/ASR*`

`ASRProvider` protocol with `QwenASR`, `WhisperAPIASR`, and `AppleSpeechASR` (on-device) implementations. `ASRFactory.create` picks the provider from config and **falls back to `AppleSpeechASR` when offline** (`NetworkMonitor`). `ASRFactory.transcribe` wraps calls with retry + a 15 s timeout. The daemon prefers Qwen and degrades through the factory; both paths write to `HistoryManager`, and **failed transcriptions persist the audio** to `Documents/SavedAudio/` with an "unrecognized" history entry rather than discarding it.

### Config & secrets

Two stores, both backed by App Group UserDefaults + a shared-Keychain access group (`com.jasonhorga.vox.shared`):
- `Shared/SharedConfigStore.swift` — used by the keyboard (and shared code).
- `VoxInput/Storage/ConfigStore.swift` — used by the main app; owns `migrateIfNeeded()` (migrates legacy `UserDefaults.standard` → App Group/Keychain).

**API keys live in the Keychain** (`Shared/KeychainStore.swift`), not UserDefaults — keep it that way. Non-sensitive settings (provider choice, custom URLs, models, standby duration) live in App Group UserDefaults.

## Conventions & gotchas

- **Adding a source file** = add it under the right directory (`VoxInput/`, `VoxInputKeyboard/`, or `Shared/`) **and re-run `xcodegen generate`**. There's no checked-in project to "add to" in Xcode. Code in `Shared/` is compiled into *both* targets, so it must not import app- or extension-only APIs.
- Commit messages follow Conventional Commits with a build tag, e.g. `fix(app): … (beta.60.5)`. Behavioral changes are heavily annotated inline with `betaNN:` comments explaining *why* a timing/threshold changed — preserve and extend that pattern when you touch the IPC/wakeup timing.
- Tuning constants (poll intervals, timeouts, heartbeat, keyboard heights, audio params) are centralized in `Shared/Constants.swift`. Change them there, not at call sites.
- SwiftLint enforces `force_unwrapping` (opt-in rule) — avoid `!`. Line length warns at 140 / errors at 200.
- The keyboard requires **Full Access** (`RequestsOpenAccess`) for network + App Group; UI degrades to a guide view when it's off (`FullAccessGuideView`). Password fields (`isSecureTextEntry`) disable voice input.
