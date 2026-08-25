import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'discovery_bridge.dart';

enum SessionRole { none, host, joiner }

class Peer {
  final String id;
  final String name;
  bool connected;
  Peer({required this.id, required this.name, this.connected = false});
}

/// Owns all session/connection state. This is the part that is genuinely
/// cross-platform: it only talks to DiscoveryBridge, never to native code
/// directly, so this file is identical on iOS and Android.
class SessionState extends ChangeNotifier {
  SessionRole role = SessionRole.none;
  String sessionName = '';
  final Map<String, Peer> _peers = {};
  final List<String> log = [];

  /// Called with decoded audio bytes whenever a peer sends a voice chunk.
  void Function(Uint8List audioBytes, String fromPeerId)? onAudioReceived;

  List<Peer> get peers => _peers.values.toList(growable: false);
  bool get isActive => role != SessionRole.none;

  SessionState() {
    DiscoveryBridge.instance.events.listen(_handleEvent);
  }

  Future<void> hostSession(String name) async {
    sessionName = name;
    role = SessionRole.host;
    _log('Hosting session "$name"');
    await DiscoveryBridge.instance.startHosting(name);
    notifyListeners();
  }

  Future<void> joinNearbySession() async {
    role = SessionRole.joiner;
    _log('Scanning for sessions...');
    await DiscoveryBridge.instance.startBrowsing();
    notifyListeners();
  }

  Future<void> connectTo(String peerId) async {
    await DiscoveryBridge.instance.connect(peerId);
  }

  Future<void> sendAudioChunk(Uint8List bytes) async {
    // Prefix with a 1-byte message-type tag so receivers can distinguish
    // audio frames from future control messages without a second channel.
    final framed = Uint8List(bytes.length + 1);
    framed[0] = 0x01; // 0x01 = audio frame
    framed.setRange(1, framed.length, bytes);
    await DiscoveryBridge.instance.sendBytes(framed);
  }

  Future<void> endSession() async {
    await DiscoveryBridge.instance.stop();
    role = SessionRole.none;
    _peers.clear();
    _log('Session ended');
    notifyListeners();
  }

  void _handleEvent(DiscoveryEvent event) {
    switch (event.type) {
      case DiscoveryEventType.peerFound:
        _peers[event.peerId] = Peer(id: event.peerId, name: event.peerName ?? event.peerId);
        _log('Found peer ${event.peerName ?? event.peerId}');
        // Joiner mode: auto-connect to the first host found.
        if (role == SessionRole.joiner) {
          connectTo(event.peerId);
        }
        break;
      case DiscoveryEventType.peerLost:
        _peers.remove(event.peerId);
        _log('Lost peer ${event.peerId}');
        break;
      case DiscoveryEventType.peerConnected:
        final existing = _peers[event.peerId];
        if (existing != null) {
          existing.connected = true;
        } else {
          _peers[event.peerId] = Peer(id: event.peerId, name: event.peerName ?? event.peerId, connected: true);
        }
        _log('Connected to ${event.peerName ?? event.peerId}');
        break;
      case DiscoveryEventType.peerDisconnected:
        _peers[event.peerId]?.connected = false;
        _log('Disconnected from ${event.peerId}');
        break;
      case DiscoveryEventType.dataReceived:
        final data = event.data;
        if (data != null && data.isNotEmpty && data[0] == 0x01) {
          onAudioReceived?.call(Uint8List.sublistView(data, 1), event.peerId);
        }
        break;
      case DiscoveryEventType.error:
        _log('Error: ${event.message}');
        break;
    }
    notifyListeners();
  }

  void _log(String message) {
    log.add(message);
    if (log.length > 200) log.removeAt(0);
  }
}
