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
- `./scripts/testflight.sh` attempted next; **archive for device failed**:
  - `error: Provisioning profile "iOS Team Provisioning Profile: br.app.egger.HermesVoice" doesn't include the CarPlay Voice Based Conversation capability. CarPlay Voice Based Conversation capability needs to be assigned to your team and bundle identifier by Apple in order to be included in a profile.`
  - `error: Entitlement com.apple.developer.carplay-voice-based-conversation requires approval from Apple to include in a profile. Please request access to the associated capability.`
- Root cause: the CarPlay Voice Based Conversation capability is **not yet enabled for the `br.app.egger.HermesVoice` App ID** in the Apple Developer portal, even though the same capability was requested/approved for the separate Jarvis App ID. Apple grants this entitlement per App ID, not per team.
- Status: **blocked on Apple Developer portal action.** Code, entitlements file and `project.yml` are committed and pushed (commit `889d323`), and the CarPlay scene compiles for the simulator, but no distributable archive/TestFlight build exists yet for `1.4.0` (27).
- Next action required (external, needs Ildemar's Apple Developer account): open developer.apple.com → Certificates, Identifiers & Profiles → Identifiers → `br.app.egger.HermesVoice`, enable "CarPlay Voice Based Conversation" (request it if not already available for this App ID, same as was done for Jarvis), regenerate/download the provisioning profile (or let Xcode automatic signing refresh it), then re-run `./scripts/testflight.sh`.

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
