import Foundation

public struct CustomProvider: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public let name: String
    public init(id: UUID = UUID(), name: String) { self.id = id; self.name = name }

    public var variable: String {
        let folded = name.folding(options: [.diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .uppercased(with: Locale(identifier: "en_US_POSIX"))
        let words = folded.components(separatedBy: CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789").inverted)
            .filter { !$0.isEmpty }
        var stem = words.joined(separator: "_")
        if stem.isEmpty { stem = "CUSTOM" }
        if stem.first?.isNumber == true { stem = "CUSTOM_" + stem }
        let suggestion = stem + "_API_KEY"
        return InputRules.validVariable(suggestion) ? suggestion : "CUSTOM_API_KEY"
    }
}

public enum CustomProviderError: LocalizedError {
    case invalidName, duplicate, corrupt
    public var errorDescription: String? {
        switch self {
        case .invalidName: "Use a provider name with 1 to 40 characters."
        case .duplicate: "That provider already exists. Choose it from the list."
        case .corrupt: "The custom provider list could not be read. Your saved keys are unchanged."
        }
    }
}

/// Only provider names and stable IDs are stored here. Credentials stay in Keychain.
public struct CustomProviderCatalog {
    private let defaults: UserDefaults
    private let key = "customProviders.v1"
    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    public static func normalizedName(_ name: String) throws -> String {
        guard !name.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) else {
            throw CustomProviderError.invalidName
        }
        let normalized = name.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard !normalized.isEmpty, normalized.count <= 40 else { throw CustomProviderError.invalidName }
        return normalized
    }

    private static func identity(_ name: String) -> String {
        name.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
    }

    public func list() throws -> [CustomProvider] {
        guard let stored = defaults.object(forKey: key) else { return [] }
        guard let data = stored as? Data, let providers = try? JSONDecoder().decode([CustomProvider].self, from: data) else {
            throw CustomProviderError.corrupt
        }
        var ids: Set<UUID> = []
        var names: Set<String> = []
        for provider in providers {
            guard (try? Self.normalizedName(provider.name)) == provider.name,
                  ids.insert(provider.id).inserted, names.insert(Self.identity(provider.name)).inserted else {
                throw CustomProviderError.corrupt
            }
        }
        return providers.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    @discardableResult public func add(name: String) throws -> CustomProvider {
        let normalized = try Self.normalizedName(name)
        var providers = try list()
        let knownNames = Provider.allCases.map(\.name) + ["Other service", "Custom"]
        guard !knownNames.contains(where: { Self.identity($0) == Self.identity(normalized) }),
              !providers.contains(where: { Self.identity($0.name) == Self.identity(normalized) }) else {
            throw CustomProviderError.duplicate
        }
        let provider = CustomProvider(name: normalized)
        providers.append(provider)
        defaults.set(try JSONEncoder().encode(providers), forKey: key)
        return provider
    }

    @discardableResult public func rename(id: UUID, name: String) throws -> CustomProvider {
        let normalized = try Self.normalizedName(name)
        var providers = try list()
        guard let index = providers.firstIndex(where: { $0.id == id }) else { throw CustomProviderError.corrupt }
        let knownNames = Provider.allCases.map(\.name) + ["Other service", "Custom"]
        guard !knownNames.contains(where: { Self.identity($0) == Self.identity(normalized) }),
              !providers.contains(where: { $0.id != id && Self.identity($0.name) == Self.identity(normalized) }) else {
            throw CustomProviderError.duplicate
        }
        let renamed = CustomProvider(id: id, name: normalized)
        providers[index] = renamed
        defaults.set(try JSONEncoder().encode(providers), forKey: key)
        return renamed
    }

    public func remove(id: UUID) throws {
        let providers = try list().filter { $0.id != id }
        defaults.set(try JSONEncoder().encode(providers), forKey: key)
    }
}
