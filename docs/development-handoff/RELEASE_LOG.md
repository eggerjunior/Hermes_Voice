# Release Log

Generated: 2026-07-13T17:21:45-03:00

Record every deploy, TestFlight/App Store upload, web publish and external processing status here.

## 2026-07-18 - Fix app stuck in "Ouvindo..." forever after barge-in (1.8.0 regression)

- App: Hermes Voice
- Platform: iOS native SwiftUI
- Bundle ID: `br.app.egger.HermesVoice`
- Version/build prepared: `1.8.1` / `37`
- Branch: `main`
- Base commit before changes: `aa66e52`'s parent (`7ea0af6`)
- User report: after interrupting Hermes with the wake word (or even without it, by the second turn), the app gets stuck showing "Ouvindo..." forever and stops responding.
- Root cause: `SpeechSynthesizer.stop()` (called both by the new wake-word interrupt and, less obviously, whenever `AVSpeechSynthesizer.stopSpeaking(at:)` cancels multiple already-queued sentence utterances) fires `didCancel` once per canceled utterance. Each of those calls checked `pendingUtterances == 0 && !turnOpen` — a condition that, once true, stays true for every subsequent cancel in the same batch — so `speechSynthesizerDidFinishSpeaking()` fired multiple times in a row. Each firing called `SpeechRecognizer.shared.startRecording()`, which internally does `stopRecording()` then immediately spins up a new `SFSpeechRecognitionTask`. Firing that in tight succession raced the still-tearing-down previous task and could leave `SFSpeechRecognizer` in a state where it accepted audio but never delivered another result — the app's `sessionState` said `.listening`, but nothing was actually listening.
- Fix 1 (`Sources/Speech/SpeechSynthesizer.swift`): added a `didNotifyFinish` flag (mirrors the existing `didNotifyStart` pattern), reset in `beginTurn()`, consumed by a new `notifyFinishIfNeeded()` that all three call sites (`endTurn`, `didFinish`, `didCancel`) now go through — guarantees at most one "finished speaking" notification per turn.
- Fix 2 (`Sources/Speech/SpeechRecognizer.swift` + `Sources/Session/VoiceSession.swift`): added `speechRecognizerDidFail()` to the delegate protocol. The recognition task's error branch now distinguishes an intentional stop (we'd already called `stopRecording()` ourselves, so `isListening` was already false) from a genuine unexpected death (`isListening` still true) — only the latter notifies the delegate. `VoiceSession.speechRecognizerDidFail()` retries `startRecording()` once after a 0.3s delay if still in `.listening`/`.speaking` and unmuted, as a self-healing safety net regardless of root cause.
- Fix 3 (`Sources/Session/VoiceSession.swift`): added an RMS energy gate (`bargeInEnergyThreshold = 0.02`, linear full-scale) — while `.speaking`, mic buffers are only forwarded to the recognizer above that threshold, to reduce the risk of Hermes hearing its own name in its own echo (imperfect AEC) and self-interrupting. Heuristic threshold, not validated on a physical device against real echo levels in this session — may need tuning based on field reports.
- Commands executed:
  - `xcodebuild -project HermesVoice.xcodeproj -scheme HermesVoice -destination 'generic/platform=iOS Simulator' build` — succeeded
  - `xcodegen generate`
  - `git commit` + `git push`
  - `./scripts/testflight.sh`
- Result: archive/export/upload all succeeded (`Upload succeeded`).
- Status: **`1.8.1` (37) uploaded to App Store Connect/TestFlight; package is processing.** Fix 1 is a definite, high-confidence correctness fix (the multi-notify bug was unambiguous from reading the code). Fixes 2 and 3 are defense-in-depth / best-effort — not exercised with real device audio in this session. Recommend hands-on retest of: (a) interrupting mid-sentence with "Hermes", (b) doing at least 3 consecutive turns without interrupting, (c) a response where Hermes says its own name, to confirm no more stuck states or false self-interrupts.

## 2026-07-18 - Barge-in wake word, provider label on main screen, AIsa provider

