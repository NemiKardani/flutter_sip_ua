# VoIP Reference

## Scope

This reference is a compact field guide for diagnosing and designing call systems across common VoIP protocols and frameworks.

## Protocol Layers

### Signalling

- SIP
  - Registration, dialogs, transactions, methods like `REGISTER`, `INVITE`, `ACK`, `BYE`, `CANCEL`, `MESSAGE`, `OPTIONS`, `REFER`, `UPDATE`, `INFO`.
  - Common failure areas: auth, route sets, contact/via issues, wrong CSeq handling, timer behavior, bad dialog matching.
- WebRTC signalling
  - The signalling channel itself is application-defined, but SDP semantics, ICE candidates, and negotiation timing are the usual pain points.
- Legacy or gateway scenarios
  - H.323, MGCP, SCCP, and ISDN/PSTN interworking may surface as normalization or capability mismatches at the edge, even if the client only speaks SIP.

### Session Description

- SDP controls media intent.
- Validate:
  - `m=` ports and payload type list
  - `c=` address reachability
  - `a=sendrecv`, `sendonly`, `recvonly`, `inactive`
  - codec intersection
  - DTMF payload types and fmtp
  - RTCP port advertisement
  - hold semantics and version bumps on re-INVITE or UPDATE

### Media

- RTP carries media frames.
- RTCP carries reports, quality signals, and sender/receiver statistics.
- Typical failures:
  - one-way audio
  - dead air with successful call setup
  - payload type mismatch
  - clock-rate mismatch
  - sequence/timestamp bugs
  - jitter buffer starvation or overflow
  - DTMF event framing issues

## Transport and Traversal

### SIP transports

- UDP
  - Common for classic SIP. Watch retransmits, MTU, fragmentation, and NAT mappings.
- TCP
  - Better for large messages and persistent connections. Watch framing and connection reuse behavior.
- TLS
  - Adds certificate and trust concerns plus server-name matching.
- WebSocket/WSS
  - Common for browser and app stacks bridging into SIP infrastructure.

### NAT traversal

- Classic SIP/RTP
  - Watch private IP leakage in SDP, wrong advertised contact, stale NAT bindings, and remote RTP learned from the wrong endpoint.
- Symmetric RTP
  - Often needed when the peer sends from a different port than it advertised or when middleboxes rewrite paths.
- WebRTC NAT traversal
  - ICE, STUN, TURN, and relay policy dominate outcomes.

## Framework Families

### Pure SIP stacks

Examples:

- custom SIP/RTP implementations
- JsSIP-style signalling stacks without built-in native media
- server-side SIP libraries

Good when:

- you want direct protocol control
- you need small footprint or strong debuggability
- you can own codec, RTP, and NAT behavior

Risks:

- more media and interop work
- NAT and device behavior are your responsibility

### WebRTC-based telephony stacks

Examples:

- SIP over WebSocket plus WebRTC media
- `flutter_webrtc`-style mobile/desktop apps
- browser softphones

Good when:

- you want mature A/V, echo cancellation, device handling, and NAT traversal

Risks:

- larger binary/runtime complexity
- opaque engine behavior
- signalling-to-WebRTC impedance mismatches

### PBXs and SBCs

Examples:

- Asterisk
- FreeSWITCH
- Kamailio
- OpenSIPS
- commercial SBCs and gateways

Common concerns:

- topology hiding
- header normalization
- registration/contact rewriting
- early media behavior
- transfer and bridge features
- RTP proxying or anchoring

## Feature Checklists

### Registration

- transport connected
- correct realm and nonce handling
- contact and expires sane
- refresh timing safe
- OPTIONS or keep-alive policy understood

### Basic call setup

- INVITE well formed
- provisional responses handled
- 200/ACK completes properly
- CANCEL path works before answer
- BYE path works after answer

### Hold and resume

- SDP direction attributes correct
- re-INVITE or UPDATE handling consistent
- media path paused/resumed correctly

### DTMF

- RTP events use correct payload type and duration handling
- SIP INFO interop only if explicitly supported

### Transfers and advanced features

- REFER, replaces, attended vs blind transfer semantics
- session timers and route sets preserved across target changes

## Debugging Heuristics

- If signalling succeeds but audio fails, inspect SDP and RTP path before touching UI logic.
- If only one platform fails, inspect permissions, transport implementation, socket behavior, and app lifecycle.
- If only one server fails, inspect interop assumptions, normalization, auth, and timers.
- If re-INVITE or hold breaks the call, inspect SDP versioning, directionality, media restarts, and dialog state transitions.
- If web works but native fails, compare transport and media stack differences instead of assuming shared behavior.
- If native works but web fails, expect browser/WebRTC restrictions or lack of raw UDP media support.

## Applying This To flutter_sip_ua

This repository is a pure-Dart SIP/RTP client, not a WebRTC-first client.

That means:

- SIP transport, SDP, and RTP details are first-class and usually worth inspecting directly.
- Media bugs are likely in socket, codec, timing, SDP, or NAT assumptions rather than browser engine behavior.
- Avoid solving protocol issues in Riverpod or widget code unless the actual bug is state propagation.
