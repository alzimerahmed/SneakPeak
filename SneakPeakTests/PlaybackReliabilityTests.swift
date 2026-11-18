//
//  PlaybackReliabilityTests.swift
//  SneakPeakTests
//
//  Tests for Phase 4 playback reliability: G4 format fallback selection and
//  G3 instance health-state classification. Pure logic only — no network.
//

import Testing
import Foundation
@testable import SneakPeak

// MARK: - G4 Format Fallback

@Suite("Format Fallback Tests")
struct FormatFallbackTests {

    private func stream(
        url: URL,
        resolution: StreamResolution?,
        format: String,
        videoCodec: String? = nil,
        audioCodec: String? = nil,
        isAudioOnly: Bool = false
    ) -> Stream {
        Stream(
            url: url,
            resolution: resolution,
            format: format,
            videoCodec: videoCodec,
            audioCodec: audioCodec,
            isAudioOnly: isAudioOnly
        )
    }

    private func video(
        height: Int,
        format: String,
        codec: String
    ) -> Stream {
        stream(
            url: URL(string: "https://cdn.example.com/\(format)-\(height)-\(codec)")!,
            resolution: StreamResolution(width: height * 16 / 9, height: height),
            format: format,
            videoCodec: codec,
            audioCodec: "opus"
        )
    }

    @Test("Codec failure falls back to a different container at the same resolution")
    func prefersDifferentFormatAtSameResolution() {
        let failed = video(height: 2160, format: "webm", codec: "av01")
        let mp4SameRes = video(height: 2160, format: "mp4", codec: "avc1")
        let mp4Lower = video(height: 1080, format: "mp4", codec: "avc1")
        let vp9Lower = video(height: 1080, format: "webm", codec: "vp09")

        let candidate = FormatFallback.candidate(
            failed: failed,
            in: [mp4Lower, vp9Lower, mp4SameRes, failed]
        )

        #expect(candidate == mp4SameRes)
    }

    @Test("Same-format failure downgrades resolution")
    func downgradesResolutionWithinSameFormat() {
        let failed = video(height: 2160, format: "mp4", codec: "avc1")
        let lower = video(height: 1080, format: "mp4", codec: "avc1")

        let candidate = FormatFallback.candidate(failed: failed, in: [lower, failed])

        #expect(candidate == lower)
    }

    @Test("No alternatives returns nil")
    func returnsNilWithoutAlternatives() {
        let failed = video(height: 1080, format: "mp4", codec: "avc1")

        #expect(FormatFallback.candidate(failed: failed, in: [failed]) == nil)
        #expect(FormatFallback.candidate(failed: failed, in: []) == nil)
    }

    @Test("Video never falls back to audio-only")
    func videoNeverFallsBackToAudioOnly() {
        let failed = video(height: 1080, format: "mp4", codec: "avc1")
        let audio = stream(
            url: URL(string: "https://cdn.example.com/audio.m4a")!,
            resolution: nil,
            format: "m4a",
            audioCodec: "mp4a",
            isAudioOnly: true
        )

        #expect(FormatFallback.candidate(failed: failed, in: [audio]) == nil)
    }

    @Test("Local file streams are never fallback candidates")
    func ignoresLocalFiles() {
        let failed = video(height: 1080, format: "mp4", codec: "avc1")
        let local = stream(
            url: URL(fileURLWithPath: "/tmp/downloaded.mp4"),
            resolution: .p1080,
            format: "mp4",
            videoCodec: "avc1",
            audioCodec: "mp4a"
        )

        #expect(FormatFallback.candidate(failed: failed, in: [local]) == nil)
    }

    @Test("Audio-only failure falls back within audio-only streams")
    func audioOnlyFallsBackWithinAudio() {
        let failed = stream(
            url: URL(string: "https://cdn.example.com/opus.weba")!,
            resolution: nil,
            format: "webm",
            audioCodec: "opus",
            isAudioOnly: true
        )
        let m4a = stream(
            url: URL(string: "https://cdn.example.com/audio.m4a")!,
            resolution: nil,
            format: "m4a",
            audioCodec: "mp4a",
            isAudioOnly: true
        )

        let candidate = FormatFallback.candidate(failed: failed, in: [m4a, failed])

        #expect(candidate == m4a)
    }

    @Test("More compatible codecs are preferred among equal candidates")
    func prefersCompatibleCodecs() {
        let failed = video(height: 1080, format: "webm", codec: "av01")
        let hevc = video(height: 1080, format: "mp4", codec: "hvc1")
        let avc = video(height: 1080, format: "mp4", codec: "avc1")

        let candidate = FormatFallback.candidate(failed: failed, in: [hevc, avc, failed])

        #expect(candidate == avc)
    }

    @Test("Codec compatibility ranks unknown codecs below known ones")
    func unknownCodecRanksLowest() {
        #expect(FormatFallback.codecCompatibility("avc1") > FormatFallback.codecCompatibility("av01"))
        #expect(FormatFallback.codecCompatibility("hvc1") > FormatFallback.codecCompatibility("xyz-unknown"))
        #expect(FormatFallback.codecCompatibility(nil) == -1)
    }
}

// MARK: - G3 Instance Health States

@Suite("Instance Health State Tests")
struct InstanceHealthStateTests {

    @Test("Fast successful probe classifies as healthy")
    func healthyClassification() {
        let state = InstanceHealthState.classify(
            InstanceHealthProbeResult(latency: 0.2, error: nil)
        )
        #expect(state == .healthy(latency: 0.2))
    }

    @Test("Slow successful probe classifies as degraded")
    func degradedClassification() {
        let state = InstanceHealthState.classify(
            InstanceHealthProbeResult(latency: InstanceHealthState.degradedThreshold + 0.1, error: nil)
        )
        #expect(state == .degraded(latency: InstanceHealthState.degradedThreshold + 0.1))
    }

    @Test("Probe at exactly the threshold stays healthy")
    func thresholdIsExclusive() {
        let state = InstanceHealthState.classify(
            InstanceHealthProbeResult(latency: InstanceHealthState.degradedThreshold, error: nil)
        )
        #expect(state == .healthy(latency: InstanceHealthState.degradedThreshold))
    }

    @Test("Failed probe classifies as unreachable with the error description")
    func unreachableClassification() {
        let state = InstanceHealthState.classify(
            InstanceHealthProbeResult(latency: nil, error: .timeout)
        )
        guard case .unreachable(let message) = state else {
            Issue.record("Expected unreachable, got \(state)")
            return
        }
        #expect(message == DetectionError.timeout.localizedDescription)
        #expect(!message.isEmpty)
    }

    @Test("Health endpoint is defined for every instance type")
    func healthEndpointsExist() {
        for type in InstanceType.allCases {
            let path = InstanceDetector.healthPath(for: type)
            #expect(path.hasPrefix("/"))
        }
        #expect(InstanceDetector.healthPath(for: .invidious) == "/api/v1/stats")
        #expect(InstanceDetector.healthPath(for: .piped) == "/healthcheck")
        #expect(InstanceDetector.healthPath(for: .peertube) == "/api/v1/config")
        #expect(InstanceDetector.healthPath(for: .yatteeServer) == "/info")
    }
}
