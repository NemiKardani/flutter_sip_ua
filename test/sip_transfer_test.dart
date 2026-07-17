import 'dart:async';

import 'package:flutter_sip_ua/sip/sip_message.dart';
import 'package:flutter_sip_ua/sip/sip_user_agent.dart';
import 'package:flutter_sip_ua/sip/transport.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'sends an in-dialog blind REFER to the normalized destination',
    () async {
      final transport = _FakeTransport();
      final ua = SipUserAgent(transportFactory: (_) => transport);
      await ua.start(
        SipAccount(
          username: '100',
          password: 'secret',
          domain: 'pbx.example.test',
          serverUri: Uri.parse('ws://pbx.example.test/sip'),
        ),
      );

      final call = await ua.makeCall('200');
      expect(call, isNotNull);
      final invite = transport.sent.lastWhere((m) => m.method == 'INVITE');
      transport.receive(
        SipMessage.response(
          code: 200,
          reason: 'OK',
          headers: [
            MapEntry('Via', invite.header('Via')!),
            MapEntry('From', invite.header('From')!),
            const MapEntry('To', '<sip:200@pbx.example.test>;tag=remote-tag'),
            MapEntry('Call-ID', invite.callId!),
            MapEntry('CSeq', invite.cseq!),
            const MapEntry('Contact', '<sip:200@media.example.test>'),
          ],
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(ua.callById(call!.id)?.state, CallState.active);
      expect(ua.transferCall(call.id, '300'), isTrue);

      final refer = transport.sent.lastWhere((m) => m.method == 'REFER');
      expect(refer.requestUri, 'sip:200@media.example.test');
      expect(refer.header('To'), '<sip:200@pbx.example.test>;tag=remote-tag');
      expect(refer.header('Refer-To'), '<sip:300@pbx.example.test>');
      expect(refer.header('Refer-Sub'), 'false');
      expect(ua.callById(call.id)?.transferPending, isTrue);

      await ua.stop();
      await transport.dispose();
    },
  );

  test(
    'completes an attended transfer with the source dialog in Replaces',
    () async {
      final transport = _FakeTransport();
      final ua = SipUserAgent(transportFactory: (_) => transport);
      await ua.start(
        SipAccount(
          username: '100',
          password: 'secret',
          domain: 'pbx.example.test',
          serverUri: Uri.parse('ws://pbx.example.test/sip'),
        ),
      );

      final source = await ua.makeCall('200');
      expect(source, isNotNull);
      final sourceInvite = transport.sent.lastWhere(
        (m) => m.method == 'INVITE',
      );
      _acceptInvite(
        transport,
        sourceInvite,
        remoteParty: '200',
        contact: 'sip:200@media.example.test',
        tag: 'source-tag',
      );
      await Future<void>.delayed(Duration.zero);

      final consultation = await ua.startAttendedTransfer(source!.id, '300');
      expect(consultation, isNotNull);
      expect(ua.callById(source.id)?.held, isTrue);
      _acceptInvite(
        transport,
        transport.sent.lastWhere((m) => m.method == 'INVITE'),
        remoteParty: '300',
        contact: 'sip:300@media.example.test',
        tag: 'consultation-tag',
      );
      await Future<void>.delayed(Duration.zero);

      expect(ua.completeAttendedTransfer(consultation!.id), isTrue);
      final refer = transport.sent.lastWhere((m) => m.method == 'REFER');
      final replaces = Uri.encodeQueryComponent(
        '${source.id};to-tag=source-tag;from-tag=${sourceInvite.fromTag}',
      );
      expect(refer.requestUri, 'sip:300@media.example.test');
      expect(
        refer.header('Refer-To'),
        '<sip:200@pbx.example.test?Replaces=$replaces>',
      );

      await ua.stop();
      await transport.dispose();
    },
  );

  test('attended transfer only disconnects the selected source call', () async {
    final transport = _FakeTransport();
    final ua = SipUserAgent(transportFactory: (_) => transport);
    await ua.start(
      SipAccount(
        username: '100',
        password: 'secret',
        domain: 'pbx.example.test',
        serverUri: Uri.parse('ws://pbx.example.test/sip'),
      ),
    );

    final unrelated = await ua.makeCall('123');
    _acceptInvite(
      transport,
      transport.sent.lastWhere((m) => m.method == 'INVITE'),
      remoteParty: '123',
      contact: 'sip:123@media.example.test',
      tag: 'unrelated-tag',
    );
    await Future<void>.delayed(Duration.zero);

    final source = await ua.makeCall('456');
    final sourceInvite = transport.sent.lastWhere((m) => m.method == 'INVITE');
    _acceptInvite(
      transport,
      sourceInvite,
      remoteParty: '456',
      contact: 'sip:456@media.example.test',
      tag: 'source-tag',
    );
    await Future<void>.delayed(Duration.zero);

    expect(unrelated, isNotNull);
    expect(source, isNotNull);
    expect(ua.setHold(unrelated!.id, false), isFalse);
    expect(ua.callById(unrelated.id)?.held, isFalse);
    expect(ua.callById(source!.id)?.held, isTrue);

    final consultation = await ua.startAttendedTransfer(source.id, '789');
    expect(consultation, isNotNull);
    _acceptInvite(
      transport,
      transport.sent.lastWhere((m) => m.method == 'INVITE'),
      remoteParty: '789',
      contact: 'sip:789@media.example.test',
      tag: 'consultation-tag',
    );
    await Future<void>.delayed(Duration.zero);

    expect(ua.callById(unrelated.id)?.state, CallState.active);
    expect(ua.callById(unrelated.id)?.held, isFalse);
    expect(ua.callById(source.id)?.state, CallState.active);
    expect(ua.callById(source.id)?.held, isTrue);

    expect(ua.completeAttendedTransfer(consultation!.id), isTrue);
    final refer = transport.sent.lastWhere((m) => m.method == 'REFER');
    final replaces = Uri.encodeQueryComponent(
      '${source.id};to-tag=source-tag;from-tag=${sourceInvite.fromTag}',
    );
    expect(refer.requestUri, 'sip:789@media.example.test');
    expect(
      refer.header('Refer-To'),
      '<sip:456@pbx.example.test?Replaces=$replaces>',
    );

    transport.receive(
      SipMessage.response(
        code: 202,
        reason: 'Accepted',
        headers: [
          MapEntry('Via', refer.header('Via')!),
          MapEntry('From', refer.header('From')!),
          MapEntry('To', refer.header('To')!),
          MapEntry('Call-ID', refer.callId!),
          MapEntry('CSeq', refer.cseq!),
        ],
      ),
    );
    await Future<void>.delayed(Duration.zero);

    final byes = transport.sent.where((m) => m.method == 'BYE').toList();
    expect(byes, hasLength(1));
    expect(byes.single.callId, source.id);
    expect(ua.callById(source.id), isNull);
    expect(ua.callById(unrelated.id)?.state, CallState.active);
    expect(ua.callById(unrelated.id)?.held, isFalse);

    await ua.stop();
    await transport.dispose();
  });

  test(
    'holds the previous call and restores it when the active call ends',
    () async {
      final transport = _FakeTransport();
      final ua = SipUserAgent(transportFactory: (_) => transport);
      await ua.start(
        SipAccount(
          username: '100',
          password: 'secret',
          domain: 'pbx.example.test',
          serverUri: Uri.parse('ws://pbx.example.test/sip'),
        ),
      );

      final first = await ua.makeCall('200');
      _acceptInvite(
        transport,
        transport.sent.lastWhere((m) => m.method == 'INVITE'),
        remoteParty: '200',
        contact: 'sip:200@media.example.test',
        tag: 'first-tag',
      );
      await Future<void>.delayed(Duration.zero);
      expect(ua.callById(first!.id)?.state, CallState.active);
      expect(ua.callById(first.id)?.held, isFalse);

      final second = await ua.makeCall('300');
      await Future<void>.delayed(Duration.zero);
      expect(ua.callById(first.id)?.held, isTrue);

      _acceptInvite(
        transport,
        transport.sent.lastWhere((m) => m.method == 'INVITE'),
        remoteParty: '300',
        contact: 'sip:300@media.example.test',
        tag: 'second-tag',
      );
      await Future<void>.delayed(Duration.zero);

      expect(ua.callById(second!.id)?.held, isFalse);
      expect(ua.callById(first.id)?.held, isTrue);

      transport.receive(
        _byeFor(
          callId: second.id,
          from: '<sip:300@pbx.example.test>;tag=second-tag',
          to: '<sip:100@pbx.example.test>',
        ),
      );
      await Future<void>.delayed(Duration.zero);

      expect(ua.callById(second.id), isNull);
      expect(ua.callById(first.id)?.state, CallState.active);
      expect(ua.callById(first.id)?.held, isFalse);

      await ua.stop();
      await transport.dispose();
    },
  );

  test(
    'activates a selected held call and holds the previous active call',
    () async {
      final transport = _FakeTransport();
      final ua = SipUserAgent(transportFactory: (_) => transport);
      await ua.start(
        SipAccount(
          username: '100',
          password: 'secret',
          domain: 'pbx.example.test',
          serverUri: Uri.parse('ws://pbx.example.test/sip'),
        ),
      );

      final first = await ua.makeCall('200');
      _acceptInvite(
        transport,
        transport.sent.lastWhere((m) => m.method == 'INVITE'),
        remoteParty: '200',
        contact: 'sip:200@media.example.test',
        tag: 'first-tag',
      );
      await Future<void>.delayed(Duration.zero);

      final second = await ua.makeCall('300');
      _acceptInvite(
        transport,
        transport.sent.lastWhere((m) => m.method == 'INVITE'),
        remoteParty: '300',
        contact: 'sip:300@media.example.test',
        tag: 'second-tag',
      );
      await Future<void>.delayed(Duration.zero);

      expect(ua.callById(first!.id)?.held, isTrue);
      expect(ua.callById(second!.id)?.held, isFalse);

      expect(ua.activateCall(first.id), isTrue);
      await Future<void>.delayed(Duration.zero);

      expect(ua.callById(first.id)?.held, isFalse);
      expect(ua.callById(second.id)?.held, isTrue);

      await ua.stop();
      await transport.dispose();
    },
  );

  test('can disable multiple calls and reject new dialogs', () async {
    final transport = _FakeTransport();
    final ua = SipUserAgent(
      multipleCallsEnabled: false,
      transportFactory: (_) => transport,
    );
    await ua.start(
      SipAccount(
        username: '100',
        password: 'secret',
        domain: 'pbx.example.test',
        serverUri: Uri.parse('ws://pbx.example.test/sip'),
      ),
    );

    final first = await ua.makeCall('200');
    _acceptInvite(
      transport,
      transport.sent.lastWhere((m) => m.method == 'INVITE'),
      remoteParty: '200',
      contact: 'sip:200@media.example.test',
      tag: 'first-tag',
    );
    await Future<void>.delayed(Duration.zero);

    expect(first, isNotNull);
    expect(await ua.makeCall('300'), isNull);

    transport.receive(_incomingInvite('incoming-call'));
    await Future<void>.delayed(Duration.zero);
    final busy = transport.sent.lastWhere((m) => m.statusCode == 486);
    expect(busy.reasonPhrase, 'Busy Here');

    await ua.stop();
    await transport.dispose();
  });
}

