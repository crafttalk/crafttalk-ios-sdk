import Foundation

// Подмена транспорта проверяет формирование запроса, но не TLS и сетевые редиректы.
final class CTTestTransport {
    let identifier = UUID().uuidString
    private let lock = NSLock()
    private var recorded: [URLRequest] = []
    private var callback: ((URLRequest) -> Void)?

    var onRequest: ((URLRequest) -> Void)? {
        get { lock.lock(); defer { lock.unlock() }; return callback }
        set { lock.lock(); defer { lock.unlock() }; callback = newValue }
    }

    var requests: [URLRequest] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }

    var configuration: URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [CTTestURLProtocol.self]
        configuration.httpAdditionalHeaders = ["X-CraftTalk-Test-ID": identifier]
        return configuration
    }

    init(respond: ((URLProtocol) -> Void)? = nil) {
        CTTestURLProtocol.register(identifier) { [weak self] connection in
            guard let self = self else { return }
            var request = connection.request
            if request.httpBody == nil, let stream = request.httpBodyStream {
                stream.open()
                defer { stream.close() }
                var bytes = Data()
                var buffer = [UInt8](repeating: 0, count: 1024)
                while true {
                    let count = stream.read(&buffer, maxLength: buffer.count)
                    guard count > 0 else { break }
                    bytes.append(contentsOf: buffer.prefix(count))
                }
                request.httpBody = bytes
            }
            self.lock.lock()
            self.recorded.append(request)
            self.lock.unlock()
            if let respond = respond {
                respond(connection)
            } else {
                let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!
                connection.client?.urlProtocol(connection, didReceive: response, cacheStoragePolicy: .notAllowed)
                connection.client?.urlProtocol(connection, didLoad: Data("ok".utf8))
                connection.client?.urlProtocolDidFinishLoading(connection)
            }
            self.onRequest?(request)
        }
    }

    deinit {
        CTTestURLProtocol.unregister(identifier)
    }
}

private final class CTTestURLProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var handlers: [String: (CTTestURLProtocol) -> Void] = [:]

    static func register(_ identifier: String, handler: @escaping (CTTestURLProtocol) -> Void) {
        lock.lock()
        defer { lock.unlock() }
        handlers[identifier] = handler
    }

    static func unregister(_ identifier: String) {
        lock.lock()
        defer { lock.unlock() }
        handlers.removeValue(forKey: identifier)
    }

    override class func canInit(with request: URLRequest) -> Bool { return true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { return request }

    override func startLoading() {
        Self.lock.lock()
        let handler = request.value(forHTTPHeaderField: "X-CraftTalk-Test-ID").flatMap { Self.handlers[$0] }
        Self.lock.unlock()
        guard let handler = handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.resourceUnavailable))
            return
        }
        handler(self)
    }

    override func stopLoading() {}
}

final class CTManualScheduler {
    final class Job {
        let delay: TimeInterval
        let action: () -> Void

        init(delay: TimeInterval, action: @escaping () -> Void) {
            self.delay = delay
            self.action = action
        }
    }

    private(set) var jobs: [Job] = []
    var pendingCount: Int { jobs.count }

    func schedule(delay: TimeInterval, action: @escaping () -> Void) {
        let job = Job(delay: delay, action: action)
        jobs.append(job)
    }

    func discardAll() { jobs.removeAll() }

    func runAll() {
        let pending = jobs
        jobs.removeAll()
        for job in pending { job.action() }
    }
}
