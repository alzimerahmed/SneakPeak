//
//  Phase5ParityTests.swift
//  SneakPeakTests
//
//  Tests for Phase 5: file-source playlists/watch-later (G5), per-channel
//  notification rules (G6), and JSON export/import round-trip (G7).
//

import Testing
import Foundation
@testable import SneakPeak

@MainActor
@Suite("Phase 5 Parity Tests")
struct Phase5ParityTests {

    // MARK: - Helpers

    /// An SMB file-source video: extractor `media_source_smb`, videoID
    /// "sourceUUID:rel/path.mp4", original URL the file URL.
    private func smbVideo() -> Video {
        let sourceID = UUID()
        let fileURL = URL(string: "smb://nas.local/share/movie.mp4")!
        return Video(
            id: .extracted(
                "\(sourceID.uuidString):movies/movie.mp4",
                extractor: MediaFile.smbProvider,
                originalURL: fileURL
            ),
            title: "Network Movie",
            description: nil,
            author: Author(id: "nas", name: "NAS Share"),
            duration: 600,
            publishedAt: nil,
            publishedText: nil,
            viewCount: nil,
            likeCount: nil,
            thumbnails: [],
            isLive: false,
            isUpcoming: false,
            scheduledStartTime: nil
        )
    }

    // MARK: - G5: File-source playlists & watch-later

    @Suite("File-Source Playlists")
    @MainActor
    struct FileSourcePlaylistTests {

        @Test("File-source video round-trips through a local playlist item")
        func playlistItemRoundTrip() {
            let video = Phase5ParityTests().smbVideo()
            let playlist = LocalPlaylist(title: "SMB Picks")
            playlist.addVideo(video)

            #expect(playlist.videoCount == 1)
            let item = playlist.sortedItems[0]

            #expect(item.sourceRawValue == "extracted")
            #expect(item.externalExtractor == MediaFile.smbProvider)
            #expect(item.videoID == video.id.videoID)

            let restored = item.toVideo()
            #expect(restored.id.videoID == video.id.videoID)
            #expect(restored.isFromSMB)
            #expect(restored.isFromMediaSource)
            #expect(restored.mediaSourceFilePath == "movies/movie.mp4")
        }

        @Test("File-source video is bookmarkable and round-trips")
        func bookmarkRoundTrip() {
            let video = Phase5ParityTests().smbVideo()
            let bookmark = Bookmark.from(video: video)
            let restored = bookmark.toVideo()

            #expect(bookmark.sourceRawValue == "extracted")
            #expect(bookmark.externalExtractor == MediaFile.smbProvider)
            #expect(restored.id.videoID == video.id.videoID)
            #expect(restored.isFromSMB)
            #expect(restored.title == video.title)
        }

        @Test("DataManager persists a file-source playlist item")
        func dataManagerPersistsFileSourceItem() async throws {
            let manager = try DataManager(inMemory: true)
            let video = Phase5ParityTests().smbVideo()
            let playlist = manager.createPlaylist(title: "Watch Later")
            manager.addToPlaylist(video, playlist: playlist)

            let stored = manager.playlist(forID: playlist.id)
            #expect(stored?.videoCount == 1)
            let item = stored?.sortedItems.first
            #expect(item?.externalExtractor == MediaFile.smbProvider)
            #expect(item?.toVideo().isFromMediaSource == true)
        }

        @Test("DataManager persists a file-source bookmark")
        func dataManagerPersistsFileSourceBookmark() async throws {
            let manager = try DataManager(inMemory: true)
            let video = Phase5ParityTests().smbVideo()
            manager.addBookmark(for: video)

            #expect(manager.isBookmarked(videoID: video.id.videoID))
            #expect(manager.bookmark(for: video.id.videoID)?.toVideo().isFromSMB == true)
        }
    }

    // MARK: - G6: Per-channel notification rules

    @Suite("Notification Rules")
    @MainActor
    struct NotificationRuleTests {

        private func video(isLive: Bool) -> Video {
            Video(
                id: .global("vid-\(isLive)"),
                title: "Video",
                description: nil,
                author: Author(id: "chan", name: "Channel"),
                duration: isLive ? 0 : 300,
                publishedAt: nil,
                publishedText: nil,
                viewCount: nil,
                likeCount: nil,
                thumbnails: [],
                isLive: isLive,
                isUpcoming: false,
                scheduledStartTime: nil
            )
        }

        @Test("All rule allows every video")
        func allRule() {
            #expect(ChannelNotificationRule.all.allowsNotification(for: video(isLive: false)))
            #expect(ChannelNotificationRule.all.allowsNotification(for: video(isLive: true)))
        }

        @Test("Livestreams-only rule filters non-live videos")
        func livestreamsOnlyRule() {
            #expect(ChannelNotificationRule.livestreamsOnly.allowsNotification(for: video(isLive: true)))
            #expect(!ChannelNotificationRule.livestreamsOnly.allowsNotification(for: video(isLive: false)))
        }

