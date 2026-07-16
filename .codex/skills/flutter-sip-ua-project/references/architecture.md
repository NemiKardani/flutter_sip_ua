# flutter_sip_ua Architecture

## Purpose

`flutter_sip_ua` is a Flutter client plus a pure-Dart SIP stack. The repo is split into app/UI code and reusable protocol/media code.

## Stable Entry Points

- `lib/main.dart`
  - Loads `SharedPreferences` before `runApp`.
  - Injects prefs into Riverpod through `sharedPreferencesProvider`.
- `lib/providers/sip_providers.dart`
  - Owns the `SipUserAgent` and `SipFileLogger`.
  - Exposes registration, calls, messages, logs, buddies, selected buddy, unread state, and theme/account persistence.

## Layer Boundaries

### App / UI

- `lib/ui/home_page.dart`
  - Restores persisted account.
  - Starts the UA.
  - Pushes call UI on call events.
  - Hosts sidebar, stream view, dialer, and log overlays.
- `lib/ui/login_page.dart`
  - Builds `SipAccount` from form input.
  - Validates supported URI schemes: `ws`, `wss`, `sip`, `sips`.
- `lib/ui/call_page.dart`
  - In-call UI orchestration only.
  - Subscribes to call updates from the UA.
  - Delegates actual SIP actions to `SipUserAgent`.

### SIP Core

- `lib/sip/sip_user_agent.dart`
  - Main signalling orchestrator.
  - Handles REGISTER, MESSAGE, INVITE, CANCEL, BYE, digest auth, session timers, and call state emission.
  - Selects transport from account URI.
  - Creates `MediaSession` and optional video session objects.
- `lib/sip/transport.dart`
  - Transport interface shared by WS/WSS, UDP, TCP, and TLS-backed SIP transport implementations.
  - SIP URI parsing helpers matter for authority-less URIs like `sip:host:5060;transport=tcp`.
- `lib/sip/sip_message.dart`
  - Message parse/encode layer used by transports and UA.
- `lib/sip/sdp.dart`
  - Builds and parses SDP offers/answers for current audio/video support.

### Media

- `lib/sip/audio/media_session.dart`
  - RTP/RTCP sockets.
  - Microphone capture through `record`.
  - G.711 encode/decode.
  - Jitter buffering, DTMF, RTP statistics, packet taps.
- `lib/sip/audio/pcm_audio_sink.dart`
  - Current audio sink implementation used by the app.
- `lib/sip/video/`
  - Early video/session helpers and codec pieces; narrower than audio path today.

## Common Change Paths

### Registration or account issues

Read in this order:

1. `lib/ui/login_page.dart`
2. `lib/providers/sip_providers.dart`
3. `lib/sip/sip_user_agent.dart`
4. `lib/sip/transport.dart`

### Call setup or hangup issues

Read in this order:

1. `lib/ui/home_page.dart`
2. `lib/ui/call_page.dart`
3. `lib/sip/sip_user_agent.dart`
4. `lib/sip/sdp.dart`
5. `lib/sip/audio/media_session.dart`

### Audio quality or RTP issues

Read in this order:

1. `lib/sip/audio/media_session.dart`
2. `lib/sip/audio/jitter_buffer.dart`
3. `lib/sip/audio/rtp.dart`
4. `lib/sip/audio/rtcp.dart`
5. matching tests under `test/`

### UI state issues

Read in this order:

1. widget under `lib/ui/widgets/`
2. `lib/ui/home_page.dart` or `lib/ui/call_page.dart`
3. `lib/providers/sip_providers.dart`

## Test Map

- `test/digest_test.dart`: digest auth behavior
- `test/sip_message_test.dart`: SIP parse/encode behavior
- `test/sdp_test.dart`, `test/sdp_video_test.dart`: SDP generation/parsing
- `test/rtp_test.dart`, `test/rtcp_test.dart`, `test/rtp_stats_test.dart`: RTP/RTCP/stats
- `test/g711_test.dart`: codec behavior
- `test/jitter_buffer_test.dart`: playout buffering
- `test/vp8_rtp_test.dart`: video RTP helpers
- `test/widget_test.dart`, `test/dial_pad_test.dart`, `test/status_chip_test.dart`: UI/widget coverage

## Current Practical Assumptions

- The app persists a single SIP account locally.
- Riverpod is the source of truth for UI-facing state.
- `SipUserAgent` is the source of truth for protocol and call lifecycle behavior.
- Pure Dart is a core design goal; avoid introducing WebRTC/libwebrtc-style dependencies unless explicitly requested.
