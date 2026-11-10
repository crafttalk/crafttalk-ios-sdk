import Foundation
import Security

/// Shared by WKWebView and URLSession. SecTrust evaluation can access the network.
internal enum CTTrustEvaluator {
    private static let queue = DispatchQueue(label: "crafttalk.trust", qos: .utility, attributes: .concurrent)

    static func handle(_ challenge: URLAuthenticationChallenge,
                       policy: CTSecurityPolicy?, legacyCertificate: Data?, legacyBaseURL: String?,
                       reportError: @escaping (CTChatError) -> Void = { CTChat.shared.report($0) },
                       completion: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
        let space = challenge.protectionSpace
        guard space.authenticationMethod == NSURLAuthenticationMethodServerTrust else {
            completion(.performDefaultHandling, nil)
            return
        }
        let host = CTSecurityPolicy.normalizedHost(space.host)
        let roots = host.flatMap { policy?.rootsByHost[$0] }
        // configure() retains the original matching rule, including IPv6 and internal names.
        // The strict host rules belong only to configure(security:).
        let pin = policy == nil && legacyBaseURL?.contains(space.host) == true ? legacyCertificate : nil
        guard policy != nil || pin != nil else {
            completion(.performDefaultHandling, nil)
            return
        }
        guard let trust = space.serverTrust else {
            if policy == nil {
                completion(.performDefaultHandling, nil)
                return
            }
            reportError(CTChatError(stage: .tls, host: host, code: NSURLErrorServerCertificateUntrusted,
                                   domain: NSURLErrorDomain))
            completion(.cancelAuthenticationChallenge, nil)
            return
        }
        queue.async {
            let accepted: Bool
            if let roots = roots {
                accepted = evaluate(trust, host: space.host, roots: roots)
            } else if let pin = pin {
                // Preserve the legacy leaf-certificate comparison for configure().
                var result = SecTrustResultType.invalid
                let status = SecTrustEvaluate(trust, &result)
                accepted = status == errSecSuccess && SecTrustGetCertificateAtIndex(trust, 0).map {
                    (SecCertificateCopyData($0) as Data) == pin
                } == true
            } else {
                // Inspect the unmodified system trust so subresource TLS failures reach onError.
                // WKWebView does not deliver navigation failures for script/fetch/WSS requests.
                accepted = evaluateSystemTrust(trust)
            }
            if !accepted {
                reportError(CTChatError(stage: .tls, host: host,
                                       code: NSURLErrorServerCertificateUntrusted, domain: NSURLErrorDomain))
            }
            if roots == nil && pin == nil {
                // Observation only: let the platform reject an invalid system trust in its
                // usual way, including WebKit's error delivery to subresources and sockets.
                completion(.performDefaultHandling, nil)
            } else {
                completion(accepted ? .useCredential : .cancelAuthenticationChallenge,
                           accepted ? URLCredential(trust: trust) : nil)
            }
        }
    }

    static func evaluate(_ trust: SecTrust, host: String, roots: [SecCertificate]) -> Bool {
        guard SecTrustSetPolicies(trust, SecPolicyCreateSSL(true, host as CFString)) == errSecSuccess,
              SecTrustSetAnchorCertificates(trust, roots as CFArray) == errSecSuccess,
              SecTrustSetAnchorCertificatesOnly(trust, false) == errSecSuccess else { return false }
        return evaluateSystemTrust(trust)
    }

    private static func evaluateSystemTrust(_ trust: SecTrust) -> Bool {
        if #available(iOS 12.0, macOS 10.14, *) {
            return SecTrustEvaluateWithError(trust, nil)
        } else {
            var result = SecTrustResultType.invalid
            return SecTrustEvaluate(trust, &result) == errSecSuccess && (result == .unspecified || result == .proceed)
        }
    }
}
