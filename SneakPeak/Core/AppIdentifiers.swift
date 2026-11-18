import Foundation

/// Centralized app identifiers - single source of truth for all app-wide identifiers.
enum AppIdentifiers {
    // MARK: - Base Identifier

    static let bundleIdentifier = "com.alzimerahmed.SonicWave"

    // MARK: - iCloud

    static var iCloudContainer: String {
        "iCloud.\(bundleIdentifier)"
    }

    /// CloudKit environment this build is signed for ("Development" or "Production"),
    /// from the `CLOUDKIT_ENV` build setting. Debug builds use Production unless
    /// built with the Debug-CKDev configuration ("SneakPeak (CloudKit Dev)" scheme).
    static var iCloudEnvironment: String {
        Bundle.main.object(forInfoDictionaryKey: "SonicWaveCloudKitEnvironment") as? String ?? "Production"
    }

    static var isCloudKitDevelopmentEnvironment: Bool {
        iCloudEnvironment == "Development"
    }

    // MARK: - Background Tasks

    static var backgroundFeedRefresh: String {
        "\(bundleIdentifier).feedRefresh"
    }

    // MARK: - User Activities (Handoff)

    static var handoffActivityType: String {
        "\(bundleIdentifier).activity"
    }

    // MARK: - URL Sessions

    static let downloadSession = "stream.sonicwave.downloads"

    // MARK: - Logging

    static var logSubsystem: String {
        bundleIdentifier
    }
}
