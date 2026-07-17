# Release Log

Generated: 2026-07-13T17:21:45-03:00

Record every deploy, TestFlight/App Store upload, web publish and external processing status here.

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
- Status: not yet uploaded to TestFlight — this turn only validated the local build. Run `scripts/testflight.sh` to ship `1.4.0` (27), then validate the CarPlay scene with CarPlay Simulator or a physical head unit connected to the same iPhone the build is installed on.

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