void _acceptInvite(
  _FakeTransport transport,
  SipMessage invite, {
  required String remoteParty,
  required String contact,
  required String tag,
}) {
  transport.receive(
    SipMessage.response(
      code: 200,
      reason: 'OK',
      headers: [
        MapEntry('Via', invite.header('Via')!),
        MapEntry('From', invite.header('From')!),
        MapEntry('To', '<sip:$remoteParty@pbx.example.test>;tag=$tag'),
        MapEntry('Call-ID', invite.callId!),
        MapEntry('CSeq', invite.cseq!),
        MapEntry('Contact', '<$contact>'),
      ],
    ),
  );
}

SipMessage _byeFor({
  required String callId,
  required String from,
  required String to,
}) {
  return SipMessage.request(
    'BYE',
    'sip:100@client.example.test',
    headers: [
      const MapEntry('Via', 'SIP/2.0/WS pbx.example.test;branch=z9hG4bK-bye'),
      MapEntry('From', from),
      MapEntry('To', to),
      MapEntry('Call-ID', callId),
      const MapEntry('CSeq', '1 BYE'),
    ],
  );
}

SipMessage _incomingInvite(String callId) {
  return SipMessage.request(
    'INVITE',
    'sip:100@client.example.test',
    headers: [
      const MapEntry(
        'Via',
        'SIP/2.0/WS pbx.example.test;branch=z9hG4bK-invite',
      ),
      const MapEntry('From', '<sip:400@pbx.example.test>;tag=incoming-tag'),
      const MapEntry('To', '<sip:100@pbx.example.test>'),
      MapEntry('Call-ID', callId),
      const MapEntry('CSeq', '1 INVITE'),
      const MapEntry('Contact', '<sip:400@media.example.test>'),
    ],
  );
}

class _FakeTransport implements SipTransport {
  final _state = StreamController<TransportState>.broadcast();
  final _messages = StreamController<SipMessage>.broadcast();
  final List<SipMessage> sent = [];
  bool _connected = false;

  @override
  Stream<TransportState> get state => _state.stream;

  @override
  Stream<SipMessage> get messages => _messages.stream;

  @override
  bool get isConnected => _connected;

  @override
  String get protocol => 'WS';

  @override
  String get localHost => 'client.example.test';

  @override
  int get localPort => 5060;

  @override
  Future<void> connect() async {
    _connected = true;
    _state.add(TransportState.connected);
  }

  @override
  Future<void> close() async {
    _connected = false;
    _state.add(TransportState.disconnected);
  }

  @override
  void send(SipMessage message) => sent.add(message);

  @override
  void sendRaw(String raw) {}

  void receive(SipMessage message) => _messages.add(message);

  Future<void> dispose() async {
    await _state.close();
    await _messages.close();
  }
}
