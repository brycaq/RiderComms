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
  bool _isTalking = false;

  @override
  void initState() {
    super.initState();
    _audio.requestMicPermission();
    final session = context.read<SessionState>();
    session.onAudioReceived = (bytes, fromPeerId) {
      _audio.playIncoming(bytes);
    };
  }

  Future<void> _startTalking() async {
    await _audio.startRecording();
    setState(() => _isTalking = true);
  }

  Future<void> _stopTalking() async {
    final bytes = await _audio.stopRecordingAndGetBytes();
    setState(() => _isTalking = false);
    if (bytes != null) {
      await context.read<SessionState>().sendAudioChunk(bytes);
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
              onTapDown: (_) => _startTalking(),
              onTapUp: (_) => _stopTalking(),
              onTapCancel: () => _stopTalking(),
              child: CircleAvatar(
                radius: 48,
                backgroundColor: _isTalking ? Colors.red : Theme.of(context).colorScheme.primary,
                child: const Icon(Icons.mic, size: 40, color: Colors.white),
              ),
            ),
          ),
          Text(_isTalking ? 'Talking...' : 'Hold to talk'),
          const SizedBox(height: 16),
        ],
      ),
    );
  }
}
