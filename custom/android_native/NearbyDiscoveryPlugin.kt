package com.example.intercom_app

import android.app.Activity
import android.content.Context
import com.google.android.gms.nearby.Nearby
import com.google.android.gms.nearby.connection.*
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Wraps Google's Nearby Connections API behind the same method/event
 * contract as the iOS MultipeerDiscoveryPlugin, so the Dart bridge is
 * platform-agnostic. Uses P2P_STAR strategy: one host advertises, many
 * joiners connect directly to it. Any received payload is relayed to this
 * device's other connected endpoints (see onPayloadReceived) - on a leaf
 * joiner that's a no-op since it only has one connection (the host), but on
 * the host it forwards audio from one joiner out to every other joiner, so
 * everyone in a session can hear everyone else.
 */
class NearbyDiscoveryPlugin(private val context: Context) :
    MethodChannel.MethodCallHandler, EventChannel.StreamHandler {

    companion object {
        // Must be identical across all installs of the app to find each other.
        private const val SERVICE_ID = "com.example.intercom_app.SERVICE"
        private const val STRATEGY_TAG = "P2P_STAR"
    }

    private val connectionsClient = Nearby.getConnectionsClient(context)
    private var eventSink: EventChannel.EventSink? = null
    private var localName: String = android.os.Build.MODEL

    // Tracks every endpoint currently connected to THIS device, so a
    // broadcast send (peerId == null) actually has somewhere to go, and so
    // relaying can exclude the original sender.
    private val connectedEndpoints = mutableSetOf<String>()

    private val payloadCallback = object : PayloadCallback() {
        override fun onPayloadReceived(endpointId: String, payload: Payload) {
            if (payload.type == Payload.Type.BYTES) {
                val bytes = payload.asBytes() ?: return
                emit(
                    mapOf(
                        "type" to "dataReceived",
                        "peerId" to endpointId,
                        "data" to bytes.toList(),
                    )
                )
                val others = connectedEndpoints.filter { it != endpointId }
                if (others.isNotEmpty()) {
                    connectionsClient.sendPayload(others, Payload.fromBytes(bytes))
                }
            }
        }

        override fun onPayloadTransferUpdate(endpointId: String, update: PayloadTransferUpdate) {
            // No-op: bytes payloads complete in one shot, no progress tracking needed.
        }
    }

    private val connectionLifecycleCallback = object : ConnectionLifecycleCallback() {
        override fun onConnectionInitiated(endpointId: String, info: ConnectionInfo) {
            // Auto-accept. For production, surface info.endpointName to the user first.
            connectionsClient.acceptConnection(endpointId, payloadCallback)
        }

        override fun onConnectionResult(endpointId: String, result: ConnectionResolution) {
            if (result.status.isSuccess) {
                connectedEndpoints.add(endpointId)
                emit(mapOf("type" to "peerConnected", "peerId" to endpointId))
            } else {
                emit(mapOf("type" to "error", "peerId" to endpointId, "message" to "Connection failed"))
            }
        }

        override fun onDisconnected(endpointId: String) {
            connectedEndpoints.remove(endpointId)
            emit(mapOf("type" to "peerDisconnected", "peerId" to endpointId))
        }
    }

    private val endpointDiscoveryCallback = object : EndpointDiscoveryCallback() {
        override fun onEndpointFound(endpointId: String, info: DiscoveredEndpointInfo) {
            emit(mapOf("type" to "peerFound", "peerId" to endpointId, "peerName" to info.endpointName))
        }

        override fun onEndpointLost(endpointId: String) {
            emit(mapOf("type" to "peerLost", "peerId" to endpointId))
        }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "startHosting" -> {
                localName = call.argument<String>("sessionName") ?: localName
                val options = AdvertisingOptions.Builder().setStrategy(Strategy.P2P_STAR).build()
                connectionsClient.startAdvertising(
                    localName, SERVICE_ID, connectionLifecycleCallback, options
                ).addOnSuccessListener { result.success(null) }
                    .addOnFailureListener { e -> result.error("ADVERTISE_FAILED", e.message, null) }
            }

            "startBrowsing" -> {
                val options = DiscoveryOptions.Builder().setStrategy(Strategy.P2P_STAR).build()
                connectionsClient.startDiscovery(
                    SERVICE_ID, endpointDiscoveryCallback, options
                ).addOnSuccessListener { result.success(null) }
                    .addOnFailureListener { e -> result.error("DISCOVER_FAILED", e.message, null) }
            }

            "connect" -> {
                val peerId = call.argument<String>("peerId")!!
                connectionsClient.requestConnection(localName, peerId, connectionLifecycleCallback)
                    .addOnSuccessListener { result.success(null) }
                    .addOnFailureListener { e -> result.error("CONNECT_FAILED", e.message, null) }
            }

            "sendBytes" -> {
                val data = call.argument<ByteArray>("data")!!
                val peerId = call.argument<String>("peerId")
                val payload = Payload.fromBytes(data)
                if (peerId != null) {
                    connectionsClient.sendPayload(peerId, payload)
                } else if (connectedEndpoints.isNotEmpty()) {
                    // This was previously a no-op comment with nothing that
                    // actually sent anything - the entire reason no audio
                    // ever got through, since every real send in the app
                    // goes through this broadcast path (no specific peerId).
                    connectionsClient.sendPayload(connectedEndpoints.toList(), payload)
                }
                result.success(null)
            }

            "stop" -> {
                connectionsClient.stopAdvertising()
                connectionsClient.stopDiscovery()
                connectionsClient.stopAllEndpoints()
                connectedEndpoints.clear()
                result.success(null)
            }

            else -> result.notImplemented()
        }
    }

    override fun onListen(arguments: Any?, sink: EventChannel.EventSink?) {
        eventSink = sink
    }

    override fun onCancel(arguments: Any?) {
        eventSink = null
    }

    private fun emit(map: Map<String, Any?>) {
        eventSink?.success(map)
    }
}
