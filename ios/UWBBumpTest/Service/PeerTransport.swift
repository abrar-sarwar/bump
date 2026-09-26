import Foundation
import MultipeerConnectivity

/// Peer transport, encapsulated so it can be swapped later (BLE L2CAP, Network
/// framework) without touching the UI or the pairing pipeline.
///
/// Topology: a STAR. One phone creates the room and coordinates; the others join
/// it. Guests are connected to the coordinator, not to each other — so when two
/// guests are matched they open a direct link on demand for the profile
/// exchange. Full profiles therefore never pass through the coordinator.
///
/// CAPACITY: `MCSession` supports at most 8 connected peers, so a room is
/// coordinator + 7 guests. This is surfaced in the UI rather than failing
/// silently. Nearby Interaction sessions are bounded separately (see
/// `RangingService.maxConcurrentPeers`).
@MainActor
final class PeerTransport: NSObject, ObservableObject {

    /// 1–15 chars, lowercase ASCII/digits/hyphen. Must match NSBonjourServices
    /// (`_bump-uwb._tcp` / `._udp`) in Info.plist exactly.
    nonisolated static let serviceType = "bump-uwb"
    nonisolated static let roomKey = "room"
    nonisolated static let nameKey = "name"
    nonisolated static let roleKey = "role"
    /// MCSession's documented limit.
    nonisolated static let maxPeers = 8

    enum Role: String { case coordinator, guest }

    @Published private(set) var role: Role = .guest
    @Published private(set) var roomCode: String = ""
    @Published private(set) var connected: [Wire.Member] = []
    @Published private(set) var discoveredRooms: [String: Wire.Member] = [:]   // roomCode -> host
    @Published private(set) var isActive = false
    /// Diagnostics only. Set by anything that went wrong, including routine
    /// recoverable things like a send to a peer that just dropped. Never treat
    /// this as a reason to stop the app.
    @Published private(set) var lastError: String?
    /// Set ONLY when discovery itself could not start, which in practice means
    /// Local Network access is off. Cleared as soon as discovery works, so a
    /// transient failure cannot strand the app forever.
    @Published private(set) var discoveryUnavailable: String?

    /// Delivered on the main actor. `from` is the peer's transient id.
    var onMessage: ((_ from: String, _ envelope: Wire.Envelope) -> Void)?
    var onPeerJoined: ((String) -> Void)?
    var onPeerLeft: ((String) -> Void)?
    var onLog: ((String) -> Void)?

    private var myPeerID: MCPeerID!
    private var session: MCSession?
    private var advertiser: MCNearbyServiceAdvertiser?
    private var browser: MCNearbyServiceBrowser?

    private var peersByID: [String: MCPeerID] = [:]
    private var names: [String: String] = [:]
    private var invited: Set<MCPeerID> = []
    private var seen = SeenMessages()
    /// Peers we want a direct link to for a partner-only profile exchange.
    private var directTargets: Set<String> = []

    var myID: String { myPeerID?.displayName ?? "" }

    // MARK: Lifecycle

    /// `displayName` is only used to build a transient peer identity. We salt it
    /// with a short random suffix so two people called "Sam" are distinguishable
    /// and so the identity does not persist across sessions.
    func start(role: Role, roomCode: String, displayName: String) {
        stop()
        self.role = role
        self.roomCode = roomCode.lowercased().trimmed()

        let suffix = String(UUID().uuidString.prefix(4))
        let safeName = String(displayName.trimmed().prefix(24))
        myPeerID = MCPeerID(displayName: "\(safeName.isEmpty ? "Someone" : safeName)#\(suffix)")
        names[myPeerID.displayName] = safeName

        let session = MCSession(peer: myPeerID, securityIdentity: nil, encryptionPreference: .required)
        session.delegate = self
        self.session = session

        // Everyone advertises and browses: the coordinator so guests can find the
        // room, guests so a matched pair can open a direct link to each other.
        let info = [Self.roomKey: self.roomCode, Self.nameKey: safeName, Self.roleKey: role.rawValue]
        let adv = MCNearbyServiceAdvertiser(peer: myPeerID, discoveryInfo: info, serviceType: Self.serviceType)
        adv.delegate = self
        adv.startAdvertisingPeer()
        advertiser = adv

        let brw = MCNearbyServiceBrowser(peer: myPeerID, serviceType: Self.serviceType)
        brw.delegate = self
        brw.startBrowsingForPeers()
        browser = brw

        isActive = true
        // A fresh start clears both: whatever failed last time is not a fact
        // about this attempt.
        discoveryUnavailable = nil
        lastError = nil
        log("transport up as \(role.rawValue) in room \"\(self.roomCode)\" (\(myPeerID.displayName))")
    }

