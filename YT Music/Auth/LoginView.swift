//
//  LoginView.swift
//  YT Music
//
//  Web sign-in sheet; captures the cookie jar once SAPISID appears.
//  Google may refuse embedded sign-in; a desktop Safari user agent is the workaround.
//

import SwiftUI
import WebKit

struct LoginView: View {
    @Environment(AuthStore.self) private var auth
    @Environment(\.dismiss) private var dismiss

    @State private var webView = LoginWebView.makeWebView()
    @State private var capturing = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("auth.login.title").font(.headline)
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.borderless)
                .keyboardShortcut(.cancelAction)
                .help("common.close")
                .accessibilityLabel("common.close")
            }
            .padding(16)
            Divider()
            LoginWebView(webView: webView) { cookies in
                Task {
                    capturing = true
                    await auth.completeLogin(with: cookies)
                    capturing = false
                }
            }
            .overlay {
                if capturing {
                    ProgressView("auth.login.signing_in")
                        .padding(20)
                        .background(.ultraThinMaterial, in: .rect(cornerRadius: 12))
                }
            }
        }
        .frame(minWidth: 520, minHeight: 640)
    }
}

private struct LoginWebView: NSViewRepresentable {
    let webView: AuthWebView
    let onCookies: ([HTTPCookie]) -> Void

    static func makeWebView() -> AuthWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        let webView = AuthWebView(frame: .zero, configuration: configuration)
        webView.customUserAgent =
            "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 "
            + "(KHTML, like Gecko) Version/17.4 Safari/605.1.15"
        return webView
    }

    func makeNSView(context: Context) -> AuthWebView {
        webView.navigationDelegate = context.coordinator
        webView.onCookiesCaptured = onCookies
        if webView.url == nil {
            let url = URL(string:
                "https://accounts.google.com/ServiceLogin?continue=https%3A%2F%2Fmusic.youtube.com%2F")!
            webView.load(URLRequest(url: url))
        }
        return webView
    }

    func updateNSView(_ nsView: AuthWebView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator() }

    final class Coordinator: NSObject, WKNavigationDelegate {
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard let authWebView = webView as? AuthWebView else { return }
            if webView.url?.host?.contains("music.youtube.com") == true {
                authWebView.captureCookies()
            }
        }
    }
}

final class AuthWebView: WKWebView {
    var onCookiesCaptured: (([HTTPCookie]) -> Void)?
    private var hasReported = false

    func captureCookies() {
        configuration.websiteDataStore.httpCookieStore.getAllCookies { [weak self] cookies in
            guard let self, !self.hasReported else { return }
            let credentials = Credentials(httpCookies: cookies)
            guard credentials.isUsable else { return }
            self.hasReported = true
            self.onCookiesCaptured?(cookies)
        }
    }
}
