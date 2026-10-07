# Changelog

## 1.0.0 - 2026-10-07

First release of a native macOS client for YouTube Music.

### Playback

- Native playback with no external tools: stream resolution and signature decoding run inside the app
- Docked playback bar with shuffle, repeat, volume, like, and an always-visible progress bar
- Media keys and Control Center integration
- Crossfade between tracks, with the next track preloaded so it starts faster
- Autoplay: continues with a radio mix when the queue runs out
- Radio and artist mixes ("Start radio", "Shuffle" on artist pages)
- 10-band graphic equalizer with presets
- Volume normalization
- Restores the queue and playback position on launch
- Plays are reported to your YouTube Music watch history, attributed to their playlist

### Browse

- Home feed with filter chips and infinite scroll
- Search with suggestions
- Explore, with charts shown as ranked rows and trend arrows
- Album, artist, playlist, channel, and feed pages with immersive tinted headers and artist banners
- Context menus on tracks and cards: play, play next, add to queue, start radio, like, add to playlist, share

### Library

- Sign in with your Google account; credentials are stored in the Keychain
- Library with server-provided filter chips, also listed in the sidebar
- Liked songs, listening history (with per-item removal), and uploads
- Upload and delete your own music files
- Create, rename, and delete playlists; add and remove tracks
- Playlist search, filter chips, and sort order
- Save playlists and subscribe to artists

### Now playing

- Inspector panel with Queue, Lyrics, Related, and Comments tabs
- Queue editing
- Timed lyrics from YouTube Music, LRCLIB, and Musixmatch, with word-level sync where available
- Related tracks and an on-device "About this song" insight
- Immersive visualizers, spectrum analyzer, and an ambient background tinted from the cover art

### Plugins

- Discord Rich Presence with links, display type, and automatic reconnect
- Track change notifications
- Last.fm scrobbling with your own API credentials
- Downloader for tracks, albums, and playlists

### App

- Native Settings window (General, Playback, Equalizer, Plugins, Storage)
- Proxy support for API requests and the audio stream
- Open at login
- Automatic updates via Sparkle
- Storage tab showing cache size, with a button to clear it
- Menu-bar commands and keyboard shortcuts
- Light and dark mode
- Crash reporting
