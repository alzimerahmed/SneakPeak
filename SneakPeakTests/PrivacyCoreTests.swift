//
//  PrivacyCoreTests.swift
//  SneakPeakTests
//
//  Tests for the Phase 3 privacy core: local subscriptions without an
//  account (G1), resume everywhere for file sources (G2), and incognito
//  playback (G10).
//

import Testing
import Foundation
@testable import SneakPeak

@MainActor
@Suite("Privacy Core Tests")
struct PrivacyCoreTests {

    // MARK: - G1: Local subscriptions without an account

    @Suite("Local Subscriptions")
    struct LocalSubscriptionTests {

        @Test("Subscribe persists locally without any account")
        func subscribePersistsLocally() async throws {
            let manager = try DataManager(inMemory: true)

            let channel = Channel(
                id: .global("chanLocal1"),
                name: "Local Channel",
                description: nil,
                subscriberCount: nil,
                thumbnailURL: nil,
                bannerURL: nil,
                isVerified: false
            )

            manager.subscribe(to: channel)

            #expect(manager.isSubscribed(to: "chanLocal1"))
            let stored = manager.subscriptions()
            #expect(stored.count == 1)
            #expect(stored.first?.channelID == "chanLocal1")
            #expect(stored.first?.name == "Local Channel")
        }

        @Test("Unsubscribe removes the local subscription")
        func unsubscribeRemoves() async throws {
            let manager = try DataManager(inMemory: true)

            let channel = Channel(id: .global("chanLocal2"), name: "Channel Two")
            manager.subscribe(to: channel)
            #expect(manager.isSubscribed(to: "chanLocal2"))

            manager.unsubscribe(from: "chanLocal2")
            #expect(!manager.isSubscribed(to: "chanLocal2"))
            #expect(manager.subscriptions().isEmpty)
        }

        @Test("Subscribing twice does not duplicate the entry")
        func subscribeIsIdempotent() async throws {
            let manager = try DataManager(inMemory: true)

            let channel = Channel(id: .global("chanLocal3"), name: "Channel Three")
            manager.subscribe(to: channel)
            manager.subscribe(to: channel)

            #expect(manager.subscriptions().count == 1)
        }
    }

    // MARK: - G1: Feed merge helper

    @Suite("Local Feed Merge")
    struct LocalFeedMergeTests {

        private func video(_ id: String, publishedAt: Date?) -> Video {
            Video(
                id: .global(id),
                title: "Video \(id)",
                description: nil,
                author: Author(id: "ch", name: "Channel"),
                duration: 100,
                publishedAt: publishedAt,
                publishedText: nil,
                viewCount: nil,
                likeCount: nil,
                thumbnails: [],
                isLive: false,
                isUpcoming: false,
                scheduledStartTime: nil
            )
        }

        @Test("Merged feed is newest first")
        func sortedNewestFirst() {
            let old = Date(timeIntervalSince1970: 1_000)
            let new = Date(timeIntervalSince1970: 2_000)
            let merged = SubscriptionFeedCache.mergedChannelVideos([
                [video("a", publishedAt: old)],
                [video("b", publishedAt: new)]
            ])

            #expect(merged.map(\.id.videoID) == ["b", "a"])
        }

        @Test("Duplicate videos across channels appear once")
        func deduplicatesByID() {
            let date = Date(timeIntervalSince1970: 1_000)
            let merged = SubscriptionFeedCache.mergedChannelVideos([
                [video("dup", publishedAt: date)],
                [video("dup", publishedAt: date), video("other", publishedAt: date)]
            ])

            #expect(merged.count == 2)
            #expect(Set(merged.map(\.id.videoID)) == Set(["dup", "other"]))
        }

        @Test("Videos without a publish date sort last")
        func undatedSortsLast() {
            let dated = Date(timeIntervalSince1970: 1_000)
            let merged = SubscriptionFeedCache.mergedChannelVideos([
                [video("undated", publishedAt: nil)],
                [video("dated", publishedAt: dated)]
            ])

            #expect(merged.map(\.id.videoID) == ["dated", "undated"])
        }

        @Test("Merge respects the total cap")
        func respectsTotalLimit() {
            let date = Date(timeIntervalSince1970: 1_000)
            let pages = (0..<10).map { page in
                (0..<10).map { index in video("v\(page)-\(index)", publishedAt: date) }
            }
            let merged = SubscriptionFeedCache.mergedChannelVideos(pages, totalLimit: 15)

            #expect(merged.count == 15)
        }
    }

    // MARK: - G2: Resume everywhere (file sources)

    @Suite("Resume Everywhere")
    struct ResumeEverywhereTests {

        private func mediaFileVideo(name: String) -> Video {
            let source = MediaSource(name: "NAS", type: .webdav, url: URL(string: "https://nas.local")!)
            let file = MediaFile(
                source: source,
                path: "/Movies/\(name)",
                name: name,
                isDirectory: false
            )
            return file.toVideo()
        }

        @Test("File-source progress round trip")
        func fileSourceProgressRoundTrip() async throws {
            let manager = try DataManager(inMemory: true)
            let video = mediaFileVideo("Movie.mp4")

            manager.updateWatchProgressLocal(for: video, seconds: 420, duration: 1_000)

            let progress = try #require(manager.watchProgress(for: video))
            #expect(progress == 420)
        }

        @Test("Resume lookup prefers the entry under the video's own source scope")
        func scopeAwareLookup() async throws {
            let manager = try DataManager(inMemory: true)

            // A file-source entry and a global (YouTube) entry that collide
            // on the same video ID string. Inserted directly — the progress
            // write path keys on the ID alone, so these represent entries
            // that arrived through different routes (e.g. sync).
            let fileVideo = mediaFileVideo("Movie.mp4")
            let globalVideo = Video(
                id: .global(fileVideo.id.videoID),
                title: "Same ID, different scope",
                description: nil,
                author: Author(id: "ch", name: "Channel"),
                duration: 1_000,
                publishedAt: nil,
                publishedText: nil,
                viewCount: nil,
                likeCount: nil,
                thumbnails: [],
                isLive: false,
                isUpcoming: false,
                scheduledStartTime: nil
            )

            let fileEntry = WatchEntry.from(video: fileVideo)
            fileEntry.watchedSeconds = 111
            manager.insertWatchEntry(fileEntry)

            let globalEntry = WatchEntry.from(video: globalVideo)
            globalEntry.watchedSeconds = 999
            manager.insertWatchEntry(globalEntry)

            // Each video resumes from its own scope's position.
            #expect(try #require(manager.watchProgress(for: fileVideo)) == 111)
            #expect(try #require(manager.watchProgress(for: globalVideo)) == 999)
        }

        @Test("No progress returns nil for an unwatched video")
        func unwatchedReturnsNil() async throws {
            let manager = try DataManager(inMemory: true)
            #expect(manager.watchProgress(for: mediaFileVideo("NeverWatched.mp4")) == nil)
        }
    }
}
