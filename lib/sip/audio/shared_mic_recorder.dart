import 'dart:async';
import 'dart:typed_data';
import 'package:record/record.dart';

/// Central singleton manager for the hardware microphone.
/// Ensures only one active [AudioRecorder] exists and distributes
/// the audio stream to all subscribing [MediaSession] instances.
class SharedMicRecorder {
  SharedMicRecorder._();
  static final instance = SharedMicRecorder._();

  AudioRecorder? _recorder;
  StreamController<Uint8List>? _controller;
  StreamSubscription<Uint8List>? _micSub;
  int _listenerCount = 0;

  /// Starts or subscribes to the shared microphone stream at the specified [sampleRate].
  Future<Stream<Uint8List>> startRecording(int sampleRate) async {
    _listenerCount++;
    if (_controller != null) {
      return _controller!.stream;
    }

    _controller = StreamController<Uint8List>.broadcast();
    final recorder = AudioRecorder();
    _recorder = recorder;

    if (!await recorder.hasPermission()) {
      _cleanup();
      throw StateError('Microphone permission denied');
    }

    try {
      final stream = await recorder.startStream(
        RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: sampleRate,
          numChannels: 1,
        ),
      );
      _micSub = stream.listen(
        (data) {
          if (_controller != null && !_controller!.isClosed) {
            _controller!.add(data);
          }
        },
        onError: (e) {
          _controller?.addError(e);
        },
      );
    } catch (e) {
      _cleanup();
      rethrow;
    }

    return _controller!.stream;
  }

  /// Stops or unsubscribes from the shared microphone stream.
  Future<void> stopRecording() async {
    _listenerCount--;
    if (_listenerCount <= 0) {
      _cleanup();
    }
  }

  void _cleanup() {
    _listenerCount = 0;
    _micSub?.cancel();
    _micSub = null;
    try {
      _recorder?.stop();
      _recorder?.dispose();
    } catch (_) {}
    _recorder = null;
    _controller?.close();
    _controller = null;
  }
}
