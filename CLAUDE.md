# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A native **macOS SwiftUI** YouTube Music client (bundle id `moe.tenshii.YT-Music`). There is no official YT Music API, so the app reverse-implements YouTube's private **InnerTube** API directly in Swift as the `WEB_REMIX` (YT Music web) client — no Python, sidecar, or yt-dlp at runtime. Playback (including signature/`n` deciphering) is all native Swift + JavaScriptCore.

## Commands

`xcode-select` points at CommandLineTools (no `xcodebuild`), so every build/test must point `DEVELOPER_DIR` at the installed Xcode-beta:

```sh
# Build
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
  xcodebuild -scheme "YT Music" -destination 'platform=macOS' build

# Run all tests
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
  xcodebuild -scheme "YT Music" -destination 'platform=macOS' test

# Run a single test (Swift Testing) — filter by suite/test name
DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer \
  xcodebuild -scheme "YT Music" -destination 'platform=macOS' test \
  -only-testing:"YT MusicTests/StreamSelectionTests"
```

- The project uses `PBXFileSystemSynchronizedRootGroup` (objectVersion 110): any `.swift` file dropped under `YT Music/` or `YT MusicTests/` is auto-included in its target — **never hand-edit `project.pbxproj` to add sources.**
- Tests use **Swift Testing** (`import Testing`, `@Test`/`@Suite`/`#expect`/`#require`), hosted in the app (`@testable import YT_Music`). The shared scheme `YT Music.xcscheme` wires the test action — required for `xcodebuild test` to find it.

## Concurrency model (important, easy to trip on)

The module sets `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`. So **everything is `@MainActor` by default.** Networking/parsing types that must run off-main are explicitly marked `nonisolated` (the InnerTube client, the decipher/resolver actors, DTOs, parsers). Any new model with computed properties touched off-main must be `nonisolated` too.

## Architecture

UI/state are `@Observable` + environment-injected; network layer is `nonisolated` actors. App-level state (`PlayerState`, `AuthStore`, sidebar `selection`) lives on the `App` struct as `@State` and is passed via environment, so the single `Window` (not `WindowGroup` — no ⌘N / multi-window) can close and reopen with state intact. An `AppDelegate` keeps the process alive after the last window closes so playback continues in the background.

Layers under `YT Music/`:

- **`Auth/`** — sign-in is a `WKWebView` sheet (`LoginView`) to music.youtube.com that captures the cookie jar once a SAPISID appears (uses a desktop Safari user agent). `Credentials` turns cookies into request headers (`Cookie` + `Authorization: SAPISIDHASH …` + `X-Goog-AuthUser`). `CredentialStore` (actor singleton) persists creds in the **Keychain** and supplies headers to every request (empty when signed out, so auth is purely additive). `AuthStore` (`@MainActor @Observable`) drives UI + a `generation` counter that views key `.task(id:)` on to re-personalize on sign-in/out.
- **`InnerTube/`** — the API client and DTOs. `InnerTubeClient` POSTs to `youtubei/v1/browse` (home feed, entity pages) and `youtubei/v1/next` (radio: `playlistId="RDAMVM<videoId>"`). `BrowseResponse`/`EntityBrowseResponse`/`WatchNextResponse` are shared Decodable renderers (all keys optional). `*Parser` files turn raw renderers into domain models.
- **`Models/`** — domain types: `HomeFeed`, `EntityPage`/`EntityHeader`/`Track`, `EntityDestination` (Hashable nav value).
- **`Features/`** — screens. `Home` owns the `NavigationStack` + `navigationDestination(for: EntityDestination.self)`; cards push entity pages. `Components/Cards.swift` holds reusable `ShelfView`/`ItemCard`/`ArtworkView` and the `.musicContextMenu(...)` modifier. `Library` requires auth (signed-out → prompt). The now-playing bar is a **docked** full-width row at the bottom of the VStack wrapping the NavigationSplitView (not an overlay/safeAreaInset).
- **`Player/`** — `AudioPlayer` (`@MainActor @Observable` AVPlayer wrapper) publishes to Control Center / media keys via `MPNowPlayingInfoCenter` and routes `MPRemoteCommandCenter` commands back. `PlayerState` owns the queue + `repeatMode` + transport, and persists/restores a snapshot via `PlaybackStore` (`UserDefaultsPlaybackStore`; nil in tests). `PlayerState` init takes optional `AudioOutput`/`StreamResolving` for test injection (nil → real defaults).

### Playback / deciphering (the fragile, high-value part)

The signature + `n`-parameter solving is the most brittle code and breaks whenever YouTube ships a new `base.js`:

- `StreamResolver` (actor) makes the `player` request with `sts`, picks the highest-bitrate **AAC/MP4** format (AVPlayer can't decode Opus/WebM), and deciphers the URL.
- `SignatureDecipher` (actor) fetches `base.js`, extracts `signatureTimestamp`, and solves sig + `n` by **running YouTube's own player code in JavaScriptCore** (it stubs browser globals, finds the URL-signer candidate structurally via the `.set("alr","yes")` fingerprint, and injects a solver before the IIFE close). `JSExtraction.swift` provides regex + brace-matching helpers with nonisolated testing seams.
- When this breaks: reference **yt-dlp**'s `youtube` extractor and its bundled deno solver (`yt.solver.core.js`) as ground truth. `PlaybackLog` (OSLog subsystem `moe.tenshii.YT-Music`, category `playback`, 🎵) logs every resolve stage; on solver failure it dumps the live base.js to `Caches/yt-base.js`. Read with `log stream --predicate 'subsystem == "moe.tenshii.YT-Music"'`.
- WEB_REMIX without auth/PoToken can return `LOGIN_REQUIRED`/`UNPLAYABLE`, and some tracks get SABR/DRM experiments that hide plain URLs.

## Gotchas

- **`BrowseResponse.SectionContent` is a `final class`, not a struct, deliberately.** As a large aggregate struct it hit a toolchain value-witness miscompile (`outlined init with copy` → EXC_BAD_ACCESS). Reference semantics avoid the bulk value copy. Apply the same fix if other big aggregate DTOs crash similarly.
- Required entitlement `ENABLE_OUTGOING_NETWORK_CONNECTIONS = YES` (both build configs; App Sandbox is on). JavaScriptCore runs via its non-JIT interpreter under hardened runtime — no extra entitlement.

## Test coverage

Playback pipeline only, all network-free: sig/`n` decipher against a synthetic base.js (`SignatureDecipherTests`), JS extraction helpers, `StreamResolver.selectAudioFormat`, `Credentials` header building, `PlayerState` resolve→load/error via injected fakes, link building, library/account/watch-next parsing. Not covered (needs live network/AVPlayer): the real `player` request, `playabilityStatus` handling, live base.js extraction, audio output.
