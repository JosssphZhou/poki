#if DEBUG
import Foundation

/// A local streaming response for the full-app draft regression. Only the named UI test enables it.
@MainActor
enum ComposerDraftUITestFixture {
    static func installIfRequested() {
        guard ProcessInfo.processInfo.arguments.contains("-pokiUITestComposerDraft") else { return }
        let provider = CustomProviders.upsert(CustomProvider(
            endpoints: [CustomEndpoint(url: "https://composer-fixture.test/v1", api: .chatCompletions)],
            model: "composer-fixture"
        ))
        ModelKeys.selectedProvider = .custom
        ModelKeys.selectedModel = CustomProviders.choiceID(provider.id, provider.model)
        URLProtocol.registerClass(ComposerDraftModelProtocol.self)
    }
}

final class ComposerDraftModelProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host() == "composer-fixture.test" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1",
                                       headerFields: ["Content-Type": "text/event-stream"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        let chunk = #"{"id":"fixture","object":"chat.completion.chunk","created":1,"model":"composer-fixture","choices":[{"index":0,"delta":{"role":"assistant","content":"Synthetic reply finished."},"finish_reason":null}]}"#
        let done = #"{"id":"fixture","object":"chat.completion.chunk","created":1,"model":"composer-fixture","choices":[{"index":0,"delta":{},"finish_reason":"stop"}]}"#
        client?.urlProtocol(self, didLoad: Data("data: \(chunk)\n\ndata: \(done)\n\ndata: [DONE]\n\n".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
#endif
