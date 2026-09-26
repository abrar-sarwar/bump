import SwiftUI

/// Clearly labelled instrument panel. Deliberately kept OUT of the normal user
/// flow — no raw sensor numbers appear on the Bump screen.
struct TestingToolsScreen: View {
    @ObservedObject var engine: BumpEngine
    @ObservedObject var store: Store

    @State private var shareItem: ShareItem?
    @State private var confirmingReset = false

    var body: some View {
        Screen {
            VStack(alignment: .leading, spacing: Space.l) {

                Card {
                    VStack(alignment: .leading, spacing: Space.xs) {
                        Text("Testing tools")
                            .font(BumpFont.sectionTitle)
                            .foregroundStyle(BumpColor.navy)
                        Text("Engineering instrumentation for tuning on real phones. Values here are live sensor readings, not part of the normal BUMP experience.")
                            .font(BumpFont.caption)
                            .foregroundStyle(BumpColor.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                // MARK: Mode
                SectionHeading(title: "Detection mode",
                               subtitle: "Combined uses motion as the gesture and fresh UWB as evidence about which peer.")
                Picker("Detection mode", selection: $store.settings.detectionMode) {
                    ForEach(Store.Settings.DetectionMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .onChange(of: store.settings.detectionMode) { _, _ in engine.applySettings() }

                // MARK: Server
                ServerSettingsSection(store: store, engine: engine)

                // MARK: Motion
                SectionHeading(title: "Motion")
                Card {
                    VStack(alignment: .leading, spacing: Space.s) {
                        metric("Live |acceleration|", String(format: "%.2f m/s²", engine.motion.currentMagnitude))
                        metric("Last spike", engine.motion.lastSpikeMagnitude.map { String(format: "%.2f m/s²", $0) } ?? "none")
                        metric("Source", "CMDeviceMotion.userAcceleration (g → m/s² × \(String(format: "%.3f", MotionDetector.G)))")
                        metric("Sensing", engine.motion.isRunning ? "running" : "stopped")
                    }
                }
                slider("Motion threshold", value: $store.settings.motionThreshold,
                       range: 5...60, step: 0.5, unit: "m/s²")
                slider("Motion cooldown", value: $store.settings.motionCooldown,
                       range: 0.2...5, step: 0.1, unit: "s")

                // MARK: UWB
                SectionHeading(title: "Ultra-wideband")
                Card {
                    VStack(alignment: .leading, spacing: Space.s) {
                        metric("Hardware", engine.ranging.isSupported ? "supported" : (engine.ranging.unsupportedReason ?? "unsupported"))
                        metric("Direction capability", engine.ranging.supportsDirection ? "supported" : "not supported")
                        metric("Active sessions", "\(engine.ranging.measurements.count) (cap \(RangingService.maxConcurrentPeers))")
                        if engine.ranging.measurements.isEmpty {
                            Text("No live measurements.")
                                .font(BumpFont.caption)
                                .foregroundStyle(BumpColor.secondaryText)
                        }
                        ForEach(engine.ranging.measurements.keys.sorted(), id: \.self) { peer in
                            if let m = engine.ranging.measurements[peer] {
                                Divider()
                                metric(engine.transport.displayName(of: peer),
                                       m.distance.map { String(format: "%.2f m", $0) } ?? "distance unavailable")
                                metric("  direction", m.direction != nil ? "available" : "unavailable")
                                metric("  measurement age", String(format: "%.1f s", m.age))
                            }
                        }
                    }
                }
                slider("UWB proximity threshold", value: $store.settings.uwbProximity,
                       range: 0.05...1.0, step: 0.01, unit: "m")
                slider("Measurement freshness limit", value: $store.settings.uwbFreshness,
                       range: 0.3...5, step: 0.1, unit: "s")

                // MARK: Pairing
                SectionHeading(title: "Pairing",
                               subtitle: "Coordinator-side. Arrival times are stamped on the host's monotonic clock; phone clocks are never subtracted from each other.")
                Card {
                    VStack(alignment: .leading, spacing: Space.s) {
                        metric("Role", engine.isCoordinator ? "coordinator" : "guest")
                        metric("Room", engine.room.code ?? "none")
                        metric("Peers connected", "\(engine.transport.connected.count) (cap \(PeerTransport.maxPeers - 1) guests)")
                        metric("Phase", String(describing: engine.phase))
                    }
                }
                slider("Pairing window", value: $store.settings.pairingWindow,
                       range: 0.1...1.5, step: 0.05, unit: "s")
                slider("Ambiguity margin", value: $store.settings.ambiguityMargin,
                       range: 0.01...0.3, step: 0.01, unit: "s")
                slider("Buffer before committing", value: $store.settings.pairingBuffer,
                       range: 0.05...0.8, step: 0.05, unit: "s")

                // MARK: Log
                SectionHeading(title: "Event log", subtitle: "Newest first, capped at 200 lines.")
                Card {
                    VStack(alignment: .leading, spacing: 3) {
                        if engine.log.isEmpty {
                            Text("Nothing logged yet.")
                                .font(BumpFont.caption)
                                .foregroundStyle(BumpColor.secondaryText)
                        }
                        ForEach(engine.log.prefix(60)) { line in
                            Text("\(line.at.formatted(date: .omitted, time: .standard))  \(line.text)")
                                .font(BumpFont.mono)
                                .foregroundStyle(BumpColor.navy)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }

                VStack(spacing: Space.s) {
                    Button("Export diagnostics") { shareItem = ShareItem(text: diagnosticsReport()) }
                        .buttonStyle(.bumpPrimary)
                    Button("Reset sensors & reconnect") {
                        engine.leaveRoom()
                        engine.applySettings()
                    }
                    .buttonStyle(.bumpSecondary)
                    Button("Clear log") { engine.clearLog() }
                        .buttonStyle(.bumpSecondary)
                    Button("Reset onboarding", role: .destructive) { confirmingReset = true }
                        .buttonStyle(.bumpSecondary)
                        .confirmationDialog("Reset onboarding?", isPresented: $confirmingReset, titleVisibility: .visible) {
                            Button("Reset and start over", role: .destructive) {
                                engine.leaveRoom()
                                store.resetOnboarding()
                            }
                            Button("Cancel", role: .cancel) {}
                        } message: {
                            Text("Clears your name, card and cloud-processing choice, then restarts onboarding. Saved connections and server settings are kept.")
                        }
                }
            }
        }
        .navigationTitle("Testing tools")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: store.settings) { _, _ in engine.applySettings() }
        .sheet(item: $shareItem) { item in
            ShareSheet(text: item.text)
        }
    }

    // MARK: Pieces

    private func metric(_ label: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(label)
                .font(BumpFont.caption)
                .foregroundStyle(BumpColor.secondaryText)
            Spacer(minLength: Space.s)
            Text(value)
                .font(BumpFont.mono)
                .foregroundStyle(BumpColor.navy)
                .multilineTextAlignment(.trailing)
        }
        .accessibilityElement(children: .combine)
    }

    private func slider(_ label: String, value: Binding<Double>,
                        range: ClosedRange<Double>, step: Double, unit: String) -> some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            HStack {
                Text(label).font(BumpFont.caption).foregroundStyle(BumpColor.secondaryText)
                Spacer()
                Text("\(value.wrappedValue, specifier: step < 0.05 ? "%.2f" : "%.1f") \(unit)")
                    .font(BumpFont.mono).foregroundStyle(BumpColor.navy)
            }
            Slider(value: value, in: range, step: step)
                .tint(BumpColor.action)
                .accessibilityLabel(label)
                .accessibilityValue("\(value.wrappedValue) \(unit)")
        }
    }

    /// Diagnostics deliberately exclude profile content, interests, bios and any
    /// raw discovery tokens. Peer names are reduced to their transient suffix.
    private func diagnosticsReport() -> String {
        var out = ["BUMP diagnostics", "generated \(Date().formatted(date: .abbreviated, time: .standard))", ""]
        out.append("device: \(UIDevice.current.model), iOS \(UIDevice.current.systemVersion)")
        out.append("role: \(engine.isCoordinator ? "coordinator" : "guest")")
        out.append("room: \(engine.room.code == nil ? "none" : "set")")
        out.append("peers connected: \(engine.transport.connected.count)")
        out.append("uwb supported: \(engine.ranging.isSupported), direction: \(engine.ranging.supportsDirection)")
        out.append("on-device AI: \(ConversationService.onDeviceModelAvailable)")
        out.append("")
        out.append("settings:")
        out.append("  mode: \(store.settings.detectionMode.rawValue)")
        out.append(String(format: "  motion threshold: %.2f m/s^2", store.settings.motionThreshold))
        out.append(String(format: "  motion cooldown: %.2f s", store.settings.motionCooldown))
        out.append(String(format: "  pairing window: %.3f s", store.settings.pairingWindow))
        out.append(String(format: "  ambiguity margin: %.3f s", store.settings.ambiguityMargin))
        out.append(String(format: "  buffer: %.3f s", store.settings.pairingBuffer))
        out.append(String(format: "  uwb proximity: %.3f m", store.settings.uwbProximity))
        out.append(String(format: "  uwb freshness: %.2f s", store.settings.uwbFreshness))
        out.append("")
        out.append("log (newest first):")
        for line in engine.log.prefix(120) {
            out.append("  \(line.at.formatted(date: .omitted, time: .standard))  \(line.text)")
        }
        return out.joined(separator: "\n")
    }
}

struct ShareItem: Identifiable { let id = UUID(); let text: String }

struct ShareSheet: UIViewControllerRepresentable {
    let text: String
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [text], applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
