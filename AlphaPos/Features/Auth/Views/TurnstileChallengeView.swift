import SwiftUI
import WebKit

enum TurnstileChallengeStatus: Equatable {
    case loading
    case ready
    case verified
    case expired
    case failed
}

struct TurnstileChallengeView: UIViewRepresentable {
    let siteKey: String
    /// Increment to force a fresh Turnstile challenge (e.g. after login/signup failure).
    var resetToken: Int = 0
    let onToken: (String?) -> Void
    var onStatus: ((TurnstileChallengeStatus) -> Void)? = nil

    func makeCoordinator() -> Coordinator {
        Coordinator(onToken: onToken, onStatus: onStatus)
    }

    func makeUIView(context: Context) -> WKWebView {
        let controller = WKUserContentController()
        controller.add(context.coordinator, name: "turnstile")
        let configuration = WKWebViewConfiguration()
        configuration.userContentController = controller
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.websiteDataStore = .default()

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.isScrollEnabled = false
        webView.scrollView.backgroundColor = .clear
        webView.scrollView.bounces = false

        context.coordinator.lastResetToken = resetToken
        context.coordinator.loadChallenge(into: webView, siteKey: siteKey)
        return webView
    }

    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.onToken = onToken
        context.coordinator.onStatus = onStatus
        guard context.coordinator.lastResetToken != resetToken else { return }
        context.coordinator.lastResetToken = resetToken
        context.coordinator.loadChallenge(into: webView, siteKey: siteKey)
    }

    static func dismantleUIView(_ uiView: WKWebView, coordinator: Coordinator) {
        coordinator.cancelLoadTimeout()
        uiView.configuration.userContentController.removeScriptMessageHandler(forName: "turnstile")
    }

    final class Coordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
        var onToken: (String?) -> Void
        var onStatus: ((TurnstileChallengeStatus) -> Void)?
        var lastResetToken: Int = -1
        private var loadTimeoutWork: DispatchWorkItem?
        private var didBecomeReady = false

        init(onToken: @escaping (String?) -> Void, onStatus: ((TurnstileChallengeStatus) -> Void)?) {
            self.onToken = onToken
            self.onStatus = onStatus
        }

        func loadChallenge(into webView: WKWebView, siteKey: String) {
            didBecomeReady = false
            publish(.loading)
            publishToken(nil)
            scheduleLoadTimeout()

            let escapedKey = siteKey.replacingOccurrences(of: "'", with: "")
            let html = """
            <!doctype html><html><head><meta name="viewport" content="width=device-width,initial-scale=1,maximum-scale=1">
            <script src="https://challenges.cloudflare.com/turnstile/v0/api.js" async defer></script></head>
            <body style="margin:0;background:transparent;display:flex;justify-content:center;align-items:center;min-height:65px">
            <div class="cf-turnstile" data-sitekey="\(escapedKey)" data-theme="dark" data-size="flexible"
              data-action="merchant_login" data-callback="ok" data-expired-callback="expired"
              data-error-callback="failed" data-timeout-callback="failed"
              data-before-interactive-callback="ready"></div>
            <script>
            function post(p){try{webkit.messageHandlers.turnstile.postMessage(p)}catch(e){}}
            function ok(t){window.__tsReady=1;post({type:'token',value:String(t||'')})}
            function expired(){post({type:'expired'})}
            function failed(){post({type:'failed'})}
            function ready(){window.__tsReady=1;post({type:'ready'})}
            setTimeout(function(){if(!window.__tsReady){post({type:'failed'})}},12000);
            </script>
            </body></html>
            """
            // Hostname must match Cloudflare Turnstile allowed hostnames for this site key.
            webView.loadHTMLString(html, baseURL: URL(string: "https://api.alphaposweb.com"))
        }

        func cancelLoadTimeout() {
            loadTimeoutWork?.cancel()
            loadTimeoutWork = nil
        }

        private func scheduleLoadTimeout() {
            cancelLoadTimeout()
            let work = DispatchWorkItem { [weak self] in
                guard let self, !self.didBecomeReady else { return }
                self.publish(.failed)
                self.publishToken(nil)
            }
            loadTimeoutWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 14, execute: work)
        }

        private func publish(_ status: TurnstileChallengeStatus) {
            DispatchQueue.main.async { self.onStatus?(status) }
        }

        private func publishToken(_ token: String?) {
            DispatchQueue.main.async { self.onToken(token) }
        }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            if let dict = message.body as? [String: Any], let type = dict["type"] as? String {
                DispatchQueue.main.async {
                    switch type {
                    case "ready":
                        self.didBecomeReady = true
                        self.cancelLoadTimeout()
                        self.publish(.ready)
                        self.publishToken(nil)
                    case "token":
                        let value = dict["value"] as? String
                        let ok = (value?.isEmpty == false)
                        self.didBecomeReady = true
                        self.cancelLoadTimeout()
                        self.publish(ok ? .verified : .expired)
                        self.publishToken(ok ? value : nil)
                    case "expired":
                        self.publish(.expired)
                        self.publishToken(nil)
                    case "failed":
                        self.cancelLoadTimeout()
                        self.publish(.failed)
                        self.publishToken(nil)
                    default:
                        break
                    }
                }
                return
            }

            // Backward-compatible plain string token / empty expiry signal.
            let token = message.body as? String
            DispatchQueue.main.async {
                let ok = token?.isEmpty == false
                if ok {
                    self.didBecomeReady = true
                    self.cancelLoadTimeout()
                    self.publish(.verified)
                    self.publishToken(token)
                } else {
                    self.publish(.expired)
                    self.publishToken(nil)
                }
            }
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            cancelLoadTimeout()
            DispatchQueue.main.async {
                self.publish(.failed)
                self.publishToken(nil)
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            cancelLoadTimeout()
            DispatchQueue.main.async {
                self.publish(.failed)
                self.publishToken(nil)
            }
        }
    }
}

