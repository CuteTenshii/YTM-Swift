//
//  ToastOverlay.swift
//  YT Music
//

import SwiftUI

struct ToastOverlay: View {
    let center: ToastCenter

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if let toast = center.current {
                ToastView(toast: toast, center: center)
                    .id(toast.id)
                    .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeOut(duration: 0.2), value: center.current?.id)
    }
}

private struct ToastView: View {
    let toast: Toast
    let center: ToastCenter

    var body: some View {
        HStack(spacing: 10) {
            if toast.style == .error {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
                    .accessibilityHidden(true)
            }
            Text(toast.message)
                .foregroundStyle(.primary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
            if let action = toast.action {
                Button(action.title) {
                    center.dismiss(toast.id)
                    action.perform()
                }
                .buttonStyle(ToastActionButtonStyle())
            }
            Button {
                center.dismiss(toast.id)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("common.close")
            .accessibilityLabel("common.close")
        }
        .font(.callout)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color(nsColor: .windowBackgroundColor), in: .rect(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.primary.opacity(0.15)))
        .shadow(color: .black.opacity(0.25), radius: 10, y: 3)
        .frame(maxWidth: 520)
        .onHover { center.setHovering($0) }
    }
}

/// Inverted fill so the action stands out against the toast in both appearances.
private struct ToastActionButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.callout.weight(.semibold))
            .foregroundStyle(Color(nsColor: .windowBackgroundColor))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Color.primary.opacity(configuration.isPressed ? 0.7 : 0.9), in: .capsule)
            .contentShape(.capsule)
    }
}
