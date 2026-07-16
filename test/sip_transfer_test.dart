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
