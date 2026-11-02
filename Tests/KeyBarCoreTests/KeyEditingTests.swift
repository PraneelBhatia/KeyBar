import Testing
import Foundation
@testable import KeyBarCore

struct KeyEditingTests {
    private var checked: KeyRecord {
        KeyRecord(name: "Personal", variable: "OLD_API_KEY", provider: .openrouter,
                  addedAt: Date(timeIntervalSince1970: 100), checkedAt: Date(timeIntervalSince1970: 200),
                  status: .valid, remainingLimit: 12.5)
    }

    @Test func metadataEditsPreserveCredentialAgeAndCheckResult() throws {
        let original = checked
        let edited = try original.applyingEdits(name: "  Work  ", variable: "WORK_API_KEY", provider: .openrouter)
        #expect(edited.id == original.id)
        #expect(edited.name == "Work" && edited.variable == "WORK_API_KEY")
        #expect(edited.addedAt == original.addedAt)
        #expect(edited.status == .valid && edited.checkedAt == original.checkedAt)
        #expect(edited.remainingLimit == original.remainingLimit)
        #expect(edited.revision != nil && edited.revision != original.revision)
    }

    @Test func providerChangesClearCheckButPreserveKeyAge() throws {
        let original = checked
        let custom = CustomProvider(name: "Acme")
        let edited = try original.applyingEdits(name: "Work", variable: "ACME_API_KEY", provider: .custom, customProvider: custom)
        #expect(edited.id == original.id && edited.addedAt == original.addedAt)
        #expect(edited.status == .unchecked && edited.checkedAt == nil && edited.remainingLimit == nil)
        #expect(edited.customProviderID == custom.id && edited.providerName == "Acme")
        let known = try edited.applyingEdits(name: "Work", variable: "GEMINI_API_KEY", provider: .gemini)
        #expect(known.customProviderID == nil && known.customProviderName == nil)
        #expect(known.providerName == "Gemini")
    }

    @Test func replacingSecretResetsAgeAndCheckState() throws {
        let original = checked
        let date = Date(timeIntervalSince1970: 300)
        let edited = try original.applyingEdits(name: "Personal", variable: original.variable, provider: .openrouter,
                                               secretReplaced: true, date: date)
        #expect(edited.id == original.id && edited.addedAt == date)
        #expect(edited.status == .unchecked && edited.checkedAt == nil && edited.remainingLimit == nil)
    }

    @Test func editsRejectInvalidFields() throws {
        let original = checked
        for (name, variable) in [("", "WORK_KEY"), ("Work", "PATH"), ("Work", "bad-name"), ("Bad\u{1b}name", "WORK_KEY")] {
            #expect(throws: VaultError.self) { try original.applyingEdits(name: name, variable: variable, provider: .openai) }
        }
        #expect(throws: VaultError.self) {
            try original.applyingEdits(name: "Work", variable: "WORK_KEY", provider: .openai, customProvider: CustomProvider(name: "Acme"))
        }
    }

    @Test func customProviderRenamePreservesIdentityAndUpdatesDisplay() throws {
        let suite = "app.keybar.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let catalog = CustomProviderCatalog(defaults: defaults)
        let provider = try catalog.add(name: "Old service")
        let record = KeyRecord(name: "Work", variable: "SERVICE_KEY", provider: .custom,
                               customProviderID: provider.id, customProviderName: provider.name)
        let renamed = try catalog.rename(id: provider.id, name: "New service")
        #expect(renamed.id == provider.id)
        #expect(record.displayProviderName(in: try catalog.list()) == "New service")
        #expect(record.displayProviderName(in: []) == "Old service")
        #expect(throws: CustomProviderError.self) { try catalog.rename(id: provider.id, name: "OpenAI") }
        _ = try catalog.add(name: "Other name")
        #expect(throws: CustomProviderError.self) { try catalog.rename(id: provider.id, name: "other name") }
        #expect(try catalog.list().contains(renamed))
    }
}

/// Opt in on a Mac with an unlocked login Keychain. Every item uses a new, isolated service and synthetic values.
struct KeychainEditingIntegrationTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["KEYBAR_KEYCHAIN_TESTS"] == "1"))
    func accountRenamePreservesStoredSecretAndReplacementUpdatesSameItem() throws {
        let vault = KeychainVault(service: "app.keybar.tests.\(UUID().uuidString)")
        let original = KeyRecord(name: "Synthetic", variable: "OLD_TEST_KEY", provider: .custom)
        defer { try? vault.delete("OLD_TEST_KEY"); try? vault.delete("NEW_TEST_KEY") }
        try vault.add(original, secret: "synthetic-original-value")
        let current = try #require(vault.list().first)
        let edited = try current.applyingEdits(name: "Edited", variable: "NEW_TEST_KEY", provider: .custom)
        try vault.update(edited, original: current)
        #expect(try vault.secret(for: "NEW_TEST_KEY") == "synthetic-original-value")
        #expect(throws: VaultError.self) { try vault.secret(for: "OLD_TEST_KEY") }
        #expect(try vault.list() == [edited])
        let replacement = try edited.applyingEdits(name: "Edited", variable: "NEW_TEST_KEY", provider: .custom, secretReplaced: true)
        try vault.update(replacement, secret: "synthetic-new-value", original: edited)
        #expect(try vault.secret(for: "NEW_TEST_KEY") == "synthetic-new-value")
        #expect(try vault.list().first?.id == original.id)
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["KEYBAR_KEYCHAIN_TESTS"] == "1"))
    func duplicateAndStaleEditsLeaveBothCredentialsIntact() throws {
        let vault = KeychainVault(service: "app.keybar.tests.\(UUID().uuidString)")
        let first = KeyRecord(name: "First", variable: "FIRST_TEST_KEY", provider: .custom)
        let second = KeyRecord(name: "Second", variable: "SECOND_TEST_KEY", provider: .custom)
        defer { try? vault.delete(first.variable); try? vault.delete(second.variable) }
        try vault.add(first, secret: "synthetic-first-value")
        try vault.add(second, secret: "synthetic-second-value")
        let current = try #require(vault.list().first(where: { $0.id == first.id }))
        let duplicate = try current.applyingEdits(name: "Changed", variable: second.variable, provider: .custom)
        #expect(throws: VaultError.self) { try vault.update(duplicate, secret: "synthetic-replacement", original: current) }
        #expect(try vault.secret(for: first.variable) == "synthetic-first-value")
        #expect(try vault.secret(for: second.variable) == "synthetic-second-value")
        #expect(try vault.list().first(where: { $0.id == first.id }) == current)
        let changed = try current.applyingEdits(name: "Updated", variable: first.variable, provider: .custom)
        try vault.update(changed, original: current)
        #expect(throws: VaultError.self) { try vault.update(duplicate, original: current) }
        #expect(try vault.list().first(where: { $0.id == first.id }) == changed)
    }
}
