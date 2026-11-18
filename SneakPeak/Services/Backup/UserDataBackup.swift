//
//  UserDataBackup.swift
//  SneakPeak
//
//  JSON export/import of all user data (G7): subscriptions, watch history,
//  bookmarks, local playlists, per-channel notification rules, media sources
//  and user settings. Credentials are never exported.
//

import Foundation

// MARK: - JSON Value

/// Type-erased Codable JSON value, used for the settings dictionary.
enum JSONValue: Codable, Hashable, Sendable {
    case null
    case bool(Bool)
    case int(Int)
    case double(Double)
    case string(String)
    case array([JSONValue])
    case dictionary([String: JSONValue])

    init(any value: Any) {
        switch value {
        case is NSNull:
            self = .null
        case let number as NSNumber:
            // Distinguish Bool from other numbers: CFBoolean is its own
            // CoreFoundation type, so the type ID is exact (a bridged Int
            // would also pass `as? Bool` for 0/1).
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                self = .bool(number.boolValue)
            } else if number.denominator == 1 {
                self = .int(number.intValue)
            } else {
                self = .double(number.doubleValue)
            }
        case let string as String:
            self = .string(string)
        case let date as Date:
            self = .double(date.timeIntervalSince1970)
        case let array as [Any]:
            self = .array(array.map { JSONValue(any: $0) })
        case let dict as [String: Any]:
            self = .dictionary(dict.mapValues { JSONValue(any: $0) })
        default:
            self = .null
        }
    }

    /// The Foundation object this value round-trips into for UserDefaults.
    var object: Any? {
        switch self {
        case .null:
            nil
        case .bool(let value):
            value
        case .int(let value):
            value
        case .double(let value):
            value
        case .string(let value):
            value
        case .array(let values):
            values.compactMap(\.object)
        case .dictionary(let values):
            values.compactMapValues(\.object)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int.self) {
            self = .int(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else if let value = try? container.decode([String: JSONValue].self) {
            self = .dictionary(value)
        } else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Unsupported JSON value"
            )
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null:
            try container.encodeNil()
        case .bool(let value):
            try container.encode(value)
        case .int(let value):
            try container.encode(value)
        case .double(let value):
            try container.encode(value)
        case .string(let value):
            try container.encode(value)
        case .array(let value):
            try container.encode(value)
        case .dictionary(let value):
            try container.encode(value)
        }
    }
}

// MARK: - Export Payload

/// The versioned export document. Field additions must keep decoding of older
/// files working: new properties need defaults.
struct UserDataBackup: Codable {
    /// Current schema version of the export format.
    static let currentSchemaVersion = 1

    var schemaVersion: Int = UserDataBackup.currentSchemaVersion
    var exportedAt: Date = Date()
    var subscriptions: [SubscriptionExport] = []
    var watchHistory: [WatchEntryExport] = []
    var bookmarks: [BookmarkExport] = []
    var playlists: [LocalPlaylistExport] = []
    var channelNotificationSettings: [ChannelNotificationSettingsExport] = []
    var mediaSources: [MediaSourceExport] = []
    /// User settings keyed by `SettingsKey` raw value.
    var settings: [String: JSONValue] = [:]
}

// MARK: - Per-Model Export Structs

struct WatchEntryExport: Codable {
    let videoID: String
    let sourceRawValue: String
    let globalProvider: String?
    let instanceURLString: String?
    let peertubeUUID: String?
    let externalExtractor: String?
    let externalURLString: String?
    let title: String
    let authorName: String
    let authorID: String
    let duration: TimeInterval
    let thumbnailURLString: String?
    let isLive: Bool
    let watchedSeconds: TimeInterval
    let isFinished: Bool
    let createdAt: Date
    let updatedAt: Date

