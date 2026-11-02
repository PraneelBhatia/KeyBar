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
        VStack(alignment: .leading, spacing: 19) {
            Text(replacing == nil ? "Add a key" : "Replace key")
                .font(.system(size: 23, weight: .semibold))
            Text("Stored in macOS Keychain under the variable name below.")
                .font(.system(size: 12)).foregroundStyle(Palette.secondary)
            VStack(alignment: .leading, spacing: 8) {
                SectionCaption(title: "API key")
                SecureField("Paste your key", text: $secret)
                    .textFieldStyle(.roundedBorder).focused($secretFocused).privacySensitive()
                    .onChange(of: secret) {
                        guard !choseProvider, replacing == nil else { return }
                        let guess = Provider.detect(secret: secret.trimmingCharacters(in: .whitespacesAndNewlines), variable: variable)
                        if guess != .custom { applyProvider(guess) }
                    }
            }
            HStack(alignment: .top, spacing: 16) {
                VStack(alignment: .leading, spacing: 8) {
                    SectionCaption(title: "Name")
                    TextField("e.g. Personal", text: $name).textFieldStyle(.roundedBorder)
                }
                VStack(alignment: .leading, spacing: 8) {
                    SectionCaption(title: "Provider")
                    Picker("Provider", selection: $provider) {
                        ForEach(Provider.allCases) { Text($0.name).tag($0) }
                    }.labelsHidden().onChange(of: provider) { choseProvider = true; applyProvider(provider) }
                }.frame(width: 165)
            }
            VStack(alignment: .leading, spacing: 8) {
                SectionCaption(title: "Environment variable")
                TextField("MY_API_KEY", text: $variable)
                    .font(.system(size: 12, design: .monospaced)).textFieldStyle(.roundedBorder)
                    .disabled(replacing != nil)
                Text("Use uppercase letters, numbers, and underscores.")
                    .font(.system(size: 10)).foregroundStyle(Palette.secondary)
                if !variable.isEmpty && !InputRules.validVariable(variable) {
                    Text("Choose a valid, non-reserved variable name, such as SERVICE_TOKEN.")
                        .font(.system(size: 10)).foregroundStyle(Palette.accent)
                }
            }
            if provider != .custom {
                VStack(alignment: .leading, spacing: 7) {
                    Toggle("Check this key when saving", isOn: $check).font(.system(size: 12))
                    Text("Sends the key to \(provider.endpoint?.host ?? provider.name) to check access. No generation request is made.")
                        .font(.system(size: 10)).foregroundStyle(Palette.secondary).fixedSize(horizontal: false, vertical: true)
                }.padding(13).background(.white.opacity(0.7), in: RoundedRectangle(cornerRadius: 9))
            } else {
                Text("This service has no checker yet. Your key can still be stored and used by agents.")
                    .font(.system(size: 11)).foregroundStyle(Palette.secondary)
            }
            if let error { Text(error).font(.system(size: 11)).foregroundStyle(Palette.accent).fixedSize(horizontal: false, vertical: true) }
            HStack {
                Button("Cancel") { secret = ""; dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button(check && provider != .custom ? "Save & check" : "Save key", action: save)
                    .buttonStyle(PrimaryButtonStyle()).disabled(!canSave).keyboardShortcut(.defaultAction)
            }.padding(.top, 5)
        }
        .padding(30).frame(width: 455).background(Palette.paper).foregroundStyle(Palette.ink)
        .tint(Palette.accent).preferredColorScheme(.light)
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
