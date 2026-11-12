import SwiftUI
import WebKit

struct ResearchAnswerText: View {
    let answer: MeetingInsight
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(Self.attributed(answer)).textSelection(.enabled)
            if let html = answer.searchSuggestionsHTML {
                GoogleSearchSuggestions(html: html).frame(height: 140)
                    .accessibilityLabel("Google検索の候補")
            }
        }
    }

    static func attributed(_ answer: MeetingInsight) -> AttributedString {
        var result = AttributedString(answer.text)
        for (index, reference) in (answer.webReferences ?? []).enumerated() where WebReference.validURL(reference.url) {
            let marker = "[[web:\(reference.id)]]"
            while let range = result.range(of: marker) {
                var citation = AttributedString("[\(index + 1)]")
                citation.link = reference.url
                result.replaceSubrange(range, with: citation)
            }
        }
        return result
    }
}

struct GoogleSearchSuggestions: NSViewRepresentable {
    let html: String
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .nonPersistent()
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = context.coordinator
        return view
    }
    func updateNSView(_ view: WKWebView, context: Context) {
        context.coordinator.load(html, into: view)
    }
    static func dismantleNSView(_ view: WKWebView, coordinator: Coordinator) {
        coordinator.task?.cancel()
        view.stopLoading()
        view.navigationDelegate = nil
    }

    @MainActor final class Coordinator: NSObject, WKNavigationDelegate {
        var task: Task<Void, Never>?
        private var loadedHTML: String?
        func load(_ html: String, into view: WKWebView) {
            guard html != loadedHTML, html.utf8.count <= 65_536 else { return }
            loadedHTML = html
            task?.cancel()
            task = Task { [weak view] in
                let rules = #"[{"trigger":{"url-filter":".*"},"action":{"type":"block"}}]"#
                guard let rule = try? await WKContentRuleListStore.default().compileContentRuleList(
                    forIdentifier: "research-no-external-resources", encodedContentRuleList: rules), !Task.isCancelled,
                    let view else { return }
                view.configuration.userContentController.removeAllContentRuleLists()
                view.configuration.userContentController.add(rule)
                view.loadHTMLString(html, baseURL: nil)
            }
        }
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction,
                     decisionHandler: @escaping @MainActor @Sendable (WKNavigationActionPolicy) -> Void) {
            if navigationAction.navigationType == .linkActivated,
               let url = navigationAction.request.url, WebReference.validURL(url) {
                NSWorkspace.shared.open(url)
                decisionHandler(.cancel)
            } else {
                decisionHandler(navigationAction.request.url?.absoluteString == "about:blank" ? .allow : .cancel)
            }
        }
    }
}