- App: Hermes Voice
- Platform: iOS native SwiftUI + backend microservice on VPS (egger.app.br)
- Bundle ID: `br.app.egger.HermesVoice`
- Version/build prepared: `1.8.0` / `36`
- Branch: `main`
- Base commit before changes: `8f9e7f7`
- User reports (App Store feedback, 3 items with screenshots):
  1. Wants a way to interrupt Hermes mid-speech with an activation word, staying background-listening while it talks (like Jarvis).
  2. Main screen only showed "motor · modelo"; wants provider shown too (3 pieces of info).
  3. Wants the "AISA" provider (console.aisa.one) added to the provider/model picker in Settings.
- Fix 1 (barge-in): `Sources/Session/VoiceSession.swift`, `Sources/App/RootView.swift` unaffected for this part. Mic now stays live during `.speaking` (`AudioEngineManager` tap now forwards buffers when `sessionState` is `.listening` OR `.speaking`; `speechSynthesizerDidStartSpeaking()` restarts the recognizer instead of stopping it). `speechRecognizerDidRecognizeText` checks for the wake word "hermes" (diacritic/case-insensitive substring) while `.speaking` and calls `SpeechSynthesizer.shared.stop()` on match, which lets the existing `didCancel` → `speechSynthesizerDidFinishSpeaking()` plumbing return the app to `.listening`. `speechRecognizerDidDetectSilence` now ignores events fired while `.speaking` (that recognizer pass is only for wake-word detection, not full turns). Relies on the AEC already enabled via `AVAudioInputNode.setVoiceProcessingEnabled(true)` (`AudioEngineManager.swift`) + shared `.voiceChat` audio session (`synthesizer.usesApplicationAudioSession = true`) for echo rejection — not verified on a physical device in this session, only by build success and code review.
- Fix 2 (provider label): `Sources/Session/VoiceSession.swift` — added `providerLabel` (fetched via `HermesAgentClient.fetchAvailableModels()`, matched against `catalog.activeProvider`), refreshed alongside `modelInfo` on launch and after connect. `Sources/App/RootView.swift` — now shows `"<providerLabel> · <motor> · <modelo>"` when available, falling back to the old 2-piece format.
- Fix 3 (AIsa provider) — backend change on VPS, **outside this git repo**:
  - `/opt/hermes-model-admin/app.py` (service `hermes-model-admin.service`, 127.0.0.1:9120): added `aisa` to `PROVIDER_LABELS` ("AIsa"), `PROVIDER_BASE_URL` (`https://api.aisa.one/v1`, confirmed OpenAI-compatible via `aisa.one/docs`), and a new `_fetch_aisa_models` fetcher hitting `GET /v1/models` with the user-supplied `AISA_API_KEY`.
  - `/docker/hermes-webui-wzbj/docker-compose.yml`: added `AISA_API_KEY: ${AISA_API_KEY:-}` to the `hermes-agent` service's `environment:` block (it was already present in `/home/hermes/.hermes/.env`, hermes's own secrets file, but that file isn't what feeds the container's OS env — `/docker/hermes-webui-wzbj/.env` via `env_file:` is).
  - `/docker/hermes-webui-wzbj/.env`: appended `AISA_API_KEY=<key provided by user in chat>`.
  - Both compose file and app.py backed up (`.bak_<timestamp>`) before editing. Container `hermes-webui-wzbj-hermes-agent-1` recreated with `docker compose up -d --force-recreate hermes-agent`; `hermes-model-admin.service` restarted. Verified via `curl 127.0.0.1:9120/api/models` → `aisa` provider now lists 100 models.
  - Not yet verified: actually switching the active model to an `aisa/*` model end-to-end through `hermes config set` + container restart (the picker lists it, but a live switch+healthcheck round-trip wasn't exercised this session).
- Commands executed:
  - `xcodebuild -project HermesVoice.xcodeproj -scheme HermesVoice -destination 'generic/platform=iOS Simulator' build` — succeeded (twice, after each Swift change)
  - `xcodegen generate`
  - `git commit` + `git push`
  - `./scripts/testflight.sh`
  - VPS: various `ssh root@2.25.189.37` commands to inspect and edit `hermes-model-admin`, `docker-compose.yml`, `.env`; `docker compose up -d --force-recreate hermes-agent`; `systemctl restart hermes-model-admin`
- Result: archive/export/upload all succeeded (`** ARCHIVE SUCCEEDED **`, `** EXPORT SUCCEEDED **`, `Upload succeeded`).
- Status: **`1.8.0` (36) uploaded to App Store Connect/TestFlight; package is processing.** Provider label and AIsa catalog listing are directly verified (curl). Barge-in logic builds cleanly and follows the existing state machine, but was not exercised on a physical device with real audio in this session — recommend a hands-on test of interrupting Hermes mid-sentence by saying "Hermes" before considering this fully verified.

## 2026-07-17 - Fix system mic indicator stuck orange after CarPlay call ends; drop fake hotword text

- App: Hermes Voice
- Platform: iOS native SwiftUI
- Bundle ID: `br.app.egger.HermesVoice`
- Version/build prepared: `1.7.1` / `35`
- Branch: `main`
- Base commit before changes: `cc86064`'s parent (`8fcccb9`)
- User report (with screenshots): on the CarPlay voice screen, while actually listening ("Ouvindo…") the system's top-bar microphone indicator is NOT lit; after ending the call and returning to the root list, it turns orange — backwards from expected. Also asked to replace "Diga 'Ei Hermes'" with "Clique aqui para conversar com o Hermes" since there's no wake-word support.
- Root cause (best-effort, unverified on a physical CarPlay unit — no simulator equivalent for the system mic indicator): `AudioEngineManager.stop()` called `audioEngine.stop()` before `removeTap(onBus:)` (reverse of Apple's recommended teardown order) and never disabled `setVoiceProcessingEnabled`. `VoiceSession.deactivateAudioSession()` swallowed `AVAudioSession.setActive(false)` failures via `try?` — if the Core Audio render thread hadn't finished tearing down yet, `setActive(false)` throws `isBusy` and the session stays active in `.playAndRecord`, which keeps the OS mic indicator lit after the call has ended.
- Fix: `Sources/Audio/AudioEngineManager.swift` — `stop()` now removes the tap before stopping the engine and disables voice processing. `Sources/Session/VoiceSession.swift` — `deactivateAudioSession()` now retries `setActive(false)` once after a short delay if the first attempt throws.
- Fix: `Sources/App/CarPlaySceneDelegate.swift` — replaced all three occurrences of "Diga 'Ei Hermes'" (list item text, idle voice-control title, active/inactive list text) with "Clique aqui para conversar com o Hermes".
- Commands executed:
  - `xcodebuild -project HermesVoice.xcodeproj -scheme HermesVoice -sdk iphonesimulator build` — succeeded
  - `xcodegen generate`
  - `git commit` + `git push`
  - `./scripts/testflight.sh`
- Result: archive/export/upload all succeeded (`** ARCHIVE SUCCEEDED **`, `** EXPORT SUCCEEDED **`, `Upload succeeded`).
- Status: **`1.7.1` (35) uploaded to App Store Connect/TestFlight; package is processing.** Text change is directly verifiable. The mic-indicator fix is a plausible root cause based on code review only — no CarPlay hardware available in this session to confirm the orange indicator now tracks recording state correctly. Needs hands-on verification in an actual CarPlay session.

## 2026-07-17 - Show active provider/model on CarPlay screen

- App: Hermes Voice
- Platform: iOS native SwiftUI
- Bundle ID: `br.app.egger.HermesVoice`
- Version/build prepared: `1.7.0` / `34`
- Branch: `main`
- Base commit before changes: `3eb0e87`
- User request: show the user's speech transcript, Hermes's response, and the active provider/model at the bottom of the CarPlay screen.
- Constraint found: `CarPlaySceneDelegate` uses only native CarPlay templates (`CPListTemplate` root + modal `CPVoiceControlTemplate`), no SwiftUI/custom view hosting. CarPlay's template API has no free-text box — `CPVoiceControlState` only supports a short rotating title + icon per state, and both `CPVoiceControlState`/`CPVoiceControlTemplate` are immutable after init (no way to update a live title). Live transcript/response text is therefore not feasible on CarPlay; user confirmed provider/model in the two fixed slots that do exist.
- Fix (`Sources/App/CarPlaySceneDelegate.swift`): added `modelLabel(from:)` formatting `"<model> · <provider>"` from `VoiceSession.modelInfo`; shown in the root `CPListItem`'s `detailText` (updated live via a new `session.$modelInfo` subscription in `observeSession()`) and appended to the `idle` state's title. Since voice-control states can't be mutated, `voiceControlTemplate` is now rebuilt via `makeVoiceControlTemplate()` right before each `presentTemplate` call (never while on-screen) so the idle title reflects the latest model/provider.
- Commands executed:
  - `xcodebuild -project HermesVoice.xcodeproj -scheme HermesVoice -sdk iphonesimulator build CODE_SIGNING_ALLOWED=NO` — succeeded
  - `git commit` + `git push` (CarPlay feature, then version bump)
  - `xcodegen generate`
  - `git commit` + `git push` (regenerated project + version bump)
  - `./scripts/testflight.sh`
- Result: archive/export/upload all succeeded (`** ARCHIVE SUCCEEDED **`, `** EXPORT SUCCEEDED **`, `Upload succeeded`).
- Status: **`1.7.0` (34) uploaded to App Store Connect/TestFlight; package is processing.** Still needs hands-on verification in an actual CarPlay session that the model/provider label appears correctly in both the root list and the idle voice-control title.

## 2026-07-17 - Fix CarPlay voice-control X button and stuck "call" indicator

- App: Hermes Voice
- Platform: iOS native SwiftUI
- Bundle ID: `br.app.egger.HermesVoice`
- Version/build prepared: `1.6.2` / `33`
- Branch: `main`
- Base commit before changes: `7ba74c2`
- User report (with screenshots): on the CarPlay "Ouvindo…" voice screen, the X button in the top-left does nothing at all when tapped. The back/chevron button next to it does end the Hermes session, but afterward the CarPlay clock/status area turns orange as if an "active call" were in progress (it isn't a real call).
- Root cause: `CPVoiceControlTemplate` is a modal template — per Apple's own guidance it must be shown/closed via `presentTemplate`/`dismissTemplate`, never `pushTemplate`/`popToRootTemplate`. `Sources/App/CarPlaySceneDelegate.swift` was pushing it onto the root `CPListTemplate`'s navigation stack instead. The X is the template's own system-provided modal close control, which only wires up correctly when the template goes through the present/dismiss flow — pushed instead, it had no action bound to it (no-op). The back chevron came from the (incorrect) push/pop navigation and did call `session.endCall()`, but because the template never went through its expected present/dismiss lifecycle, CarPlay's own "voice session" chrome wasn't torn down cleanly, leaving the orange indicator stuck.
- Fix (`Sources/App/CarPlaySceneDelegate.swift`): `presentVoiceControl()` now calls `interfaceController?.presentTemplate(voiceControlTemplate, ...)` instead of `pushTemplate`; `popToRootIfNeeded()` now calls `interfaceController?.dismissTemplate(...)` instead of `popToRootTemplate`. `templateDidDisappear` delegate callback (which fires for both push/pop and present/dismiss) still drives `session.endCall()`, so state stays in sync either way.
- Commands executed:
  - `xcodebuild -scheme HermesVoice -destination 'generic/platform=iOS' build` — succeeded
  - `git commit` + `git push` (CarPlay fix, then version bump)
  - `xcodegen generate`
  - `git commit` + `git push` (regenerated project + version bump)
  - `./scripts/testflight.sh`
- Result: archive/export/upload all succeeded (`** ARCHIVE SUCCEEDED **`, `** EXPORT SUCCEEDED **`, `Upload succeeded`).
- Status: **`1.6.2` (33) uploaded to App Store Connect/TestFlight; package is processing.** Still needs hands-on verification in an actual CarPlay session (real or simulator) that tapping the X now properly ends the session and that the orange "call" indicator no longer appears/sticks after ending via either button.

## 2026-07-17 - Larger transcript area on main screen

- App: Hermes Voice
- Platform: iOS native SwiftUI
- Bundle ID: `br.app.egger.HermesVoice`
- Version/build prepared: `1.6.1` / `32`
- Branch: `main`
- Base commit before changes: `a6df99c`
- User report (App Store feedback, build 1.6.0/31): "Aumenta o espaço do tamanho da transcrição da minha fala e da fala do Hermes."
- Fix (`Sources/App/RootView.swift`): user-speech transcript and Hermes-response text bumped from `.body` to `.title3`; both boxes now scroll with taller max heights (220pt / 260pt) instead of clipping; the whole screen content wrapped in a `ScrollView` so the larger text never gets cut off on smaller devices.
- Commands executed:
  - `xcodebuild ... -destination 'generic/platform=iOS Simulator' -configuration Debug build` — succeeded
  - `git commit` + `git push` (UI fix, then version bump)
  - `./scripts/testflight.sh`
  - `python3 ~/.claude/skills/ildemar_project-handoff-docs/scripts/update_handoff_docs.py .`
- Result: archive/export/upload all succeeded (`** ARCHIVE SUCCEEDED **`, `** EXPORT SUCCEEDED **`, `Upload succeeded`).
- Status: **`1.6.1` (32) uploaded to App Store Connect/TestFlight; package is processing.** Still needs hands-on verification that the larger transcript text looks right and doesn't crowd out the call/mute buttons on a real device.

## 2026-07-17 - Remove CallKit; CarPlay voice-control UI matching Jarvis

- App: Hermes Voice
- Platform: iOS native SwiftUI
- Bundle ID: `br.app.egger.HermesVoice`
- Version/build prepared: `1.6.0` / `31`
- Branch: `main`
- Base commit before changes: `c95bee1`
- User report: the CarPlay screen looked different from the sibling app Jarvis (which works fine and is not a simulated phone call), and starting a conversation showed a phone-call banner in CarPlay's now-playing/media UI. User confirmed Jarvis never needs the phone screen open to keep working.
- Root cause: Hermes deliberately used CallKit (`CXProvider`/`CXCallController` in `Sources/Call/CallManager.swift`) to model the conversation as a VoIP call — that's exactly what made it show up as a phone call on lock screen/CarPlay media. Jarvis never used CallKit; it activates `AVAudioSession` directly (`.playAndRecord`/`.spokenAudio`) and stays alive in the background purely via `UIBackgroundModes: [audio]`.
- Fix:
  - Deleted `Sources/Call/CallManager.swift`. `VoiceSession.startCall()/endCall()` now call `AVAudioSession.sharedInstance().setCategory(.playAndRecord, mode: .voiceChat, ...)`/`setActive(...)` directly; `toggleMute()` just stops/starts the recognizer instead of a `CXSetMutedCallAction`.
  - `project.yml`: `UIBackgroundModes` changed from `[audio, voip]` to `[audio]`.
  - `Sources/App/CarPlaySceneDelegate.swift` rewritten to use `CPVoiceControlTemplate` (idle/listening/processing/speaking/error states with animated icons), pushed on top of the root `CPListTemplate`, mirroring Jarvis's `CarPlaySceneDelegate` exactly. Previously it only used a plain `CPListTemplate` with static list-item text.
  - Cleaned up stale CallKit/VoIP references in comments (`RootView.swift`, `SpeechSynthesizer.swift`, `SpeechRecognizer.swift`, `StartHermesCallIntent.swift`).
- Commands executed:
  - `xcodegen generate`
  - `xcodebuild -project HermesVoice.xcodeproj -scheme HermesVoice -destination 'generic/platform=iOS' -configuration Debug build CODE_SIGNING_ALLOWED=NO` — succeeded, both before and after the CallKit removal.
  - `git commit` + `git push`
  - `./scripts/testflight.sh`
  - `python3 ~/.claude/skills/ildemar_project-handoff-docs/scripts/update_handoff_docs.py .`
- Result: archive/export/upload all succeeded (`** ARCHIVE SUCCEEDED **`, `** EXPORT SUCCEEDED **`, `Upload succeeded`).
- Status: **`1.6.0` (31) uploaded to App Store Connect/TestFlight; package is processing.** Still needs hands-on verification in CarPlay (or CarPlay simulator) that no call banner appears, and that the app still works with the iPhone locked (no CallKit safety net anymore — background survival now depends solely on the active `AVAudioSession` + `UIBackgroundModes: [audio]`, same mechanism as Jarvis).

## 2026-07-17 - Fix CarPlay tap doing nothing

- App: Hermes Voice
- Platform: iOS native SwiftUI
- Bundle ID: `br.app.egger.HermesVoice`
- Version/build prepared: `1.4.1` / `28`
- Branch: `main`
- Base commit before changes: `683dad1`
- Root cause: after the CarPlay app scene shipped in `1.4.0`/build 27, the icon appeared on CarPlay and connected, but tapping the list item did nothing. `CarPlaySceneDelegate` only posted a `.hermesCarPlayActivate` notification; the only listener was `RootView`'s `.onReceive`, which only exists once the iPhone's own SwiftUI scene has been created. When CarPlay connects without the app having been opened on the phone first, `RootView` never exists, so nothing was listening and the tap was a silent no-op.
- Fix: `Sources/App/CarPlaySceneDelegate.swift` now calls `VoiceSession.shared.startCall()/endCall()` directly instead of posting a notification, and subscribes (Combine) to `VoiceSession`'s `$isCallActive`/`$sessionState`/`$errorMessage` publishers to keep the CarPlay list item's text/detail in sync with the real conversation state (listening/processing/speaking) and to surface errors via `CPAlertTemplate`. Removed the now-dead `.hermesCarPlayActivate` notification and its `RootView` listener.
- Commands executed:
  - `xcodegen generate`
  - `xcodebuild -project HermesVoice.xcodeproj -scheme HermesVoice -destination 'generic/platform=iOS' -configuration Debug build`
  - `git commit` + `git push` (commits `3397257`, `3f4b524`)
  - `./scripts/testflight.sh`
  - `python3 ~/.claude/skills/ildemar_project-handoff-docs/scripts/update_handoff_docs.py .`
- Result: device build succeeded; archive/export/upload all succeeded (`** ARCHIVE SUCCEEDED **`, `** EXPORT SUCCEEDED **`, `Upload succeeded`).
- Status: **`1.4.1` (28) uploaded to App Store Connect/TestFlight; package is processing.** Still needs to be verified hands-on in a car (or CarPlay simulator) to confirm the tap now actually starts the Hermes conversation end-to-end.

## 2026-07-17 - Native CarPlay App Scene

- App: Hermes Voice
- Platform: iOS native SwiftUI
- Bundle ID: `br.app.egger.HermesVoice`
- Version/build prepared: `1.4.0` / `27`
- Branch: `main`
- Base commit before changes: `c5ac27f`
- Change: added `Sources/App/CarPlaySceneDelegate.swift` (`CPTemplateApplicationSceneDelegate`, `CPListTemplate`) and registered it in `project.yml`'s `UIApplicationSceneManifest`, following the same pattern already shipped in the local Jarvis app. Added `com.apple.developer.carplay-voice-based-conversation` to `Sources/HermesVoice.entitlements` via `project.yml` entitlements properties, now that Apple approved this entitlement. Tapping the CarPlay list item posts `.hermesCarPlayActivate`, observed by `RootView` to call `session.startCall()`.
- Commands executed:
  - `xcodegen generate`
  - `git commit` + `git push` (commit `e1761c0b`)
  - `xcodebuild -project HermesVoice.xcodeproj -scheme HermesVoice -destination 'generic/platform=iOS Simulator' build`
  - `python3 ~/.codex/skills/project-handoff-docs/scripts/update_handoff_docs.py .`
- Result: simulator build succeeded with the new `CarPlaySceneDelegate` compiled into the app target.
- `./scripts/testflight.sh` attempted next; **archive for device failed**:
  - `error: Provisioning profile "iOS Team Provisioning Profile: br.app.egger.HermesVoice" doesn't include the CarPlay Voice Based Conversation capability. CarPlay Voice Based Conversation capability needs to be assigned to your team and bundle identifier by Apple in order to be included in a profile.`
  - `error: Entitlement com.apple.developer.carplay-voice-based-conversation requires approval from Apple to include in a profile. Please request access to the associated capability.`
- Root cause: the CarPlay Voice Based Conversation capability was **not yet enabled for the `br.app.egger.HermesVoice` App ID** in the Apple Developer portal at that point, even though the same capability was already approved for the separate Jarvis App ID. Apple grants this entitlement per App ID, not per team.
- Resolution: Ildemar enabled "CarPlay Voice Based Conversation" for the `br.app.egger.HermesVoice` App ID in the Apple Developer portal (Certificates, Identifiers & Profiles → Identifiers). The local `xcodebuild archive` step still failed once more with `No Accounts: Add a new account in Accounts settings` because no Xcode account was signed in on this machine and the archive step wasn't passing the App Store Connect API key for automatic provisioning updates.
- Fix: updated `scripts/testflight.sh` to also pass `-authenticationKeyPath/-authenticationKeyID/-authenticationKeyIssuerID` (the same ASC API key already used for export/upload) to the `xcodebuild archive` step, so automatic signing can refresh the provisioning profile without a signed-in Xcode account.
- Re-run after the fix: `./scripts/testflight.sh` succeeded end-to-end — `** ARCHIVE SUCCEEDED **` (new profile picked up the CarPlay capability), export `** EXPORT SUCCEEDED **`, upload result `Upload succeeded`.
- Status: **`1.4.0` (27), commit `f016032`, uploaded to App Store Connect/TestFlight; package is processing.**

## 2026-07-13 - TestFlight Release With Widget

- App: Hermes Voice
- Platform: iOS native SwiftUI
- Bundle ID: `br.app.egger.HermesVoice`
- Widget Bundle ID: `br.app.egger.HermesVoice.widgets`
- Version/build prepared: `1.3.0` / `26`
- Branch: `main`
- Base commit before changes: `2e4d00ad`
- Status: uploaded to App Store Connect/TestFlight; package is processing.
- Commands executed:
  - `xcodegen generate`
  - `xcodebuild -project HermesVoice.xcodeproj -scheme HermesVoice -destination 'generic/platform=iOS Simulator' build`
  - `python3 ~/.codex/skills/project-handoff-docs/scripts/update_handoff_docs.py .`
- Result: simulator build succeeded with app target plus embedded `HermesVoiceWidgets.appex`.
- Archive result: succeeded. Final archive path: `~/Library/Developer/Xcode/Archives/2026-07-13/HermesVoice 1.3.0 (26)-ascbundle.xcarchive`.
- Archive commit injected: `3cbeead0`.
- App Store Connect correction: app record exists with bundle ID `br.app.egger.HermesVoice`; project bundle ID was aligned to match exact casing before final upload.
- Upload command: `xcodebuild -exportArchive ... -authenticationKeyPath ... -authenticationKeyID ... -authenticationKeyIssuerID ...`
- Upload result: `Uploaded HermesVoice` / `EXPORT SUCCEEDED`.
- Notes: CarPlay continues through CallKit as a system-call interface. WidgetKit/Live Activity added for iPhone/Dynamic Island while entitlement for a true CarPlay app/widget is pending.
- Upload status: uploaded successfully; App Store Connect reported the package is processing.