    init(from entry: WatchEntry) {
        self.videoID = entry.videoID
        self.sourceRawValue = entry.sourceRawValue
        self.globalProvider = entry.globalProvider
        self.instanceURLString = entry.instanceURLString
        self.peertubeUUID = entry.peertubeUUID
        self.externalExtractor = entry.externalExtractor
        self.externalURLString = entry.externalURLString
        self.title = entry.title
        self.authorName = entry.authorName
        self.authorID = entry.authorID
        self.duration = entry.duration
        self.thumbnailURLString = entry.thumbnailURLString
        self.isLive = entry.isLive
        self.watchedSeconds = entry.watchedSeconds
        self.isFinished = entry.isFinished
        self.createdAt = entry.createdAt
        self.updatedAt = entry.updatedAt
    }

    func toWatchEntry() -> WatchEntry {
        let entry = WatchEntry(
            videoID: videoID,
            sourceRawValue: sourceRawValue,
            globalProvider: globalProvider,
            instanceURLString: instanceURLString,
            peertubeUUID: peertubeUUID,
            externalExtractor: externalExtractor,
            externalURLString: externalURLString,
            title: title,
            authorName: authorName,
            authorID: authorID,
            duration: duration,
            thumbnailURLString: thumbnailURLString,
            watchedSeconds: watchedSeconds,
            isFinished: isFinished,
            isLive: isLive
        )
        entry.createdAt = createdAt
        entry.updatedAt = updatedAt
        return entry
    }
}

struct BookmarkExport: Codable {
    let videoID: String
    let sourceRawValue: String
    let globalProvider: String?
    let instanceURLString: String?
    let peertubeUUID: String?
    let externalExtractor: String?
    let externalURLString: String?
    let title: String
    let authorName: String
    let authorID: String
    let duration: TimeInterval
    let thumbnailURLString: String?
    let isLive: Bool
    let viewCount: Int?
    let publishedAt: Date?
    let publishedText: String?
    let note: String?
    let tags: [String]
    let createdAt: Date

    init(from bookmark: Bookmark) {
        self.videoID = bookmark.videoID
        self.sourceRawValue = bookmark.sourceRawValue
        self.globalProvider = bookmark.globalProvider
        self.instanceURLString = bookmark.instanceURLString
        self.peertubeUUID = bookmark.peertubeUUID
        self.externalExtractor = bookmark.externalExtractor
        self.externalURLString = bookmark.externalURLString
        self.title = bookmark.title
        self.authorName = bookmark.authorName
        self.authorID = bookmark.authorID
        self.duration = bookmark.duration
        self.thumbnailURLString = bookmark.thumbnailURLString
        self.isLive = bookmark.isLive
        self.viewCount = bookmark.viewCount
        self.publishedAt = bookmark.publishedAt
        self.publishedText = bookmark.publishedText
        self.note = bookmark.note
        self.tags = bookmark.tags
        self.createdAt = bookmark.createdAt
    }

    func toBookmark() -> Bookmark {
        let bookmark = Bookmark(
            videoID: videoID,
            sourceRawValue: sourceRawValue,
            globalProvider: globalProvider,
            instanceURLString: instanceURLString,
            peertubeUUID: peertubeUUID,
            externalExtractor: externalExtractor,
            externalURLString: externalURLString,
            title: title,
            authorName: authorName,
            authorID: authorID,
            duration: duration,
            thumbnailURLString: thumbnailURLString,
            isLive: isLive,
            viewCount: viewCount,
            publishedAt: publishedAt,
            publishedText: publishedText,
            note: note,
            tags: tags
        )
        bookmark.createdAt = createdAt
        return bookmark
    }
}

struct LocalPlaylistExport: Codable {
    let id: UUID
    let title: String
    let playlistDescription: String?
    let createdAt: Date
    let updatedAt: Date
    let items: [LocalPlaylistItemExport]

    init(from playlist: LocalPlaylist) {
        self.id = playlist.id
        self.title = playlist.title
        self.playlistDescription = playlist.playlistDescription
        self.createdAt = playlist.createdAt
        self.updatedAt = playlist.updatedAt
        self.items = playlist.sortedItems.map { LocalPlaylistItemExport(from: $0) }
    }
}

