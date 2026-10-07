import AppKit
import WebKit

// The window: the app's title strip on top (the traffic lights in it), the
// site under it, and the loading screen over the site until it has loaded
// - or saying it can't (offline), or waiting for the sign-in in the browser.
final class SiteWindow: NSObject, NSWindowDelegate, WKNavigationDelegate, WKUIDelegate {
    private enum SiteState: String { case loading, offline, browser, ready }

    private let stripHeight: CGFloat = 36
    // The loading screen stays at least this long, so it fades instead of
    // flashing; the fade itself takes `fade`.
    private let minLoading: TimeInterval = 0.9
    private let fade: TimeInterval = 0.4
    private let sessionCookie = "reevun_session"
    private let sessionDays = 60

    private let window: NSWindow
    private let strip: WKWebView
    private let site: WKWebView
    private var loading: WKWebView?
    // The loading screen fading out, if one is.
    private var hiding: WKWebView?
    private var shownAt = Date()
    private var state = SiteState.loading
    private var failed = false
    private let signIn = SignIn()
    private var popups: [NSWindow] = []

    override init() {
        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1360, height: 860),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered, defer: false)
        window.titlebarAppearsTransparent = true
        window.titleVisibility = .hidden
        window.title = "Reevun"
        window.minSize = NSSize(width: 960, height: 620)
        window.backgroundColor = .white
        window.isReleasedWhenClosed = false
        window.center()
        // Reopens where the person left it.
        window.setFrameAutosaveName("Reevun")

        strip = Screens.view(page: "titlebar") { method, _ in method == "info" ? Screens.info() : nil }
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        configuration.applicationNameForUserAgent = "ReevunApp/\(version) (macos)"
        site = WKWebView(frame: .zero, configuration: configuration)
        super.init()

        window.delegate = self
        site.navigationDelegate = self
        site.uiDelegate = self
        site.underPageBackgroundColor = .white
        let content = window.contentView!
        place(strip, top: 0, height: stripHeight)
        place(site, top: stripHeight)
        // The whole strip moves the window (double-click zooms it), over the
        // page that draws it.
        place(DragArea(), top: 0, height: stripHeight)
        content.layoutSubtreeIfNeeded()
        showOverlay(.loading)
        dashboard()
    }

    func show() {
        window.makeKeyAndOrderFront(nil)
        placeTrafficLights()
    }

    private func place(_ child: NSView, top: CGFloat, height: CGFloat? = nil) {
        let content = window.contentView!
        child.translatesAutoresizingMaskIntoConstraints = false
        content.addSubview(child)
        var constraints = [
            child.topAnchor.constraint(equalTo: content.topAnchor, constant: top),
            child.leadingAnchor.constraint(equalTo: content.leadingAnchor),
            child.trailingAnchor.constraint(equalTo: content.trailingAnchor),
        ]
        constraints.append(height.map { child.heightAnchor.constraint(equalToConstant: $0) } ?? child.bottomAnchor.constraint(equalTo: content.bottomAnchor))
        NSLayoutConstraint.activate(constraints)
    }

    // The traffic lights, centred in the strip rather than in the system's
    // shorter title bar.
    private func placeTrafficLights() {
        guard let close = window.standardWindowButton(.closeButton), let bar = close.superview?.superview else { return }
        bar.frame = NSRect(x: bar.frame.minX, y: window.frame.height - stripHeight, width: bar.frame.width, height: stripHeight)
        let buttons: [NSWindow.ButtonType] = [.closeButton, .miniaturizeButton, .zoomButton]
        for (index, type) in buttons.enumerated() {
            guard let button = window.standardWindowButton(type) else { continue }
            button.setFrameOrigin(NSPoint(x: 14 + CGFloat(index) * 20, y: (stripHeight - button.frame.height) / 2))
        }
    }

    func windowDidResize(_ notification: Notification) { placeTrafficLights() }
    func windowDidExitFullScreen(_ notification: Notification) { placeTrafficLights() }

    func windowWillClose(_ notification: Notification) {
        if notification.object as? NSWindow === window { signIn.cancel() }
    }

    private func dashboard() {
        site.load(URLRequest(url: Site.dashboard))
    }

    // MARK: The loading screen

    private func report(_ next: SiteState) {
        state = next
        if let loading { Screens.emit(loading, "siteState", next.rawValue) }
    }

    // The screen over the site, in a given state (made again if it's gone or
    // going).
    private func showOverlay(_ next: SiteState) {
        if loading == nil || loading === hiding {
            let overlay = Screens.view(page: "loading") { [weak self] method, _ in self?.loadingMessage(method) }
            place(overlay, top: stripHeight)
            loading = overlay
            shownAt = Date()
        }
        report(next)
    }

    // The site has loaded: the screen fades out (its page does that on
    // "ready"), then goes.
    private func showSite() {
        guard let overlay = loading, overlay !== hiding else { return }
        hiding = overlay
        let wait = max(0, minLoading - Date().timeIntervalSince(shownAt))
        DispatchQueue.main.asyncAfter(deadline: .now() + wait) { [weak self] in
            guard let self else { return }
            report(.ready)
            DispatchQueue.main.asyncAfter(deadline: .now() + fade) { [weak self] in
                overlay.removeFromSuperview()
                if self?.loading === overlay { self?.loading = nil }
                if self?.hiding === overlay { self?.hiding = nil }
            }
        }
    }

    private func loadingMessage(_ method: String) -> Any? {
        switch method {
        case "info": return Screens.info()
        case "siteState": return state.rawValue
        case "retry":
            report(.loading)
            dashboard()
        case "reopenSignIn": signIn.waiting ? signIn.reopen() : startSignIn()
        case "cancelSignIn":
            signIn.cancel()
            showSite()
        default: break
        }
        return nil
    }

    // MARK: Signing in

    // While the browser sign-in is open the app waits on its own screen;
    // signed in, the dashboard loads with the new session.
    private func startSignIn() {
        showOverlay(.browser)
        if signIn.waiting { return signIn.reopen() }
        signIn.start { [weak self] token in
            guard let self else { return }
            report(.loading)
            let cookie = HTTPCookie(properties: [
                .domain: Site.url.host!,
                .path: "/",
                .name: sessionCookie,
                .value: token,
                .secure: "TRUE",
                .expires: Date().addingTimeInterval(TimeInterval(sessionDays * 24 * 60 * 60)),
                .sameSitePolicy: HTTPCookieStringPolicy.sameSiteLax,
                HTTPCookiePropertyKey("HttpOnly"): "TRUE",
            ])!
            site.configuration.websiteDataStore.httpCookieStore.setCookie(cookie) { [weak self] in
                self?.dashboard()
                NSApp.activate(ignoringOtherApps: true)
                self?.window.makeKeyAndOrderFront(nil)
            }
        }
    }

    // MARK: Where pages go

    // Reevun pages stay; signing in goes to the browser sign-in; Reevun ID's
    // pages and other links open in the browser. Whether `url` leaves.
    private func leaves(_ url: URL) -> Bool {
        if Site.stays(url) || ["about", "blob", "data"].contains(url.scheme) { return false }
        if Site.isSignIn(url) { startSignIn() } else if Site.opensOutside(url) { NSWorkspace.shared.open(url) }
        return true
    }

    func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        // The page itself (or a new window) going elsewhere; what it embeds
        // (frames) is left alone.
        let page = action.targetFrame?.isMainFrame ?? true
        guard page, let url = action.request.url, leaves(url) else { return decisionHandler(.allow) }
        decisionHandler(.cancel)
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        guard webView === site else { return }
        failed = false
    }

    // A page that failed (offline, the site down) keeps the screen up in its
    // offline state until a load succeeds. A load replaced by another one,
    // or stopped by the app, isn't one.
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        guard webView === site else { return }
        failed = true
        let error = error as NSError
        let stopped = (error.domain == NSURLErrorDomain && error.code == NSURLErrorCancelled) || (error.domain == WKError.errorDomain && error.code == 102)
        if !stopped { showOverlay(.offline) }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard webView === site, !failed, state != .ready else { return }
        showSite()
    }

    // The page process gone (out of memory, say): load again.
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        guard webView === site else { return }
        showOverlay(.loading)
        dashboard()
    }

    // A new window from the site (Discord's bot invite): a window of its own
    // while it's a Reevun or Discord page, else in the browser.
    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for action: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        guard let url = action.request.url, !leaves(url) else { return nil }
        let popup = WKWebView(frame: NSRect(x: 0, y: 0, width: 500, height: 760), configuration: configuration)
        popup.navigationDelegate = self
        popup.uiDelegate = self
        let holder = NSWindow(contentRect: popup.frame, styleMask: [.titled, .closable, .resizable], backing: .buffered, defer: false)
        holder.isReleasedWhenClosed = false
        holder.contentView = popup
        holder.center()
        holder.makeKeyAndOrderFront(nil)
        popups.append(holder)
        return popup
    }

    func webViewDidClose(_ webView: WKWebView) {
        popups.removeAll { holder in
            guard holder.contentView === webView else { return false }
            holder.close()
            return true
        }
    }

    // In the site's six languages, as the rest of the app's own words.
    private static let cancelTitle: String = {
        let titles = ["ru": "Отмена", "de": "Abbrechen", "es": "Cancelar", "tr": "İptal", "zh": "取消"]
        let language = Locale.preferredLanguages.first.map { String($0.prefix(2)) } ?? "en"
        return titles[language] ?? "Cancel"
    }()

    // The site's alert() and confirm(), as the system's own dialogs.
    func webView(_ webView: WKWebView, runJavaScriptAlertPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping () -> Void) {
        let alert = NSAlert()
        alert.messageText = message
        alert.beginSheetModal(for: webView.window ?? window) { _ in completionHandler() }
    }

    func webView(_ webView: WKWebView, runJavaScriptConfirmPanelWithMessage message: String, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping (Bool) -> Void) {
        let alert = NSAlert()
        alert.messageText = message
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: Self.cancelTitle)
        alert.beginSheetModal(for: webView.window ?? window) { response in completionHandler(response == .alertFirstButtonReturn) }
    }

    // Files for the site's file fields.
    func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping ([URL]?) -> Void) {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = parameters.allowsMultipleSelection
        panel.canChooseDirectories = parameters.allowsDirectories
        panel.beginSheetModal(for: webView.window ?? window) { response in completionHandler(response == .OK ? panel.urls : nil) }
    }
}

// Moves the window by the title strip; double-click zooms it, as a title
// bar does.
private final class DragArea: NSView {
    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 { window?.performZoom(nil) } else { window?.performDrag(with: event) }
    }
}
