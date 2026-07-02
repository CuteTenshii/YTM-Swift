# YT Music

A native **macOS** YouTube Music client, built entirely in **SwiftUI**.

There's no official YouTube Music API, so this app reverse-implements YouTube's
private **InnerTube** API directly in Swift — no Python, no sidecar, no yt-dlp.
Browsing, playback, and even signature/`n`-parameter deciphering all run natively
in Swift + JavaScriptCore.

## Features

- 🎵 **Playback** — gapless streaming with crossfade and a 10-band graphic equalizer
- 🏠 **Browse** — home feed, explore, search, albums, artists, and playlists
- 📚 **Library** — your playlists, likes, listening history, and uploads
- ✏️ **Playlist editing** — create, rename, delete, and add/remove tracks
- ⬆️ **Uploads** — browse, upload, and delete your own music files
- 🎤 **Lyrics** — timed & synced lyrics from three providers (YouTube Music, LRCLIB, Musixmatch)
- 💬 **Now Playing panel** — queue, lyrics, and comments inspector
- 📻 **Radio & autoplay** — start a radio from any track; queue keeps going on its own
- ⌨️ **Menu-bar commands** with keyboard shortcuts and Control Center / media-key support
- 🔌 **Plugins** — Discord Rich Presence, notifications, Last.fm scrobbling, and a downloader

## Requirements

- macOS (Apple Silicon or Intel)
- A recent Xcode to build
- A Google account to sign in (sign-in happens in an embedded web view; cookies are stored in the Keychain)

## Building

Open `YT Music.xcodeproj` in Xcode and hit **Run**.

## Architecture

State is `@Observable` and injected through the environment; the networking layer
is a set of `nonisolated` actors. The module defaults to `@MainActor` isolation,
so anything that runs off-main is explicitly marked.

| Layer | Responsibility |
| --- | --- |
| `Auth/` | Web-view sign-in, cookie → header credentials, Keychain persistence |
| `InnerTube/` | The InnerTube API client, DTOs, and parsers |
| `Models/` | Domain types (feeds, tracks, playlists, lyrics, comments…) |
| `Features/` | Screens — Home, Search, Library, Entity pages, Now Playing, Uploads… |
| `Player/` | `AudioPlayer` (dual-AVPlayer crossfade), queue, equalizer tap |
| `Settings/` | Audio prefs, equalizer, download directory |
| `Plugins/` | Registry-driven integrations (Discord, notifications, Last.fm, downloader) |

The fragile, high-value part is **stream resolution**: `StreamResolver` picks the
best AAC/MP4 format and `SignatureDecipher` solves the signature and `n` parameter
by running YouTube's own `base.js` player code inside JavaScriptCore. This is what
breaks when YouTube ships a new player build.

## Testing

Unit tests use **Swift Testing** and cover the playback pipeline network-free:
signature/`n` deciphering against a synthetic `base.js`, stream format selection,
credential header building, lyrics parsing, and queue/resolve logic.

## Disclaimer

An unofficial client for personal use. Not affiliated with, endorsed by, or
sponsored by Google or YouTube.
