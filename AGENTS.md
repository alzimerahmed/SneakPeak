# SneakPeak — Rules for AI Agents

## Project

SneakPeak = privacy-focused video player for **iOS + iPadOS + macOS + tvOS** (Swift), forked from Yattee (upstream: https://github.com/yattee/yattee, base `main` @ v2.0.0, re-swept 2026-11-17). Plays YouTube via **Invidious / Piped / self-hosted Yattee Server**, plus **PeerTube, local files, SMB shares, WebDAV**. Core surfaces: custom **MPV-based player** (H.264/H.265/VP9/AV1, 4K), PiP + background audio, SponsorBlock + DeArrow + Return YouTube Dislike integrations, playback queue/history/resume, chapter navigation, subscriptions, bookmarks/playlists, downloads, iCloud sync, Handoff, tvOS TopShelf, Share extension. Highest-severity defect surfaces: **the MPV player pipeline (`Player`/`MPVController`), multi-source account/session layer (`AccountsManager`, `API`), and iCloud sync (CloudKit-backed `DataManager`, SwiftData)**.

**Owner:** Alzimer Ahmed <alzimerahmed84@gmail.com> — repo https://github.com/alzimerahmed/SneakPeak (fresh history, no upstream remote).

**License:** AGPL-3.0. Upstream `LICENSE` and copyright headers in existing source files must be preserved — AGPLv3 does not permit stripping attribution. Upstream monetization (FUNDING.yml, PayPal/donation links, Discord community link, AltStore listing, CNAME) was removed in the rebrand sweep — do not restore.

**Scope:** Single `SneakPeak.xcodeproj` — 4 targets: `SneakPeak` app target (iOS/macOS/tvOS, SwiftUI multiplatform), `SneakPeakShareExtension`, `SneakPeakTopShelf` (tvOS), `SneakPeakTests`. Bundle IDs `com.alzimerahmed.SneakPeak.*`, URL scheme `sneakpeak://`, app group `group.com.alzimerahmed.SneakPeak.shared`. `YatteeServer*`/`yatteeServer*` type names intentionally retained — they denote the upstream **Yattee Server** backend product, not this app's identity. The `yattee/MPVKit.git` dependency URL is the real MPVKit fork — do not "rebrand" it.

## Ground Truth (read first)

- **`docs/architecture.md`** is the architecture & conventions ground truth — read it before touching code. `docs/research.md` (ADRs/gotchas) and `docs/CONCEPTS.md` (vocabulary) back it up. `docs/` is fully gitignored — private, never push.
- **`AGENTS.md`** (this file) is the workflow/rules layer — the only tracked agent doc.
- SwiftFormat/periphery (`.periphery.yml`) own style/lint where configured — don't hand-police what the tooling owns.

## How It Works (domain constraints — read before touching the code)

- **Multiplatform SwiftUI app:** one `SneakPeak/` source tree with `#if os(tvOS)` / `#if os(macOS)` conditionals; `AppDelegate`/scene lifecycle differs per platform. tvOS has a separate `Info-tvOS.plist` and the TopShelf extension.
- **Player = MPV (libmpv), not AVPlayer:** MPV is vendored via the MPVKit Swift package; `MPVController` owns the render pipeline; `Player` (ObservableObject) is the app-facing facade — queue, chapters, seek, speed, PiP. Player UI is SwiftUI with gesture layers (seek/volume/brightness) and seek-preview storyboards.
- **API layer:** `API` protocol with per-backend implementations — Invidious, Piped, PeerTube, Yattee Server, Local, SMB, WebDAV. `AccountsManager` owns per-account sessions/credentials (Keychain-backed). SponsorBlock/DeArrow/RYD are auxiliary API clients layered on top.
- **Persistence:** SwiftData-backed `DataManager` + iCloud sync (bookmarks, subscriptions, history, settings). Sync conflicts and per-account isolation are the fragile spots.
- **Downloads:** offline video/audio with quality selection; background download tasks.
- **Integrations:** SponsorBlock skip categories are user-configurable; DeArrow swaps titles/thumbnails; both degrade gracefully offline.

## Tech Stack & Conventions (do not fight it)

- **Deployment targets:** iOS 18.0 / macOS 15.0 / tvOS 18.0 — newest APIs freely, no availability checks for older OSes.
- **Swift 5 language mode + approachable concurrency** (`SWIFT_APPROACHABLE_CONCURRENCY=YES`) — write Sendable-correct code; Xcode 26 toolchain required (source uses iOS 26 APIs).
- **Build configurations:** `Debug`, `Release` (App Store/TestFlight, **must stay Sparkle-free**), `Release-DeveloperID` (Sparkle auto-update, GitHub Releases + Homebrew cask). All Sparkle code wrapped in `#if SPARKLE`.
- **Lint:** `periphery scan` (dead code) — config `.periphery.yml`.
- **Localization:** `Localizable.xcstrings` exists; upstream used Weblate (`weblate-credits.json`).
- **Commits:** Conventional Commits (`type(scope): description`). Work on `main` (fresh repo).
- **Upstream:** no upstream remote by design. Cherry-pick from `yattee/yattee` only if deliberately decided — prefer additive changes so cherry-picks stay cheap.

## Build / Verify

```bash
# CI only — .github/workflows/ci.yml (push to main, PRs to main):
#   macos-26 runner, Xcode 26 (iOS 26 SDK required — source uses iOS 26 APIs)
#   → xcodebuild -resolvePackageDependencies
#   → build-for-testing (Debug, macOS destination, ad-hoc signed, no entitlements)
#   → test-without-building -only-testing:SneakPeakTests
#     (skips entitlement-dependent suites — see ci.yml for the -skip-testing list)
```

**Remote-first verification (mandatory):** this workspace is **Windows — we do NOT build or test locally.** No Xcode here; local work is edit-only + static review. Push and let GitHub Actions verify — a CI green check counts as the gate.

**No secret-dependent jobs:** CI builds/tests unsigned — never add steps needing signing certs, Match certs, App Store Connect keys, or notarization credentials. Fastlane `Match`/notarization lanes are removed — keep them out of CI.

## Removed on Purpose — Do NOT Re-add

- `.github/FUNDING.yml` (upstream GitHub Sponsors/Patreon/donations), `CNAME` (upstream site domain), `altstore-source.json` (upstream's AltStore listing), `buildServer.json` (local SourceKit state), `DerivedDataReview/` (review artifacts), `fastlane/` + `Gemfile*` (App Store delivery lanes needing certs we don't have), `Yattee2.icon`.
- Upstream ownership strings replaced: GitHub links → `alzimerahmed/SneakPeak`, support/donation/Discord links removed, `ORGANIZATIONNAME`, LaunchScreen/About copyright.
- Do NOT remove upstream copyright headers in existing source files or `LICENSE` (AGPLv3 legal requirement), and do NOT remove upstream attribution from README.
- Upstream `.github/workflows/release.yml` and `update-altstore.yml` removed — they publish upstream artifacts; our CI is `ci.yml` until the SneakPeak release pipeline shipped (release.yml added 2026-11-18).

## Gotchas

- **No local build safety net** — grep all references (`project.pbxproj`, entitlements, `Info.plist`, schemes, URL scheme `sneakpeak://`, app group `group.com.alzimerahmed.SneakPeak.shared`) before deleting or renaming anything.
- **MPV vendoring:** MPV comes from the `yattee/MPVKit` package pin — do not "upgrade" it casually; the build assumes those binaries.
- **`#if SPARKLE` discipline:** adding Sparkle-touching code outside the guard breaks the App Store `Release` config.
- **tvOS conditionals:** `#if os(tvOS)` blocks diverge silently — test-relevant changes need the tvOS target considered even though CI runs macOS tests only.
- **Typos/legacy names are API:** `YatteeServer*`/`yatteeServer*` identifiers name the upstream Yattee Server product — do not "rebrand" them. Any other legacy `Yattee*` type names only change in coordinated passes.
- **Tests are macOS-hosted:** `xcodebuild test -destination 'platform=macOS'` — player/network tests are mocked; don't point them at live Invidious instances.
- Windows checkout: shell scripts (`*.sh`) and plist XML are line-ending sensitive — write LF.
- Windows Git Bash: `printf` mangles `\U`/`\C` in backslash paths — use forward slashes or heredocs.

## Agent Guidelines & Workflow (this repo's .devin system)

### Resource Discipline (mandatory, non-trivial tasks)
Before any non-trivial task:
1. Read `docs/toolset.md` intent-map (task type → resources)
2. Invoke every skill + sub-agent in that row
3. Read every rule for that task type (`.devin/rules/`)
4. At task end: `code-reviewer` sub-agent on final diff (non-negotiable)
5. Append learnings via `/ce-compound` if durable lesson

Phase implementations follow `.devin/prompt/phase.md`; quick tasks follow `.devin/prompt/quick.md` + `.devin/prompt/rules.md`. Skip all this for single-line edits, pure Q&A, reading files.

### Project-Type Filter (native iOS/macOS/tvOS Swift app)
Per `docs/toolset.md` intent-map:
- **Skip irrelevant:** css-architect (no CSS), pwa-engineer (native app — keep offline-*patterns* only), web-scraper, design-cloner, monorepo-manager (single `.xcodeproj`), email-engineer (no email surface), payment-integrator (AGPL FOSS, no purchases), seo-specialist (deferred → ASO at ship phase).
- **Keep universal:** code-reviewer, debugger, test-engineer, security-auditor, performance-engineer, git-master, migration-specialist, docs-writer, build-optimizer, devops-engineer, dx-optimizer, caveman-compressor, vibe-coding-auditor.
- **Keep domain-fit:** media-optimizer (video pipeline = core), animation-engineer, design-system-builder, frontend-designer (SwiftUI taste, anti-slop), content-writer, backend-architect (API layer: Invidious/Piped/PeerTube/SMB/WebDAV), state-manager, database-engineer (SwiftData + CloudKit sync), file-handler (downloads = core), search-architect (unified multi-source search), realtime-engineer (Handoff/remote-control phases), i18n-specialist (xcstrings/Weblate), type-safety-engineer (Swift 6 strict concurrency), a11y-specialist (VoiceOver), analytics-engineer (privacy-first, local-only), pixel-analyst, researcher.
- **Quality gates:** CI-only — unsigned build + `SneakPeakTests` on GitHub Actions macOS runner. No local builds.

## Communication Style

Default **caveman-lite** (lightly compressed, readable, technically accurate). `/caveman` skill for full/ultra/wenyan modes.

## Key References

> `docs/` is the private knowledge layer — **fully gitignored**, local workspace only. `AGENTS.md` is the only tracked agent doc.

- `docs/toolset.md` — intent map (task type → skills, sub-agents, rules)
- `docs/plan.md` — phased plan + status
- `docs/project.md` — project state/structure
- `docs/tools-log.md` — .devin resources invoked per session
- `docs/CONCEPTS.md` — project vocabulary
- `docs/research.md` — research, ADRs, gotchas, open questions
- `docs/idea.md` — competitive analysis + Feature Gap List
- `docs/design/design-system.md` — UI tokens + rules
- `docs/architecture.md` — architecture ground truth
