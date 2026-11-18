//
//  FileThumbnailDiskCache.swift
//  SneakPeak
//
//  Size-capped LRU disk cache for file-source video thumbnails
//  (SMB/WebDAV/local folder browsing). Actor-isolated for safe
//  concurrent access from list rows.
//

import Foundation

/// Persistent disk cache for generated file-source thumbnails.
///
/// Entries are keyed by a stable digest of (source, path, modification date)
/// — see `FileThumbnailService.cacheKey(for:)` — and stored as JPEG files.
/// When the total size exceeds `sizeLimitBytes`, least-recently-used entries
/// are evicted; a cache hit touches the entry's modification date, which is
/// the LRU clock.
actor FileThumbnailDiskCache {
    static let shared = FileThumbnailDiskCache()

    private let fileManager = FileManager.default
    private let directory: URL
    private let sizeLimitBytes: Int

    /// Total size of stored entries, computed once and maintained afterwards.
    private var totalSize: Int?

    /// - Parameters:
    ///   - directory: Storage directory (created if missing).
    ///   - sizeLimitBytes: Maximum total size of stored thumbnails.
    ///     Passing `0` disables eviction (used by tests that only check
    ///     hit/miss behavior).
    init(directory: URL? = nil, sizeLimitBytes: Int? = nil) {
        // Fall back to the temporary directory if the caches directory
        // cannot be resolved (never crash init over a cache location).
        let base = directory
            ?? FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
                .appendingPathComponent("FileThumbnails", isDirectory: true)
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
                .appendingPathComponent("FileThumbnails", isDirectory: true)

        #if os(tvOS)
        let defaultLimit = 100 * 1024 * 1024 // 100 MB
        #elseif os(macOS)
        let defaultLimit = 300 * 1024 * 1024 // 300 MB
        #else
        let defaultLimit = 200 * 1024 * 1024 // 200 MB
        #endif

        self.directory = base
        self.sizeLimitBytes = sizeLimitBytes ?? defaultLimit

        try? fileManager.createDirectory(at: base, withIntermediateDirectories: true)
    }

    // MARK: - Public API

    /// Returns cached image data for the key, or nil on miss.
    /// A hit refreshes the entry's modification date (LRU touch).
    func data(forKey key: String) -> Data? {
        let url = entryURL(forKey: key)
        guard let data = try? Data(contentsOf: url) else { return nil }

        // LRU touch: bump modification date so eviction measures recency.
        try? fileManager.setAttributes(
            [.modificationDate: Date()],
            ofItemAtPath: url.path
        )
        return data
    }

    /// Stores image data under the key, evicting LRU entries if the
    /// size cap would be exceeded. Eviction always keeps the entry
    /// just written.
    func store(_ data: Data, forKey key: String) {
        let url = entryURL(forKey: key)
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            return // Cache write failure is never fatal.
        }

        if let total = totalSize {
            // A same-key rewrite replaces the old file, so subtract its
            // previous size before adding the new one or the running total
            // double-counts rewritten entries.
            let previousSize = fileSize(at: url) ?? 0
            totalSize = total - previousSize + data.count
        }

        guard sizeLimitBytes > 0 else { return }
        evictIfNeeded(keeping: key)
    }

    /// Removes a single entry (e.g. when generation failed and a
    /// placeholder was written).
    func remove(forKey key: String) {
        let url = entryURL(forKey: key)
        if let size = fileSize(at: url), let total = totalSize {
            totalSize = max(0, total - size)
        }
        try? fileManager.removeItem(at: url)
    }

    /// Clears all cached thumbnails.
    func clear() {
        try? fileManager.removeItem(at: directory)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        totalSize = 0
    }

    // MARK: - Eviction

    private func evictIfNeeded(keeping protectedKey: String) {
        var entries = allEntries()
        var total = totalSize ?? entries.reduce(0) { $0 + $1.size }
        guard total > sizeLimitBytes else {
            totalSize = total
            return
        }

        // Oldest modification date first = least recently used.
        entries.sort { $0.modified < $1.modified }

        for entry in entries where total > sizeLimitBytes {
            guard entry.key != protectedKey else { continue }
            try? fileManager.removeItem(at: entryURL(forKey: entry.key))
            total -= entry.size
        }

        totalSize = total
    }

    private struct CacheEntry {
        let key: String
        let size: Int
        let modified: Date
    }

    private func allEntries() -> [CacheEntry] {
        let contents = (try? fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey],
            options: []
        )) ?? []

        return contents.compactMap { url in
            let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey])
            guard let size = values?.fileSize else { return nil }
            return CacheEntry(
                key: url.lastPathComponent,
                size: size,
                modified: values?.contentModificationDate ?? .distantPast
            )
        }
    }

    // MARK: - Helpers

    private func entryURL(forKey key: String) -> URL {
        directory.appendingPathComponent(key)
    }

    private func fileSize(at url: URL) -> Int? {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey])
        return values?.fileSize
    }
}
