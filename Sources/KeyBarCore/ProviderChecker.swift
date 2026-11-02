import Foundation

public struct CheckResult: Sendable {
    public let status: KeyStatus
    public let remainingLimit: Double?
    public init(_ status: KeyStatus, remainingLimit: Double? = nil) {
        self.status = status; self.remainingLimit = remainingLimit
    }
}

private final class NoRedirects: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask,
                    willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

public enum ProviderChecker {
    public static func request(provider: Provider, secret: String) -> URLRequest? {
        guard let url = provider.endpoint, InputRules.validSecret(secret) else { return nil }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        switch provider {
        case .gemini: request.setValue(secret, forHTTPHeaderField: "x-goog-api-key")
        case .anthropic:
            request.setValue("Bearer \(secret)", forHTTPHeaderField: "Authorization")
            request.setValue("2026-10-21", forHTTPHeaderField: "anthropic-version")
        case .openai, .openrouter: request.setValue("Bearer \(secret)", forHTTPHeaderField: "Authorization")
        case .custom: return nil
        }
        return request
    }
    public static func check(provider: Provider, secret: String) async -> CheckResult {
        guard let request = request(provider: provider, secret: secret) else { return CheckResult(.unchecked) }
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        config.httpCookieStorage = nil
        config.urlCredentialStorage = nil
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 20
        let session = URLSession(configuration: config, delegate: NoRedirects(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, data.count <= 2_000_000 else { return CheckResult(.unavailable) }
            return interpret(provider: provider, code: http.statusCode, data: data)
        } catch {
            // Never expose NSError or a provider's body: either may contain credentials.
            return CheckResult(.unavailable)
        }
    }
    public static func interpret(provider: Provider, code: Int, data: Data) -> CheckResult {
        if provider == .custom { return CheckResult(.unchecked) }
        switch code {
        case 401: return CheckResult(.invalid)
        case 403: return CheckResult(.restricted)
        case 429: return CheckResult(.rateLimited)
        case 402: return CheckResult(.restricted)
        default: break
        }
        let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        if provider == .gemini, code == 400,
           let error = json?["error"] as? [String: Any], let details = error["details"] as? [[String: Any]],
           details.contains(where: { $0["reason"] as? String == "API_KEY_INVALID" }) { return CheckResult(.invalid) }
        guard code == 200, let json else { return CheckResult(.unavailable) }
        if provider == .openrouter {
            guard let info = json["data"] as? [String: Any], info["usage"] is NSNumber else { return CheckResult(.unavailable) }
            let remaining = (info["limit_remaining"] as? NSNumber)?.doubleValue
            return CheckResult(.valid, remainingLimit: remaining?.isFinite == true ? remaining : nil)
        }
        guard json[provider == .gemini ? "models" : "data"] is [Any] else { return CheckResult(.unavailable) }
        return CheckResult(.valid)
    }
}
