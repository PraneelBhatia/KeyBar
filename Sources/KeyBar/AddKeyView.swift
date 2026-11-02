import SwiftUI
import KeyBarCore

struct AddKeyView: View {
    let store: KeyStore
    var replacing: KeyRecord?
    let saved: (UUID) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var variable = ""
    @State private var secret = ""
    @State private var provider: Provider = .custom
    @State private var check = true
    @State private var error: String?
    @State private var choseProvider = false
    @FocusState private var secretFocused: Bool

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && name.count <= 80 &&
        InputRules.validVariable(variable) && InputRules.validSecret(secret)
    }
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(replacing == nil ? "Add key" : "Replace key").font(.headline)
                Spacer()
                Image(systemName: "lock.shield").foregroundStyle(.secondary)
                    .help("Stored in local macOS Keychain. No sync.")
                    .accessibilityLabel("Stored in local macOS Keychain")
            }.padding(20)
            Form {
                SecureField("API key", text: $secret, prompt: Text("Paste key"))
                    .focused($secretFocused).privacySensitive()
                    .help("Paste a single API key. Its value stays in Keychain.")
                    .onChange(of: secret) {
                        guard !choseProvider, replacing == nil else { return }
                        let guess = Provider.detect(secret: secret, variable: variable)
                        if guess != .custom { applyProvider(guess) }
                    }
                TextField("Name", text: $name, prompt: Text("Personal"))
                Picker("Provider", selection: Binding(get: { provider }, set: {
                    choseProvider = true
                    applyProvider($0)
                })) {
                    ForEach(Provider.allCases) { Text($0.name).tag($0) }
                }
                TextField("Variable", text: $variable, prompt: Text("MY_API_KEY"))
                    .disabled(replacing != nil)
                    .help("Uppercase letters, numbers, and underscores. Process-control names such as PATH are reserved.")
                if !variable.isEmpty && !InputRules.validVariable(variable) {
                    Text("Use a name such as SERVICE_TOKEN.").font(.caption).foregroundStyle(.red)
                }
                if provider != .custom {
                    Toggle("Check on save", isOn: $check)
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
        .onAppear {
            if let replacing { name = replacing.name; variable = replacing.variable; provider = replacing.provider; choseProvider = true }
            secretFocused = true
        }
        .onDisappear { secret = "" }
    }
    private func applyProvider(_ value: Provider) {
        let previousDefaults = Provider.allCases.map(\.variable)
        if replacing == nil && (variable.isEmpty || previousDefaults.contains(variable)) { variable = value.variable }
        provider = value
        if name.isEmpty && value != .custom { name = value.name }
    }
    private func save() {
        do {
            let id = try store.save(name: name.trimmingCharacters(in: .whitespacesAndNewlines), variable: variable,
                                    provider: provider, secret: secret, replacing: replacing, check: check && provider != .custom)
            secret = ""; saved(id); dismiss()
        } catch { self.error = (error as? VaultError)?.errorDescription ?? "Could not save this key. Please try again." }
    }
}
