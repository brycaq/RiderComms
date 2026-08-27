import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../session_state.dart';
import '../audio_service.dart';

class SessionScreen extends StatefulWidget {
  const SessionScreen({super.key});
  @override
  State<SessionScreen> createState() => _SessionScreenState();
}

class _SessionScreenState extends State<SessionScreen> {
  final _audio = AudioService();
  bool _muted = false;
  Timer? _chunkTimer;
  bool _disposed = false;

  // Automatic feed: record a short chunk, send it, immediately start the
  // next one. This is NOT true continuous streaming (raw PCM would need a
  // dedicated streaming-playback plugin that record/audioplayers don't
  // provide) - it's short rolling clips, which gives hands-free automatic
  // transmission with a small latency and a near-imperceptible gap between
  // chunks, while reusing the same record/playback pipeline already proven
  // to work. Shorten this for lower latency at the cost of more overhead
  // per chunk, or lengthen it for the opposite trade-off.
  static const _chunkDuration = Duration(milliseconds: 1200);

  @override
  void initState() {
    super.initState();
    final session = context.read<SessionState>();
    session.onAudioReceived = (bytes, fromPeerId) {
      _audio.playIncoming(bytes);
    };
    _startAutoFeed();
  }

  Future<void> _startAutoFeed() async {
    final granted = await _audio.requestMicPermission();
    if (!granted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Microphone permission is required to transmit audio.')),
        );
      }
      return;
    }
    _recordAndSendCycle();
  }

  Future<void> _recordAndSendCycle() async {
    if (_disposed || _muted) return;
    await _audio.startRecording();
    _chunkTimer = Timer(_chunkDuration, () async {
      if (_disposed) return;
      final bytes = await _audio.stopRecordingAndGetBytes();
      if (bytes != null && bytes.isNotEmpty && !_muted && mounted) {
        await context.read<SessionState>().sendAudioChunk(bytes);
      }
      _recordAndSendCycle();
    });
  }

  Future<void> _toggleMute() async {
    setState(() => _muted = !_muted);
    if (_muted) {
      _chunkTimer?.cancel();
      await _audio.stopRecordingAndGetBytes(); // stop and discard the in-flight clip
    } else {
      _recordAndSendCycle();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _chunkTimer?.cancel();
    _audio.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionState>();

    return Scaffold(
      appBar: AppBar(
        title: Text(session.role == SessionRole.host ? 'Hosting: ${session.sessionName}' : 'Joined session'),
        actions: [
          IconButton(
            icon: const Icon(Icons.call_end),
            onPressed: () async {
              _chunkTimer?.cancel();
              await session.endSession();
              if (context.mounted) Navigator.of(context).pop();
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.builder(
              itemCount: session.peers.length,
              itemBuilder: (context, i) {
                final peer = session.peers[i];
                return ListTile(
                  leading: Icon(peer.connected ? Icons.person : Icons.person_outline),
                  title: Text(peer.name),
                  subtitle: Text(peer.connected ? 'Connected' : 'Discovered'),
                );
              },
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(24),
            child: GestureDetector(
              onTap: _toggleMute,
              child: CircleAvatar(
                radius: 48,
                backgroundColor: _muted ? Colors.grey : Theme.of(context).colorScheme.primary,
                child: Icon(_muted ? Icons.mic_off : Icons.mic, size: 40, color: Colors.white),
              ),
            ),
          ),
          Text(_muted ? 'Muted - tap to unmute' : 'Live - tap to mute'),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
