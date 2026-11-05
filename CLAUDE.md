# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

A native **macOS SwiftUI** YouTube Music client (bundle id `moe.tenshii.YT-Music`). There is no official YT Music API, so the app reverse-implements YouTube's private **InnerTube** API in Swift as the `WEB_REMIX` (YT Music web) client. No Python, sidecar, or yt-dlp at runtime: playback, including signature/`n` deciphering, is native Swift + JavaScriptCore.

Beyond browsing and playback it covers search, explore, podcast episodes, listening history, uploads (browse, upload, delete your own files), playlist editing (create/rename/delete, add/remove tracks, collaboration, voting), a now-playing queue/lyrics/comments inspector, timed lyrics (three providers), and a menu-bar command set with keyboard shortcuts.

## Commands

`xcode-select -p` should point at a full Xcode install (not bare CommandLineTools) for `xcodebuild` to work. If it doesn't, point `DEVELOPER_DIR` at your installed Xcode.app for each command below.

```sh
# Build
xcodebuild -scheme "YouTube Music" -destination 'platform=macOS' build

# Run all tests
xcodebuild -scheme "YouTube Music" -destination 'platform=macOS' test

# Run a single test (Swift Testing), filtered by suite/test name
xcodebuild -scheme "YouTube Music" -destination 'platform=macOS' test \
  -only-testing:"YT MusicTests/StreamSelectionTests"
```

- The project uses `PBXFileSystemSynchronizedRootGroup` (objectVersion 110): any `.swift` file under `YT Music/` or `YT MusicTests/` is auto-included in its target. **Never hand-edit `project.pbxproj` to add sources.**
- Tests use **Swift Testing** (`import Testing`, `@Test`/`@Suite`/`#expect`/`#require`), hosted in the app (`@testable import YT_Music`). The shared scheme `YouTube Music.xcscheme` wires the test action, which `xcodebuild test` needs.

## Concurrency model

