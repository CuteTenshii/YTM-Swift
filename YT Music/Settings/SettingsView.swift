//
//  SettingsView.swift
//  YT Music
//

import Sparkle
import SwiftUI

struct SettingsView: View {
    let updater: SPUUpdater?

    var body: some View {
        TabView {
            Tab("settings.tab.general", systemImage: "gearshape") {
                GeneralSettingsTab(updater: updater)
            }
            Tab("settings.tab.playback", systemImage: "speaker.wave.2") {
                PlaybackSettingsTab()
            }
            Tab("settings.tab.equalizer", systemImage: "slider.horizontal.3") {
                EqualizerSettingsTab()
            }
            Tab("settings.tab.plugins", systemImage: "puzzlepiece.extension") {
                PluginsSettingsTab()
            }
            Tab("settings.tab.storage", systemImage: "internaldrive") {
                StorageSettingsTab()
            }
        }
    }
}

private struct GeneralSettingsTab: View {
    let updater: SPUUpdater?
    @Environment(AppSettings.self) private var settings
    @State private var checksForUpdates = false

    var body: some View {
        @Bindable var settings = settings

        Form {
            Section("settings.general.startup") {
                Toggle("settings.general.open_at_login", isOn: $settings.openAtLogin)
            }

            Section("settings.general.language") {
                Picker("settings.general.language.title", selection: $settings.language) {
                    ForEach(AppLanguage.allCases) { Text($0.label).tag($0) }
                }
                if settings.needsRelaunchForLanguage {
                    LabeledContent {
                        Button("settings.general.language.relaunch") { settings.relaunch() }
                    } label: {
                        Text("settings.general.language.help")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.disabled)
                    }
                }
            }

            Section("settings.general.network") {
                TextField("settings.general.proxy.title", text: $settings.proxyURL)
                    .textFieldStyle(.roundedBorder)
                Text("settings.general.proxy.help")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .textSelection(.disabled)
                if !settings.proxyURL.isEmpty && NetworkProxy(string: settings.proxyURL) == nil {
                    Text("settings.general.proxy.invalid")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            if let updater {
                Section("settings.general.updates") {
                    Toggle("settings.general.updates.auto", isOn: $checksForUpdates)
                        .onChange(of: checksForUpdates) { _, enabled in
                            updater.automaticallyChecksForUpdates = enabled
                        }
                }
                .onAppear { checksForUpdates = updater.automaticallyChecksForUpdates }
            }
        }
        .formStyle(.grouped)
    }
}

private struct PlaybackSettingsTab: View {
    @Environment(AppSettings.self) private var settings

