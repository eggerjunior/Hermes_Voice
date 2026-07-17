# Project Context

Generated: 2026-07-17T18:48:12-03:00

## Snapshot

- Project: `Hermes_Voice`
- Root: `/Users/ildemareggerjunior/Projects/Hermes_Voice`
- Branch: `main`
- Commit: `c95bee13`
- Git status: dirty
- Version: `1.6.0`
- Build: `31`
- Bundle/package id: `br.app.egger.HermesVoice`
- Detected stack: ios_xcodegen

## Product Purpose

TODO: Describe what this app does, who uses it, and the core user outcome.

## Current User-Facing Features

TODO: List implemented features and important flows.

## Architecture

TODO: Explain modules, app layers, data flow, and boundaries.

## Important Files

- `HANDOFF.md`
- `README.md`
- `project.yml`
- `scripts/create_app.py`
- `scripts/testflight.sh`


## Data Model And Storage

TODO: Document local storage, databases, sync model, migrations and backup/import format.

## Integrations And External Services

TODO: Document APIs, cloud services, app store services, auth requirements and non-secret identifiers.

## Versioning And Release Rules

Detected version/build fields:

```json
{
  "version": "1.6.0",
  "build": "31",
  "git_commit_fallback": "dev",
  "bundle_id": "br.app.egger.HermesVoice",
  "development_team": "E743636TCJ"
}
```

TODO: Record the exact release checklist used by this project.

## Local Development

TODO: Add setup, run, test and build commands.

## Testing And Validation

TODO: List validation commands and the last known results.

## Recent Decisions

- **CallKit removed (v1.6.0/build 31):** the app no longer registers the conversation as a VoIP call (`CXProvider`/`CXCallController`, previously in `Sources/Call/CallManager.swift`, now deleted). `VoiceSession.startCall()/endCall()` activate `AVAudioSession` directly (`.playAndRecord`/`.voiceChat`, `.defaultToSpeaker`), matching the approach already used by the sibling app Jarvis (`~/Projects/Jarvis@apvictorio`). Reason: CallKit made the conversation show up as a phone call on the lock screen and in CarPlay's now-playing/media UI, which the user didn't want. `UIBackgroundModes` dropped `voip`, kept only `audio` — an active audio session with that background mode is what keeps the app alive with the phone locked (confirmed working this way in Jarvis), not CallKit.
- **CarPlay screen now uses `CPVoiceControlTemplate`** (`Sources/App/CarPlaySceneDelegate.swift`) instead of a plain `CPListTemplate` with static text — same native voice-assistant UI component Jarvis uses, with animated idle/listening/processing/speaking/error states driven by `VoiceSession`'s published state via Combine.

## Known Risks And Pending Work

TODO: List blockers, external processing, known bugs and next steps.

## Import Notes For Other Tools

Read `IMPORT_MANIFEST.json` first, then this file, then key files listed above. Never load secret files.