struct LocalPlaylistItemExport: Codable {
    let id: UUID
    let sortOrder: Int
    let videoID: String
    let sourceRawValue: String
    let globalProvider: String?
    let instanceURLString: String?
    let peertubeUUID: String?
    let externalExtractor: String?
    let externalURLString: String?
    let title: String
    let authorName: String
    let authorID: String
    let duration: TimeInterval
    let thumbnailURLString: String?
    let isLive: Bool
    let addedAt: Date

    init(from item: LocalPlaylistItem) {
        self.id = item.id
        self.sortOrder = item.sortOrder
        self.videoID = item.videoID
        self.sourceRawValue = item.sourceRawValue
        self.globalProvider = item.globalProvider
        self.instanceURLString = item.instanceURLString
        self.peertubeUUID = item.peertubeUUID
        self.externalExtractor = item.externalExtractor
        self.externalURLString = item.externalURLString
        self.title = item.title
        self.authorName = item.authorName
        self.authorID = item.authorID
        self.duration = item.duration
        self.thumbnailURLString = item.thumbnailURLString
        self.isLive = item.isLive
        self.addedAt = item.addedAt
    }

    func toPlaylistItem() -> LocalPlaylistItem {
        let item = LocalPlaylistItem(
            id: id,
            sortOrder: sortOrder,
            videoID: videoID,
            sourceRawValue: sourceRawValue,
            globalProvider: globalProvider,
            instanceURLString: instanceURLString,
            peertubeUUID: peertubeUUID,
            externalExtractor: externalExtractor,
            externalURLString: externalURLString,
            title: title,
            authorName: authorName,
            authorID: authorID,
            duration: duration,
            thumbnailURLString: thumbnailURLString,
            isLive: isLive
        )
        item.addedAt = addedAt
        return item
    }
}

struct ChannelNotificationSettingsExport: Codable {
    let channelID: String
    let notificationsEnabled: Bool
    let ruleRawValue: String
    let updatedAt: Date
    let sourceRawValue: String
    let instanceURLString: String?
    let globalProvider: String?

    init(from settings: ChannelNotificationSettings) {
        self.channelID = settings.channelID
        self.notificationsEnabled = settings.notificationsEnabled
        self.ruleRawValue = settings.ruleRawValue
        self.updatedAt = settings.updatedAt
        self.sourceRawValue = settings.sourceRawValue
        self.instanceURLString = settings.instanceURLString
        self.globalProvider = settings.globalProvider
    }

    func toChannelNotificationSettings() -> ChannelNotificationSettings {
        let settings = ChannelNotificationSettings(
            channelID: channelID,
            notificationsEnabled: notificationsEnabled,
            sourceRawValue: sourceRawValue,
            instanceURLString: instanceURLString,
            globalProvider: globalProvider
        )
        settings.ruleRawValue = ruleRawValue
        settings.updatedAt = updatedAt
        return settings
    }
}

// MARK: - Service

/// Builds and applies `UserDataBackup` documents.
@MainActor
final class UserDataBackupService {
    /// Summary of one import pass.
    struct ImportSummary {
        var subscriptions: Int = 0
        var watchEntries: Int = 0
        var bookmarks: Int = 0
        var playlists: Int = 0
        var notificationSettings: Int = 0
        var mediaSources: Int = 0
        var settings: Int = 0
    }

    private let dataManager: DataManager
    private let defaults: UserDefaults
    private let mediaSourcesManager: MediaSourcesManager?

    init(
        dataManager: DataManager,
        defaults: UserDefaults = .standard,
        mediaSourcesManager: MediaSourcesManager? = nil
    ) {
        self.dataManager = dataManager
        self.defaults = defaults
        self.mediaSourcesManager = mediaSourcesManager
    }

    // MARK: Export

