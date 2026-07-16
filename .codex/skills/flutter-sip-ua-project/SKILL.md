---
name: flutter-sip-ua-project
description: Use this skill when working in the flutter_sip_ua repository to get a compact project map, key files, architecture boundaries, and editing guidance for SIP core, media, Riverpod state, and Flutter UI work without re-reading the whole codebase.
metadata:
  short-description: Project context for flutter_sip_ua
---

# Flutter SIP UA Project

Use this skill for any development task in this repository unless the task is fully isolated and already names the exact file to change.

## Quick Map

- Flutter app entry: `lib/main.dart`
- App state + UA ownership: `lib/providers/sip_providers.dart`
- SIP signalling core: `lib/sip/sip_user_agent.dart`
- Transport abstraction: `lib/sip/transport.dart`
- Audio / RTP / RTCP: `lib/sip/audio/`
- Video helpers: `lib/sip/video/`
- Home shell: `lib/ui/home_page.dart`
- Login flow: `lib/ui/login_page.dart`
- Call screen: `lib/ui/call_page.dart`
- Widget modules: `lib/ui/widgets/`
- Tests: `test/`

## How To Use This Context

1. Start from the layer closest to the requested change.
2. Read `references/architecture.md` for the durable project map and common edit paths.
3. Only open deeper files after choosing the relevant layer.

## Fast Routing

- SIP registration, INVITE, MESSAGE, auth, timers: start in `lib/sip/sip_user_agent.dart`
- WS/WSS, UDP, TCP, TLS transport work: start in `lib/sip/transport.dart`
- RTP, DTMF, microphone capture, jitter, RTCP: start in `lib/sip/audio/media_session.dart`
- Persisted account, providers, app lifecycle: start in `lib/providers/sip_providers.dart`
- Navigation, login restore, dialer, call-route behavior: start in `lib/ui/home_page.dart`
- In-call UI actions and state: start in `lib/ui/call_page.dart`
- Theme and visual system: start in `lib/ui/theme.dart` and `lib/ui/bp_palette.dart`
- Protocol or codec regressions: inspect matching tests under `test/` before editing

## Repo Guardrails

- Treat existing uncommitted platform/setup files as user-owned unless the task explicitly targets them.
- Prefer changing the narrowest layer possible:
  - UI-only behavior: keep changes out of `lib/sip/`
  - Provider/state wiring: prefer `lib/providers/` before touching UI widgets
  - Protocol/media behavior: prefer `lib/sip/` before adding UI workarounds
- Preserve cross-platform conditional imports and web/native boundaries.
- When adding behavior, check whether a focused test already exists in `test/` and extend it before adding broad widget coverage.