The module sets `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, so **everything is `@MainActor` by default.** Types that must run off-main are explicitly `nonisolated`: the InnerTube client, the decipher/resolver actors, DTOs, parsers. Any new model with computed properties touched off-main must be `nonisolated` too.

## Architecture

UI and state are `@Observable` and environment-injected; the network layer is `nonisolated` actors.

App-level state (`PlayerState`, `AuthStore`, sidebar `selection`) lives on the `App` struct as `@State` and is passed via environment. The app uses a single `Window` (not `WindowGroup`, so no ⌘N or multi-window), which can close and reopen with state intact. An `AppDelegate` keeps the process alive after the last window closes so playback continues in the background. A second `Window` (id `stats`) hosts Stats for Nerds.

### `Auth/`

- Sign-in is a `WKWebView` sheet (`LoginView`) to music.youtube.com that captures the cookie jar once a SAPISID appears (desktop Safari user agent).
- `Credentials` turns cookies into request headers: `Cookie`, `Authorization: SAPISIDHASH ...`, `X-Goog-AuthUser`.
- `CredentialStore` (actor singleton) persists creds in the **Keychain** and supplies headers to every request. Headers are empty when signed out, so auth is purely additive.
- `AuthStore` (`@MainActor @Observable`) drives UI and a `generation` counter that views key `.task(id:)` on to re-personalize on sign-in/out.

### `InnerTube/`

The API client and DTOs.

- `InnerTubeClient` POSTs to `youtubei/v1/browse` (home feed, entity pages, `FEmusic_history`, `FEmusic_library_privately_owned_landing` uploads) and `youtubei/v1/next` (radio via `playlistId="RDAMVM<videoId>"`, plus the lyrics-tab browse id and the comments token).
- `BrowseResponse`/`EntityBrowseResponse`/`WatchNextResponse` are shared Decodable renderers with all keys optional. `*Parser` files turn raw renderers into domain models.
- Multi-client: a `ClientProfile` selects `webRemix` (default, music.youtube.com) or `web` (www.youtube.com). **Comments are fetched anonymously via the `web` client**: they are a YouTube surface, not a YT Music one, and audio-only tracks often have no panel.
- Capability groups:
  - **Lyrics**: `LyricsProviding.lyrics(for:)` is two-step (`next` → lyrics browse id → `browse`). `InnerTubeClient` conforms alongside the standalone providers.
  - **Comments**: `CommentsProviding` (`comments`/`moreComments`/`commentReplies`).
  - **Playlist edits**: `createPlaylist`/`deletePlaylist`/`renamePlaylist`/`addToPlaylist`/`removeFromPlaylist` via `browse/edit_playlist` batch actions. **Remove needs both `videoId` and the playlist-scoped `setVideoId`.** `addToPlaylistOptions` comes from `playlist/get_add_to_playlist`.
  - **History**: `history()` and `removeHistoryItems(feedbackTokens:)` via `feedback`. Tokens are per row; there is no bulk clear.
  - **Uploads**: `uploads()`, two-step resumable `uploadSong(fileURL:)` to `upload.youtube.com`, `deleteUpload(entityId:)`.
- Auth 401 maps to `InnerTubeError.unauthorized` and posts a `.ytmSessionExpired` notification.

### `Models/`

Domain types:

- Shelves and pages: `Shelf`/`ShelfItem` (shared by every shelf-laid-out page), `HomeFeed`/`FeedChip`, `EntityPage`/`EntityHeader`, `Track`, `EntityDestination` (Hashable nav value).
- Library and playlists: `HistorySection` (date-bucketed, each its own playable queue), `EditablePlaylist` (the "add to playlist" picker model), `PlaylistVoting`, `PlaylistCollaboration` (the `get_panel` collaboration settings).
- Comments: `Comment`/`CommentPage` (paginated, with reply tokens).
- Lyrics: `Lyrics` (plain `text`, optional synced `lines`, `source`), `LyricLine`/`TimedWord` (per-word richsync timing), `LyricsFocus` (`.none`/`.line`/`.interlude(progress:)`), `LyricsProvider` (`.youtubeMusic`/`.lrclib`/`.musixmatch`), `LyricsQuery`, plus the `LRCParser`/`MusixmatchRichSync` decoders. All `nonisolated` and unit-tested.

### `Features/`

Screens.

- `Home` owns the `NavigationStack` and `navigationDestination(for: EntityDestination.self)`; cards push entity pages.
- `Navigator` routes app-wide so the now-playing bar and context menus, which sit outside every tab's `NavigationStack`, can open artist/album pages.
- `Components/` holds the reusable `ShelfViews.swift` (`ShelfView`), `Cards.swift` (`ItemCard`), `ArtworkView.swift`, and `MusicContextMenu.swift` (the `.musicContextMenu(...)` modifier).
- `Library` requires auth (signed-out shows a prompt).
- The now-playing bar is a **docked** full-width row at the bottom of the VStack wrapping the NavigationSplitView, not an overlay or `safeAreaInset`.
- Now-playing extras: `ImmersiveLyricsView` (full-screen lyrics), `SpectrumVisualizerView`/`MilkdropVisualizerView` (immersive visualizers), `StatsForNerdsView`.

### `Player/`

- `AudioPlayer` (`@MainActor @Observable` AVPlayer wrapper) publishes to Control Center and media keys via `MPNowPlayingInfoCenter` and routes `MPRemoteCommandCenter` commands back. It holds **two AVPlayers** (`active`/`idle`) for crossfade.
- `PlayerState` owns the queue, `repeatMode`, and transport, and persists/restores a snapshot via `PlaybackStore` (`UserDefaultsPlaybackStore`; nil in tests). Its init takes optional `AudioOutput`/`StreamResolving`/`AppSettings` for test injection (nil uses the real defaults).
- **Autoplay**: when a track starts with nothing after it (a one-off from home, or the last album/playlist track) and repeat is off, `maybeContinueWithRadio`/`appendRadio` fetch a radio and append its tracks. A one-off's seed becomes the queue head; explicit `startRadio` still replaces the queue.
- `VolumeNormalization`: YouTube-style loudness. Tracks louder than the reference level are turned down; quieter ones are left alone.
- `Handoff`: advertises the playing track as its music.youtube.com URL.
- `WatchHistory` (in `InnerTube/`): reports plays to YT Music history via the player response's `videostatsPlaybackUrl`/`videostatsWatchtimeUrl`.
- `Shared/PlaybackIntents`: App Intents for Shortcuts, Siri, and Spotlight, driving the shared `PlayerState`.

#### Equalizer and spectrum

- `Player/Equalizer.swift` + `Player/EqualizerTap.swift`. AVPlayer has no native EQ, so a graphic EQ runs in an `MTAudioProcessingTap` installed per `AVPlayerItem`, applying RBJ peaking biquads (`Biquad`/`BiquadState`) to the decoded PCM.
- The pure DSP/model (bands, presets, `EqualizerSettings`, processor) is `nonisolated` and unit-tested. The tap glue is the untested realtime layer.
- Gotcha: tap C-callbacks must be `nonisolated` to form `@convention(c)` pointers under the module's default `@MainActor` isolation.
- `SpectrumAnalyzer` is an FFT meter that piggybacks on the same tap and feeds the visualizers.

### `Networking/`

- `NetworkSession` holds `NetworkProxy` (http/https only) and applies the `proxyURL` setting.
- AVPlayer has no proxy option, so `ProxiedStreamLoader` rewrites stream URLs to a custom scheme and fetches them through the proxy.

### `Settings/`

- `AppSettings` (`@MainActor @Observable`, UserDefaults-backed, env-injected, created before `PlayerState`) holds:
  - Audio: `audioQuality`/`preferAudioOverVideo` (become a Sendable `StreamPreferences` for the resolver), `volumeNormalization`, `crossfadeEnabled`/`crossfadeSeconds`, `nextTrackPreloadSeconds`, persisted volume/mute, `podcastPlaybackRate`.
  - Equalizer: 10 bands (`equalizerEnabled` + per-band dB `equalizerGains`), exposed as a Sendable `EqualizerSettings` via an `onEqualizerChange` callback wired by `PlayerState`.
  - Behavior: `autoplay`, `lyricsProvider`, `playOnSingleClick`, `proxyURL`, `openAtLogin` (`LoginItem`).
  - Downloads: `downloadDirectory`, a security-scoped bookmark.
- `SettingsView` is the native macOS `Settings` scene (⌘,): a toolbar-tab `TabView` with General, Playback, Equalizer, Plugins, and Storage tabs. Its environments are injected separately from the main window scene.
  - General: login item, proxy, Sparkle updates (`UpdateCommands` adds Check for Updates).
  - Storage: clears the cache.
  - Plugins: registry-driven (see below).

### `Plugins/`

A registry, not hardcoded wiring.

- `Plugin` is a `@MainActor` protocol: `id`/`name`/`summary`, `setActive`, `playbackDidChange`, `playbackDidProgress` (~0.5s playhead ticks), optional `configuration: AnyView?`.
- `PluginHost` (`@Observable`) owns `[any Plugin]`, persists enabled ids (`"plugins.enabled"`), and fans `PlayerState.onPlaybackChange` (a Sendable `PlaybackSnapshot`) and `onPlaybackProgress` out to enabled plugins via the generic `PluginBridge`.
- **Adding a plugin = write one type + add one line to the `plugins` array in `YT_MusicApp.init()`.**
- Concrete plugins:
  - `DiscordPlugin` → `DiscordRPC` (unix-socket IPC).
  - `NotificationsPlugin` → `TrackChangeNotifier`.
  - `LastfmPlugin` → `LastfmClient`/`ScrobbleTracker`. The signature, eligibility, and tracker are tested; the network/auth layer is not. The user enters their own API key and shared secret in the plugin config and approves access in the browser (desktop token flow: `auth.getToken` → approve on last.fm → `auth.getSession`). The session key is persisted with the account in the Keychain. No hardcoded credentials, and the password never touches the app.
  - `DownloaderPlugin` → `Downloader` (batch album/playlist downloads into per-collection subfolders; needs `ENABLE_USER_SELECTED_FILES = readwrite`).
  - `SponsorBlockPlugin` → `SponsorBlockClient` (skips segments of the chosen categories from `playbackDidProgress`).
  - `ReturnYouTubeDislikePlugin` → `ReturnYouTubeDislike` (dislike counts from returnyoutubedislikeapi.com).

## Playback and deciphering (the fragile, high-value part)

Signature and `n`-parameter solving is the most brittle code and breaks whenever YouTube ships a new `base.js`.

- `StreamResolver` (actor) makes the `player` request with `sts`, picks the highest-bitrate **AAC/MP4** format (AVPlayer can't decode Opus/WebM), and deciphers the URL.
- `SignatureDecipher` (actor) fetches `base.js`, extracts `signatureTimestamp`, and solves sig + `n` by **running YouTube's own player code in JavaScriptCore**. It stubs browser globals, finds the URL-signer candidate structurally via the `.set("alr","yes")` fingerprint, and injects a solver before the IIFE close. `JSExtraction.swift` provides regex and brace-matching helpers with nonisolated testing seams.
- WEB_REMIX without auth/PoToken can return `LOGIN_REQUIRED`/`UNPLAYABLE`, and some tracks get SABR/DRM experiments that hide plain URLs.

### When it breaks

- Use **yt-dlp**'s `youtube` extractor and its bundled deno solver (`yt.solver.core.js`) as ground truth.
- `StreamResolver`/`SignatureDecipher` log every resolve stage to OSLog (subsystem `moe.tenshii.YT-Music`, category `playback`); `InnerTubeClient` logs each request under `requests`. Read with `log stream --predicate 'subsystem == "moe.tenshii.YT-Music"'`.
- On solver failure `DebugDump` writes the live base.js to `Caches/yt-base.js`.

### Latency (expected, not a bug)

Starting a track runs `StreamResolver.audioStream`: `signatureTimestamp()` → `player` POST → `selectAudioFormat` → `streamURL(for:)` decipher → AVPlayer buffers the googlevideo stream before audio starts. The base.js fetch and JSCore solver build are **cached** (`SignatureDecipher.cached`), so the first play of a session is slowest. Later plays still pay one `player` round-trip plus remote buffering (typically 1-3s).

**Seeking**: `AudioPlayer.seek` uses a 0.75s `toleranceBefore/After` so AVPlayer snaps to the nearest keyframe instead of decoding to the exact frame over a remote stream. Scrubbing is near-instant at the cost of frame precision, which is fine for a music player.

## Gotchas

- **`BrowseResponse.SectionContent` is a `final class`, not a struct, deliberately.** As a large aggregate struct it hit a toolchain value-witness miscompile (`outlined init with copy` → EXC_BAD_ACCESS). Reference semantics avoid the bulk value copy. Apply the same fix if other big aggregate DTOs crash similarly.
- **End-of-track relies on a backstop, not just the notification.** With two AVPlayers, `AudioPlayer` fires `signalEnd()` once per item (`hasSignalledEnd`). Besides `didPlayToEndTimeNotification`, `tick` signals end when `timeControlStatus != .playing && currentTime >= duration-0.5`, and clamps `currentTime` to `duration`. `PlayerState.crossfadeLoading` stops a faded-out track's natural end from double-advancing. Don't remove these or a missed notification will hang playback (the original symptom).
- **App Sandbox is off** (`ENABLE_APP_SANDBOX = NO`, hardened runtime on). That is why `DiscordRPC` can reach Discord's local IPC socket (`discord-ipc-N` in the real host `$TMPDIR`). `ENABLE_OUTGOING_NETWORK_CONNECTIONS = YES` is set in both build configs but is a no-op while the sandbox is off.
- JavaScriptCore runs via its non-JIT interpreter under hardened runtime, so no extra entitlement is needed.

## Test coverage

Everything is network-free. Suites cover:

- **Playback pipeline**: sig/`n` decipher against synthetic and realistic base.js (`SignatureDecipherTests`, `SignatureDecipherRealisticTests`), JS extraction helpers, `StreamResolver.selectAudioFormat`, `PlayerState` resolve→load/error via injected fakes, volume normalization, EQ DSP, spectrum analyzer.
- **Parsers and models**: home, search, explore, entity, library, history, uploads, watch-next, related, comments, credits, lyrics, add-to-playlist, collaboration, voting, podcasts, account info.
- **Plugins and services**: `PluginHost`, Discord RPC, Last.fm, SponsorBlock, Return YouTube Dislike.
- **Misc**: `Credentials` header building, link building, `Navigator`, network proxy and `ProxiedStreamLoader`, Handoff.

Not covered (needs live network or AVPlayer): the real `player` request, `playabilityStatus` handling, live base.js extraction, audio output, `AudioPlayer`, the downloader, and the library/history/uploads view models.
