import Flutter
import MultipeerConnectivity

/// Wraps MultipeerConnectivity (advertiser + browser + session) behind the
/// same method/event contract as the Android NearbyDiscoveryPlugin, so the
/// Dart bridge never needs a platform check.
class MultipeerDiscoveryPlugin: NSObject, FlutterStreamHandler {

    private let serviceType = "intercom-app" // must match Info.plist NSBonjourServices, <=15 chars, lowercase+hyphen
    private var peerID: MCPeerID!
    private var session: MCSession!
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?
    private var eventSink: FlutterEventSink?
    private var discoveredPeers: [String: MCPeerID] = [:]

    override init() {
        super.init()
        peerID = MCPeerID(displayName: UIDevice.current.name)
        session = MCSession(peer: peerID, securityIdentity: nil, encryptionPreference: .required)
        session.delegate = self
    }

    func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        switch call.method {
        case "startHosting":
            let args = call.arguments as? [String: Any]
            let sessionName = args?["sessionName"] as? String ?? peerID.displayName
            let info = ["session": sessionName]
            advertiser = MCNearbyServiceAdvertiser(peer: peerID, discoveryInfo: info, serviceType: serviceType)
            advertiser?.delegate = self
            advertiser?.startAdvertisingPeer()
            result(nil)

        case "startBrowsing":
            browser = MCNearbyServiceBrowser(peer: peerID, serviceType: serviceType)
            browser?.delegate = self
            browser?.startBrowsingForPeers()
            result(nil)

        case "connect":
            guard let args = call.arguments as? [String: Any],
                  let peerIdStr = args["peerId"] as? String,
                  let targetPeer = discoveredPeers[peerIdStr] else {
                result(FlutterError(code: "PEER_NOT_FOUND", message: nil, details: nil))
                return
            }
            browser?.invitePeer(targetPeer, to: session, withContext: nil, timeout: 15)
            result(nil)

        case "sendBytes":
            guard let args = call.arguments as? [String: Any],
                  let data = args["data"] as? FlutterStandardTypedData else {
                result(FlutterError(code: "BAD_ARGS", message: nil, details: nil))
                return
            }
            let peerIdStr = args["peerId"] as? String
            do {
                if let peerIdStr = peerIdStr, let target = discoveredPeers[peerIdStr] {
                    try session.send(data.data, toPeers: [target], with: .reliable)
                } else if !session.connectedPeers.isEmpty {
                    try session.send(data.data, toPeers: session.connectedPeers, with: .reliable)
                }
                result(nil)
            } catch {
                result(FlutterError(code: "SEND_FAILED", message: error.localizedDescription, details: nil))
            }

        case "stop":
            advertiser?.stopAdvertisingPeer()
            browser?.stopBrowsingForPeers()
            session.disconnect()
            result(nil)

        default:
            result(FlutterMethodNotImplemented)
        }
    }

    // MARK: - FlutterStreamHandler

    func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
        eventSink = events
        return nil
    }

    func onCancel(withArguments arguments: Any?) -> FlutterError? {
        eventSink = nil
        return nil
    }

    private func emit(_ map: [String: Any?]) {
        DispatchQueue.main.async { self.eventSink?(map) }
    }

    private func idFor(_ peer: MCPeerID) -> String {
        // MCPeerID has no stable string id; use displayName as the id since
        // it's what discoveredPeers is keyed on. Swap for a UUID exchanged
        // in discoveryInfo if you need names to collide safely.
        return peer.displayName
    }
}

// MARK: - MCNearbyServiceAdvertiserDelegate

extension MultipeerDiscoveryPlugin: MCNearbyServiceAdvertiserDelegate {
    func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didReceiveInvitationFromPeer peerID: MCPeerID,
                     withContext context: Data?, invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        // Auto-accept. For production, prompt the user first.
        invitationHandler(true, session)
    }
}

// MARK: - MCNearbyServiceBrowserDelegate

extension MultipeerDiscoveryPlugin: MCNearbyServiceBrowserDelegate {
    func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID, withDiscoveryInfo info: [String: String]?) {
        discoveredPeers[idFor(peerID)] = peerID
        emit(["type": "peerFound", "peerId": idFor(peerID), "peerName": peerID.displayName])
    }

    func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        discoveredPeers.removeValue(forKey: idFor(peerID))
        emit(["type": "peerLost", "peerId": idFor(peerID)])
    }
}

// MARK: - MCSessionDelegate

extension MultipeerDiscoveryPlugin: MCSessionDelegate {
    func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        switch state {
        case .connected:
            emit(["type": "peerConnected", "peerId": idFor(peerID), "peerName": peerID.displayName])
        case .notConnected:
            emit(["type": "peerDisconnected", "peerId": idFor(peerID)])
        case .connecting:
            break
        @unknown default:
            break
        }
    }

    func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        emit(["type": "dataReceived", "peerId": idFor(peerID), "data": FlutterStandardTypedData(bytes: data)])
    }

    // Unused stream/resource APIs - required by the protocol.
    func session(_ session: MCSession, didReceive stream: InputStream, withName streamName: String, fromPeer peerID: MCPeerID) {}
    func session(_ session: MCSession, didStartReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, with progress: Progress) {}
    func session(_ session: MCSession, didFinishReceivingResourceWithName resourceName: String, fromPeer peerID: MCPeerID, at localURL: URL?, withError error: Error?) {}
}
