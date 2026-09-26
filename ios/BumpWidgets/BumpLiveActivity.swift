import ActivityKit
import SwiftUI
import WidgetKit

/// BUMP's Live Activity: Dynamic Island in all three sizes plus the Lock Screen
/// presentation ActivityKit requires.
///
/// This file renders state and nothing else. Every sensor, transport and
/// matching decision lives in the app process; the widget only reads
/// `ContentState` and fires App Intents. A slow interface update can therefore
/// never change a matching outcome.
@available(iOS 17.0, *)
struct BumpLiveActivity: Widget {

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: BumpActivityAttributes.self) { context in
            LockScreenView(context: context)
                .activityBackgroundTint(Brand.ink)
                .activitySystemActionForegroundColor(Brand.blue)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Mark()
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if let expires = context.state.proposalExpiresAt,
                       context.state.needsDecision {
                        // Let the system tick this down. No timer in the app.
                        Text(timerInterval: Date()...expires, countsDown: true)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(Brand.dim)
                            .frame(maxWidth: 52)
                    } else if context.state.nearbyCount > 0, context.state.state == .ready {
                        Label("\(context.state.nearbyCount)", systemImage: "person.2.fill")
                            .font(.caption)
                            .foregroundStyle(Brand.dim)
                    }
                }
                DynamicIslandExpandedRegion(.center) {
                    ExpandedCenter(state: context.state)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    ExpandedActions(attributes: context.attributes, state: context.state)
                }
            } compactLeading: {
                Mark(compact: true)
            } compactTrailing: {
                StatusGlyph(state: context.state.state)
            } minimal: {
                StatusGlyph(state: context.state.state)
            }
            .keylineTint(Brand.blue)
            .widgetURL(deepLink(context.state))
        }
    }

    private func deepLink(_ state: BumpActivityAttributes.ContentState) -> URL? {
        if let id = state.connectionID { return URL(string: "bump://connection/\(id)") }
        return URL(string: "bump://bump")
    }
}

// MARK: - Brand

/// The Dynamic Island surface is always dark, so the warm ivory ground does not
/// apply here. We keep the brand blue and pick text colours that stay legible
/// on black.
@available(iOS 17.0, *)
private enum Brand {
    static let blue = Color(red: 0.451, green: 0.663, blue: 0.961)   // #73A9F5
    static let ink = Color(red: 0.05, green: 0.07, blue: 0.11)
    static let dim = Color.white.opacity(0.62)
    static let good = Color(red: 0.36, green: 0.82, blue: 0.60)
    static let warn = Color(red: 1.0, green: 0.76, blue: 0.35)
}

// MARK: - Pieces

@available(iOS 17.0, *)
private struct Mark: View {
    var compact = false
    var body: some View {
        Text("BUMP")
            .font(.system(size: compact ? 11 : 13, weight: .black).width(.expanded))
            .foregroundStyle(Brand.blue)
            .accessibilityLabel("BUMP")
    }
}

@available(iOS 17.0, *)
private struct StatusGlyph: View {
    let state: BumpActivityState
    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 14, weight: .semibold))
            .foregroundStyle(tint)
            .accessibilityLabel(state.headline)
    }
    private var symbol: String {
        switch state {
        case .preparing, .discovering: return "dot.radiowaves.left.and.right"
        case .ready:                   return "hand.tap.fill"
        case .candidate, .awaitingMe:  return "person.fill.questionmark"
        case .awaitingPeer:            return "hourglass"
        case .connected:               return "checkmark.circle.fill"
        case .paused:                  return "pause.circle"
        case .unavailable:             return "exclamationmark.triangle.fill"
        case .ended:                   return "stop.circle"
        }
    }
    private var tint: Color {
        switch state {
        case .connected: return Brand.good
        case .candidate, .awaitingMe, .unavailable: return Brand.warn
        case .paused, .ended: return Brand.dim
        default: return Brand.blue
        }
    }
}

@available(iOS 17.0, *)
private struct ExpandedCenter: View {
    let state: BumpActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(headline)
                .font(.headline)
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            if let detail {
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(Brand.dim)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var headline: String {
        if state.needsDecision, let name = state.peerName { return "Did you bump with \(name)?" }
        if state.state == .awaitingPeer, let name = state.peerName { return "Waiting for \(name)" }
        return state.state.headline
    }

    private var detail: String? {
        switch state.state {
        case .ready:       return "Bring your phones together."
        case .discovering: return state.nearbyCount > 0
            ? "\(state.nearbyCount) nearby"
            : "Ask them to open BUMP too."
        case .connected:   return "Tap to see what you share."
        case .unavailable: return state.unavailableReason ?? "Open BUMP to reconnect."
        case .paused:      return "BUMP is not listening right now."
        default:           return nil
        }
    }
}

@available(iOS 17.0, *)
private struct ExpandedActions: View {
    let attributes: BumpActivityAttributes
    let state: BumpActivityAttributes.ContentState

    var body: some View {
        if state.needsDecision, let proposalID = state.proposalID {
            HStack(spacing: 8) {
                // LiveActivityIntent runs in the app process, so confirming does
                // not bring the BUMP interface to the foreground.
                Button(intent: ConfirmBumpIntent(sessionID: attributes.sessionID,
                                                 proposalID: proposalID)) {
                    Label("Confirm", systemImage: "checkmark")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .tint(Brand.blue)

                Button(intent: RejectBumpIntent(sessionID: attributes.sessionID,
                                                proposalID: proposalID)) {
                    Label("Not them", systemImage: "xmark")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .tint(Color.white.opacity(0.18))
            }
            .buttonStyle(.borderedProminent)
        } else if state.state == .connected {
            Link(destination: URL(string: "bump://connection/\(state.connectionID ?? "")")!) {
                Label("See what you share", systemImage: "arrow.up.right")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
        } else if state.state == .unavailable {
            Link(destination: URL(string: "bump://bump")!) {
                Label("Open BUMP", systemImage: "arrow.up.right")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
        } else if state.state != .ended {
            Button(intent: StopBumpIntent(sessionID: attributes.sessionID)) {
                Text("Stop")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .tint(Brand.dim)
        }
    }
}

// MARK: - Lock Screen

@available(iOS 17.0, *)
private struct LockScreenView: View {
    let context: ActivityViewContext<BumpActivityAttributes>

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Mark()
                ExpandedCenter(state: context.state)
            }
            Spacer(minLength: 0)
            StatusGlyph(state: context.state.state)
                .font(.title2)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .overlay(alignment: .bottom) {
            if context.state.needsDecision {
                ExpandedActions(attributes: context.attributes, state: context.state)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 10)
            }
        }
    }
}
