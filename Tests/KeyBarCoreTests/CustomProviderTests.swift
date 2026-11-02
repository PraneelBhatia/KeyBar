import Testing
import Foundation
@testable import KeyBarCore

struct CustomProviderTests {
    private func withCatalog(_ body: (CustomProviderCatalog, UserDefaults) throws -> Void) throws {
        let suite = "app.keybar.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        try body(CustomProviderCatalog(defaults: defaults), defaults)
    }

    @Test func namesPersistAndDuplicatesAreRejected() throws {
        try withCatalog { catalog, defaults in
            let first = try catalog.add(name: "  Acme   AI  ")
            #expect(first.name == "Acme AI")
            let restored = CustomProviderCatalog(defaults: defaults)
            #expect(try restored.list() == [first])
            for duplicate in ["acme ai", "ACME AI", "OpenAI", "gemini", "Custom"] {
                #expect(throws: CustomProviderError.self) { try catalog.add(name: duplicate) }
            }
            #expect(try catalog.list() == [first])
        }
    }

    @Test func namesAreValidatedAndVariablesAreSafe() throws {
        for name in ["", "   ", "bad\nname", String(repeating: "x", count: 41)] {
            #expect(throws: CustomProviderError.self) { try CustomProviderCatalog.normalizedName(name) }
        }
        let examples: [(String, String)] = [
            ("Acme AI", "ACME_AI_API_KEY"), ("123 Service", "CUSTOM_123_SERVICE_API_KEY"),
            ("Café", "CAFE_API_KEY"), ("🔑", "CUSTOM_API_KEY"), ("Python tools", "CUSTOM_API_KEY")
        ]
        for (name, variable) in examples {
            let provider = CustomProvider(name: name)
            #expect(provider.variable == variable)
            #expect(InputRules.validVariable(provider.variable))
        }
    }

    @Test func deletingProviderKeepsSavedKeyLabelAndIdentity() throws {
        try withCatalog { catalog, _ in
            let provider = try catalog.add(name: "Acme")
            let record = KeyRecord(name: "Work", variable: "ACME_API_KEY", provider: .custom,
                                   customProviderID: provider.id, customProviderName: provider.name)
            let persisted = try JSONEncoder().encode(record)
            try catalog.remove(id: provider.id)
            #expect(try catalog.list().isEmpty)
            let restored = try JSONDecoder().decode(KeyRecord.self, from: persisted)
            #expect(restored.providerName == "Acme")
            #expect(restored.customProviderID == provider.id)
            #expect(restored.id == record.id)
            #expect(restored.provider.endpoint == nil)
        }
    }

    @Test func legacyKeyMetadataStillDecodes() throws {
        let original = KeyRecord(name: "Existing", variable: "EXISTING_KEY", provider: .custom)
        var object = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any])
        object.removeValue(forKey: "customProviderID")
        object.removeValue(forKey: "customProviderName")
        let decoded = try JSONDecoder().decode(KeyRecord.self, from: JSONSerialization.data(withJSONObject: object))
        #expect(decoded == original)
        #expect(decoded.providerName == "Custom")
        #expect(decoded.customProviderID == nil)
        let known = KeyRecord(name: "Known", variable: "GEMINI_API_KEY", provider: .gemini, customProviderName: "Ignored")
        #expect(known.providerName == "Gemini")
    }

    @Test func corruptCatalogIsNotSilentlyOverwritten() throws {
        try withCatalog { catalog, defaults in
            let corrupt = Data("not valid metadata".utf8)
            defaults.set(corrupt, forKey: "customProviders.v1")
            #expect(throws: CustomProviderError.self) { try catalog.list() }
            #expect(throws: CustomProviderError.self) { try catalog.add(name: "Acme") }
            #expect(defaults.data(forKey: "customProviders.v1") == corrupt)
        }
    }
}
