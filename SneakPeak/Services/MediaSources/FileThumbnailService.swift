//
//  FileThumbnailService.swift
//  SneakPeak
//
//  Generates and caches video thumbnails for file sources
//  (local folders, WebDAV, SMB) so media browser browsing feels fast.
//

import AVFoundation
import CoreGraphics
import CryptoKit
import Foundation
import ImageIO

/// Actor that produces thumbnail image data for `MediaFile`s, backed by
/// `FileThumbnailDiskCache`.
///
/// Generation strategy per source type:
/// - **localFolder** — `AVAssetImageGenerator` on the local file URL.
/// - **webdav** — ranged HTTP GET of the first ~1.5 MB (Basic auth) into a
///   temp file, then `AVAssetImageGenerator` on it. Files whose metadata
///   lives beyond that range fail gracefully and fall back to the icon.
/// - **smb** — no generation: the SMB bridge only exposes whole-file
///   download, which is far too expensive for a thumbnail. Returns nil and
///   the row keeps its SF Symbol icon (see ADR in docs/research.md).
///
/// Failures are negatively cached in memory with a TTL so scrolling a
/// folder does not re-attempt generation for the same file repeatedly,
/// while transient failures (network hiccups, server restarts) get a
/// retry after the TTL expires.
actor FileThumbnailService {
    static let shared = FileThumbnailService()

    /// Bytes fetched from a WebDAV server before attempting frame extraction.
    private static let webdavFetchLimit = 1_500_000

    /// How long a failed generation stays negatively cached before retry.
    private static let failureTTL: TimeInterval = 10 * 60

    private let cache: FileThumbnailDiskCache
    private let session: URLSession

    /// In-flight generation, deduplicated per cache key.
    private var inFlight: [String: Task<Data?, Never>] = [:]

    /// Keys that failed to generate, with the time they may be retried.
    private var failedKeys: [String: Date] = [:]

    init(cache: FileThumbnailDiskCache = .shared, session: URLSession = .shared) {
        self.cache = cache
        self.session = session
    }

    // MARK: - Public API

    /// Cached-or-generated thumbnail JPEG data, or nil when unavailable.
    func imageData(for file: MediaFile, password: String?) async -> Data? {
        guard file.isVideo, !file.isDirectory else { return nil }

        let key = Self.cacheKey(for: file)

        if let cached = await cache.data(forKey: key) {
            return cached
        }

        // Negative cache with TTL: a key whose retry time has passed is
        // attempted again.
        if let retryAfter = failedKeys[key] {
            if retryAfter > Date() { return nil }
            failedKeys[key] = nil
        }

        if let running = inFlight[key] {
            return await running.value
        }
        return await generate(file, key: key, password: password)
    }

    /// Stable cache identity: source UUID + path + modification date.
    /// Same file → same key across launches; modified file → new key.
    nonisolated static func cacheKey(for file: MediaFile) -> String {
        let timestamp = file.modifiedDate.map { String($0.timeIntervalSince1970) } ?? "none"
        let identity = "\(file.source.id.uuidString)|\(file.path)|\(timestamp)"
        let digest = SHA256.hash(data: Data(identity.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// Clears the disk cache (e.g. from a settings "clear caches" action).
    func clearCache() async {
        failedKeys.removeAll()
        await cache.clear()
    }

    // MARK: - Generation

    private func generate(_ file: MediaFile, key: String, password: String?) async -> Data? {
        let task = Task { [weak self] in
            await self?.performGeneration(file, password: password)
        }
        inFlight[key] = task

        defer { inFlight[key] = nil }
        let data = await task.value

        if let data {
            await cache.store(data, forKey: key)
        } else {
            failedKeys[key] = Date().addingTimeInterval(Self.failureTTL)
        }
        return data
    }

    private func performGeneration(_ file: MediaFile, password: String?) async -> Data? {
        switch file.source.type {
        case .localFolder:
            return await Self.extractFrame(from: file.url)
        case .webdav:
            return await generateWebDAV(file, password: password)
        case .smb:
            return nil // Bridge has no partial read; see class docs.
        }
    }

    private func generateWebDAV(_ file: MediaFile, password: String?) async -> Data? {
        var request = URLRequest(url: file.url)
        request.httpMethod = "GET"
        request.timeoutInterval = 15
        request.setValue("bytes=0-\(Self.webdavFetchLimit - 1)", forHTTPHeaderField: "Range")

        if let username = file.source.username, !username.isEmpty {
            let credentials = Data("\(username):\(password ?? "")".utf8)
                .base64EncodedString()
            request.setValue("Basic \(credentials)", forHTTPHeaderField: "Authorization")
        }

        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse,
              (200...299).contains(http.statusCode),
              !data.isEmpty,
              // 206 = honored range. A 200 means the server ignored the
              // Range header and sent the whole file — refuse anything
              // larger than the intended window so we never pull a
              // multi-GB video just for a thumbnail.
              (http.statusCode == 206 || data.count <= Self.webdavFetchLimit)
        else { return nil }

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("sonicwave-thumb-\(UUID().uuidString)")
        guard (try? data.write(to: tempURL, options: .atomic)) != nil else { return nil }
        defer { try? FileManager.default.removeItem(at: tempURL) }

        return await Self.extractFrame(from: tempURL)
    }

    /// Extracts a representative frame and encodes it as JPEG.
    /// Runs off the actor so slow decodes don't block other lookups.
    private nonisolated static func extractFrame(from url: URL) async -> Data? {
        let asset = AVURLAsset(url: url)

        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: 480, height: 480)
        generator.requestedTimeToleranceBefore = CMTime(seconds: 2, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 8, preferredTimescale: 600)

        // Ask near the start; generous tolerance lets the generator pick a
        // nearby keyframe instead of decoding from zero for long stretches.
        let target = CMTime(seconds: 5, preferredTimescale: 600)

        guard let (image, _) = try? await generator.image(at: target) else { return nil }
        return jpegData(from: image)
    }

    private nonisolated static func jpegData(from image: CGImage) -> Data? {
        let output = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            output,
            "public.jpeg" as CFString,
            1,
            nil
        ) else { return nil }

        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return output as Data
    }
}
