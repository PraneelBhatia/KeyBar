import AppKit
import Observation
import KeyBarCore

@MainActor @Observable
final class KeyStore {
    var records: [KeyRecord] = []
    var customProviders: [CustomProvider] = []
    var checking: Set<UUID> = []
    var error: String?
    var handoffMode: HandoffMode = .choose
    let demo: Bool
    private let vault = KeychainVault()
    private let providerCatalog = CustomProviderCatalog()

    init(demo: Bool = false) {
        self.demo = demo
        if demo {
            records = [
                KeyRecord(name: "Personal", variable: "OPENROUTER_API_KEY", provider: .openrouter,
                          addedAt: Date().addingTimeInterval(-86400 * 12), checkedAt: Date(), status: .valid, remainingLimit: 24.82),
                KeyRecord(name: "Workbench", variable: "ANTHROPIC_API_KEY", provider: .anthropic,
                          addedAt: Date().addingTimeInterval(-86400 * 5), checkedAt: Date(), status: .valid),
                KeyRecord(name: "Side projects", variable: "GEMINI_API_KEY", provider: .gemini,
                          addedAt: Date().addingTimeInterval(-86400 * 2), status: .unchecked),
                KeyRecord(name: "Production", variable: "SERVICE_TOKEN", provider: .custom,
                          addedAt: Date().addingTimeInterval(-86400 * 21))
            ]
        } else { refresh() }
    }
    func refresh() {
        guard !demo else { return }
        do { records = try vault.list(); customProviders = try providerCatalog.list() }
        catch { report(error) }
    }
    func save(name: String, variable: String, provider: Provider, secret: String,
              replacing: KeyRecord?, check: Bool, customProvider: CustomProvider? = nil) throws -> UUID {
        guard InputRules.validVariable(variable), (replacing != nil && secret.isEmpty) || InputRules.validSecret(secret),
              !name.isEmpty, name.count <= 80 else { throw VaultError.invalidInput }
        guard customProvider == nil || provider == .custom else { throw VaultError.invalidInput }
        var record = KeyRecord(name: name, variable: variable, provider: provider,
                               customProviderID: customProvider?.id, customProviderName: customProvider?.name, revision: UUID())
        if let replacing {
            guard !checking.contains(replacing.id) else { throw VaultError.invalidInput }
            record = try replacing.applyingEdits(name: name, variable: variable, provider: provider,
                                                customProvider: customProvider, secretReplaced: !secret.isEmpty)
            if demo {
                guard secret.isEmpty, let index = records.firstIndex(where: { $0 == replacing }) else { throw VaultError.invalidInput }
                records[index] = record
                return record.id
            }
            try vault.update(record, secret: secret.isEmpty ? nil : secret, original: replacing)
        } else {
            guard !demo else { throw VaultError.invalidInput }
            try vault.add(record, secret: secret)
        }
        refresh()
        if check { Task { await self.check(record) } }
        return record.id
    }
    func check(_ record: KeyRecord) async {
        guard !demo, record.provider != .custom, checking.insert(record.id).inserted else { return }
        defer { checking.remove(record.id) }
        do {
            let secret = try vault.secret(for: record.variable)
            let result = await ProviderChecker.check(provider: record.provider, secret: secret)
            // A deleted or replaced item must not be resurrected by an in-flight check.
            guard let current = try vault.list().first(where: { $0.id == record.id }),
                  current.addedAt == record.addedAt, current.revision == record.revision,
                  current.provider == record.provider, current.variable == record.variable else { return }
            var updated = current
            updated.checkedAt = Date(); updated.status = result.status; updated.remainingLimit = result.remainingLimit
            try vault.update(updated)
            refresh()
        } catch { report(error) }
    }
    func delete(_ record: KeyRecord) {
        guard !demo else { return }
        do { try vault.delete(record.variable); refresh() }
        catch { report(error) }
    }
    func addCustomProvider(name: String) throws -> CustomProvider {
        guard !demo else { throw VaultError.invalidInput }
        let provider = try providerCatalog.add(name: name)
        customProviders = try providerCatalog.list()
        return provider
    }
    func removeCustomProvider(_ provider: CustomProvider) {
        guard !demo else { return }
        do {
            guard let currentProvider = try providerCatalog.list().first(where: { $0.id == provider.id }) else { refresh(); return }
            // Preserve the latest provider label when removing a renamed reusable entry.
            for record in try vault.list() where record.provider == .custom && record.customProviderID == provider.id {
                if record.customProviderName != currentProvider.name {
                    var updated = record
                    updated.customProviderName = currentProvider.name
                    updated.revision = UUID()
                    try vault.update(updated, original: record)
                }
            }
            try providerCatalog.remove(id: provider.id)
            refresh()
        } catch { report(error) }
    }
    func renameCustomProvider(_ provider: CustomProvider, name: String) throws {
        guard !demo else { throw VaultError.invalidInput }
        try providerCatalog.rename(id: provider.id, name: name)
        customProviders = try providerCatalog.list()
    }
    func providerName(for record: KeyRecord) -> String { record.displayProviderName(in: customProviders) }
    func report(_ error: Error) {
        self.error = (error as? VaultError)?.errorDescription ?? (error as? EnvironmentFileError)?.errorDescription ?? (error as? CustomProviderError)?.errorDescription ?? "KeyBar could not complete the request. Please try again."
    }
    var executable: String { Bundle.main.executableURL?.path ?? CommandLine.arguments[0] }
    func handoff(_ record: KeyRecord) -> String { InputRules.handoff(record, executable: executable, mode: handoffMode) }
    var shellProfile: URL {
        let directory = ProcessInfo.processInfo.environment["ZDOTDIR"].map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? FileManager.default.homeDirectoryForCurrentUser
        return directory.appendingPathComponent(".zshrc")
    }
    func loadDotenv(_ record: KeyRecord, to url: URL) throws {
        guard !demo else { throw VaultError.invalidInput }
        try EnvironmentFiles.writeDotenv(variable: record.variable, secret: vault.secret(for: record.variable), to: url, replace: true)
    }
    func enableShell(_ record: KeyRecord, at url: URL) throws {
        guard !demo, try vault.list().contains(where: { $0.id == record.id }) else { throw VaultError.missing }
        try EnvironmentFiles.enableShell(variable: record.variable, at: url)
    }
    func copyInstructions(_ record: KeyRecord) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(handoff(record), forType: .string)
    }
}