    var body: some View {
        @Bindable var settings = settings

        Form {
            Section("settings.playback.audio") {
                Picker("settings.playback.quality", selection: $settings.audioQuality) {
                    ForEach(AudioQuality.allCases) { quality in
                        Text(quality.label).tag(quality)
                    }
                }
                Toggle("settings.playback.prefer_audio", isOn: $settings.preferAudioOverVideo)
                Text("settings.playback.prefer_audio.help")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("settings.playback.normalize", isOn: $settings.volumeNormalization)
                Text("settings.playback.normalize.help")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("settings.playback.crossfade") {
                Toggle("settings.playback.crossfade.toggle", isOn: $settings.crossfadeEnabled)
                if settings.crossfadeEnabled {
                    HStack {
                        Slider(value: $settings.crossfadeSeconds, in: 1...12, step: 1)
                        Text(String(format: String(localized: "settings.playback.seconds"), Int(settings.crossfadeSeconds)))
                            .font(.callout.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 34, alignment: .trailing)
                    }
                    Text("settings.playback.crossfade.help")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Section("settings.playback.next_track") {
                Toggle("settings.playback.autoplay", isOn: $settings.autoplay)
                Text("settings.playback.autoplay.help")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Toggle("settings.playback.preload", isOn: Binding(
                    get: { settings.nextTrackPreloadSeconds > 0 },
                    set: { settings.nextTrackPreloadSeconds = $0 ? 5 : 0 }
                ))
                HStack {
                    Slider(
                        value: Binding(
                            get: { max(5, settings.nextTrackPreloadSeconds) },
                            set: { settings.nextTrackPreloadSeconds = $0 }
                        ),
                        in: 5...60,
                        step: 5
                    )
                    Text(settings.nextTrackPreloadSeconds > 0
                         ? String(format: String(localized: "settings.playback.seconds"), Int(settings.nextTrackPreloadSeconds))
                         : String(localized: "settings.playback.preload.off"))
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 36, alignment: .trailing)
                }
                .disabled(settings.nextTrackPreloadSeconds == 0)
                Text("settings.playback.preload.help")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("settings.playback.track_lists") {
                Toggle("settings.playback.single_click", isOn: $settings.playOnSingleClick)
                Text("settings.playback.single_click.help")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("settings.playback.lyrics") {
                LabeledContent("settings.playback.lyrics.source") {
                    DescribedMenu(
                        selection: $settings.lyricsProvider,
                        choices: LyricsProvider.allCases.map {
                            .init(value: $0, title: $0.label, detail: lyricsDetail($0))
                        }
                    )
                }
            }
        }
        .formStyle(.grouped)
    }

    private func lyricsDetail(_ provider: LyricsProvider) -> String {
        switch provider {
        case .youtubeMusic: String(localized: "settings.playback.lyrics.youtube_music")
        case .lrclib: String(localized: "settings.playback.lyrics.lrclib")
        case .musixmatch: String(localized: "settings.playback.lyrics.musixmatch")
        }
    }
}

private struct EqualizerSettingsTab: View {
    @Environment(AppSettings.self) private var settings

    private var selectedPreset: EqualizerPreset? {
        EqualizerPreset.matching(settings.equalizerGains)
    }

    var body: some View {
        @Bindable var settings = settings

        Form {
            Section {
                Toggle("settings.eq.enable", isOn: $settings.equalizerEnabled)
            }

            if settings.equalizerEnabled {
                Section {
                    Picker("settings.eq.preset", selection: Binding(
                        get: { selectedPreset },
                        set: { if let preset = $0 { settings.applyEqualizerPreset(preset) } }
                    )) {
                        if selectedPreset == nil {
                            Text("settings.eq.custom").tag(EqualizerPreset?.none)
                        }
                        ForEach(EqualizerPreset.allCases) { preset in
                            Text(preset.label).tag(EqualizerPreset?.some(preset))
                        }
                    }

                    HStack(alignment: .bottom, spacing: 10) {
                        ForEach(Array(EqualizerBands.frequencies.indices), id: \.self) { index in
                            BandSlider(
                                gain: Binding(
                                    get: { settings.equalizerGains[index] },
                                    set: { setGain($0, at: index) }
                                ),
                                label: EqualizerBands.label(forIndex: index)
                            )
                        }
                    }
                    .padding(.vertical, 4)

                    Button("settings.eq.reset") { settings.applyEqualizerPreset(.flat) }
                        .disabled(selectedPreset == .flat)
                }
            }
        }
        .formStyle(.grouped)
    }

    /// Avoids a full array copy per slider tick.
    private func setGain(_ value: Double, at index: Int) {
        var gains = settings.equalizerGains
        guard index < gains.count else { return }
        gains[index] = value
        settings.equalizerGains = gains
    }
}

private struct PluginsSettingsTab: View {
    @Environment(PluginHost.self) private var pluginHost

    var body: some View {
        Form {
            Section {
                ForEach(pluginHost.plugins, id: \.id) { plugin in
                    PluginRow(plugin: plugin, host: pluginHost)
                }
            }
        }
        .formStyle(.grouped)
    }
}

private struct StorageSettingsTab: View {
    @State private var cacheBytes = URLCache.shared.currentDiskUsage

    var body: some View {
        Form {
            Section("settings.storage.cache") {
                LabeledContent("settings.storage.size") {
                    Text(Int64(cacheBytes).formatted(.byteCount(style: .file)))
                        .monospacedDigit()
                }
                Button("settings.storage.clear") {
                    URLCache.shared.removeAllCachedResponses()
                    ImageCache.shared.removeAll()
                    cacheBytes = URLCache.shared.currentDiskUsage
                }
                .disabled(cacheBytes == 0)
                Text("settings.storage.help")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .onAppear { cacheBytes = URLCache.shared.currentDiskUsage }
    }
}

private struct BandSlider: View {
    @Binding var gain: Double
    let label: String

    var body: some View {
        VStack(spacing: 4) {
            Slider(value: $gain, in: EqualizerBands.gainRange, step: 1)
                .frame(height: 90)
                .rotationEffect(.degrees(-90))
                .frame(width: 24, height: 90)
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

private struct PluginRow: View {
    let plugin: any Plugin
    let host: PluginHost

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Toggle(plugin.name, isOn: Binding(
                get: { host.isEnabled(plugin) },
                set: { host.setEnabled($0, for: plugin) }
            ))
            Text(plugin.summary)
                .font(.caption)
                .foregroundStyle(.secondary)
            if host.isEnabled(plugin), let configuration = plugin.configuration {
                configuration
                    .padding(.top, 4)
            }
        }
    }
}

#Preview {
    SettingsView(updater: nil)
        .environment(AppSettings())
        .environment(PluginHost(plugins: [DiscordPlugin(), NotificationsPlugin()]))
}
