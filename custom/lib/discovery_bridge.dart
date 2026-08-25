import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/services.dart';

/// Event types emitted by the native discovery layer.
/// Both the iOS (MultipeerConnectivity) and Android (Nearby Connections)
/// native modules emit the SAME event names + payload shape, so this
/// bridge never needs to know which platform it's running on.
enum DiscoveryEventType { peerFound, peerLost, peerConnected, peerDisconnected, dataReceived, error }

class DiscoveryEvent {
  final DiscoveryEventType type;
  final String peerId;
  final String? peerName;
  final Uint8List? data;
  final String? message;

  DiscoveryEvent({
    required this.type,
    required this.peerId,
    this.peerName,
    this.data,
    this.message,
  });

  factory DiscoveryEvent.fromMap(Map<dynamic, dynamic> map) {
    final typeStr = map['type'] as String;
    final type = switch (typeStr) {
      'peerFound' => DiscoveryEventType.peerFound,
      'peerLost' => DiscoveryEventType.peerLost,
      'peerConnected' => DiscoveryEventType.peerConnected,
      'peerDisconnected' => DiscoveryEventType.peerDisconnected,
      'dataReceived' => DiscoveryEventType.dataReceived,
      _ => DiscoveryEventType.error,
    };
    return DiscoveryEvent(
      type: type,
      peerId: map['peerId'] as String? ?? '',
      peerName: map['peerName'] as String?,
      data: map['data'] != null ? Uint8List.fromList(List<int>.from(map['data'])) : null,
      message: map['message'] as String?,
    );
  }
}

/// Single entry point the rest of the app talks to. It forwards calls to
/// whichever native module is registered for the current platform - the
/// native side (Kotlin/Swift) is responsible for actually doing BLE / Wi-Fi
/// Direct / Multipeer discovery. Dart code never needs a Platform.isIOS check.
class DiscoveryBridge {
  DiscoveryBridge._();
  static final DiscoveryBridge instance = DiscoveryBridge._();

  static const MethodChannel _methodChannel = MethodChannel('intercom/discovery_methods');
  static const EventChannel _eventChannel = EventChannel('intercom/discovery_events');

  Stream<DiscoveryEvent>? _eventStream;

  Stream<DiscoveryEvent> get events {
    _eventStream ??= _eventChannel
        .receiveBroadcastStream()
        .map((raw) => DiscoveryEvent.fromMap(raw as Map<dynamic, dynamic>));
    return _eventStream!;
  }

  /// Start advertising a session so nearby peers can find and join it.
  Future<void> startHosting(String sessionName) async {
    await _methodChannel.invokeMethod('startHosting', {'sessionName': sessionName});
  }

  /// Start scanning for nearby advertised sessions.
  Future<void> startBrowsing() async {
    await _methodChannel.invokeMethod('startBrowsing');
  }

  /// Request a connection to a discovered peer (host).
  Future<void> connect(String peerId) async {
    await _methodChannel.invokeMethod('connect', {'peerId': peerId});
  }

  /// Send raw bytes (audio chunk or control message) to one or all connected peers.
  /// Pass peerId = null to broadcast to everyone in the session.
  Future<void> sendBytes(Uint8List data, {String? peerId}) async {
    await _methodChannel.invokeMethod('sendBytes', {
      'data': data,
      'peerId': peerId,
    });
  }

  /// Stop advertising/browsing and tear down all connections.
  Future<void> stop() async {
    await _methodChannel.invokeMethod('stop');
  }
}
