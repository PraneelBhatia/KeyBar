import Foundation

public enum Provider: String, Codable, CaseIterable, Sendable, Identifiable {
    case custom, gemini, openrouter, anthropic, openai
    public var id: Self { self }
    public var name: String {
        switch self {
        case .custom: "Custom"
        case .gemini: "Gemini"
        case .openrouter: "OpenRouter"
        case .anthropic: "Anthropic"
        case .openai: "OpenAI"
        }
    }
    public var variable: String {
        switch self {
        case .custom: "MY_API_KEY"
        case .gemini: "GEMINI_API_KEY"
        case .openrouter: "OPENROUTER_API_KEY"
        case .anthropic: "ANTHROPIC_API_KEY"
        case .openai: "OPENAI_API_KEY"
        }
    }
    public var endpoint: URL? {
        let address: String
        switch self {
        case .custom: return nil
        case .gemini: address = "https://generativelanguage.googleapis.com/v1beta/models?pageSize=1"
        case .openrouter: address = "https://openrouter.ai/api/v1/key"
        case .anthropic: address = "https://api.anthropic.com/v1/models?limit=1"
        case .openai: address = "https://api.openai.com/v1/models"
        }
        return URL(string: address)
    }
    public static func detect(secret: String, variable: String = "") -> Self {
        // Specific prefixes take precedence over a possibly stale variable name.
        if secret.hasPrefix("sk-or-") { return .openrouter }
        if secret.hasPrefix("sk-ant-") { return .anthropic }
        if secret.hasPrefix("sk-proj-") || secret.hasPrefix("sk-svcacct-") { return .openai }
        // Google keys can serve other APIs; only the variable opts into Gemini.
        return allCases.first { $0 != .custom && $0.variable == variable.uppercased() } ?? .custom
    }
}

public enum KeyStatus: String, Codable, Sendable {
    case unchecked, valid, invalid, restricted, rateLimited, unavailable
    public var label: String {
        switch self {
        case .unchecked: "Unchecked"
        case .valid: "Valid"
        case .invalid: "Invalid"
        case .restricted: "Restricted"
        case .rateLimited: "Rate limited"
        case .unavailable: "Check unavailable"
        }
    }
    public var explanation: String {
        switch self {
        case .unchecked: "Stored securely. This key has not been checked."
        case .valid: "The provider accepted this key. Billing and model access may still vary."
        case .invalid: "The provider rejected this credential. Replace it or check your provider dashboard."
        case .restricted: "The provider denied access. The key may have limited permissions or account restrictions."
        case .rateLimited: "The provider is limiting requests. Try checking again later."
        case .unavailable: "Could not confirm this key. Check your connection or try again later."
        }
    }
}

public struct KeyRecord: Identifiable, Codable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var variable: String
    public var provider: Provider
    public var revision: UUID?
    public var customProviderID: UUID?
    public var customProviderName: String?
    public var providerName: String { provider == .custom ? customProviderName ?? provider.name : provider.name }
    public var addedAt: Date
    public var checkedAt: Date?
    public var status: KeyStatus
    public var remainingLimit: Double?
    public init(id: UUID = UUID(), name: String, variable: String, provider: Provider,
                addedAt: Date = Date(), checkedAt: Date? = nil, status: KeyStatus = .unchecked,
                remainingLimit: Double? = nil, customProviderID: UUID? = nil, customProviderName: String? = nil, revision: UUID? = nil) {
        self.id = id; self.name = name; self.variable = variable; self.provider = provider
        self.addedAt = addedAt; self.checkedAt = checkedAt; self.status = status
        self.remainingLimit = remainingLimit
        self.revision = revision
        self.customProviderID = customProviderID; self.customProviderName = customProviderName
    }
}

public enum InputRules {
    public static func validVariable(_ value: String) -> Bool {
        // A key must never overwrite PATH, DYLD_*, shell startup controls, etc.
        guard value.count <= 128,
              value.range(of: "\\A[A-Z_][A-Z0-9_]*\\z", options: .regularExpression) != nil else { return false }
        let reserved: Set<String> = ["PATH", "HOME", "SHELL", "USER", "LOGNAME", "TMPDIR", "IFS", "ENV", "BASH_ENV",
                                     "ZDOTDIR", "SHELLOPTS", "BASHOPTS", "CDPATH", "GLOBIGNORE", "PROMPT_COMMAND",
                                     "PS4", "SSLKEYLOGFILE", "SSL_CERT_FILE", "SSL_CERT_DIR", "CURL_CA_BUNDLE",
                                     "REQUESTS_CA_BUNDLE", "GIT_CONFIG", "GIT_CONFIG_COUNT"]
        let reservedPrefixes = ["DYLD_", "LD_", "PYTHON", "NODE_", "RUBY", "PERL", "BASH_FUNC_", "GIT_CONFIG_"]
        return !reserved.contains(value) && !reservedPrefixes.contains(where: value.hasPrefix)
    }
    public static func validSecret(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.count <= 16_384 && !value.unicodeScalars.contains {
            CharacterSet.controlCharacters.contains($0) || CharacterSet.whitespacesAndNewlines.contains($0)
        }
    }
    public static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\"'\"'") + "'"
    }
}
