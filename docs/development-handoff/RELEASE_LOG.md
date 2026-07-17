# Release Log

Generated: 2026-07-13T17:21:45-03:00

Record every deploy, TestFlight/App Store upload, web publish and external processing status here.

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
