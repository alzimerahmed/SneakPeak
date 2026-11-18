//
//  FileThumbnailCacheTests.swift
//  SneakPeakTests
//
//  Tests for the Phase 6 file-source thumbnail disk cache (G11):
//  hit/miss behavior, LRU eviction bound, and cache key stability.
//

import Testing
import Foundation
@testable import SneakPeak

@Suite("File Thumbnail Cache Tests")
struct FileThumbnailCacheTests {

    // MARK: - Helpers

    private func makeTemporaryCache(sizeLimit: Int = 0) throws -> FileThumbnailDiskCache {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("thumb-cache-tests-\(UUID().uuidString)", isDirectory: true)
        return FileThumbnailDiskCache(directory: directory, sizeLimitBytes: sizeLimit)
    }

    private func makeFile(path: String = "/Movies/movie.mp4", modified: Date? = Date(timeIntervalSince1970: 1_700_000_000)) -> MediaFile {
        MediaFile(
            source: .webdav(name: "NAS", url: URL(string: "https://nas.local")!),
            path: path,
            name: "movie.mp4",
            isDirectory: false,
            size: 1_000,
            modifiedDate: modified
        )
    }

    // MARK: - Hit / Miss

    @Test("Store then read is a cache hit")
    func storeThenHit() async throws {
        let cache = try makeTemporaryCache()
        let key = FileThumbnailService.cacheKey(for: makeFile())

        await cache.store(Data([1, 2, 3]), forKey: key)
        let data = await cache.data(forKey: key)

        #expect(data == Data([1, 2, 3]))
    }

    @Test("Unknown key is a miss")
    func unknownKeyMisses() async throws {
        let cache = try makeTemporaryCache()

        let data = await cache.data(forKey: "nonexistent-key")

        #expect(data == nil)
    }

    @Test("Remove drops the entry")
    func removeDropsEntry() async throws {
        let cache = try makeTemporaryCache()
        let key = FileThumbnailService.cacheKey(for: makeFile())

        await cache.store(Data([9]), forKey: key)
        await cache.remove(forKey: key)

        #expect(await cache.data(forKey: key) == nil)
    }

    @Test("Clear empties the cache")
    func clearEmpties() async throws {
        let cache = try makeTemporaryCache()
        let key = FileThumbnailService.cacheKey(for: makeFile())

        await cache.store(Data([7]), forKey: key)
        await cache.clear()

        #expect(await cache.data(forKey: key) == nil)
    }

    // MARK: - Eviction Bound

    @Test("Eviction keeps total size under the cap")
    func evictionRespectsBound() async throws {
        // Cap of 3 bytes with 2-byte entries: at most 2 entries survive.
        let cache = try makeTemporaryCache(sizeLimit: 3)

        let keys = (0..<5).map { "key-\($0)" }
        for key in keys {
            await cache.store(Data([0, 0]), forKey: key)
        }

        // The just-written entry must survive; at most one older entry fits.
        var survivingBytes = 0
        for key in keys {
            if await cache.data(forKey: key) != nil {
                survivingBytes += 2
            }
        }
        #expect(survivingBytes <= 3)
        #expect(await cache.data(forKey: "key-4") != nil) // newest kept
    }

    @Test("LRU touch protects recently used entries from eviction")
    func lruTouchProtectsRecentEntry() async throws {
        // Cap of 4 bytes: two 2-byte entries can survive.
        let cache = try makeTemporaryCache(sizeLimit: 4)

        await cache.store(Data([0, 0]), forKey: "a")
        try await Task.sleep(nanoseconds: 20_000_000)
        await cache.store(Data([0, 0]), forKey: "b")
        try await Task.sleep(nanoseconds: 20_000_000)
        // Touch "a" — now more recently used than "b".
        _ = await cache.data(forKey: "a")
        try await Task.sleep(nanoseconds: 20_000_000)
        await cache.store(Data([0, 0]), forKey: "c")

        // "b" (least recently used) is evicted; "a" and "c" survive.
        #expect(await cache.data(forKey: "a") != nil)
        #expect(await cache.data(forKey: "b") == nil)
        #expect(await cache.data(forKey: "c") != nil)
    }

    // MARK: - Key Stability

    @Test("Cache key is stable for identical files")
    func keyIsStable() throws {
        let file = makeFile()

        #expect(FileThumbnailService.cacheKey(for: file) == FileThumbnailService.cacheKey(for: file))
    }

    @Test("Cache key differs per source, path, and modification date")
    func keyDistinguishesInputs() throws {
        let base = makeFile()
        let otherPath = makeFile(path: "/Movies/other.mp4")
        let otherDate = makeFile(modified: Date(timeIntervalSince1970: 1_700_000_100))

        #expect(FileThumbnailService.cacheKey(for: base) != FileThumbnailService.cacheKey(for: otherPath))
        #expect(FileThumbnailService.cacheKey(for: base) != FileThumbnailService.cacheKey(for: otherDate))
    }

    @Test("Cache key is a hex digest of fixed length")
    func keyIsHexDigest() throws {
        let key = FileThumbnailService.cacheKey(for: makeFile())

        #expect(key.count == 64) // SHA-256
        #expect(key.allSatisfy { $0.isHexDigit })
    }

    // MARK: - Service Behavior

    @Test("Non-video and directory files never produce thumbnails")
    func nonVideoReturnsNil() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("thumb-service-tests-\(UUID().uuidString)", isDirectory: true)
        let service = FileThumbnailService(
            cache: FileThumbnailDiskCache(directory: directory, sizeLimitBytes: 0)
        )

        let folder = MediaFile(
            source: .webdav(name: "NAS", url: URL(string: "https://nas.local")!),
            path: "/Movies",
            name: "Movies",
            isDirectory: true
        )

        #expect(await service.imageData(for: folder, password: nil) == nil)
    }

    @Test("SMB files return nil without generation (no partial-read bridge)")
    func smbReturnsNil() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("thumb-service-tests-\(UUID().uuidString)", isDirectory: true)
        let service = FileThumbnailService(
            cache: FileThumbnailDiskCache(directory: directory, sizeLimitBytes: 0)
        )

        let file = MediaFile(
            source: .smb(name: "Server", url: URL(string: "smb://nas.local")!),
            path: "Share/movie.mp4",
            name: "movie.mp4",
            isDirectory: false
        )

        #expect(await service.imageData(for: file, password: nil) == nil)
    }
}
