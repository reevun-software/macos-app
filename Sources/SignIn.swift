import AppKit
import Network

// Signing in happens in the browser, not in the app: the app opens Reevun
// ID's id.reevun.app/app?port=…&state=… and listens on that port of
// 127.0.0.1. There the person signs in (or already is) and confirms; Reevun
// ID sends the browser back here with a session of the app's own, which
// becomes the app's session cookie - the same one the website reads. An
// unfinished sign-in stops listening after `timeout`.
final class SignIn {
    private(set) var url: URL?
    private var listener: NWListener?
    private var state = ""
    private let timeout: TimeInterval = 10 * 60

    var waiting: Bool { listener != nil }

    // `done` gets the session token, on the main thread.
    func start(done: @escaping (String) -> Void) {
        cancel()
        var bytes = [UInt8](repeating: 0, count: 24)
        _ = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        state = Data(bytes).base64EncodedString().replacingOccurrences(of: "+", with: "-").replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "=", with: "")
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        guard let listener = try? NWListener(using: parameters) else { return }
        self.listener = listener
        let expected = state
        listener.newConnectionHandler = { [weak self] connection in
            connection.start(queue: .main)
            connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { data, _, _, _ in
                let line = data.flatMap { String(data: $0, encoding: .utf8) }?.components(separatedBy: "\r\n").first ?? ""
                guard let token = Self.token(from: line, state: expected) else {
                    return Self.answer(connection, "HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n")
                }
                Self.answer(connection, "HTTP/1.1 302 Found\r\nLocation: \(Site.idURL.absoluteString)/app/done\r\nContent-Length: 0\r\nConnection: close\r\n\r\n")
                self?.cancel()
                done(token)
            }
        }
        listener.stateUpdateHandler = { [weak self] update in
            guard case .ready = update, let self, let port = listener.port?.rawValue else { return }
            var url = URLComponents(url: Site.idURL.appendingPathComponent("app"), resolvingAgainstBaseURL: false)!
            url.queryItems = [URLQueryItem(name: "port", value: String(port)), URLQueryItem(name: "state", value: expected)]
            self.url = url.url
            reopen()
        }
        listener.start(queue: .main)
        DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { [weak self, weak listener] in
            if let listener, self?.listener === listener { self?.cancel() }
        }
    }

    // Opens the browser's sign-in page (again).
    func reopen() {
        if let url { NSWorkspace.shared.open(url) }
    }

    func cancel() {
        listener?.cancel()
        listener = nil
        url = nil
    }

    // "GET /callback?state=…&token=… HTTP/1.1" with this sign-in's state.
    static func token(from line: String, state: String) -> String? {
        let parts = line.split(separator: " ")
        guard parts.count >= 2, parts[0] == "GET", let url = URLComponents(string: "http://127.0.0.1\(parts[1])"), url.path == "/callback" else { return nil }
        let value = { (name: String) in url.queryItems?.first { $0.name == name }?.value }
        guard value("state") == state, let token = value("token"), !token.isEmpty else { return nil }
        return token
    }

    private static func answer(_ connection: NWConnection, _ response: String) {
        connection.send(content: Data(response.utf8), completion: .contentProcessed { _ in connection.cancel() })
    }
}
