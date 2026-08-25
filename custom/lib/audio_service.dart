import 'dart:io';
import 'dart:typed_data';
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';
import 'package:uuid/uuid.dart';

/// Push-to-talk capture + playback. Deliberately simple: record a short
/// clip while the mic button is held, read it back as bytes, hand it to
/// SessionState to send. This trades continuous streaming for reliability -
/// see the README for the path to full-duplex streaming later.
class AudioService {
  final AudioRecorder _recorder = AudioRecorder();
  final AudioPlayer _player = AudioPlayer();
  final _uuid = const Uuid();
  String? _currentRecordingPath;

  Future<bool> requestMicPermission() async {
    final status = await Permission.microphone.request();
    return status.isGranted;
  }

  Future<void> startRecording() async {
    if (!await _recorder.hasPermission()) return;
    final dir = await getTemporaryDirectory();
    _currentRecordingPath = '${dir.path}/ptt_${_uuid.v4()}.m4a';
    await _recorder.start(
      const RecordConfig(encoder: AudioEncoder.aacLc, bitRate: 32000, sampleRate: 16000),
      path: _currentRecordingPath!,
    );
  }

  /// Stops recording and returns the clip as raw bytes ready to send
  /// over the discovery bridge's data channel.
  Future<Uint8List?> stopRecordingAndGetBytes() async {
    final path = await _recorder.stop();
    if (path == null) return null;
    final file = File(path);
    if (!await file.exists()) return null;
    final bytes = await file.readAsBytes();
    await file.delete();
    return bytes;
  }

  /// Plays a received audio chunk immediately.
  Future<void> playIncoming(Uint8List bytes) async {
    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/incoming_${_uuid.v4()}.m4a';
    final file = File(path);
    await file.writeAsBytes(bytes);
    await _player.play(DeviceFileSource(path));
    // Clean up after playback finishes.
    _player.onPlayerComplete.listen((_) async {
      if (await file.exists()) await file.delete();
    });
  }

  void dispose() {
    _recorder.dispose();
    _player.dispose();
  }
}
