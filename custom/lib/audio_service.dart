import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:audioplayers/audioplayers.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';
import 'package:uuid/uuid.dart';

/// Continuous capture + playback for the automatic (always-on, mutable) feed.
///
/// Capture uses record's raw-PCM streaming mode (startStream) instead of
/// the old start()/stop()-per-clip approach. The microphone opens ONCE and
/// stays open - there's no per-chunk codec initialization cost, which was
/// the dominant source of latency before. Raw PCM chunks arriving off the
/// stream are batched into small self-contained WAV files (just a 44-byte
/// header, no encoding needed since it's already raw PCM) and handed to a
/// callback roughly every [chunkDuration].
///
/// Playback is unchanged in approach: each received WAV chunk is written to
/// a temp file and played via audioplayers.
class AudioService {
  static const sampleRate = 16000;
  static const numChannels = 1;

  final AudioRecorder _recorder = AudioRecorder();
  final AudioPlayer _player = AudioPlayer();
  final _uuid = const Uuid();

  StreamSubscription<Uint8List>? _pcmSub;
  Timer? _batchTimer;
  final List<int> _buffer = [];

  Future<bool> requestMicPermission() async {
    final status = await Permission.microphone.request();
    return status.isGranted;
  }

  /// Starts continuous capture. [onChunk] fires roughly every
  /// [chunkDuration] with a small ready-to-send WAV file.
  Future<void> startStreamingCapture(
    void Function(Uint8List wavBytes) onChunk, {
    Duration chunkDuration = const Duration(milliseconds: 300),
  }) async {
    if (!await _recorder.hasPermission()) return;
    final stream = await _recorder.startStream(
      const RecordConfig(encoder: AudioEncoder.pcm16bits, sampleRate: sampleRate, numChannels: numChannels),
    );
    _buffer.clear();
    _pcmSub = stream.listen((chunk) => _buffer.addAll(chunk));
    _batchTimer = Timer.periodic(chunkDuration, (_) {
      if (_buffer.isEmpty) return;
      final pcm = Uint8List.fromList(_buffer);
      _buffer.clear();
      onChunk(_wrapWav(pcm));
    });
  }

  Future<void> stopStreamingCapture() async {
    _batchTimer?.cancel();
    _batchTimer = null;
    await _pcmSub?.cancel();
    _pcmSub = null;
    if (await _recorder.isRecording()) {
      await _recorder.stop();
    }
    _buffer.clear();
  }

  /// Wraps raw PCM16 mono bytes in a minimal 44-byte WAV header so it's a
  /// self-contained playable file - no encoding needed, just a header.
  Uint8List _wrapWav(Uint8List pcm) {
    const bitsPerSample = 16;
    final byteRate = sampleRate * numChannels * bitsPerSample ~/ 8;
    final blockAlign = numChannels * bitsPerSample ~/ 8;
    final b = BytesBuilder();
    b.add('RIFF'.codeUnits);
    b.add(_u32(36 + pcm.length));
    b.add('WAVE'.codeUnits);
    b.add('fmt '.codeUnits);
    b.add(_u32(16));
    b.add(_u16(1)); // PCM format
    b.add(_u16(numChannels));
    b.add(_u32(sampleRate));
    b.add(_u32(byteRate));
    b.add(_u16(blockAlign));
    b.add(_u16(bitsPerSample));
    b.add('data'.codeUnits);
    b.add(_u32(pcm.length));
    b.add(pcm);
    return b.toBytes();
  }

  List<int> _u32(int v) => [v & 0xff, (v >> 8) & 0xff, (v >> 16) & 0xff, (v >> 24) & 0xff];
  List<int> _u16(int v) => [v & 0xff, (v >> 8) & 0xff];

  /// Plays a received WAV chunk immediately.
  Future<void> playIncoming(Uint8List bytes) async {
    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/incoming_${_uuid.v4()}.wav';
    final file = File(path);
    await file.writeAsBytes(bytes);
    await _player.play(DeviceFileSource(path));
    _player.onPlayerComplete.listen((_) async {
      if (await file.exists()) await file.delete();
    });
  }

  void dispose() {
    _batchTimer?.cancel();
    _pcmSub?.cancel();
    _recorder.dispose();
    _player.dispose();
  }
}
