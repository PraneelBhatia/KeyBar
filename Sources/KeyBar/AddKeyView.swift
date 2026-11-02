import SwiftUI
import KeyBarCore

struct AddKeyView: View {
    let store: KeyStore
    var editing: KeyRecord?
    let saved: (UUID) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var variable = ""
    @State private var secret = ""
    @State private var selection: ProviderSelection = .unspecified
    @State private var check = true
    @State private var error: String?
    @State private var choseProvider = false
    @State private var showCustomProvider = false
    @State private var showProviders = false
    @State private var customName = ""
    @FocusState private var customNameFocused: Bool
    @FocusState private var secretFocused: Bool
    @FocusState private var nameFocused: Bool

    private enum ProviderSelection: Hashable {
        case unspecified, builtin(Provider), named(UUID)
    }
    private var provider: Provider {
        if case .builtin(let value) = selection { return value }
        return .custom
    }
    private var customProvider: CustomProvider? {
        guard case .named(let id) = selection else { return nil }
        if let provider = store.customProviders.first(where: { $0.id == id }) { return provider }
        if let editing, editing.customProviderID == id, let name = editing.customProviderName {
            return CustomProvider(id: id, name: name)
        }
        return nil
    }
    private var canSave: Bool {
        !showCustomProvider && !showProviders && selection != .unspecified &&
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && name.count <= 80 &&
        InputRules.validVariable(variable) && ((editing != nil && secret.isEmpty) || InputRules.validSecret(secret))
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(editing == nil ? "Add key" : "Edit key").font(.headline)
                Spacer()
                Image(systemName: "lock.shield").foregroundStyle(.secondary)
                    .help("Stored in local macOS Keychain. No sync.")
                    .accessibilityLabel("Stored in local macOS Keychain")
            }.padding(20)
            Form {
                SecureField("API key", text: $secret, prompt: Text(editing == nil ? "Paste key" : "Leave unchanged"))
                    .focused($secretFocused).privacySensitive()
                    .disabled(store.demo)
                    .help(editing == nil ? "Paste a single API key. Its value stays in Keychain." : "Leave blank to keep the stored key, or paste a new key to replace it.")
                    .onChange(of: secret) {
                        guard !choseProvider, editing == nil else { return }
                        let guess = Provider.detect(secret: secret, variable: variable)
                        if guess != .custom { applyProvider(.builtin(guess)) }
                    }
                TextField("Name", text: $name, prompt: Text("Personal")).focused($nameFocused)
                providerPicker
                if showCustomProvider { customProviderEditor }
                if showProviders {
                    Section {
                        CustomProviderRows(store: store)
                        HStack {
                            Spacer()
                            Button("Done") { showProviders = false }
                        }
                    } header: { Text("Custom providers") }
                }
                TextField("Variable", text: $variable, prompt: Text("MY_API_KEY"))
                    .help("Uppercase letters, numbers, and underscores. Process-control names such as PATH are reserved.")
                if let editing, variable != editing.variable {
                    Text("Copy new instructions and reload exports after renaming.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if !variable.isEmpty && !InputRules.validVariable(variable) {
                    Text("Use a name such as SERVICE_TOKEN.").font(.caption).foregroundStyle(.red)
                }
                if provider != .custom {
                    Toggle("Check on save", isOn: $check).disabled(store.demo)
                        .help("Sends this key to \(provider.endpoint?.host ?? provider.name) to check access. No generation request.")
                    if check {
                        Text(provider.endpoint?.host ?? provider.name)
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
            .formStyle(.grouped)
            if let error { Text(error).font(.callout).foregroundStyle(.red).padding(.horizontal, 20) }
            HStack {
                Button("Cancel") { secret = ""; dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button(check && provider != .custom ? "Save & check" : "Save", action: save)
                    .keybarPrimaryButton().disabled(!canSave).keyboardShortcut(.defaultAction)
            }.padding(20)
        }
        .frame(width: 420)
        // Draft fields are seeded from metadata; the stored secret is never loaded into the editor.
        .onAppear {
            if let editing {
                name = editing.name; variable = editing.variable
                if editing.provider == .custom, let id = editing.customProviderID, editing.customProviderName != nil {
                    selection = .named(id)
                } else { selection = .builtin(editing.provider) }
                choseProvider = true; check = false; nameFocused = true
            } else { secretFocused = true }
        }
        .onChange(of: store.customProviders.map(\.id)) {
            if case .named(let id) = selection,
               !store.customProviders.contains(where: { $0.id == id }), editing?.customProviderID != id {
                selection = .unspecified
            }
        }
        .onDisappear { secret = "" }
    }

    private var providerLabel: String {
        switch selection {
        case .unspecified: "Select provider"
        case .builtin(let value): value.name
        case .named: customProvider?.name ?? "Select provider"
        }
    }

    private var providerPicker: some View {
        LabeledContent("Provider") {
            Menu {
                ForEach(Provider.allCases.filter { $0 != .custom }) { provider in
                    Button(provider.name) { chooseProvider(.builtin(provider)) }
                }
                if editing?.provider == .custom, editing?.customProviderID == nil {
                    Button("Custom") { chooseProvider(.builtin(.custom)) }
                }
                ForEach(store.customProviders) { provider in
                    Button(provider.name) { chooseProvider(.named(provider.id)) }
                }
                if let editing, let id = editing.customProviderID, let name = editing.customProviderName,
                   !store.customProviders.contains(where: { $0.id == id }) {
                    Button("\(name) (removed)") { chooseProvider(.named(id)) }
                }
                Divider()
                Button("Custom…") {
                    error = nil; customName = ""; showProviders = false; showCustomProvider = true
                }
                Button("Manage custom providers…") {
                    error = nil; showCustomProvider = false; showProviders = true
                }
            } label: { Text(providerLabel) }
            .menuStyle(.borderlessButton).fixedSize()
            .accessibilityLabel("Provider")
            .help("Custom adds a reusable provider name. Custom keys are stored without sending a check request.")
        }
    }

    private var customProviderEditor: some View {
        HStack {
            TextField("Provider name", text: $customName, prompt: Text("e.g. Cloudflare"))
                .focused($customNameFocused).onSubmit(addCustomProvider)
                .help("A name for the provider list. Custom providers have no automatic key check.")
            Button("Add", action: addCustomProvider)
                .disabled((try? CustomProviderCatalog.normalizedName(customName)) == nil || store.demo)
            Button("Cancel", systemImage: "xmark") { showCustomProvider = false; error = nil }
                .labelStyle(.iconOnly).buttonStyle(.borderless)
                .help("Cancel adding a provider")
        }
        .onAppear { customNameFocused = true }
    }

    private func chooseProvider(_ value: ProviderSelection) {
        choseProvider = true; showCustomProvider = false; showProviders = false; error = nil
        applyProvider(value)
    }

    private func addCustomProvider() {
        do {
            let provider = try store.addCustomProvider(name: customName)
            chooseProvider(.named(provider.id))
            if secret.isEmpty { secretFocused = true }
        } catch {
            self.error = (error as? CustomProviderError)?.errorDescription ?? "Could not add this provider."
        }
    }

    private func applyProvider(_ value: ProviderSelection) {
        let previousName = customProvider?.name ?? (provider == .custom ? "" : provider.name)
        let previousVariable = customProvider?.variable
        let defaults = Provider.allCases.map(\.variable) + store.customProviders.map(\.variable) + [previousVariable].compactMap { $0 }
        selection = value
        let suggestedName = customProvider?.name ?? (provider == .custom ? "" : provider.name)
        let suggestedVariable = customProvider?.variable ?? provider.variable
        if editing == nil && (variable.isEmpty || defaults.contains(variable)) { variable = suggestedVariable }
        if name.isEmpty || name == previousName { name = suggestedName }
    }

    private func save() {
        do {
            let id = try store.save(name: name.trimmingCharacters(in: .whitespacesAndNewlines), variable: variable,
                                    provider: provider, secret: secret, replacing: editing, check: check && provider != .custom,
                                    customProvider: customProvider)
            secret = ""; saved(id); dismiss()
        } catch { self.error = (error as? VaultError)?.errorDescription ?? "Could not save this key. Please try again." }
    }
}
