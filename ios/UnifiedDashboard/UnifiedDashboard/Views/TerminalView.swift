import SwiftUI
import WebKit

struct TerminalView: View {
    @EnvironmentObject var settings: ServerSettings

    @State private var isLoading = true
    @State private var loadError: String?

    var body: some View {
        VStack(spacing: 0) {
            // Screen header
            HStack {
                Text("Terminal")
                    .font(.system(size: 20, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.textPrimary)
                Spacer()
                Button {
                    Haptic.tap()
                    reloadTerminal()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(Color.textDim)
                        .frame(width: 32, height: 32)
                        .background(Color.cardBg)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Color.cardBorder, lineWidth: 1))
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 8)

            // Loading bar
            if isLoading {
                ProgressView()
                    .progressViewStyle(.linear)
                    .tint(.portalGreen)
            }

            // Content
            if let base = settings.baseURL {
                if let error = loadError {
                    Spacer()
                    VStack(spacing: 14) {
                        EmptyState(
                            icon: "exclamationmark.triangle",
                            title: "Failed to Load",
                            message: error
                        )
                        Button {
                            Haptic.tap()
                            reloadTerminal()
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 12, weight: .bold))
                                Text("Retry")
                                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                            }
                            .foregroundStyle(Color.portalBlue)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                            .background(Color.portalBlue.opacity(0.1))
                            .clipShape(Capsule())
                        }
                    }
                    Spacer()
                } else {
                    let termURL = base.appendingPathComponent("/terminal")
                    TerminalWebView(
                        url: termURL,
                        authHeader: settings.basicAuthHeader,
                        serverHost: base.host,
                        sshHost: settings.sshHost,
                        sshPort: settings.sshPort,
                        sshUser: settings.sshUser,
                        sshPassword: settings.sshPassword,
                        onFinishLoading: {
                            withAnimation { isLoading = false }
                        },
                        onError: { msg in
                            withAnimation {
                                isLoading = false
                                loadError = msg
                            }
                        }
                    )
                    .id("terminal-\(terminalReloadId)")
                }
            } else {
                Spacer()
                EmptyState(
                    icon: "server.rack",
                    title: "Not Connected",
                    message: "Set your server URL in Settings"
                )
                Spacer()
            }
        }
        .background(Color.portalBg)
    }

    @State private var terminalReloadId = 0

    private func reloadTerminal() {
        loadError = nil
        isLoading = true
        terminalReloadId += 1
    }
}

// MARK: - WKWebView wrapper for terminal

struct TerminalWebView: UIViewRepresentable {
    let url: URL
    let authHeader: String?
    let serverHost: String?
    var sshHost: String = ""
    var sshPort: String = "22"
    var sshUser: String = ""
    var sshPassword: String = ""
    var onFinishLoading: (() -> Void)? = nil
    var onError: ((String) -> Void)? = nil

    func makeCoordinator() -> Coordinator {
        Coordinator(
            authHeader: authHeader,
            serverHost: serverHost,
            onFinishLoading: onFinishLoading,
            onError: onError
        )
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true

        // Dark background to prevent white flash
        let darkCSS = """
        var style = document.createElement('style');
        style.textContent = 'html, body { background-color: #0a0e14 !important; }';
        document.documentElement.appendChild(style);
        """
        let cssScript = WKUserScript(source: darkCSS, injectionTime: .atDocumentEnd, forMainFrameOnly: false)
        config.userContentController.addUserScript(cssScript)

        // If SSH credentials are saved, auto-fill and auto-connect
        if !sshHost.isEmpty && !sshUser.isEmpty && !sshPassword.isEmpty {
            let escapedHost = escapeForJS(sshHost)
            let escapedPort = escapeForJS(sshPort)
            let escapedUser = escapeForJS(sshUser)
            let escapedPass = escapeForJS(sshPassword)
            let autoConnect = """
            (function() {
                var attempts = 0;
                function tryAutoConnect() {
                    if (++attempts > 50) return;
                    var hostEl = document.getElementById('ssh-host');
                    var portEl = document.getElementById('ssh-port');
                    var userEl = document.getElementById('ssh-user');
                    var passEl = document.getElementById('ssh-pass');
                    var form = document.getElementById('connect-form');
                    if (!hostEl || !form) { setTimeout(tryAutoConnect, 100); return; }
                    hostEl.value = '\(escapedHost)';
                    portEl.value = '\(escapedPort)';
                    userEl.value = '\(escapedUser)';
                    passEl.value = '\(escapedPass)';
                    if (typeof doConnect === 'function') {
                        doConnect(new Event('submit'));
                    } else {
                        form.requestSubmit();
                    }
                }
                if (document.readyState === 'complete') tryAutoConnect();
                else window.addEventListener('load', tryAutoConnect);
            })();
            """
            let autoScript = WKUserScript(source: autoConnect, injectionTime: .atDocumentEnd, forMainFrameOnly: true)
            config.userContentController.addUserScript(autoScript)
        }

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = UIColor(Color.portalBg)
        webView.scrollView.backgroundColor = webView.backgroundColor
        webView.scrollView.isScrollEnabled = false // Terminal handles its own scrolling
        webView.navigationDelegate = context.coordinator

        var request = URLRequest(url: url)
        if let auth = authHeader {
            request.setValue(auth, forHTTPHeaderField: "Authorization")
        }
        webView.load(request)
        return webView
    }

    private func escapeForJS(_ str: String) -> String {
        str.replacingOccurrences(of: "\\", with: "\\\\")
           .replacingOccurrences(of: "'", with: "\\'")
           .replacingOccurrences(of: "\n", with: "\\n")
           .replacingOccurrences(of: "\r", with: "\\r")
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    class Coordinator: NSObject, WKNavigationDelegate {
        let authHeader: String?
        let serverHost: String?
        let onFinishLoading: (() -> Void)?
        let onError: ((String) -> Void)?

        init(authHeader: String?, serverHost: String?,
             onFinishLoading: (() -> Void)?, onError: ((String) -> Void)?) {
            self.authHeader = authHeader
            self.serverHost = serverHost
            self.onFinishLoading = onFinishLoading
            self.onError = onError
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            onFinishLoading?()
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            onError?(error.localizedDescription)
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            onError?(error.localizedDescription)
        }

        func webView(_ webView: WKWebView,
                     decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let auth = authHeader,
                  let requestURL = navigationAction.request.url,
                  let host = serverHost,
                  requestURL.host == host else {
                decisionHandler(.allow)
                return
            }

            if navigationAction.request.value(forHTTPHeaderField: "Authorization") != nil {
                decisionHandler(.allow)
                return
            }

            decisionHandler(.cancel)
            var newRequest = navigationAction.request
            newRequest.setValue(auth, forHTTPHeaderField: "Authorization")
            webView.load(newRequest)
        }
    }
}
