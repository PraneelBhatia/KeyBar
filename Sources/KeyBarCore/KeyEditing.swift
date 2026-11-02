import Foundation

extension KeyRecord {
    /// Metadata edits preserve the credential's identity and age. New credentials reset their check state.
    public func applyingEdits(name: String, variable: String, provider: Provider,
                              customProvider: CustomProvider? = nil, secretReplaced: Bool = false,
                              date: Date = Date()) throws -> KeyRecord {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name.count <= 80,
              !name.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }),
              InputRules.validVariable(variable), customProvider == nil || provider == .custom else {
            throw VaultError.invalidInput
        }
        if let customProvider { _ = try CustomProviderCatalog.normalizedName(customProvider.name) }
        var updated = self
        updated.name = name
        updated.variable = variable
        updated.provider = provider
        updated.customProviderID = customProvider?.id
        updated.customProviderName = customProvider?.name
        updated.revision = UUID()
        if secretReplaced { updated.addedAt = date }
        if secretReplaced || self.provider != provider {
            updated.status = .unchecked
            updated.checkedAt = nil
            updated.remainingLimit = nil
        }
        return updated
    }

    public func displayProviderName(in providers: [CustomProvider]) -> String {
        guard provider == .custom, let id = customProviderID else { return providerName }
        return providers.first(where: { $0.id == id })?.name ?? providerName
    }
}
