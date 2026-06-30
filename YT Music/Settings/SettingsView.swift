//
//  SettingsView.swift
//  YT Music
//
//  The Settings screen: audio quality, prefer-audio-over-video, crossfade, and
//  a registry-driven Plugins section. Audio/crossfade live in AppSettings;
//  plugins render themselves from the PluginHost, so new plugins appear here
//  automatically without editing this file.
//

import SwiftUI

struct SettingsView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(PluginHost.self) private var pluginHost

    var body: some View {
        @Bindable var settings = settings

        Form {
            Section("Audio") {
                Picker("Audio quality", selection: $settings.audioQuality) {
                    ForEach(AudioQuality.allCases) { quality in
                        Text(quality.label).tag(quality)
                    }
                }
                Toggle("Prefer audio over video", isOn: $settings.preferAudioOverVideo)
                Text("Play music videos as audio-only streams. Turn off to allow combined video+audio streams when they're higher quality.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Crossfade") {
                Toggle("Crossfade between tracks", isOn: $settings.crossfadeEnabled)
                if settings.crossfadeEnabled {
                    HStack {
                        Slider(value: $settings.crossfadeSeconds, in: 1...12, step: 1)
                        Text("\(Int(settings.crossfadeSeconds))s")
                            .font(.callout.monospacedDigit())
                            .foregroundStyle(.secondary)
                            .frame(width: 34, alignment: .trailing)
                    }
                    Text("Overlap the end of each track with the start of the next.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            EqualizerSection(settings: settings)

            Section("Plugins") {
                ForEach(pluginHost.plugins, id: \.id) { plugin in
                    PluginRow(plugin: plugin, host: pluginHost)
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
    }
}

/// The equalizer controls: enable toggle, a preset picker, and a row of
/// vertical gain sliders (one per band) shown while it's enabled.
private struct EqualizerSection: View {
    @Bindable var settings: AppSettings

    /// The preset matching the current gains, or nil → "Custom".
    private var selectedPreset: EqualizerPreset? {
        EqualizerPreset.matching(settings.equalizerGains)
    }

    var body: some View {
        Section("Equalizer") {
            Toggle("Enable equalizer", isOn: $settings.equalizerEnabled)

            if settings.equalizerEnabled {
                Picker("Preset", selection: Binding(
                    get: { selectedPreset },
                    set: { if let preset = $0 { settings.applyEqualizerPreset(preset) } }
                )) {
                    if selectedPreset == nil {
                        Text("Custom").tag(EqualizerPreset?.none)
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

                Button("Reset to flat") { settings.applyEqualizerPreset(.flat) }
                    .disabled(selectedPreset == .flat)
            }
        }
    }

    /// Writes a single band's gain without replacing the whole array binding
    /// (which would otherwise need a full copy on each slider tick).
    private func setGain(_ value: Double, at index: Int) {
        var gains = settings.equalizerGains
        guard index < gains.count else { return }
        gains[index] = value
        settings.equalizerGains = gains
    }
}

/// One band's vertical gain slider with its frequency label underneath.
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

/// One plugin's toggle, description, and (when enabled) its configuration UI.
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
    SettingsView()
        .environment(AppSettings())
        .environment(PluginHost(plugins: [DiscordPlugin(), NotificationsPlugin()]))
        .frame(width: 600, height: 700)
}
