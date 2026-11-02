import AppKit
import Observation
import KeyBarCore

@MainActor @Observable
final class KeyStore {
    var records: [KeyRecord] = []
    var checking: Set<UUID> = []
    var error: String?
    var handoffMode: HandoffMode = .choose
    let demo: Bool
    private let vault = KeychainVault()

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
        do { records = try vault.list() }
        catch { report(error) }
    }
    func save(name: String, variable: String, provider: Provider, secret: String,
              replacing: KeyRecord?, check: Bool) throws -> UUID {
        guard !demo else { throw VaultError.invalidInput }
        guard InputRules.validVariable(variable), InputRules.validSecret(secret),
              !name.isEmpty, name.count <= 80 else { throw VaultError.invalidInput }
        var record = KeyRecord(name: name, variable: variable, provider: provider)
        if let replacing {
            guard !checking.contains(replacing.id) else { throw VaultError.invalidInput }
            // Keep identity and variable on replacement; the added date becomes the rotation date.
            record.id = replacing.id
            record.variable = replacing.variable
            try vault.update(record, secret: secret)
        } else { try vault.add(record, secret: secret) }
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
                  current.addedAt == record.addedAt else { return }
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
    func report(_ error: Error) {
        self.error = (error as? VaultError)?.errorDescription ?? (error as? EnvironmentFileError)?.errorDescription ?? "KeyBar could not complete the request. Please try again."
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