/// Shared captcha block for auth forms: Turnstile + clear status / reload guidance.
struct AuthCaptchaBlock: View {
    let siteKey: String
    @Binding var captchaToken: String?
    @Binding var captchaResetToken: Int
    @Binding var captchaStatus: TurnstileChallengeStatus
    var appearance: Appearance = .onDarkGlass
    var instanceId: String = "auth"

    enum Appearance {
        case onDarkGlass
        case onLightSheet
    }

    private var needsAttention: Bool {
        switch captchaStatus {
        case .expired, .failed:
            return true
        case .loading, .ready, .verified:
            return false
        }
    }

    private var waitingForCheck: Bool {
        captchaStatus == .ready && captchaToken == nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TurnstileChallengeView(
                siteKey: siteKey,
                resetToken: captchaResetToken,
                onToken: deferCaptchaTokenUpdate,
                onStatus: deferCaptchaStatusUpdate
            )
            .id("\(instanceId)-\(captchaResetToken)")
            .frame(height: 72)
            .opacity(needsAttention ? 0.35 : 1)

            if captchaStatus == .loading {
                Label("auth_captcha_loading".t, systemImage: "arrow.triangle.2.circlepath")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(secondaryText)
            } else if waitingForCheck {
                Label("auth_captcha_required_hint".t, systemImage: "checkmark.shield")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .fixedSize(horizontal: false, vertical: true)
            } else if needsAttention {
                VStack(alignment: .leading, spacing: 8) {
                    Label("auth_captcha_unavailable_title".t, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(Color(hex: "FBBF24"))
                    Text("auth_captcha_unavailable_body".t)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(secondaryText)
                        .fixedSize(horizontal: false, vertical: true)

                    Button {
                        captchaToken = nil
                        captchaStatus = .loading
                        captchaResetToken += 1
                    } label: {
                        Text("auth_captcha_reload_btn".t)
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 10)
                            .background(Capsule().fill(Color(hex: "2D71F8")))
                    }
                    .buttonStyle(.plain)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.orange.opacity(appearance == .onDarkGlass ? 0.14 : 0.1))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Color(hex: "FBBF24").opacity(0.45), lineWidth: 1)
                )
            }
        }
    }

    private func deferCaptchaTokenUpdate(_ token: String?) {
        let binding = $captchaToken
        Task { @MainActor in
            await Task.yield()
            guard binding.wrappedValue != token else { return }
            binding.wrappedValue = token
        }
    }

    private func deferCaptchaStatusUpdate(_ status: TurnstileChallengeStatus) {
        let binding = $captchaStatus
        Task { @MainActor in
            await Task.yield()
            guard binding.wrappedValue != status else { return }
            binding.wrappedValue = status
        }
    }

    private var secondaryText: Color {
        appearance == .onDarkGlass ? Color.white.opacity(0.7) : Color.primary.opacity(0.65)
    }
}