        @Test("Digest rule never fires a standard notification")
        func digestRule() {
            #expect(!ChannelNotificationRule.digest.allowsNotification(for: video(isLive: false)))
            #expect(!ChannelNotificationRule.digest.allowsNotification(for: video(isLive: true)))
        }

        @Test("Unknown raw value falls back to all")
        func unknownRawValueFallsBack() {
            let settings = ChannelNotificationSettings(channelID: "chan")
            settings.ruleRawValue = "bogus"
            #expect(settings.rule == .all)
        }

        @Test("Rule persists per channel and defaults to all")
        func rulePersistsPerChannel() async throws {
            let manager = try DataManager(inMemory: true)

            #expect(manager.notificationRule(for: "chanA") == .all)

            manager.setNotificationRule(.livestreamsOnly, for: "chanA")
            #expect(manager.notificationRule(for: "chanA") == .livestreamsOnly)
            // Setting a rule must not silently enable notifications.
            #expect(!manager.notificationsEnabled(for: "chanA"))

            manager.setNotificationRule(.digest, for: "chanB")
            #expect(manager.notificationRule(for: "chanB") == .digest)
            #expect(manager.notificationRule(for: "chanA") == .livestreamsOnly)
        }
    }

    // MARK: - G7: JSON export/import round-trip

    @Suite("Data Export/Import")
    @MainActor
    struct DataExportTests {

        @Test("Export/import round-trips subscriptions, history, bookmarks, playlists and rules")
        func roundTrip() async throws {
            let source = try DataManager(inMemory: true)

            let channel = Channel(id: .global("chanExport"), name: "Exported Channel")
            source.subscribe(to: channel)

            let watched = Video(
                id: .global("vidWatched"),
                title: "Watched Video",
                description: nil,
                author: Author(id: "chanExport", name: "Exported Channel"),
                duration: 100,
                publishedAt: nil,
                publishedText: nil,
                viewCount: nil,
                likeCount: nil,
                thumbnails: [],
                isLive: false,
                isUpcoming: false,
                scheduledStartTime: nil
            )
            source.updateWatchProgressLocal(for: watched, seconds: 50)
            source.addBookmark(for: watched)

            let smbVideo = Phase5ParityTests().smbVideo()
            let playlist = source.createPlaylist(title: "Round Trip")
            source.addToPlaylist(smbVideo, playlist: playlist)
            source.setNotificationsEnabled(true, for: "chanExport")
            source.setNotificationRule(.digest, for: "chanExport")

            let service = UserDataBackupService(dataManager: source, defaults: UserDefaults(suiteName: "phase5-test")!)
            let data = try service.exportData()

            // Decode fresh manager, import into it.
            let target = try DataManager(inMemory: true)
            let importService = UserDataBackupService(dataManager: target, defaults: UserDefaults(suiteName: "phase5-test-2")!)
            let summary = try importService.importData(data)

            #expect(summary.subscriptions == 1)
            #expect(summary.watchEntries == 1)
            #expect(summary.bookmarks == 1)
            #expect(summary.playlists == 1)
            #expect(summary.notificationSettings == 1)

            #expect(target.isSubscribed(to: "chanExport"))
            #expect(target.watchEntry(for: "vidWatched")?.watchedSeconds == 50)
            #expect(target.isBookmarked(videoID: "vidWatched"))

            let importedPlaylist = target.playlists().first
            #expect(importedPlaylist?.title == "Round Trip")
            #expect(importedPlaylist?.videoCount == 1)
            #expect(importedPlaylist?.sortedItems.first?.toVideo().isFromSMB == true)

            #expect(target.notificationsEnabled(for: "chanExport"))
            #expect(target.notificationRule(for: "chanExport") == .digest)
        }

        @Test("Importing twice does not duplicate records")
        func importIsIdempotent() async throws {
            let source = try DataManager(inMemory: true)
            let channel = Channel(id: .global("chanIdem"), name: "Idempotent")
            source.subscribe(to: channel)

            let service = UserDataBackupService(dataManager: source, defaults: UserDefaults(suiteName: "phase5-test")!)
            let data = try service.exportData()

            let target = try DataManager(inMemory: true)
            let importService = UserDataBackupService(dataManager: target, defaults: UserDefaults(suiteName: "phase5-test-2")!)
            _ = try importService.importData(data)
            let second = try importService.importData(data)

            #expect(second.subscriptions == 0)
            #expect(target.subscriptions().count == 1)
        }

        @Test("Exported JSON decodes with iso8601 dates and carries schema version")
        func jsonShape() async throws {
            let source = try DataManager(inMemory: true)
            let service = UserDataBackupService(dataManager: source, defaults: UserDefaults(suiteName: "phase5-test")!)
            let data = try service.exportData()

            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            #expect(json?["schemaVersion"] as? Int == UserDataBackup.currentSchemaVersion)
            #expect(json?["exportedAt"] != nil)

            // Credentials must never be exported: no password-looking keys.
            let text = String(data: data, encoding: .utf8) ?? ""
            #expect(!text.lowercased().contains("password"))
        }
    }
}
