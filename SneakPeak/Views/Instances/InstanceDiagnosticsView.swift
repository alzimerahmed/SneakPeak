//
//  InstanceDiagnosticsView.swift
//  SneakPeak
//
//  Connection health & diagnostics screen (G3): per-instance probe with
//  latency, health state, and the static capability table.
//

import SwiftUI

struct InstanceDiagnosticsView: View {
    @Environment(\.appEnvironment) private var appEnvironment
    @State private var states: [UUID: InstanceHealthState] = [:]
    @State private var isProbing = false

    private var instances: [Instance] {
        (appEnvironment?.instancesManager?.instances ?? [])
            .sorted { $0.dateAdded < $1.dateAdded }
    }

    var body: some View {
        Group {
            if instances.isEmpty {
                ContentUnavailableView(
                    String(localized: "diagnostics.empty.title"),
                    systemImage: "server.rack",
                    description: Text(String(localized: "diagnostics.empty.description"))
                )
            } else {
                probeList
            }
        }
        #if !os(tvOS)
        .navigationTitle(String(localized: "diagnostics.title"))
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .task { await probeAll() }
    }

    // MARK: - List

    private var probeList: some View {
        List {
            Section {
                Button {
                    Task { await probeAll() }
                } label: {
                    Label(
                        String(localized: "diagnostics.probeAgain"),
                        systemImage: "arrow.clockwise"
                    )
                }
                .disabled(isProbing)
                .accessibilityIdentifier("diagnostics.probeAgain")
            }

            Section {
                ForEach(instances) { instance in
                    instanceRow(instance)
                }
            }
        }
    }

    // MARK: - Row

    private func instanceRow(_ instance: Instance) -> some View {
        let state = states[instance.id] ?? .unknown
        return HStack(alignment: .top, spacing: 12) {
            Image(systemName: state.systemImage)
                .foregroundStyle(state.color)
                .font(.title3)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(instance.displayName)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    if !instance.isEnabled {
                        Text(String(localized: "sources.status.disabled"))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(.quaternary)
                            .clipShape(Capsule())
                    }
                }

                Text("\(instance.type.displayName) - \(instance.displayURL)")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Text(state.label)
                    .font(.subheadline)
                    .foregroundStyle(state.color)

                Text(capabilitiesText(for: instance))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel(for: instance, state: state))
    }

    /// Static capability summary from the per-type capability table — what
    /// this backend can do once it is reachable. No network involved.
    private func capabilitiesText(for instance: Instance) -> String {
        var capabilities: [String] = []
        if instance.supportsFeed { capabilities.append(String(localized: "diagnostics.cap.feed")) }
        if instance.supportsAuthentication { capabilities.append(String(localized: "diagnostics.cap.accounts")) }
        if instance.supportsSearchFilters { capabilities.append(String(localized: "diagnostics.cap.searchFilters")) }
        if instance.supportsSuggestions { capabilities.append(String(localized: "diagnostics.cap.suggestions")) }
        if instance.supportsPopular { capabilities.append(String(localized: "diagnostics.cap.popular")) }
        if instance.supportsVideoProxying { capabilities.append(String(localized: "diagnostics.cap.proxying")) }
        return String(localized: "diagnostics.capabilities \(capabilities.joined(separator: ", "))")
    }

    private func accessibilityLabel(for instance: Instance, state: InstanceHealthState) -> String {
        String(localized: "diagnostics.row.a11y \(instance.displayName) \(state.label)")
    }

    // MARK: - Probing

    /// Probes every instance concurrently. Detectors are resolved on the
    /// main actor first (per-instance invalid-certificate clients), then the
    /// actor-isolated probes run in parallel.
    private func probeAll() async {
        guard let appEnvironment, !instances.isEmpty else { return }

        let targets: [(instance: Instance, detector: InstanceDetector)] = instances.map { instance in
            let detector: InstanceDetector
            if instance.allowInvalidCertificates {
                detector = InstanceDetector(
                    httpClient: appEnvironment.httpClientFactory.createClient(allowInvalidCertificates: true)
                )
            } else {
                detector = appEnvironment.instanceDetector
            }
            return (instance, detector)
        }

        for (instance, _) in targets {
            states[instance.id] = .probing
        }
        isProbing = true
        defer { isProbing = false }

        await withTaskGroup(of: (UUID, InstanceHealthState).self) { group in
            for (instance, detector) in targets {
                group.addTask {
                    let probe = await detector.probeHealth(url: instance.url, type: instance.type)
                    return (instance.id, InstanceHealthState.classify(probe))
                }
            }
            for await (id, state) in group {
                states[id] = state
            }
        }
    }
}

// MARK: - State Presentation

extension InstanceHealthState {
    var systemImage: String {
        switch self {
        case .unknown: return "circle.dashed"
        case .probing: return "ellipsis.circle"
        case .healthy: return "checkmark.circle.fill"
        case .degraded: return "exclamationmark.triangle.fill"
        case .unreachable: return "xmark.octagon.fill"
        }
    }

    var color: Color {
        switch self {
        case .unknown: return .secondary
        case .probing: return .blue
        case .healthy: return .green
        case .degraded: return .orange
        case .unreachable: return .red
        }
    }

    var label: String {
        switch self {
        case .unknown:
            return String(localized: "diagnostics.state.unknown")
        case .probing:
            return String(localized: "diagnostics.state.probing")
        case .healthy(let latency):
            return String(localized: "diagnostics.state.healthy \(Self.latencyText(latency))")
        case .degraded(let latency):
            return String(localized: "diagnostics.state.degraded \(Self.latencyText(latency))")
        case .unreachable(let message):
            return String(localized: "diagnostics.state.unreachable \(message)")
        }
    }

    private static func latencyText(_ latency: TimeInterval) -> String {
        let milliseconds = Int((latency * 1000).rounded())
        return String(localized: "diagnostics.latency.ms \(milliseconds)")
    }
}