    /// Builds the backup document from current local state.
    func makeBackup() -> UserDataBackup {
        var backup = UserDataBackup()
        backup.subscriptions = dataManager.subscriptions().map(SubscriptionExport.init)
        backup.watchHistory = dataManager.allWatchEntries().map(WatchEntryExport.init)
        backup.bookmarks = dataManager.allBookmarks().map(BookmarkExport.init)
        backup.playlists = dataManager.playlists().map(LocalPlaylistExport.init)
        backup.channelNotificationSettings = dataManager.allChannelNotificationSettings()
            .map(ChannelNotificationSettingsExport.init)
        backup.mediaSources = mediaSourcesManager?.sources
            .filter { $0.type != .localFolder } // device-specific, never portable
            .map(MediaSourceExport.init) ?? []
        backup.settings = settingsSnapshot()
        return backup
    }

    /// Encodes the backup to pretty-printed JSON.
    func exportData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(makeBackup())
    }

    /// Snapshot of user-controlled settings stored in UserDefaults.
    /// Only keys owned by `SettingsKey` are taken — system keys are left alone.
    private func settingsSnapshot() -> [String: JSONValue] {
        let all = defaults.dictionaryRepresentation()
        let ownedKeys = Set(SettingsKey.allCases.map(\.rawValue))
        return all
            .filter { ownedKeys.contains($0.key) }
            .mapValues { JSONValue(any: $0) }
    }

    // MARK: Import

    /// Decodes and applies a backup. Existing records are kept; imported
    /// records that would duplicate an existing one (same source scope) are
    /// skipped, so importing twice is safe.
    func importData(_ data: Data) throws -> ImportSummary {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let backup = try decoder.decode(UserDataBackup.self, from: data)

        guard backup.schemaVersion <= UserDataBackup.currentSchemaVersion else {
            throw BackupError.unsupportedSchemaVersion(backup.schemaVersion)
        }

        var summary = ImportSummary()

        // Snapshot existing keys up front so each record is a Set lookup
        // instead of a per-record fetch + save (O(n) instead of O(n²) on the
        // main actor). One save() per section.
        let scopeSuffix: (String, String?, String?, String?) -> String = {
            SourceScope.from(
                sourceRawValue: $0,
                globalProvider: $1,
                instanceURLString: $2,
                externalExtractor: $3
            ).recordNameSuffix
        }

        let existingSubscriptionKeys = Set(
            dataManager.subscriptions().map {
                "\($0.channelID)|\(scopeSuffix($0.sourceRawValue, $0.providerName, $0.instanceURLString, nil))"
            }
        )
        var insertedSubscriptions: [Subscription] = []
        for export in backup.subscriptions {
            // Imported subscriptions have no providerName, so the scope key
            // must match what the inserted entity will derive (nil provider).
            let key = "\(export.channelID)|\(scopeSuffix(export.sourceRawValue, nil, export.instanceURLString, nil))"
            guard !existingSubscriptionKeys.contains(key) else { continue }
            existingSubscriptionKeys.insert(key)
            let subscription = Subscription(
                channelID: export.channelID,
                sourceRawValue: export.sourceRawValue,
                instanceURLString: export.instanceURLString,
                name: export.name,
                channelDescription: export.channelDescription,
                subscriberCount: export.subscriberCount,
                avatarURLString: export.avatarURLString,
                bannerURLString: export.bannerURLString,
                isVerified: export.isVerified,
                channelURLString: nil
            )
            dataManager.modelContext.insert(subscription)
            insertedSubscriptions.append(subscription)
            summary.subscriptions += 1
        }
        if !insertedSubscriptions.isEmpty {
            for subscription in insertedSubscriptions {
                dataManager.cloudKitSync?.queueSubscriptionSave(subscription)
            }
            dataManager.save()
        }

        let existingWatchKeys = Set(
            dataManager.allWatchEntries().map {
                "\($0.videoID)|\(scopeSuffix($0.sourceRawValue, $0.globalProvider, $0.instanceURLString, $0.externalExtractor))"
            }
        )
        var insertedWatchEntries: [WatchEntry] = []
        for export in backup.watchHistory {
            let key = "\(export.videoID)|\(scopeSuffix(export.sourceRawValue, export.globalProvider, export.instanceURLString, export.externalExtractor))"
            guard !existingWatchKeys.contains(key) else { continue }
            existingWatchKeys.insert(key)
            let entry = export.toWatchEntry()
            dataManager.modelContext.insert(entry)
            insertedWatchEntries.append(entry)
            summary.watchEntries += 1
        }
        if !insertedWatchEntries.isEmpty {
            for entry in insertedWatchEntries {
                dataManager.cloudKitSync?.queueWatchEntrySave(entry)
            }
            dataManager.save()
            TopShelfSnapshotWriter.writeContinueWatching(dataManager: dataManager)
        }

        let existingBookmarkKeys = Set(
            dataManager.allBookmarks().map {
                "\($0.videoID)|\(scopeSuffix($0.sourceRawValue, $0.globalProvider, $0.instanceURLString, $0.externalExtractor))"
            }
        )
        var insertedBookmarks: [Bookmark] = []
        for export in backup.bookmarks {
            let key = "\(export.videoID)|\(scopeSuffix(export.sourceRawValue, export.globalProvider, export.instanceURLString, export.externalExtractor))"
            guard !existingBookmarkKeys.contains(key) else { continue }
            existingBookmarkKeys.insert(key)
            let bookmark = export.toBookmark()
            dataManager.modelContext.insert(bookmark)
            dataManager.cachedBookmarkedVideoIDs.insert(bookmark.videoID)
            insertedBookmarks.append(bookmark)
            summary.bookmarks += 1
        }
        if !insertedBookmarks.isEmpty {
            for bookmark in insertedBookmarks {
                dataManager.cloudKitSync?.queueBookmarkSave(bookmark)
            }
            dataManager.save()
            TopShelfSnapshotWriter.writeBookmarks(dataManager: dataManager)
        }

        let existingPlaylistIDs = Set(dataManager.playlists().map(\.id))
        for export in backup.playlists {
            // Skip playlists that already exist (same id) so re-importing a
            // backup never duplicates playlists or their items.
            guard !existingPlaylistIDs.contains(export.id) else { continue }
            existingPlaylistIDs.insert(export.id)
            let playlist = LocalPlaylist(
                id: export.id,
                title: export.title,
                description: export.playlistDescription
            )
            playlist.createdAt = export.createdAt
            playlist.updatedAt = export.updatedAt
            dataManager.modelContext.insert(playlist)
            summary.playlists += 1
            for itemExport in export.items {
                let item = itemExport.toPlaylistItem()
                item.playlist = playlist
                dataManager.modelContext.insert(item)
            }
            dataManager.cloudKitSync?.queuePlaylistSave(playlist)
        }
        if summary.playlists > 0 {
            dataManager.save()
            NotificationCenter.default.post(name: .playlistsDidChange, object: nil)
        }

        for export in backup.channelNotificationSettings {
            dataManager.upsertChannelNotificationSettings(export.toChannelNotificationSettings())
            summary.notificationSettings += 1
        }

        if let mediaSourcesManager {
            for export in backup.mediaSources {
                guard let source = export.toMediaSource() else { continue }
                if mediaSourcesManager.sources.contains(where: { $0.id == source.id }) {
                    mediaSourcesManager.update(source)
                } else {
                    mediaSourcesManager.add(source)
                    summary.mediaSources += 1
                }
            }
        }

        for (key, value) in backup.settings {
            if let object = value.object {
                defaults.set(object, forKey: key)
                summary.settings += 1
            }
        }

        return summary
    }

    enum BackupError: LocalizedError {
        case unsupportedSchemaVersion(Int)

        var errorDescription: String? {
            switch self {
            case .unsupportedSchemaVersion(let version):
                String(format: NSLocalizedString("backup.error.schemaVersion %lld", comment: "Backup schema too new"), version)
            }
        }
    }
}
