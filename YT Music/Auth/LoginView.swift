//
//  LoginView.swift
//  YT Music
//
//  Web sign-in sheet. Hosts a WKWebView pointed at Google sign-in (continuing to
//  music.youtube.com). When it lands back on YT Music with a SAPISID cookie, we
//  capture the jar and hand it to AuthStore.
//
//  Note: Google sometimes refuses sign-in in embedded web views ("this browser
//  may not be secure"). Presenting a desktop Safari user agent is the usual
//  workaround; it isn't guaranteed to hold forever.
//

import SwiftUI
import WebKit

struct LoginView: View {
    @Environment(AuthStore.self) private var auth
    @Environment(\.dismiss) private var dismiss

    @State private var webView = LoginWebView.makeWebView()
    @State private var capturing = false

    var body: some View {
        NavigationStack {
            LoginWebView(webView: webView) { cookies in
                Task {
                    capturing = true
                    await auth.completeLogin(with: cookies)
                    capturing = false
                }
            }
            .overlay {
                if capturing {
                    ProgressView("Signing in…")
                        .padding(20)
                        .background(.ultraThinMaterial, in: .rect(cornerRadius: 12))
                }
            }
            .navigationTitle("Sign in to YouTube Music")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    // Manual fallback if auto-detection doesn't fire.
                    Button("Done") { webView.captureCookies() }
                }
            }
        }
        .frame(minWidth: 520, minHeight: 640)
    }
}

/// NSViewRepresentable wrapper around the login WKWebView.
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
            // Once we're back on music.youtube.com, try to capture.
            if webView.url?.host?.contains("music.youtube.com") == true {
                authWebView.captureCookies()
            }
        }
    }
}

/// WKWebView that knows how to capture the relevant cookies and report a usable
/// session exactly once.
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
