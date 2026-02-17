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

    var body: some View {
        VStack(spacing: 0) {
            // Drag indicator
            Capsule()
                .fill(Color.textDim.opacity(0.4))
                .frame(width: 36, height: 5)
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
                                    ? Fmt.hexColor(bot.color).opacity(0.12)
                                    : Color.clear
                            )
                            .foregroundStyle(isSelected ? .textPrimary : .textDim)
                            .clipShape(Capsule())
                            .overlay(
                                Capsule()
                                    .stroke(
                                        isSelected
                                            ? Fmt.hexColor(bot.color).opacity(0.3)
                                            : Color.cardBorder,
                                        lineWidth: 1
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

            // Loading bar
            if isWebViewLoading {
                ProgressView()
                    .progressViewStyle(.linear)
                    .tint(.portalGreen)
            }

            // WebView
            if let base = settings.baseURL {
                let dashURL = base.appendingPathComponent("/bot/\(selectedBot)/")
                BotWebView(
                    url: dashURL,
                    authHeader: settings.basicAuthHeader,
                    onFinishLoading: {
                        withAnimation { isWebViewLoading = false }
                    }
                )
                .id(selectedBot)
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

    func makeCoordinator() -> Coordinator {
        Coordinator(onFinishLoading: onFinishLoading)
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

        init(onFinishLoading: (() -> Void)?) {
            self.onFinishLoading = onFinishLoading
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            onFinishLoading?()
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            onFinishLoading?()
        }
    }
}
