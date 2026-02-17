import SwiftUI
import WebKit

struct BotDashboardView: View {
    @EnvironmentObject var settings: ServerSettings

    private let bots: [(id: String, name: String, short: String, color: String)] = [
        ("weather", "Weather Bot", "WX", "#4CAF50"),
        ("btc-range", "BTC Range Arb", "BTC", "#f7931a"),
        ("sports-arb", "Sports Arb", "SPT", "#58a6ff"),
    ]

    @State private var selectedBot: String = "weather"
    @State private var isWebViewLoading = true
    @State private var webViewError: String?

    var body: some View {
        VStack(spacing: 0) {
            // Screen header
            HStack {
                Text("Dashboards")
                    .font(.system(size: 20, weight: .bold, design: .monospaced))
                    .foregroundStyle(.textPrimary)
                Spacer()
                Button {
                    Haptic.tap()
                    isWebViewLoading = true
                    let current = selectedBot
                    selectedBot = ""
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        selectedBot = current
                    }
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.textDim)
                        .frame(width: 32, height: 32)
                        .background(Color.cardBg)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(Color.cardBorder, lineWidth: 1))
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 8)

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
                            webViewError = nil
                            isWebViewLoading = true
                            let current = selectedBot
                            selectedBot = ""
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                                selectedBot = current
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 12, weight: .bold))
                                Text("Retry")
                                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                            }
                            .foregroundStyle(.portalBlue)
                            .padding(.horizontal, 20)
                            .padding(.vertical, 10)
                            .background(.portalBlue.opacity(0.1))
                            .clipShape(Capsule())
                        }
                    }
                    Spacer()
                } else {
                    let dashURL = base.appendingPathComponent("/bot/\(selectedBot)/")
                    BotWebView(
                        url: dashURL,
                        authHeader: settings.basicAuthHeader,
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
        .background(Color.portalBg)
    }
}

// MARK: - WKWebView wrapper

struct BotWebView: UIViewRepresentable {
    let url: URL
    let authHeader: String?
    var onFinishLoading: (() -> Void)? = nil
    var onError: ((String) -> Void)? = nil

    func makeCoordinator() -> Coordinator {
        Coordinator(onFinishLoading: onFinishLoading, onError: onError)
    }

    func makeUIView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.allowsInlineMediaPlayback = true
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
        let onFinishLoading: (() -> Void)?
        let onError: ((String) -> Void)?

        init(onFinishLoading: (() -> Void)?, onError: ((String) -> Void)?) {
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
    }
}
