//
//  FormatFallback.swift
//  SneakPeak
//
//  Pure selection logic for playback format fallback (G4): when a stream fails
//  to load (codec/container failure, e.g. AV1 on a device without a decoder),
//  pick the best alternative stream to retry with.
//

import Foundation

/// Picks an alternative stream after a playback failure.
enum FormatFallback {
    /// Codec compatibility order for fallback preference (earlier = more
    /// universally decodable). H.264 first because every target device
    /// hardware-decodes it; AV1 last because support is the rarest.
    private static let codecCompatibilityOrder = [
        "avc1", "h264", "hvc1", "hev1", "hevc", "vp9", "vp09", "av01", "av1",
    ]

    /// Compatibility rank of a codec (higher = more compatible). Unknown
    /// codecs rank below all known ones.
    static func codecCompatibility(_ codec: String?) -> Int {
        guard let codec else { return -1 }
        let lower = codec.lowercased()
        for (index, known) in codecCompatibilityOrder.enumerated() {
            if lower.contains(known) {
                return codecCompatibilityOrder.count - index
            }
        }
        return 0
    }

    /// Selects the stream to retry with after `failed` could not play.
    ///
    /// Preference order:
    /// 1. A different container/codec at most the failed resolution (fixes a
    ///    codec failure without paying an avoidable quality drop).
    /// 2. A different container/codec at any resolution.
    /// 3. Any other stream of the same kind (quality downgrade within the
    ///    same container — the stream itself may have been bad).
    ///
    /// Audio-only content falls back within audio-only streams; video never
    /// falls back to audio-only (that is the user's explicit Audio Mode).
    /// - Parameter triedURLs: Stream URLs already attempted for this video —
    ///   excluded from the pool so retry sequences cannot ping-pong between
    ///   two failing streams.
    /// Returns `nil` when there is nothing else to try.
    static func candidate(
        failed: Stream,
        in streams: [Stream],
        triedURLs: Set<URL> = []
    ) -> Stream? {
        let pool = streams.filter {
            $0.url != failed.url && !triedURLs.contains($0.url) && !$0.url.isFileURL
        }
        let sameKind = pool.filter { $0.isAudioOnly == failed.isAudioOnly }
        guard !sameKind.isEmpty else { return nil }

        let failedFormat = StreamFormat.detect(from: failed)
        let failedResolution = failed.resolution

        let differentFormat = sameKind.filter { StreamFormat.detect(from: $0) != failedFormat }

        // Prefer candidates that don't exceed the failed resolution, then the
        // highest resolution within that, then the most compatible codec.
        func rank(_ stream: Stream) -> (Int, Int, Int) {
            let overResolution = failedResolution.map { resolution in
                (stream.resolution?.height ?? 0) > resolution.height ? 1 : 0
            } ?? 0
            let height = stream.resolution?.height ?? 0
            return (overResolution, -height, -codecCompatibility(stream.videoCodec))
        }

        if let best = differentFormat.min(by: { rank($0) < rank($1) }) {
            return best
        }

        // Same format: a quality downgrade — the ranking already prefers
        // resolution at most the failed one, highest within that.
        return sameKind.min(by: { rank($0) < rank($1) })
    }
}
