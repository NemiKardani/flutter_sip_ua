import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/sip_providers.dart';
import '../sip/sip_user_agent.dart';
import 'bp_palette.dart';
import 'widgets/call/call_action_panels.dart';
import 'widgets/call/call_backdrop.dart';
import 'widgets/call/call_party_card.dart';
import 'widgets/call/call_stats_panel.dart';
import 'widgets/call/call_top_bar.dart';
import 'widgets/call/transfer_sheet.dart';
import 'widgets/dial_pad.dart';

/// Full-screen call surface that orchestrates the modular call widgets.
///
/// Responsibilities kept here:
///   * Subscribe to UA call updates and own derived state (timer,
///     mute/hold/speaker/record/keypad/stats toggles, DTMF history).
///   * Pick which action panel to render given [SipCall.state].
///   * Wire individual button handlers to the SIP user agent.
class CallPage extends ConsumerStatefulWidget {
  const CallPage({super.key, required this.callId});
  final String callId;

  @override
  ConsumerState<CallPage> createState() => _CallPageState();
}

class _CallPageState extends ConsumerState<CallPage>
    with SingleTickerProviderStateMixin {
  StreamSubscription<SipCall>? _sub;
  SipCall? _call;
  Timer? _ticker;
  Duration _elapsed = Duration.zero;
  DateTime? _activeSince;

  // UI-only toggles (Record / Add-call have user-facing fallbacks since the
  // UA does not yet implement recording/conference control).
  bool _muted = false;
  bool _speaker = false;
  bool _showKeypad = false;
  bool _recording = false;
  bool _showStats = false;
  String _dtmfHistory = '';

  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1500),
  )..repeat(reverse: true);

  SipUserAgent get _ua => ref.read(sipUserAgentProvider);

  @override
  void initState() {
    super.initState();
    final initial = _ua.callById(widget.callId);
    if (initial != null) {
      _call = initial;
      _muted = _ua.isMuted(widget.callId) ?? false;
      if (initial.state == CallState.active) {
        _activeSince = initial.startedAt ?? DateTime.now();
        _startTicker();
      }
    }
    _sub = _ua.callStream.listen(_onAnyCallUpdate);
  }

  void _startTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _activeSince == null) return;
      setState(() => _elapsed = DateTime.now().difference(_activeSince!));
    });
  }

  void _onUpdate(SipCall c) {
    setState(() => _call = c);
    if (c.state == CallState.active && _activeSince == null) {
      _activeSince = DateTime.now();
      _startTicker();
    }
    if (c.state == CallState.ended) {
      _ticker?.cancel();
      _pulse.stop();
      // Don't auto-pop — show the ended summary so the user can
      // dismiss it or place a call back.
    }
  }

  void _onAnyCallUpdate(SipCall c) {
    if (c.id == widget.callId) {
      _onUpdate(c);
      return;
    }
    final current = _call;
    final shouldFollowActiveCall =
        c.state == CallState.active &&
        !c.held &&
        (current == null || current.state == CallState.ended || current.held);
    if (shouldFollowActiveCall) _switchToCall(c.id);
  }

  @override
  void dispose() {
    _sub?.cancel();
    _ticker?.cancel();
    _pulse.dispose();
    super.dispose();
  }

  // ── Handlers ─────────────────────────────────────────────────────────

  void _toggleMute() {
    final next = !_muted;
    final applied = _ua.setMuted(widget.callId, next);
    if (applied != null) setState(() => _muted = applied);
  }

  void _toggleHold() {
    final c = _call;
    if (c == null) return;
    final applied = _ua.setHold(widget.callId, !c.held);
    if (applied == null) _toast('Cannot hold this call right now');
  }

  void _toggleSpeaker() => setState(() => _speaker = !_speaker);

  void _toggleKeypad() => setState(() => _showKeypad = !_showKeypad);

  void _toggleRecording() {
    setState(() => _recording = !_recording);
    _toast(_recording ? 'Recording started' : 'Recording stopped');
  }

  void _toggleStats() => setState(() => _showStats = !_showStats);

  void _sendDtmf(String d) {
    _ua.sendDtmf(widget.callId, d);
    setState(() {
      final next = _dtmfHistory + d;
      _dtmfHistory = next.length > 16 ? next.substring(next.length - 16) : next;
    });
  }

  Future<void> _onTransfer() async {
    final req = await TransferSheet.show(context);
    if (req == null || !mounted) return;
    if (req.attended) {
      final consultation = await _ua.startAttendedTransfer(
        widget.callId,
        req.target,
      );
      if (!mounted) return;
      if (consultation == null) {
        _toast('Cannot start an attended transfer right now');
        return;
      }
      Navigator.of(context).push(
        MaterialPageRoute(
          settings: const RouteSettings(name: 'call'),
          builder: (_) => CallPage(callId: consultation.id),
        ),
      );
      return;
    }
    final sent = _ua.transferCall(widget.callId, req.target);
    _toast(
      sent
          ? 'Transfer request sent to ${req.target}'
          : 'Cannot transfer this call right now',
    );
  }

  void _completeAttendedTransfer() {
    final sent = _ua.completeAttendedTransfer(widget.callId);
    _toast(
      sent
          ? 'Completing attended transfer'
          : 'Cannot complete this transfer right now',
    );
    if (sent) Navigator.of(context).maybePop();
  }

  Future<void> _onAddCall() async {
    if (!enableMultipleCalls) {
      _toast('Multiple calls are disabled');
      return;
    }
    final target = await _showDialTargetSheet(
      title: 'Add another call',
      actionLabel: 'Call',
      icon: Icons.person_add_alt_1,
    );
    if (target == null || !mounted) return;
    final call = await _ua.makeCall(target);
    if (!mounted) return;
    if (call == null) {
      _toast('Cannot start another call right now');
      return;
    }
    _switchToCall(call.id);
  }

  void _onCallBack() {
    final c = _call;
    if (c == null) return;
    _ua.makeCall(c.remoteParty);
    Navigator.of(context).maybePop();
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<String?> _showDialTargetSheet({
    required String title,
    required String actionLabel,
    required IconData icon,
  }) {
    final controller = TextEditingController();
    return showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (ctx) {
        final viewInsets = MediaQuery.viewInsetsOf(ctx).bottom;
        return Padding(
          padding: EdgeInsets.fromLTRB(24, 4, 24, viewInsets + 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                title,
                style: Theme.of(
                  ctx,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                autofocus: true,
                keyboardType: TextInputType.text,
                decoration: InputDecoration(
                  border: const OutlineInputBorder(),
                  labelText: 'Destination',
                  hintText: 'extension or sip:user@host',
                  prefixIcon: Icon(icon),
                ),
                onSubmitted: (_) {
                  final target = controller.text.trim();
                  if (target.isNotEmpty) Navigator.of(ctx).pop(target);
                },
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () {
                  final target = controller.text.trim();
                  if (target.isNotEmpty) Navigator.of(ctx).pop(target);
                },
                icon: Icon(icon),
                label: Text(actionLabel),
              ),
            ],
          ),
        );
      },
    ).whenComplete(controller.dispose);
  }

  void _switchToCall(String callId) {
    if (!mounted) return;
    _ua.activateCall(callId);
    if (callId == widget.callId) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        settings: const RouteSettings(name: 'call'),
        builder: (_) => CallPage(callId: callId),
      ),
    );
  }

  // ── Build ────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final c = _call;
    final state = c?.state ?? CallState.idle;

    return PopScope(
      // Allow pop in any non-active state so users can bail out of an
      // accidentally placed outgoing call.
      canPop: state != CallState.active,
      child: Scaffold(
        body: Stack(
          children: [
            Positioned.fill(
              child: CallBackdrop(state: state, party: c?.remoteParty),
            ),
            SafeArea(
              child: c == null
                  ? const Center(child: CircularProgressIndicator())
                  : _buildContent(c, state),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(SipCall c, CallState state) {
    final liveCalls = ref
        .watch(callsProvider)
        .recents
        .where(
          (call) =>
              call.state == CallState.active ||
              call.state == CallState.incomingRinging ||
              call.state == CallState.outgoingRinging,
        )
        .toList();
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: IntrinsicHeight(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    CallTopBar(
                      outgoing: c.outgoing,
                      state: state,
                      recording: _recording,
                      onMinimise: () => Navigator.of(context).maybePop(),
                    ),
                    const SizedBox(height: 16),
                    CallPartyCard(
                      party: c.remoteParty,
                      state: state,
                      held: c.held,
                      elapsed: _elapsed,
                      pulse: _pulse,
                    ),
                    if (enableMultipleCalls && liveCalls.length > 1) ...[
                      const SizedBox(height: 18),
                      _MultiCallTray(
                        calls: liveCalls,
                        selectedCallId: c.id,
                        onSwitch: _switchToCall,
                      ),
                    ],
                    if (_dtmfHistory.isNotEmpty && state == CallState.active)
                      Padding(
                        padding: const EdgeInsets.only(top: 12),
                        child: Text(
                          _dtmfHistory,
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(
                                letterSpacing: 4,
                                fontFeatures: const [
                                  FontFeature.tabularFigures(),
                                ],
                              ),
                        ),
                      ),
                    if (_showStats && state == CallState.active)
                      const CallStatsPanel(
                        codec: 'PCMU',
                        bitrateKbps: null,
                        packetLossPct: null,
                        jitterMs: null,
                        rttMs: null,
                      ),
                    const Spacer(),
                    if (_showKeypad && state == CallState.active) ...[
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: DialPad(compact: true, onKey: _sendDtmf),
                      ),
                      TextButton.icon(
                        onPressed: _toggleKeypad,
                        icon: const Icon(Icons.keyboard_arrow_down),
                        label: const Text('Hide keypad'),
                      ),
                    ],
                    _buildActions(c, state),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildActions(SipCall c, CallState state) {
    switch (state) {
      case CallState.incomingRinging:
        return IncomingCallActions(
          onAnswer: () => _ua.answer(c.id),
          onDecline: () => _ua.hangup(c.id),
        );
      case CallState.outgoingRinging:
        return OutgoingCallActions(onCancel: () => _ua.hangup(c.id));
      case CallState.active:
        // Hide the bulky action grid behind the keypad — BP does the
        // same: when the keypad opens, the action row collapses.
        if (_showKeypad) return const SizedBox.shrink();
        return ActiveCallActions(
          muted: _muted,
          held: c.held,
          speaker: _speaker,
          recording: _recording,
          statsVisible: _showStats,
          onMute: _toggleMute,
          onHold: _toggleHold,
          onSpeaker: _toggleSpeaker,
          onKeypad: _toggleKeypad,
          onTransfer: c.transferPending ? null : _onTransfer,
          onCompleteTransfer: _ua.attendedTransferSourceFor(c.id) == null
              ? null
              : (c.transferPending ? null : _completeAttendedTransfer),
          onRecord: _toggleRecording,
          onAddCall: _onAddCall,
          onToggleStats: _toggleStats,
          onHangup: () => _ua.hangup(c.id),
        );
      case CallState.ended:
        return EndedCallActions(
          onClose: () => Navigator.of(context).maybePop(),
          onCallBack: _onCallBack,
        );
      case CallState.idle:
        return const SizedBox.shrink();
    }
  }
}

class _MultiCallTray extends StatelessWidget {
  const _MultiCallTray({
    required this.calls,
    required this.selectedCallId,
    required this.onSwitch,
  });

  final List<SipCall> calls;
  final String selectedCallId;
  final ValueChanged<String> onSwitch;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.58),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.call_split, size: 18, color: scheme.primary),
              const SizedBox(width: 8),
              Text(
                'Live calls',
                style: Theme.of(
                  context,
                ).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final call in calls)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: _CallLineChip(
                      call: call,
                      selected: call.id == selectedCallId,
                      onTap: () => onSwitch(call.id),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CallLineChip extends StatelessWidget {
  const _CallLineChip({
    required this.call,
    required this.selected,
    required this.onTap,
  });

  final SipCall call;
  final bool selected;
  final VoidCallback onTap;

  String get _name {
    var value = call.remoteParty;
    if (value.startsWith('sip:')) value = value.substring(4);
    final at = value.indexOf('@');
    return at > 0 ? value.substring(0, at) : value;
  }

  String get _label {
    return switch (call.state) {
      CallState.incomingRinging => 'Incoming',
      CallState.outgoingRinging => 'Calling',
      CallState.active => call.held ? 'On hold' : 'Active',
      CallState.ended => 'Ended',
      CallState.idle => 'Idle',
    };
  }

  IconData get _icon {
    return switch (call.state) {
      CallState.incomingRinging => Icons.call_received,
      CallState.outgoingRinging => Icons.call_made,
      CallState.active => call.held ? Icons.pause : Icons.call,
      CallState.ended => Icons.call_end,
      CallState.idle => Icons.phone_disabled,
    };
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bp = Theme.of(context).bp;
    final color = switch (call.state) {
      CallState.active => call.held ? bp.holdingCall : bp.activeCall,
      CallState.incomingRinging ||
      CallState.outgoingRinging => bp.presenceRinging,
      CallState.ended => bp.hangup,
      CallState.idle => scheme.outline,
    };
    final foreground = selected ? scheme.onPrimary : scheme.onSurface;
    final canTap = !selected || call.held;
    final tooltip = selected
        ? (call.held ? 'Resume $_name' : 'Current call')
        : 'Switch to $_name';
    return Tooltip(
      message: tooltip,
      child: Material(
        color: selected ? scheme.primary : scheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: selected ? scheme.primary : color),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: canTap ? onTap : null,
          child: SizedBox(
            width: 152,
            height: 58,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(
                children: [
                  Icon(
                    _icon,
                    size: 18,
                    color: selected ? scheme.onPrimary : color,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.labelLarge
                              ?.copyWith(
                                color: foreground,
                                fontWeight: FontWeight.w700,
                              ),
                        ),
                        Text(
                          _label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(
                                color: foreground.withValues(alpha: 0.78),
                              ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
