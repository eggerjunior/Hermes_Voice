# Release Log

Generated: 2026-07-13T17:21:45-03:00

Record every deploy, TestFlight/App Store upload, web publish and external processing status here.

## 2026-07-13 - TestFlight Release With Widget

- App: Hermes Voice
- Platform: iOS native SwiftUI
- Bundle ID: `br.app.egger.hermesvoice`
- Widget Bundle ID: `br.app.egger.hermesvoice.widgets`
- Version/build prepared: `1.3.0` / `26`
- Branch: `main`
- Base commit before changes: `2e4d00ad`
- Status: archive succeeded; TestFlight upload blocked by missing App Store Connect app record.
- Commands executed:
  - `xcodegen generate`
  - `xcodebuild -project HermesVoice.xcodeproj -scheme HermesVoice -destination 'generic/platform=iOS Simulator' build`
  - `python3 ~/.codex/skills/project-handoff-docs/scripts/update_handoff_docs.py .`
- Result: simulator build succeeded with app target plus embedded `HermesVoiceWidgets.appex`.
- Archive result: succeeded. Archive path: `~/Library/Developer/Xcode/Archives/2026-07-13/HermesVoice 1.3.0 (26).xcarchive`.
- Archive commit injected: `dfe95881`.
- App Store Connect check: Bundle ID exists as `32VX2LCV28`, but no app record exists for `br.app.egger.hermesvoice`.
- Blocker: App Store Connect API returned `The resource 'apps' does not allow 'CREATE'. Allowed operations are: GET_COLLECTION, GET_INSTANCE, UPDATE`.
- Required next action: create the App Store Connect app record manually or provide an API key/account permission that can create apps, then rerun `./scripts/testflight.sh`.
- Notes: CarPlay continues through CallKit as a system-call interface. WidgetKit/Live Activity added for iPhone/Dynamic Island while entitlement for a true CarPlay app/widget is pending.
- Upload status: not uploaded because export/upload cannot fetch app information until the app record exists.
