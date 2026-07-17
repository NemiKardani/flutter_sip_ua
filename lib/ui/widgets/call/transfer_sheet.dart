import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../providers/sip_providers.dart';
import '../../../sip/sip_user_agent.dart';

/// Result of a transfer dialog: the SIP target plus how to transfer.
class TransferRequest {
  const TransferRequest({required this.target, required this.attended});

  final String target;

  /// `true` ⇒ Attended (consultation) transfer, the user wants to talk
  /// to the destination first.
  /// `false` ⇒ Blind transfer, REFER the call straight through.
  final bool attended;
}

/// Browser-Phone style transfer bottom sheet. Supports blind and attended
/// transfers; attended transfer starts a consultation call before completion.
class TransferSheet extends ConsumerStatefulWidget {
  const TransferSheet({
    super.key,
    required this.currentCallId,
    required this.currentCallParty,
  });

  final String currentCallId;
  final String currentCallParty;

  static Future<TransferRequest?> show(
    BuildContext context, {
    required String currentCallId,
    required String currentCallParty,
  }) {
    return showModalBottomSheet<TransferRequest>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: TransferSheet(
          currentCallId: currentCallId,
          currentCallParty: currentCallParty,
        ),
      ),
    );
  }

  @override
  ConsumerState<TransferSheet> createState() => _TransferSheetState();
}

class _TransferSheetState extends ConsumerState<TransferSheet> {
  final _ctl = TextEditingController();

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  void _submit({required bool attended}) {
    final t = _ctl.text.trim();
    if (t.isEmpty) return;
    Navigator.of(context).pop(TransferRequest(target: t, attended: attended));
  }

  String _normalizeParty(String party) {
    var value = party;
    if (value.startsWith('sip:')) value = value.substring(4);
    final at = value.indexOf('@');
    return at > 0 ? value.substring(0, at) : value;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final viewInsets = MediaQuery.viewInsetsOf(context).bottom;

    // Retrieve and filter unique recent calls
    final recents = ref.watch(callsProvider).recents;
    final uniqueRecents = <String>{};
    final recentCallsList = <SipCall>[];

    for (final c in recents) {
      if (c.id == widget.currentCallId) continue;
      final normalizedParty = _normalizeParty(c.remoteParty);
      if (normalizedParty == _normalizeParty(widget.currentCallParty)) continue;
      if (uniqueRecents.add(normalizedParty)) {
        recentCallsList.add(c);
      }
    }

    return Padding(
      padding: EdgeInsets.only(bottom: viewInsets + 24, top: 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Transfer call',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          Text(
            'Enter a destination number or select from recent calls to perform a blind transfer.',
            style: Theme.of(
              context,
            ).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _ctl,
            autofocus: true,
            keyboardType: TextInputType.text,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              labelText: 'Destination',
              hintText: 'extension or sip:user@host',
              prefixIcon: Icon(Icons.phone_forwarded),
            ),
            onSubmitted: (_) => _submit(attended: false),
          ),
          if (recentCallsList.isNotEmpty) ...[
            const SizedBox(height: 16),
            Text(
              'Select from recent calls',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: scheme.onSurface,
                  ),
            ),
            const SizedBox(height: 8),
            Container(
              constraints: const BoxConstraints(maxHeight: 180),
              decoration: BoxDecoration(
                border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
                borderRadius: BorderRadius.circular(12),
              ),
              child: ListView.separated(
                shrinkWrap: true,
                padding: EdgeInsets.zero,
                itemCount: recentCallsList.length,
                separatorBuilder: (context, index) => Divider(height: 1, color: scheme.outlineVariant.withValues(alpha: 0.3)),
                itemBuilder: (context, index) {
                  final item = recentCallsList[index];
                  final name = _normalizeParty(item.remoteParty);
                  return ListTile(
                    dense: true,
                    leading: CircleAvatar(
                      radius: 16,
                      backgroundColor: scheme.primaryContainer.withValues(alpha: 0.5),
                      child: Icon(Icons.person, color: scheme.primary, size: 16),
                    ),
                    title: Text(
                      name,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                    subtitle: Text(
                      item.remoteParty,
                      style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
                    ),
                    trailing: Icon(Icons.arrow_forward_ios, size: 12, color: scheme.onSurfaceVariant),
                    onTap: () {
                      _ctl.text = item.remoteParty;
                    },
                  );
                },
              ),
            ),
          ],
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: scheme.primary,
                foregroundColor: scheme.onPrimary,
              ),
              onPressed: () => _submit(attended: false),
              icon: const Icon(Icons.send),
              label: const Text('Transfer'),
            ),
          ),
        ],
      ),
    );
  }
}
