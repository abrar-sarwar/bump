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
    /// Diagnostics and readiness: how many distinct BUMP phones this transport
    /// has seen since it started. Zero for a long time usually means Local
    /// Network access was declined; iOS gives Multipeer no error for that.
    @Published private(set) var peersSeen = 0
    /// A guest has invited a coordinator and is waiting for the session to form.
    @Published private(set) var joinInFlight = false
    /// Delivery counters, for the two-phone comparison.
    @Published private(set) var sentCount = 0
    @Published private(set) var undeliveredCount = 0
    @Published private(set) var receivedCount = 0

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
    /// Coordinators of OUR room seen by the browser, so a failed invitation can
    /// be retried (the browser will not report the peer again).
    private var coordinatorCandidates: [String: MCPeerID] = [:]
    private var inviteAttempts: [String: Int] = [:]
    nonisolated static let maxInviteAttempts = 3
    private var seenPeerNames: Set<String> = []

    var myID: String { myPeerID?.displayName ?? "" }

    // MARK: Server relay

    /// Which path carries messages. The relay replaces Multipeer entirely for
    /// a session: the BUMP server keeps the room's member list, names the
    /// coordinator (earliest member still connected) and forwards the same
    /// wire frames. It never matches bumps or reads messages.
    enum Mode: Equatable { case multipeer, relay(URL) }
    @Published private(set) var mode: Mode = .multipeer
    var isRelay: Bool { if case .relay = mode { return true } else { return false } }
    /// The coordinator's id changed (relay only). The engine re-introduces
    /// itself to a new coordinator and takes over matching if it is us.
    var onCoordinatorChanged: ((String) -> Void)?
    @Published private(set) var relayCoordinator: String?
    @Published private(set) var relayStreamUp = false
    private var relayTask: Task<Void, Never>?
    private var relaySendChain: Task<Void, Never>?
    private static let relaySession: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 30      // polls are held for up to 20 s
        config.waitsForConnectivity = false
        config.urlCache = nil
        return URLSession(configuration: config)
    }()

    func startRelay(baseURL: URL, roomCode: String, displayName: String) {
        stop()
        self.role = .guest               // until the server names a coordinator
        self.roomCode = roomCode.lowercased().trimmed()
        let safeName = String(displayName.trimmed().prefix(24))
        let wantedPrefix = "\(safeName.isEmpty ? "Someone" : safeName)#"
        if myPeerID == nil || !myPeerID.displayName.hasPrefix(wantedPrefix) {
            myPeerID = MCPeerID(displayName: wantedPrefix + String(UUID().uuidString.prefix(4)))
        }
        names[myPeerID.displayName] = safeName
        mode = .relay(baseURL)
        isActive = true
        discoveryUnavailable = nil
        lastError = nil
        log("transport up via server relay \(baseURL.host ?? "") in room \"\(self.roomCode)\" (\(myPeerID.displayName))")
        let me = myPeerID.displayName, room = self.roomCode
        relayTask = Task { [weak self] in
            await self?.runRelayPolling(baseURL: baseURL, room: room, me: me, name: safeName)
        }
    }

    /// Long-poll loop. Each reply carries the member list and any messages;
    /// the cursor acknowledges what we have received so the server can drop it.
    private func runRelayPolling(baseURL: URL, room: String, me: String, name: String) async {
        var cursor = 0, mv = -1, failures = 0
        while !Task.isCancelled {
            var comps = URLComponents(url: baseURL.appendingPathComponent("v1/relay/poll"), resolvingAgainstBaseURL: false)!
            comps.queryItems = [.init(name: "room", value: room), .init(name: "peer", value: me),
                                .init(name: "name", value: name), .init(name: "cursor", value: "\(cursor)"),
                                .init(name: "mv", value: "\(mv)")]
            var request = URLRequest(url: comps.url!)
            request.timeoutInterval = 30        // server holds for up to 20 s
            do {
                let (data, response) = try await Self.relaySession.data(for: request)
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                guard status == 200, let reply = try? JSONDecoder().decode(RelayReply.self, from: data) else {
                    log("[relay] poll refused (HTTP \(status))")
                    if status == 409 { discoveryUnavailable = "The BUMP server says this room is full." }
                    throw URLError(.badServerResponse)
                }
                if failures > 0 || !relayStreamUp { log("[relay] connected to server") }
                failures = 0
                relayStreamUp = true
                mv = reply.mv
                applyMembers(reply.members, coordinator: reply.coordinator)
                for msg in reply.messages { relayMessage(msg) }
                cursor = reply.cursor
            } catch {
                guard !Task.isCancelled else { return }
                failures += 1
                if failures == 1 { log("[relay] poll failed: \(error.localizedDescription)") }
                // Past a few failures the peers are unreachable; say so.
                if failures == 3 { relayDropped() }
                try? await Task.sleep(nanoseconds: UInt64(min(failures, 5)) * 1_000_000_000)
            }
        }
    }

    private struct RelayMember: Decodable { let id: String; let name: String }
    private struct RelayMsg: Decodable { let seq: Int; let from: String; let data: String }
    private struct RelayReply: Decodable {
        let members: [RelayMember]
        let coordinator: String?
        let mv: Int
        let messages: [RelayMsg]
        let cursor: Int
    }

    private func applyMembers(_ members: [RelayMember], coordinator: String?) {
        for m in members { names[m.id] = m.name }
        let others = members.filter { $0.id != myID }
        let before = Set(connected.map(\.id))
        let after = Set(others.map(\.id))
        if !after.isEmpty { peersSeen = max(peersSeen, after.count) }
        let newRole: Role = coordinator == myID ? .coordinator : .guest
        if newRole != role { role = newRole; log("[relay] role -> \(newRole.rawValue)") }
        connected = others.map { Wire.Member(id: $0.id, displayName: $0.name) }
        for id in before.subtracting(after) { log("disconnected: \(id)"); onPeerLeft?(id) }
        for id in after.subtracting(before) { log("connected: \(id)"); onPeerJoined?(id) }
        if relayCoordinator != coordinator {
            relayCoordinator = coordinator
            if let coordinator { onCoordinatorChanged?(coordinator) }
        }
    }

    private func relayMessage(_ msg: RelayMsg) {
        guard let frame = Data(base64Encoded: msg.data) else { return }
        receivedCount += 1
        do {
            let envelope = try Wire.decode(frame)
            guard seen.accept(envelope.id) else { return }
            onMessage?(msg.from, envelope)
        } catch {
            log("bad frame from \(msg.from): \(error.localizedDescription)")
        }
    }

    private func relayDropped() {
        relayStreamUp = false
        let gone = connected.map(\.id)
        connected = []
        relayCoordinator = nil
        role = .guest
        for id in gone { onPeerLeft?(id) }
        log("[relay] reconnecting")
    }

    /// Sends are chained so frames leave in order: the protocol relies on it
    /// (a seal must land before the profile that follows it).
    private func relaySend(_ frame: Data, to targets: [String], kind: String, baseURL: URL) {
        struct Body: Encodable { let room: String; let from: String; let to: [String]; let data: String }
        struct Reply: Decodable { let delivered: [String]; let missing: [String] }
        let body = Body(room: roomCode, from: myID, to: targets, data: frame.base64EncodedString())
        let previous = relaySendChain
        relaySendChain = Task { [weak self] in
            await previous?.value
            var request = URLRequest(url: baseURL.appendingPathComponent("v1/relay/send"))
            request.httpMethod = "POST"
            request.timeoutInterval = 5
            request.setValue("application/json", forHTTPHeaderField: "content-type")
            request.httpBody = try? JSONEncoder().encode(body)
            do {
                let (data, response) = try await Self.relaySession.data(for: request)
                let status = (response as? HTTPURLResponse)?.statusCode ?? 0
                if status == 200, let reply = try? JSONDecoder().decode(Reply.self, from: data) {
                    if !reply.missing.isEmpty {
                        self?.undeliveredCount += 1
                        self?.log("[net] relay could not deliver \(kind) to \(reply.missing.joined(separator: ","))")
                    }
                } else {
                    self?.undeliveredCount += 1
                    self?.log("[net] relay send \(kind) failed (HTTP \(status))")
                }
            } catch {
                self?.undeliveredCount += 1
                self?.log("[net] relay send \(kind) failed: \(error.localizedDescription)")
            }
        }
    }

    // MARK: Lifecycle

    /// `displayName` is only used to build a transient peer identity. We salt it
    /// with a short random suffix so two people called "Sam" are distinguishable
    /// and so the identity does not persist across sessions.
    func start(role: Role, roomCode: String, displayName: String) {
        stop()
        self.role = role
        self.roomCode = roomCode.lowercased().trimmed()

        let safeName = String(displayName.trimmed().prefix(24))
        // One MCPeerID per app run. Apple advises reusing the peer ID rather
        // than creating a new one per session, and it matters here: every
        // host hand-off used to mint a new identity, which left the old one in
        // other phones' browsers (a ghost coordinator that absorbs invites) and
        // re-rolled the id the step-down tie-break compares.
        let wantedPrefix = "\(safeName.isEmpty ? "Someone" : safeName)#"
        if myPeerID == nil || !myPeerID.displayName.hasPrefix(wantedPrefix) {
            myPeerID = MCPeerID(displayName: wantedPrefix + String(UUID().uuidString.prefix(4)))
        }
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
        if case .relay(let baseURL) = mode, !roomCode.isEmpty {
            // Best effort, so the other phone sees us go now rather than when
            // the server notices we stopped polling.
            var request = URLRequest(url: baseURL.appendingPathComponent("v1/relay/leave"))
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "content-type")
            request.httpBody = try? JSONSerialization.data(withJSONObject: ["room": roomCode, "peer": myID])
            Self.relaySession.dataTask(with: request).resume()
        }
        relayTask?.cancel(); relayTask = nil
        relayStreamUp = false; relayCoordinator = nil
        mode = .multipeer
        advertiser?.stopAdvertisingPeer(); advertiser = nil
        browser?.stopBrowsingForPeers(); browser = nil
        session?.disconnect(); session = nil
        peersByID.removeAll(); invited.removeAll(); directTargets.removeAll()
        coordinatorCandidates.removeAll(); inviteAttempts.removeAll()
        seenPeerNames.removeAll(); peersSeen = 0
        joinInFlight = false
        connected = []
        discoveredRooms = [:]
        isActive = false
    }

    /// Ask for a direct link to a specific peer (used for the partner-only
    /// profile exchange between two guests).
    func openDirectLink(to peerID: String) {
        guard !isRelay else { return }     // every relay member is already reachable
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

    /// Returns whether the message was handed to a connected peer. `.reliable`
    /// Multipeer delivery means a true result arrives in order unless the link
    /// drops; the protocol's reply messages (proposal, timeout, welcome) are
    /// the end-to-end outcome. A false result is always logged with the kind of
    /// message, so "message not delivered" is visible in an exported log.
    @discardableResult
    func send(_ body: Wire.Body, to peerIDs: [String]) -> Bool {
        let kind = Wire.kind(of: body)
        if case .relay(let baseURL) = mode {
            let targets = peerIDs.filter { id in connected.contains { $0.id == id } }
            guard !targets.isEmpty, let frame = try? Wire.encode(body) else {
                undeliveredCount += 1
                log("[net] not delivered \(kind): no connected target")
                return false
            }
            sentCount += 1
            relaySend(frame, to: targets, kind: kind, baseURL: baseURL)
            return true
        }
        guard let session else {
            undeliveredCount += 1
            log("[net] not delivered \(kind): no session")
            return false
        }
        let targets = peerIDs.compactMap { peersByID[$0] }.filter { session.connectedPeers.contains($0) }
        guard !targets.isEmpty else {
            undeliveredCount += 1
            log("[net] not delivered \(kind): no connected target")
            return false
        }
        do {
            // Reliable: every message here is a state change we cannot lose.
            try session.send(Wire.encode(body), toPeers: targets, with: .reliable)
            sentCount += 1
            return true
        } catch {
            undeliveredCount += 1
            lastError = error.localizedDescription
            log("[net] send \(kind) failed: \(error.localizedDescription)")
            return false
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
        guard !isRelay else { return }
        guard let session else { connected = []; return }
        connected = session.connectedPeers.map {
            Wire.Member(id: $0.displayName, displayName: displayName(of: $0.displayName))
        }
        joinInFlight = role == .guest && connected.isEmpty && !invited.isEmpty
    }

    /// Invite a coordinator of our room, bounded per peer.
    private func inviteCoordinator(_ peerID: MCPeerID) {
        guard role == .guest, let session, let browser,
              !session.connectedPeers.contains(peerID), !invited.contains(peerID) else { return }
        let attempts = inviteAttempts[peerID.displayName, default: 0]
        guard attempts < Self.maxInviteAttempts else {
            log("[net] gave up inviting \(peerID.displayName) after \(attempts) attempts")
            return
        }
        inviteAttempts[peerID.displayName] = attempts + 1
        invited.insert(peerID)
        browser.invitePeer(peerID, to: session, withContext: nil, timeout: 10)
        joinInFlight = connected.isEmpty
        log("[net] inviting coordinator \(peerID.displayName) (attempt \(attempts + 1))")
    }

    /// True if a coordinator for our room is visible or an invite is pending.
    var coordinatorReachable: Bool { !coordinatorCandidates.isEmpty || joinInFlight }
}

// MARK: - MCSessionDelegate

extension PeerTransport: MCSessionDelegate {

    nonisolated func session(_ session: MCSession, peer peerID: MCPeerID, didChange state: MCSessionState) {
        Task { @MainActor in
            switch state {
            case .connected:
                self.peersByID[peerID.displayName] = peerID
                self.inviteAttempts[peerID.displayName] = nil
                self.refreshConnected()
                self.log("connected: \(peerID.displayName)")
                self.onPeerJoined?(peerID.displayName)
            case .notConnected:
                let wasConnected = self.connected.contains { $0.id == peerID.displayName }
                self.invited.remove(peerID)
                self.refreshConnected()
                self.log("disconnected: \(peerID.displayName)")
                // A failed invitation also lands here. Only report a peer as
                // "left" if it had actually joined; otherwise an invite timeout
                // would tear down unrelated state in the engine.
                if wasConnected { self.onPeerLeft?(peerID.displayName) }
                // Retry a coordinator we still see, after a short pause.
                if self.role == .guest, self.connected.isEmpty,
                   let candidate = self.coordinatorCandidates[peerID.displayName] {
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 800_000_000)
                        guard self.coordinatorCandidates[peerID.displayName] != nil else { return }
                        self.inviteCoordinator(candidate)
                    }
                }
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
                self.receivedCount += 1
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
            if self.seenPeerNames.insert(peerID.displayName).inserted {
                self.peersSeen = self.seenPeerNames.count
            }

            if peerRole == Role.coordinator.rawValue {
                self.discoveredRooms[room] = Wire.Member(id: peerID.displayName, displayName: name)
            }
            // Room scoping: we only ever talk to peers in OUR room.
            guard room == self.roomCode else { return }

            if peerRole == Role.coordinator.rawValue {
                self.coordinatorCandidates[peerID.displayName] = peerID
            } else {
                // Same id re-advertising as a guest: it stepped down.
                self.coordinatorCandidates[peerID.displayName] = nil
            }

            if self.role == .guest, peerRole == Role.coordinator.rawValue {
                // A guest joins the room by inviting its coordinator. We never
                // auto-connect to an arbitrary nearby phone, only to the host of
                // our room.
                self.inviteCoordinator(peerID)
            } else if self.directTargets.contains(peerID.displayName) {
                self.openDirectLink(to: peerID.displayName)
            }
        }
    }

    nonisolated func browser(_ browser: MCNearbyServiceBrowser, lostPeer peerID: MCPeerID) {
        Task { @MainActor in
            self.discoveredRooms = self.discoveredRooms.filter { $0.value.id != peerID.displayName }
            self.coordinatorCandidates[peerID.displayName] = nil
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
