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
- Status: release prepared for TestFlight upload.
- Commands executed:
  - `xcodegen generate`
  - `xcodebuild -project HermesVoice.xcodeproj -scheme HermesVoice -destination 'generic/platform=iOS Simulator' build`
  - `python3 ~/.codex/skills/project-handoff-docs/scripts/update_handoff_docs.py .`
- Result: simulator build succeeded with app target plus embedded `HermesVoiceWidgets.appex`.
- Notes: CarPlay continues through CallKit as a system-call interface. WidgetKit/Live Activity added for iPhone/Dynamic Island while entitlement for a true CarPlay app/widget is pending.
- Upload status: pending at commit time; final App Store Connect status reported after `scripts/testflight.sh`.
