//
//  ChannelNotificationSettings.swift
//  SneakPeak
//
//  SwiftData model for per-channel notification preferences.
//  These settings are synced via iCloud independently of the subscription source.
//

import Foundation
import SwiftData

/// Per-channel notification rule, applied when a channel has notifications enabled.
enum ChannelNotificationRule: String, Codable, Sendable, CaseIterable, Identifiable {
    /// Notify on every new video.
    case all
    /// Notify only when the new video is a livestream.
    case livestreamsOnly
    /// No per-video alerts; one summary notification per background refresh.
    case digest

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .all: String(localized: "channel.notificationRule.all")
        case .livestreamsOnly: String(localized: "channel.notificationRule.livestreamsOnly")
        case .digest: String(localized: "channel.notificationRule.digest")
        }
    }

    var systemImage: String {
        switch self {
        case .all: "bell"
        case .livestreamsOnly: "dot.radiowaves.left.and.right"
        case .digest: "bell.badge"
        }
    }

    /// Whether a standard (non-digest) notification may fire for this video.
    /// Digest channels are summarized separately by the caller.
    func allowsNotification(for video: Video) -> Bool {
        switch self {
        case .all:
            true
        case .livestreamsOnly:
            video.isLive
        case .digest:
            false
        }
    }
}

/// Stores notification preferences for a channel.
/// This is separate from subscriptions so notification settings persist
/// across subscription account changes (local vs Invidious).
@Model
final class ChannelNotificationSettings {
    // MARK: - Properties

    /// The channel ID this setting applies to.
    @Attribute(.unique) var channelID: String = ""

    /// Whether notifications are enabled for this channel.
    var notificationsEnabled: Bool = false

    /// The notification rule applied when notifications are enabled.
    var ruleRawValue: String = ChannelNotificationRule.all.rawValue

    /// The parsed notification rule (falls back to `.all` for unknown values).
    var rule: ChannelNotificationRule {
        get { ChannelNotificationRule(rawValue: ruleRawValue) ?? .all }
        set { ruleRawValue = newValue.rawValue }
    }

    /// When this setting was last updated.
    var updatedAt: Date = Date()

    /// Source type: "global", "federated", or "extracted".
    var sourceRawValue: String = "global"

    /// Instance URL for federated sources.
    var instanceURLString: String?

    /// Provider name for global sources (e.g. "youtube").
    var globalProvider: String?

    // MARK: - Initialization

    init(
        channelID: String,
        notificationsEnabled: Bool = false,
        sourceRawValue: String = "global",
        instanceURLString: String? = nil,
        globalProvider: String? = nil
    ) {
        self.channelID = channelID
        self.notificationsEnabled = notificationsEnabled
        self.updatedAt = Date()
        self.sourceRawValue = sourceRawValue
        self.instanceURLString = instanceURLString
        self.globalProvider = globalProvider
    }

    // MARK: - Methods

    /// Updates the notifications enabled state and timestamp.
    func setNotificationsEnabled(_ enabled: Bool) {
        notificationsEnabled = enabled
        updatedAt = Date()
    }

    /// Updates the notification rule and timestamp.
    func setRule(_ newRule: ChannelNotificationRule) {
        rule = newRule
        updatedAt = Date()
    }
}
