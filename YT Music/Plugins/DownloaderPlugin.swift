//
//  DownloaderPlugin.swift
//  YT Music
//
//

import SwiftUI
import AppKit

@MainActor
final class DownloaderPlugin: Plugin {
    let id = "downloader"
    let name = String(localized: "plugins.downloader.name")
    let summary = String(localized: "plugins.downloader.summary")

    let downloader: Downloader

    init(downloader: Downloader) {
        self.downloader = downloader
    }

    func setActive(_ active: Bool) {
        downloader.isEnabled = active
    }

    var configuration: AnyView? {
        AnyView(DownloaderConfigView(downloader: downloader))
    }
}

private struct DownloaderConfigView: View {
    @Environment(AppSettings.self) private var settings
    @Environment(PlayerState.self) private var player
    let downloader: Downloader

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            LabeledContent("plugins.downloader.save_to") {
                HStack(spacing: 8) {
                    Text(settings.effectiveDownloadDirectory.path)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(.secondary)
                    Button("plugins.downloader.choose", action: chooseFolder)
                    if settings.downloadDirectory != nil {
                        Button("common.reset") { settings.setDownloadDirectory(nil) }
                    }
                }
            }

            HStack {
                Button(action: startDownload) {
                    Label("plugins.downloader.current", systemImage: "arrow.down.circle")
                }
                .disabled(player.currentSnapshot == nil || downloader.isBusy)

                if downloader.isBusy {
                    Button("common.cancel", role: .cancel) { downloader.cancel() }
                }
            }

            status
        }
    }

    @ViewBuilder
    private var status: some View {
        switch downloader.status {
        case .idle:
            EmptyView()
        case .running(let progress):
            VStack(alignment: .leading, spacing: 4) {
                Text(runningLabel(progress)).font(.caption).foregroundStyle(.secondary)
                if let fraction = progress.fraction {
                    ProgressView(value: fraction)
                } else {
                    ProgressView().controlSize(.small)
                }
            }
        case .finished(let summary, _):
            Label(summary, systemImage: "checkmark.circle")
                .font(.caption).foregroundStyle(.green)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle")
                .font(.caption).foregroundStyle(.red)
        }
    }

    private func runningLabel(_ progress: Downloader.Progress) -> String {
        let head = progress.total > 1 ? "(\(progress.index)/\(progress.total)) " : ""
        return head + String(format: String(localized: "plugins.downloader.running"), progress.currentTitle)
    }

    private func startDownload() {
        guard let snapshot = player.currentSnapshot else { return }
        downloader.download(snapshot,
                            to: settings.effectiveDownloadDirectory,
                            preferences: settings.streamPreferences)
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = String(localized: "plugins.downloader.panel.prompt")
        panel.message = String(localized: "plugins.downloader.panel.message")
        if panel.runModal() == .OK, let url = panel.url {
            settings.setDownloadDirectory(url)
        }
    }
}
