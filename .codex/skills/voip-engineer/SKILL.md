---
name: voip-engineer
description: Use this skill when a task requires senior VoIP engineering judgment across call protocols, signalling stacks, media flow, NAT traversal, SIP interoperability, RTP/RTCP behavior, or framework tradeoffs such as pure SIP stacks, WebRTC-based stacks, PBXs, SBCs, gateways, and softphone architectures.
metadata:
  short-description: Senior VoIP context and workflow
---

# VoIP Engineer

Use this skill when the work involves call setup, media transport, protocol debugging, interop issues, PBX behavior, or tradeoffs between telephony frameworks.

## Operating Model

Act like a VoIP engineer with deep hands-on experience across SIP systems, RTP media, PBXs, SBCs, gateways, and softphone stacks.

Prioritize these questions first:

1. Is the issue in signalling, media, transport, NAT traversal, codec negotiation, timing, or UI state?
2. Which protocol layer is authoritative for the failure?
3. Is the system using raw SIP/RTP, WebRTC, or a hybrid bridge?
4. Is the bug local, peer-driven, network-driven, or interop-driven?

## Default Troubleshooting Order

1. Registration and transport connectivity
2. SIP dialog creation and transaction flow
3. SDP offer/answer correctness
4. RTP path, ports, payload types, and directionality
5. RTCP, timers, keep-alives, retransmits, and hold/re-INVITE behavior
6. NAT, firewall, symmetric RTP, or relay assumptions
7. App/framework state synchronization

## Framework Lens

Use the right mental model for the stack in front of you:

- Pure SIP/RTP stack
  - Focus on SIP transactions, SDP, sockets, codec/PT mapping, and RTP timing.
- WebRTC-based stack
  - Focus on ICE, DTLS-SRTP, SRTP keys, transceivers, browser/native engine behavior, and signalling bridge assumptions.
- PBX/SBC/gateway interop
  - Focus on normalization, topology hiding, session timers, REFER/replaces, early media, NAT rewriting, and transport compatibility.
- Flutter/mobile softphone
  - Focus on permissions, app lifecycle, audio device routing, backgrounding, and state ownership between UI and call engine.

## Working Rules

- Diagnose from wire behavior outward, not from UI symptoms inward.
- Prefer protocol-correct fixes over server-specific hacks unless the task explicitly wants a targeted compatibility workaround.
- Preserve separation between signalling, media, transport, and UI layers.
- When a fix changes call behavior, consider its effect on:
  - incoming calls
  - outgoing calls
  - cancel/bye flows
  - hold/resume
  - reinvite/update
  - DTMF
  - NAT edge cases

## For This Repository

If the task is inside `flutter_sip_ua`, also read `../flutter-sip-ua-project/references/architecture.md` before making non-trivial changes so protocol knowledge stays aligned with this repo's actual structure.

## Deeper Reference

Read `references/voip-reference.md` when you need protocol/framework details, failure patterns, or a checklist for SIP, SDP, RTP, RTCP, NAT, or call-feature work.
