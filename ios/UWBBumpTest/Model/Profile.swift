import Foundation

/// The local user's profile, stored on this phone. Only the `shareable` subset
/// ever leaves it, and only to a confirmed partner. (Onboarding may send the
/// user's own intro and answers to the BUMP server and xAI to draft this — only
/// with their permission, and never the saved profile itself.)
struct Profile: Codable, Equatable, Sendable {
    var displayName: String = ""
    var bio: String = ""
    var interests: [Interest] = []
    /// Approved experiences and goals. Interests stay in `interests` so matching
    /// and older saved profiles keep working unchanged.
    var details: [ProfileFact] = []
    /// Interest id → the user's own words that support it. Private: kept so the
    /// user can see where a suggestion came from, never shared.
    var interestEvidence: [String: String] = [:]
    /// Small square JPEG (see `ProfilePhoto`). Part of the card, so a confirmed
    /// partner receives it; never sent to the BUMP server or xAI.
    var photo: Data?

    init(displayName: String = "", bio: String = "", interests: [Interest] = [],
         details: [ProfileFact] = [], interestEvidence: [String: String] = [:], photo: Data? = nil) {
        self.displayName = displayName
        self.bio = bio
        self.interests = interests
        self.details = details
        self.interestEvidence = interestEvidence
        self.photo = photo
    }

    /// Profiles saved before `details` / `interestEvidence` existed must keep
    /// loading, so every newer field is optional on the way in.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        displayName = try c.decodeIfPresent(String.self, forKey: .displayName) ?? ""
        bio = try c.decodeIfPresent(String.self, forKey: .bio) ?? ""
        interests = try c.decodeIfPresent([Interest].self, forKey: .interests) ?? []
        details = try c.decodeIfPresent([ProfileFact].self, forKey: .details) ?? []
        interestEvidence = try c.decodeIfPresent([String: String].self, forKey: .interestEvidence) ?? [:]
        photo = try c.decodeIfPresent(Data.self, forKey: .photo)
    }

    var isComplete: Bool {
        !displayName.trimmed().isEmpty && (!interests.isEmpty || !details.isEmpty)
    }

    var experiences: [ProfileFact] { details.filter { $0.kind == .experience } }
    var goals: [ProfileFact] { details.filter { $0.kind == .goal } }

    /// The subset we are willing to hand to a confirmed partner. Going through
    /// one explicit type means we never accidentally widen what gets sent:
    /// evidence quotes, transcripts, drafts and preferences are not in here.
    var shareable: SharedProfile {
        SharedProfile(displayName: displayName.trimmed(), bio: bio.trimmed(), interests: interests,
                      details: details.map { SharedFact(id: $0.id, kind: $0.kind, text: $0.text.trimmed()) },
                      photo: photo)
    }
}

/// One approved experience or goal (or, during onboarding, an interest).
struct ProfileFact: Codable, Equatable, Hashable, Identifiable, Sendable {
    enum Kind: String, Codable, CaseIterable, Sendable {
        case interest, experience, goal

        var title: String {
            switch self {
            case .interest: return "Interests"
            case .experience: return "Experiences"
            case .goal: return "Goals"
            }
        }
    }

    /// Stable identifier, so a fact can be referenced from a talking point.
    var id: String
    var kind: Kind
    var text: String
    /// The user's exact words that support this fact, if it was extracted.
    /// Private — `SharedFact` has no such field.
    var evidence: String?

    init(id: String = "fact-\(UUID().uuidString.prefix(8).lowercased())",
         kind: Kind, text: String, evidence: String? = nil) {
        self.id = id
        self.kind = kind
        self.text = text
        self.evidence = evidence
    }
}

/// An approved fact as a confirmed partner sees it: no evidence, no drafts.
struct SharedFact: Codable, Equatable, Hashable, Identifiable, Sendable {
    var id: String
    var kind: ProfileFact.Kind
    var text: String
}

/// What actually crosses the wire, and only to a confirmed partner.
struct SharedProfile: Codable, Equatable, Hashable, Sendable {
    var displayName: String
    var bio: String
    var interests: [Interest]
    var details: [SharedFact]
    var photo: Data?

    init(displayName: String, bio: String, interests: [Interest], details: [SharedFact] = [], photo: Data? = nil) {
        self.displayName = displayName
        self.bio = bio
        self.interests = interests
        self.details = details
        self.photo = photo
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        displayName = try c.decode(String.self, forKey: .displayName)
        bio = try c.decodeIfPresent(String.self, forKey: .bio) ?? ""
        interests = try c.decodeIfPresent([Interest].self, forKey: .interests) ?? []
        details = try c.decodeIfPresent([SharedFact].self, forKey: .details) ?? []
        photo = try c.decodeIfPresent(Data.self, forKey: .photo)
    }
}

/// One grounded thing two profiles genuinely share.
struct SharedHighlight: Codable, Equatable, Hashable, Identifiable, Sendable {
    var id: String { interestID }
    let interestID: String
    /// Human sentence, e.g. "You both play jazz piano."
    let statement: String
    /// The exact entry from each profile that supports the claim. Evidence, so
    /// nothing is asserted that isn't in both profiles.
    var yourEntry: String
    var theirEntry: String
    /// 2 = specific interest, 1 = broad category.
    let specificity: Int
}