    /// Give discovery a clean slate, for example after the person has been to
    /// Settings. Without this, a blocked session could never retry: only a
    /// successful start clears the flag, and a blocked engine never starts.
    func clearDiscoveryBlock() {
        discoveryUnavailable = nil
    }

    func stop() {
        advertiser?.stopAdvertisingPeer(); advertiser = nil
        browser?.stopBrowsingForPeers(); browser = nil
        session?.disconnect(); session = nil
        peersByID.removeAll(); invited.removeAll(); directTargets.removeAll()
        connected = []
        discoveredRooms = [:]
        isActive = false
    }

    /// Ask for a direct link to a specific peer (used for the partner-only
    /// profile exchange between two guests).
    func openDirectLink(to peerID: String) {
        directTargets.insert(peerID)
        guard let session, let peer = peersByID[peerID], !session.connectedPeers.contains(peer) else { return }
        guard !invited.contains(peer) else { return }
        // Deterministic lead avoids two crossing invitations.
        guard myPeerID.displayName < peer.displayName else {
            log("waiting for \(peer.displayName) to open the direct link")
            return
        }
        invited.insert(peer)
        browser?.invitePeer(peer, to: session, withContext: nil, timeout: 12)
        log("opening direct link to \(peer.displayName)")
    }

    // MARK: Send

    func send(_ body: Wire.Body, to peerIDs: [String]) {
        guard let session else { return }
        let targets = peerIDs.compactMap { peersByID[$0] }.filter { session.connectedPeers.contains($0) }
        guard !targets.isEmpty else { return }
        do {
            // Reliable: every message here is a state change we cannot lose.
            try session.send(Wire.encode(body), toPeers: targets, with: .reliable)
        } catch {
            lastError = error.localizedDescription
            log("send failed: \(error.localizedDescription)")
        }
    }

    func broadcast(_ body: Wire.Body) {
        send(body, to: connected.map(\.id))
    }

    func displayName(of peerID: String) -> String {
        names[peerID] ?? peerID.components(separatedBy: "#").first ?? peerID
    }

    private func log(_ s: String) { onLog?(s) }

    private func refreshConnected() {
        guard let session else { connected = []; return }
        connected = session.connectedPeers.map {
            Wire.Member(id: $0.displayName, displayName: displayName(of: $0.displayName))
        }
    }
}

// MARK: - MCSessionDelegate

extension PeerTransport: MCSessionDelegate {

    nonisolated func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        Task { @MainActor in
            switch state {
            case .connected:
                self.peersByID[peerID.displayName] = peerID
                self.refreshConnected()
                self.log("connected: \(peerID.displayName)")
                self.onPeerJoined?(peerID.displayName)
            case .notConnected:
                self.invited.remove(peerID)
                self.refreshConnected()
                self.log("disconnected: \(peerID.displayName)")
                self.onPeerLeft?(peerID.displayName)
            case .connecting:
                self.log("connecting: \(peerID.displayName)")
            @unknown default: break
            }
        }
    }

    nonisolated func session(_ session: MCSession, didReceive data: Data, fromPeer peerID: MCPeerID) {
        Task { @MainActor in
            do {
                let envelope = try Wire.decode(data)
                // Idempotent: drop duplicates and late re-deliveries.
                guard self.seen.accept(envelope.id) else {
                    self.log("dropped duplicate \(envelope.id.prefix(8))")
                    return
                }
                self.onMessage?(peerID.displayName, envelope)
            } catch {
                self.lastError = error.localizedDescription
                self.log("bad frame from \(peerID.displayName): \(error.localizedDescription)")
            }
        }
    }

    nonisolated func session(_ s: MCSession, didReceive: InputStream, withName: String, fromPeer: MCPeerID) {}
    nonisolated func session(_ s: MCSession, didStartReceivingResourceWithName: String, fromPeer: MCPeerID, with: Progress) {}
    nonisolated func session(_ s: MCSession, didFinishReceivingResourceWithName: String, fromPeer: MCPeerID, at: URL?, withError: Error?) {}
}

