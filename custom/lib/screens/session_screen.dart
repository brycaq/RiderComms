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

  // How often a batch of continuously-captured audio gets sent. Shorter =
  // lower latency but more send overhead per second of audio; this is safe
  // to shorten further (e.g. 150-200ms) since capture is now continuous -
  // there's no per-chunk codec startup cost to worry about anymore.
  static const _chunkDuration = Duration(milliseconds: 300);

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
    await _audio.startStreamingCapture(
      (wavBytes) {
        if (!_muted && mounted) {
          context.read<SessionState>().sendAudioChunk(wavBytes);
        }
      },
      chunkDuration: _chunkDuration,
    );
  }

  Future<void> _toggleMute() async {
    setState(() => _muted = !_muted);
    if (_muted) {
      await _audio.stopStreamingCapture();
    } else {
      await _startAutoFeed();
    }
  }

  @override
  void dispose() {
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
              await _audio.stopStreamingCapture();
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
