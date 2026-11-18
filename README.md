# SneakPeak — privacy-focused video player for iOS, tvOS and macOS

<div align="center">

[![Platform](https://img.shields.io/badge/platform-iOS%20%7C%20iPadOS%20%7C%20macOS%20%7C%20tvOS-black?logo=apple)](https://github.com/alzimerahmed/SneakPeak)
[![Swift](https://img.shields.io/badge/Swift%206-SwiftUI-orange?logo=swift)](https://www.swift.org)
[![CI](https://github.com/alzimerahmed/SneakPeak/actions/workflows/ci.yml/badge.svg)](https://github.com/alzimerahmed/SneakPeak/actions/workflows/ci.yml)
[![Release](https://img.shields.io/github/v/release/alzimerahmed/SneakPeak?include_prereleases)](https://github.com/alzimerahmed/SneakPeak/releases)
[![AGPL v3](https://shields.io/badge/License-AGPL%20v3-blue.svg)](https://www.gnu.org/licenses/agpl-3.0.en.html)

*Watch from your own sources — Invidious, Piped, PeerTube, self-hosted servers, SMB, WebDAV and local files — without an account.*

[Features](#features) • [Releases](#releases) • [Building](#building)

</div>

---

## Features

* Native SwiftUI interface for iPhone, iPad, Mac and Apple TV, with customization settings
* MPV-based player: 4K playback, H.264/H.265/VP9/AV1, custom controls and gestures
* Fullscreen, Picture in Picture and background audio playback
* Playback queue, history and resume
* [SponsorBlock](https://sponsor.ajay.app/) integration with configurable skip categories
* [DeArrow](https://dearrow.ajay.app/) title and thumbnail replacement
* Subscriptions, bookmarks and playlists with iCloud sync
* Local subscriptions that work without any account
* Incognito playback sessions that skip history, Handoff and remote-control tracking
* Per-instance connection diagnostics and automatic format fallback on stream failure
* Downloads for offline video and audio
* JSON export/import of all user data (subscriptions, history, bookmarks, playlists, settings)
* Thumbnail disk cache for fast SMB/WebDAV browsing
* Automation via the `sneakpeak://` URL scheme, x-callback-url, Shortcuts and Siri
* tvOS Top Shelf integration and share extension

## Releases

Download CI-built artifacts from the [Releases page](https://github.com/alzimerahmed/SneakPeak/releases). Every release is built and tested by GitHub Actions on a macOS runner — see `.github/workflows/release.yml`.

## Building

Requires Xcode 26 or newer on macOS (the source uses iOS 26 APIs).

```bash
git clone https://github.com/alzimerahmed/SneakPeak.git
open SneakPeak.xcodeproj
# select the SneakPeak scheme and run
```

CI builds and tests every push to `main` — see [.github/workflows/ci.yml](.github/workflows/ci.yml).

## Contributing

Fork the repository, create a branch, and open a pull request against `main`. Commits follow [Conventional Commits](https://www.conventionalcommits.org/).

## License

SneakPeak is a fork of [Yattee](https://github.com/yattee/yattee) and is shared under the [AGPL v3](https://www.gnu.org/licenses/agpl-3.0.en.html) license, like upstream. Upstream copyright and attribution are preserved.

© Alzimer Ahmed and SneakPeak contributors; © Yattee contributors for upstream code.