// MARK: - Browsing

extension PeerTransport: MCNearbyServiceBrowserDelegate {

    nonisolated func browser(_ browser: MCNearbyServiceBrowser, foundPeer peerID: MCPeerID,
                             withDiscoveryInfo info: [String: String]?) {
        let room = info?[PeerTransport.roomKey] ?? ""
        let name = info?[PeerTransport.nameKey] ?? ""
        let peerRole = info?[PeerTransport.roleKey] ?? ""
        Task { @MainActor in
            self.peersByID[peerID.displayName] = peerID
            self.names[peerID.displayName] = name
            self.discoveryUnavailable = nil     // we can clearly see peers

            if peerRole == Role.coordinator.rawValue {
                self.discoveredRooms[room] = Wire.Member(id: peerID.displayName, displayName: name)
            }
            // Room scoping: we only ever talk to peers in OUR room.
            guard room == self.roomCode else { return }

            if self.role == .guest, peerRole == Role.coordinator.rawValue,
               let session = self.session, !session.connectedPeers.contains(peerID),
               !self.invited.contains(peerID) {
                // A guest joins the room by inviting its coordinator. We never
                // auto-connect to an arbitrary nearby phone — only to the host of
                // the room code the user typed.
                self.invited.insert(peerID)
                browser.invitePeer(peerID, to: session, withContext: nil, timeout: 15)
                self.log("joining room via coordinator \(peerID.displayName)")
            } else if self.directTargets.contains(peerID.displayName) {
                self.openDirectLink(to: peerID.displayName)
            }
        }
    }

    nonisolated func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        Task { @MainActor in
            self.discoveredRooms = self.discoveredRooms.filter { $0.value.id != peerID.displayName }
            self.log("lost sight of \(peerID.displayName)")
        }
    }

    nonisolated func browser(_ browser: MCNearbyServiceBrowser, didNotStartBrowsingForPeers error: Error) {
        Task { @MainActor in
            self.discoveryUnavailable = "BUMP needs Local Network access to see the phones around you. Turn it on in Settings, then come back."
            self.lastError = "Can't look for nearby phones. Local Network access is usually the reason."
            self.log("browse failed: \(error.localizedDescription)")
        }
    }
}

// MARK: - Advertising

extension PeerTransport: MCNearbyServiceAdvertiserDelegate {

    nonisolated func advertiser(_ advertiser: MCNearbyServiceAdvertiser,
                                didReceiveInvitationFromPeer peerID: MCPeerID,
                                withContext context: Data?,
                                invitationHandler: @escaping (Bool, MCSession?) -> Void) {
        Task { @MainActor in
            guard let session = self.session else { return invitationHandler(false, nil) }
            let roomIsFull = session.connectedPeers.count >= PeerTransport.maxPeers - 1
            // Accept a guest into our room if we coordinate it, or accept a
            // direct link we asked for. Never accept a stranger otherwise.
            let wanted = (self.role == .coordinator) || self.directTargets.contains(peerID.displayName)
            if wanted && !roomIsFull {
                self.peersByID[peerID.displayName] = peerID
                self.log("accepting \(peerID.displayName)")
                invitationHandler(true, session)
            } else {
                self.log(roomIsFull ? "room full, refused \(peerID.displayName)"
                                    : "refused unexpected invitation from \(peerID.displayName)")
                invitationHandler(false, nil)
            }
        }
    }

    nonisolated func advertiser(_ advertiser: MCNearbyServiceAdvertiser, didNotStartAdvertisingPeer error: Error) {
        Task { @MainActor in
            self.discoveryUnavailable = "BUMP needs Local Network access for other phones to see you. Turn it on in Settings, then come back."
            self.lastError = "Can't make this phone visible. Local Network access is usually the reason."
            self.log("advertise failed: \(error.localizedDescription)")
        }
    }
}