/// Something worth talking about, backed by an approved entry from EACH profile.
struct TalkingPoint: Codable, Equatable, Hashable, Identifiable, Sendable {
    enum Kind: String, Codable, Sendable {
        /// Both people listed the same thing.
        case shared
        /// Related but different things — an opportunity, never a claim of overlap.
        case complementary
    }

    /// The verified candidate this came from. Stable, so both phones agree.
    let id: String
    let kind: Kind
    /// One neutral question for both people. Never says "you" of one person
    /// only, because the partner's phone shows the same text.
    let prompt: String
    var yourEntry: String
    var theirEntry: String
    let source: ConnectionInsight.OpenerSource
}

/// The agreed result of a connection. Generated by exactly one participant and
/// shared, so both phones show the same thing.
struct ConnectionInsight: Codable, Equatable, Hashable, Sendable {
    var highlights: [SharedHighlight]
    var opener: String
    /// How the opener was produced. Surfaced in the UI — a template is never
    /// presented as an AI result.
    var openerSource: OpenerSource
    /// 0–4 grounded talking points. Empty for connections saved before these
    /// existed.
    var talkingPoints: [TalkingPoint]

    init(highlights: [SharedHighlight], opener: String, openerSource: OpenerSource,
         talkingPoints: [TalkingPoint] = []) {
        self.highlights = highlights
        self.opener = opener
        self.openerSource = openerSource
        self.talkingPoints = talkingPoints
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        highlights = try c.decodeIfPresent([SharedHighlight].self, forKey: .highlights) ?? []
        opener = try c.decode(String.self, forKey: .opener)
        openerSource = try c.decode(OpenerSource.self, forKey: .openerSource)
        talkingPoints = try c.decodeIfPresent([TalkingPoint].self, forKey: .talkingPoints) ?? []
    }

    /// The shared talking point for a highlight, if one was written, so the UI
    /// can show them together instead of twice.
    func point(for highlight: SharedHighlight) -> TalkingPoint? {
        talkingPoints.first { $0.id == "shared:\(highlight.interestID)" }
    }

    /// Talking points not already attached to a highlight.
    var unattachedPoints: [TalkingPoint] {
        let attached = Set(highlights.map { "shared:\($0.interestID)" })
        return talkingPoints.filter { !attached.contains($0.id) }
    }

    /// The generator computes "your"/"their" entries from its own side. The
    /// partner flips them on receipt so evidence reads correctly on both phones.
    func mirrored() -> ConnectionInsight {
        var copy = self
        copy.highlights = highlights.map {
            var h = $0; h.yourEntry = $0.theirEntry; h.theirEntry = $0.yourEntry; return h
        }
        copy.talkingPoints = talkingPoints.map {
            var t = $0; t.yourEntry = $0.theirEntry; t.theirEntry = $0.yourEntry; return t
        }
        return copy
    }

    enum OpenerSource: String, Codable, Sendable {
        case onDeviceModel      // Apple Foundation Models, on device
        case grok               // xAI Grok, via the BUMP server, with both people's permission
        case fallbackTemplate   // deterministic, no model involved

        var label: String {
            switch self {
            case .onDeviceModel: return "Written on device by Apple Intelligence"
            case .grok: return "Written by Grok (xAI) via the BUMP server"
            case .fallbackTemplate: return "Suggested question"
            }
        }
    }
}

/// A saved connection. Local only.
struct SavedConnection: Codable, Equatable, Identifiable, Sendable {
    var id: UUID = UUID()
    var partnerName: String
    var partnerBio: String
    /// The partner's card photo, if they had one. Optional, so connections
    /// saved before photos existed still load.
    var partnerPhoto: Data?
    var metOn: Date
    var roomName: String
    var insight: ConnectionInsight
    /// How the two phones were paired. A manual pick is recorded honestly and is
    /// NOT counted as a hardware-detected bump.
    var pairingEvidence: PairingEvidence

    enum PairingEvidence: String, Codable, Sendable {
        case motionOnly
        case motionAndUWB
        case manualSelection

        var label: String {
            switch self {
            case .motionOnly: return "Matched thru motion"
            case .motionAndUWB: return "Matched thru BUMP"
            case .manualSelection: return "Matched thru manual pick"
            }
        }
    }
}

/// Local-only privacy choices. Stored in its own file, never part of `Profile`,
/// so it cannot ride along in `shareable`.
struct PrivacyPreferences: Codable, Equatable, Sendable {
    enum Cloud: String, Codable, Sendable {
        /// Not asked yet — nothing is sent until the user chooses.
        case undecided
        /// The user allowed their intro, answers and (with a partner who also
        /// allowed it) shared interests to be processed by the BUMP server and xAI.
        case allowed
        /// Nothing goes to the BUMP server or xAI.
        case localOnly
    }
    var cloud: Cloud = .undecided

    var allowsCloud: Bool { cloud == .allowed }

    /// "Show what we have in common": nearby phones with this on see only the
    /// broad topics both people share. Off unless the person turns it on.
    /// Optional so older settings files still load.
    var showsCommonGround: Bool?
    var sharesCommonGround: Bool { showsCommonGround ?? false }
}
