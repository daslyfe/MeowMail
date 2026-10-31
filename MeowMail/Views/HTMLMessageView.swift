import SwiftUI
import WebKit

/// Shows newsletter-style mail as designed. Scripts never run, and remote
/// images stay blocked until requested so senders can't track opens.
struct HTMLMessageView: View {
    var html: String
    @State private var height: CGFloat = 200
    @State private var allowImages = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            WebContainer(html: Self.document(html, allowImages: allowImages), height: $height)
                .frame(height: height)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            if !allowImages {
                Button("Load remote images") { allowImages = true }
                    .font(.caption2)
                    .buttonStyle(.plain)
                    .foregroundStyle(Theme.muted)
            }
        }
    }

    static func document(_ html: String, allowImages: Bool) -> String {
        let images = allowImages ? "data: https:" : "data:"
        let policy = "default-src 'none'; img-src \(images); style-src 'unsafe-inline'; base-uri 'none'; form-action 'none'"
        return """
        <!doctype html><meta charset="utf-8">\
        <meta http-equiv="Content-Security-Policy" content="\(policy)">\
        <meta name="viewport" content="width=device-width, initial-scale=1">\
        <style>body{margin:8px;background:#fff;color:#000;font-family:-apple-system;overflow-wrap:anywhere}img{max-width:100%;height:auto}</style>\
        \(html)
        """
    }
}

@MainActor
private func makeWebView(_ coordinator: WebContainer.Coordinator) -> WKWebView {
    let configuration = WKWebViewConfiguration()
    configuration.defaultWebpagePreferences.allowsContentJavaScript = false
    configuration.websiteDataStore = .nonPersistent()
    let view = WKWebView(frame: .zero, configuration: configuration)
    view.navigationDelegate = coordinator
    return view
}

#if os(macOS)
struct WebContainer: NSViewRepresentable {
    var html: String
    @Binding var height: CGFloat

    func makeCoordinator() -> Coordinator { Coordinator(height: $height) }
    func makeNSView(context: Context) -> WKWebView { makeWebView(context.coordinator) }

    func updateNSView(_ view: WKWebView, context: Context) {
        context.coordinator.load(html, in: view)
    }
}
#else
struct WebContainer: UIViewRepresentable {
    var html: String
    @Binding var height: CGFloat

    func makeCoordinator() -> Coordinator { Coordinator(height: $height) }

    func makeUIView(context: Context) -> WKWebView {
        let view = makeWebView(context.coordinator)
        view.scrollView.isScrollEnabled = false
        return view
    }

    func updateUIView(_ view: WKWebView, context: Context) {
        context.coordinator.load(html, in: view)
    }
}
#endif

extension WebContainer {
    final class Coordinator: NSObject, WKNavigationDelegate {
        private var height: Binding<CGFloat>
        private var loaded: String?

        init(height: Binding<CGFloat>) { self.height = height }

        func load(_ html: String, in view: WKWebView) {
            guard html != loaded else { return }
            loaded = html
            view.loadHTMLString(html, baseURL: nil)
        }

        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction,
                     decisionHandler: @escaping @MainActor (WKNavigationActionPolicy) -> Void) {
            if action.navigationType == .linkActivated, let url = action.request.url {
                if url.scheme == "https" || url.scheme == "http" || url.scheme == "mailto" {
                    #if os(macOS)
                    NSWorkspace.shared.open(url)
                    #else
                    UIApplication.shared.open(url)
                    #endif
                }
                decisionHandler(.cancel)
                return
            }
            let scheme = action.request.url?.scheme
            decisionHandler(scheme == "about" ? .allow : .cancel)
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // Page scripts are off; this measurement is run by the app itself.
            webView.evaluateJavaScript("document.documentElement.scrollHeight") { [height] value, _ in
                if let value = value as? CGFloat { height.wrappedValue = max(80, value) }
            }
        }
    }
}
