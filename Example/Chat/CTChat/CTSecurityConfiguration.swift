import Foundation
import Security

/// Additional root CAs and permitted chat destinations. Configure before opening a chat.
public struct CTSecurityConfiguration {
    public let trustedRootsByHost: [String: [Data]]
    public let allowedRedirectHosts: Set<String>

    public init(trustedRootsByHost: [String: [Data]] = [:], allowedRedirectHosts: Set<String> = []) {
        self.trustedRootsByHost = trustedRootsByHost
        self.allowedRedirectHosts = allowedRedirectHosts
    }
}

/// Sanitized diagnostics: no visitor data, request contents, tokens or URL paths.
public struct CTChatError: Error, LocalizedError {
    public enum Stage: String {
        case configuration, tls, navigation, download, pushRegistration
    }

    public let stage: Stage
    public let host: String?
    public let code: Int
    public let domain: String

    public var errorDescription: String? {
        return "CTChat stage=\(stage.rawValue) host=\(host ?? "-") domain=\(domain) code=\(code)"
    }

    internal init(stage: Stage, host: String?, code: Int, domain: String = "CTChat") {
        self.stage = stage
        self.host = host.flatMap(CTSecurityPolicy.normalizedHost)
        self.code = code
        self.domain = domain
    }

    internal init(stage: Stage, url: URL?, error: Error) {
        let error = error as NSError
        self.init(stage: stage, host: url?.host, code: error.code, domain: error.domain)
    }
}

internal struct CTSecurityPolicy {
    let rootsByHost: [String: [SecCertificate]]
    let allowedHosts: Set<String>

    // ASCII DNS names (IDNs must be supplied as punycode) and IPv4 literals.
    // Normalize case and one terminal DNS dot; never match a substring or subdomain.
    static func normalizedHost(_ host: String) -> String? {
        var name = host.lowercased()
        if name.hasSuffix(".") { name.removeLast() }
        guard !name.isEmpty, name.utf8.count <= 253 else { return nil }
        let labels = name.split(separator: ".", omittingEmptySubsequences: false)
        for label in labels {
            guard !label.isEmpty, label.utf8.count <= 63,
                  label.first != "-", label.last != "-",
                  label.utf8.allSatisfy({ (97...122).contains($0) || (48...57).contains($0) || $0 == 45 }) else {
                return nil
            }
        }
        return name
    }

    init(configuration: CTSecurityConfiguration, baseURL: URL?) throws {
        var roots: [String: [SecCertificate]] = [:]
        var hosts = Set<String>()
        for (input, data) in configuration.trustedRootsByHost {
            guard let host = Self.normalizedHost(input) else {
                throw CTChatError(stage: .configuration, host: nil, code: 1)
            }
            guard !data.isEmpty else {
                throw CTChatError(stage: .configuration, host: host, code: 2)
            }
            for bytes in data {
                guard let certificate = SecCertificateCreateWithData(nil, bytes as CFData) else {
                    throw CTChatError(stage: .configuration, host: host, code: 3)
                }
                roots[host, default: []].append(certificate)
            }
        }
        for input in configuration.allowedRedirectHosts {
            guard let host = Self.normalizedHost(input) else {
                throw CTChatError(stage: .configuration, host: nil, code: 1)
            }
            hosts.insert(host)
        }
        guard let url = baseURL, url.scheme?.lowercased() == "https",
              url.user == nil, url.password == nil,
              let host = url.host.flatMap(Self.normalizedHost) else {
            throw CTChatError(stage: .configuration, host: nil, code: 4)
        }
        hosts.insert(host)
        rootsByHost = roots
        allowedHosts = hosts
    }

    func allows(_ url: URL) -> Bool {
        guard url.scheme?.lowercased() == "https", url.user == nil, url.password == nil,
              let host = url.host.flatMap(Self.normalizedHost) else { return false }
        return allowedHosts.contains(host)
    }

    func rejection(for url: URL?, stage: CTChatError.Stage = .navigation) -> CTChatError {
        return CTChatError(stage: stage, host: url?.host, code: 5)
    }
}
