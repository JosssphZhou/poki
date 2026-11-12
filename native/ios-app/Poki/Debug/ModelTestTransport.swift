#if DEBUG && targetEnvironment(simulator)
import Foundation

/// Opt-in transport for isolated UI tests. Production builds never include it.
final class ModelTestTransport: URLProtocol {
    private static var proxy: URL?
    private var forwardedTask: URLSessionDataTask?
    static func installIfGiven() {
        guard let raw = ProcessInfo.processInfo.environment["POKI_UI_TEST_PROXY"],
              let url = URL(string: raw), url.scheme == "http", url.host == "127.0.0.1" else { return }
        proxy = url
        URLProtocol.registerClass(Self.self)
    }
    override class func canInit(with request: URLRequest) -> Bool {
        proxy != nil && ["api.deepseek.com"].contains(request.url?.host ?? "")
    }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        guard let proxy = Self.proxy else { return }
        guard request.value(forHTTPHeaderField: "Authorization")?.hasPrefix("Bearer fixture-") == true else {
            client?.urlProtocol(self, didFailWithError: URLError(.userAuthenticationRequired))
            return
        }
        var forwarded = request
        forwarded.setValue(request.url?.absoluteString, forHTTPHeaderField: "X-Poki-Test-Original-URL")
        forwarded.url = proxy.appendingPathComponent("model")
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = []
        forwardedTask = URLSession(configuration: configuration).dataTask(with: forwarded) { [weak self] data, response, error in
            guard let self else { return }
            if let error { self.client?.urlProtocol(self, didFailWithError: error); return }
            guard let response = response as? HTTPURLResponse, let url = self.request.url,
                  let mapped = HTTPURLResponse(url: url, statusCode: response.statusCode, httpVersion: "HTTP/1.1", headerFields: ["Content-Type": "text/event-stream"]) else { return }
            self.client?.urlProtocol(self, didReceive: mapped, cacheStoragePolicy: .notAllowed)
            if let data { self.client?.urlProtocol(self, didLoad: data) }
            self.client?.urlProtocolDidFinishLoading(self)
        }
        forwardedTask?.resume()
    }
    override func stopLoading() { forwardedTask?.cancel() }
}
#endif
