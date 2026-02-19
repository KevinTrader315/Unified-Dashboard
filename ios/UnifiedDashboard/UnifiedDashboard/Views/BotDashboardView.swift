import SwiftUI
import WebKit

struct BotDashboardView: View {
    @EnvironmentObject var settings: ServerSettings

    @State private var bots: [(id: String, name: String, short: String, color: String)] = []
    @State private var selectedBot: String = ""
    @State private var isWebViewLoading = true
    @State private var webViewError: String?
    @State private var botsLoaded = false

    var body: some View {
        VStack(spacing: 0) {
            // Screen header
            HStack {
                Text("Dashboards")
                    .font(.system(size: 20, weight: .bold, design: .monospaced))
                    .foregroundStyle(Color.textPrimary)
                Spacer()
                Button {
                    Haptic.tap()
                    Task { await refreshAll() }
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

            if !botsLoaded {
                Spacer()
                ProgressView()
                    .tint(.textDim)
                Text("Loading bots...")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(Color.textDim)
                    .padding(.top, 8)
                Spacer()
            } else if bots.isEmpty {
                Spacer()
                EmptyState(
                    icon: "cpu",
                    title: "No Bots Found",
                    message: "No bots were returned by the server"
                )
                Spacer()
            } else {
                // Bot selector bar
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(bots, id: \.id) { bot in
                            let isSelected = selectedBot == bot.id
                            Button {
                                Haptic.tap()
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    selectedBot = bot.id
                                    isWebViewLoading = true
                                    webViewError = nil
                                }
                            } label: {
                                HStack(spacing: 7) {
                                    Circle()
                                        .fill(Fmt.hexColor(bot.color))
                                        .frame(width: 7, height: 7)
                                    Text(bot.name)
                                        .font(.system(size: 12, weight: .semibold, design: .monospaced))
                                        .lineLimit(1)
                                }
                                .padding(.horizontal, 14)
                                .padding(.vertical, 9)
                                .background(
                                    isSelected
                                        ? Fmt.hexColor(bot.color).opacity(0.15)
                                        : Color.cardBg
                                )
                                .foregroundStyle(isSelected ? .white : .textDim)
                                .clipShape(Capsule())
                                .overlay(
                                    Capsule()
                                        .stroke(
                                            isSelected
                                                ? Fmt.hexColor(bot.color).opacity(0.5)
                                                : Color.cardBorder,
                                            lineWidth: isSelected ? 1.5 : 1
                                        )
                                )
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                }
                .overlay(alignment: .bottom) {
                    Color.cardBorder.frame(height: 1)
                }

                // Bot stats strip
                if let bot = bots.first(where: { $0.id == selectedBot }) {
                    HStack(spacing: 0) {
                        StatPill(label: "BOT", value: bot.short, color: Fmt.hexColor(bot.color))
                        StatPill(label: "STATUS", value: "Active", color: .portalGreen)
                        StatPill(label: "UPTIME", value: "99.8%", color: .textPrimary)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.cardBg)
                    .overlay(alignment: .bottom) {
                        Color.cardBorder.frame(height: 1)
                    }
                    .transition(.opacity.combined(with: .move(edge: .top)))
                }

                // Loading bar
                if isWebViewLoading {
                    ProgressView()
                        .progressViewStyle(.linear)
                        .tint(.portalGreen)
                }

                // WebView
                if let base = settings.baseURL {
                    if let webError = webViewError {
                        Spacer()
                        VStack(spacing: 14) {
                            EmptyState(
                                icon: "exclamationmark.triangle",
                                title: "Failed to Load",
                                message: webError
                            )
                            Button {
                                Haptic.tap()
                                reloadWebView()
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
                    } else if !selectedBot.isEmpty {
                        let dashURL = base.appendingPathComponent("/bot/\(selectedBot)/")
                        BotWebView(
                            url: dashURL,
                            authHeader: settings.basicAuthHeader,
                            serverHost: base.host,
                            onFinishLoading: {
                                withAnimation { isWebViewLoading = false }
                            },
                            onError: { errorMsg in
                                withAnimation {
                                    isWebViewLoading = false
                                    webViewError = errorMsg
                                }
                            }
                        )
                        .id(selectedBot)
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
        }
        .background(Color.portalBg)
        .task { await loadBots() }
        .onAppear { Task { await loadBots() } }
    }

    // MARK: - Load bots from API

    private func loadBots() async {
        let client = APIClient(settings: settings)
        do {
            let overview = try await client.fetchOverview()
            let sorted = overview.bots.sorted(by: { $0.key < $1.key })
            let mapped = sorted.map { (id: $0.key, name: $0.value.name, short: $0.value.short, color: $0.value.color) }
            await MainActor.run {
                self.bots = mapped
                if selectedBot.isEmpty, let first = mapped.first {
                    selectedBot = first.id
                }
                botsLoaded = true
            }
        } catch {
            await MainActor.run {
                botsLoaded = true
            }
        }
    }

    private func refreshAll() async {
        await loadBots()
        reloadWebView()
        Haptic.success()
    }

    private func reloadWebView() {
        webViewError = nil
        isWebViewLoading = true
        let current = selectedBot
        selectedBot = ""
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
            selectedBot = current
        }
    }
}

// MARK: - WKWebView wrapper

struct BotWebView: UIViewRepresentable {
    let url: URL
    let authHeader: String?
    let serverHost: String?
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

        // Inject dark background CSS so pages don't flash white
        let darkCSS = """
        var style = document.createElement('style');
        style.textContent = 'html, body { background-color: #0a0e14 !important; color-scheme: dark; }';
        document.documentElement.appendChild(style);
        """
        let script = WKUserScript(source: darkCSS, injectionTime: .atDocumentEnd, forMainFrameOnly: false)
        config.userContentController.addUserScript(script)

        // Inject fetch/XHR interceptor to add auth header to all API requests
        if let auth = authHeader {
            let escapedAuth = auth.replacingOccurrences(of: "'", with: "\\'")
            let authInterceptor = """
            (function() {
                var authValue = '\(escapedAuth)';

                // Override fetch to inject Authorization header
                var originalFetch = window.fetch;
                window.fetch = function(input, init) {
                    init = init || {};
                    init.headers = init.headers || {};
                    if (init.headers instanceof Headers) {
                        if (!init.headers.has('Authorization')) {
                            init.headers.set('Authorization', authValue);
                        }
                    } else {
                        if (!init.headers['Authorization']) {
                            init.headers['Authorization'] = authValue;
                        }
                    }
                    return originalFetch.call(this, input, init);
                };

                // Override XMLHttpRequest to inject Authorization header
                var originalOpen = XMLHttpRequest.prototype.open;
                var originalSend = XMLHttpRequest.prototype.send;
                XMLHttpRequest.prototype.open = function() {
                    this._authInjected = false;
                    return originalOpen.apply(this, arguments);
                };
                XMLHttpRequest.prototype.send = function() {
                    if (!this._authInjected) {
                        try { this.setRequestHeader('Authorization', authValue); } catch(e) {}
                        this._authInjected = true;
                    }
                    return originalSend.apply(this, arguments);
                };
            })();
            """
            let authScript = WKUserScript(source: authInterceptor, injectionTime: .atDocumentStart, forMainFrameOnly: false)
            config.userContentController.addUserScript(authScript)
        }

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.isOpaque = false
        webView.backgroundColor = UIColor(Color.portalBg)
        webView.scrollView.backgroundColor = webView.backgroundColor
        webView.navigationDelegate = context.coordinator

        var request = URLRequest(url: url)
        if let auth = authHeader {
            request.setValue(auth, forHTTPHeaderField: "Authorization")
        }
        webView.load(request)
        return webView
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

        /// Inject auth header on every navigation request to the portal server.
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

            // If request already has auth, allow it
            if navigationAction.request.value(forHTTPHeaderField: "Authorization") != nil {
                decisionHandler(.allow)
                return
            }

            // Cancel and re-issue with auth header
            decisionHandler(.cancel)
            var newRequest = navigationAction.request
            newRequest.setValue(auth, forHTTPHeaderField: "Authorization")
            webView.load(newRequest)
        }
    }
}
