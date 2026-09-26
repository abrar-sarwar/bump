import Foundation
import MultipeerConnectivity

/// Ambient StreetPass peer discovery, fully separate from `PeerTransport`.
/// There is no room code and no coordinator: any two phones advertising this
/// service connect to each other automatically, bounded by
/// `config.maxConcurrentPeers`. This is a deliberately different trust model
/// from `PeerTransport`, which never connects to an unscoped stranger —
/// StreetPass's entire purpose is ambient discovery of anyone else running
/// BUMP.
@MainActor
final class StreetPassTransport: NSObject, ObservableObject {

    /// 1–15 chars, lowercase ASCII/digits/hyphen, matching NSBonjourServices
    /// in Info.plist exactly.
    nonisolated static let serviceType = "bump-streetpass"

    @Published private(set) var connectedPeerIDs: Set<String> = []
    var config = StreetPassConfig()

    var onMessage: ((_ from: String, _ envelope: StreetPassWire.Envelope) -> Void)?
    var onPeerJoined: ((String) -> Void)?
    var onPeerLeft: ((String) -> Void)?
    var onLog: ((String) -> Void)?

    private var myPeerID: MCPeerID!
    private var session: MCSession?
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?
    private var peersByID: [String: MCPeerID] = [:]
    private var invited: Set<MCPeerID> = []
    private var seen = SeenMessages()

    var myID: String { myPeerID?.displayName ?? "" }

    func start(displayName: String) {
        stop()
        let suffix = String(UUID().uuidString.prefix(4))
        let safeName = String(displayName.trimmed().prefix(24))
        myPeerID = MCPeerID(displayName: "\(safeName.isEmpty ? "Someone" : safeName)#\(suffix)")

        let session = MCSession(peer: myPeerID, securityIdentity: nil, encryptionPreference: .required)
        session.delegate = self
        self.session = session

        let adv = MCNearbyServiceAdvertiser(peer: myPeerID, discoveryInfo: nil, serviceType: Self.serviceType)
        adv.delegate = self
        adv.startAdvertisingPeer()
        advertiser = adv

        let brw = MCNearbyServiceBrowser(peer: myPeerID, serviceType: Self.serviceType)
        brw.delegate = self
        brw.startBrowsingForPeers()
        browser = brw

        log("StreetPass transport up (\(myPeerID.displayName))")
    }

    func stop() {
        advertiser?.stopAdvertisingPeer(); advertiser = nil
        browser?.stopBrowsingForPeers(); browser = nil
        session?.disconnect(); session = nil
        peersByID.removeAll(); invited.removeAll()
        connectedPeerIDs = []
    }

    func send(_ body: StreetPassWire.Body, to peerID: String) {
        guard let session, let peer = peersByID[peerID], session.connectedPeers.contains(peer) else { return }
        do {
            try session.send(try StreetPassWire.encode(body), toPeers: [peer], with: .reliable)
        } catch {
            log("StreetPass send failed: \(error.localizedDescription)")
        }
    }

    private func log(_ s: String) { onLog?(s) }

    private func refreshConnected() {
        guard let session else { connectedPeerIDs = []; return }
        connectedPeerIDs = Set(session.connectedPeers.map(\.displayName))
    }
}

// MARK: - MCSessionDelegate

extension StreetPassTransport: MCSessionDelegate {

    nonisolated func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        Task { @MainActor in
            switch state {
            case .connected:
                self.peersByID[peerID.displayName] = peerID
                self.refreshConnected()
                self.log("StreetPass connected: \(peerID.displayName)")
                self.onPeerJoined?(peerID.displayName)
            case .notConnected:
                self.invited.remove(peerID)
                self.refreshConnected()
                self.log("StreetPass disconnected: \(peerID.displayName)")
                self.onPeerLeft?(peerID.displayName)
            case .connecting:
                self.log("StreetPass connecting: \(peerID.displayName)")
            @unknown default: break
            }
        }
    }

    nonisolated func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        Task { @MainActor in
            do {
                let envelope = try StreetPassWire.decode(data)
                guard self.seen.accept(envelope.id) else { return }
                self.onMessage?(peerID.displayName, envelope)
            } catch {
                self.log("StreetPass bad frame from \(peerID.displayName): \(error.localizedDescription)")
            }
        }
    }

    nonisolated func session(_ s: MCSession, didReceive: InputStream, withName: String, fromPeer: MCPeerID) {}
    nonisolated func session(_ s: MCSession, didStartReceivingResourceWithName: String, fromPeer: MCPeerID, with: Progress) {}
    nonisolated func session(_ s: MCSession, didFinishReceivingResourceWithName: String, fromPeer: MCPeerID, at: URL?, withError: Error?) {}
}

// MARK: - Browsing

extension StreetPassTransport: MCNearbyServiceBrowserDelegate {

    nonisolated func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID,
                             withDiscoveryInfo info: [String: String]?) {
        Task { @MainActor in
            self.peersByID[peerID.displayName] = peerID
            guard let session = self.session, !session.connectedPeers.contains(peerID),
                  !self.invited.contains(peerID) else { return }
            guard session.connectedPeers.count < self.config.maxConcurrentPeers else {
                self.log("StreetPass at the \(self.config.maxConcurrentPeers)-peer cap; not inviting \(peerID.displayName)")
                return
            }
            // Deterministic lead avoids two crossing invitations, same trick
            // PeerTransport uses for its direct-link handshake.
            guard self.myPeerID.displayName < peerID.displayName else { return }
            self.invited.insert(peerID)
            browser.invitePeer(peerID, to: session, withContext: nil, timeout: 10)
        }
    }

    nonisolated func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        Task { @MainActor in self.log("StreetPass lost sight of \(peerID.displayName)") }
    }

    nonisolated func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        Task { @MainActor in self.log("StreetPass browse failed: \(error.localizedDescription)") }
    }
}

// MARK: - Advertising

extension StreetPassTransport: MCNearbyServiceAdvertiserDelegate {

    nonisolated func advertiser(_ advertiser: MCNearbyServiceAdvertiser,
                                didReceiveInvitationFromPeer peerID: MCPeerID,
                                withContext context: Data?,
                                invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        Task { @MainActor in
            guard let session = self.session else { return invitationHandler(false, nil) }
            let atCap = session.connectedPeers.count >= self.config.maxConcurrentPeers
            if atCap {
                self.log("StreetPass at cap, refused \(peerID.displayName)")
                invitationHandler(false, nil)
            } else {
                self.peersByID[peerID.displayName] = peerID
                invitationHandler(true, session)
            }
        }
    }

    nonisolated func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        Task { @MainActor in self.log("StreetPass advertise failed: \(error.localizedDescription)") }
    }
}
