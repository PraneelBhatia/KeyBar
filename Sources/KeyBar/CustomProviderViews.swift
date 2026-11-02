import SwiftUI
import KeyBarCore

struct CustomProviderRows: View {
    let store: KeyStore
    @State private var editingID: UUID?
    @State private var editedName = ""
    @State private var error: String?
    @FocusState private var renameFocused: Bool

    var body: some View {
        if store.customProviders.isEmpty {
            Text("No custom providers").foregroundStyle(.secondary)
        } else {
            ForEach(store.customProviders) { provider in
                HStack {
                    if editingID == provider.id {
                        TextField("Provider name", text: $editedName).labelsHidden().focused($renameFocused)
                            .onAppear { renameFocused = true }.onSubmit { rename(provider) }
                        Button("Save", systemImage: "checkmark") { rename(provider) }
                            .labelStyle(.iconOnly).buttonStyle(.borderless)
                            .disabled((try? CustomProviderCatalog.normalizedName(editedName)) == nil)
                            .help("Save provider name")
                        Button("Cancel", systemImage: "xmark") { editingID = nil; error = nil }
                            .labelStyle(.iconOnly).buttonStyle(.borderless)
                            .help("Cancel rename")
                    } else {
                        Text(provider.name)
                        Spacer()
                        Button("Edit provider", systemImage: "pencil") {
                            editedName = provider.name; editingID = provider.id; error = nil
                        }
                        .labelStyle(.iconOnly).buttonStyle(.borderless).disabled(store.demo)
                        .accessibilityLabel("Edit \(provider.name)")
                        .help("Edit provider name")
                        Button(role: .destructive) { store.removeCustomProvider(provider) } label: {
                            Image(systemName: "trash")
                        }
                        .buttonStyle(.borderless).disabled(store.demo)
                        .accessibilityLabel("Delete \(provider.name)")
                        .help("Remove from the provider list. Saved keys are kept.")
                    }
                }
            }
        }
        if let error { Text(error).font(.callout).foregroundStyle(.red) }
    }

    private func rename(_ provider: CustomProvider) {
        do {
            try store.renameCustomProvider(provider, name: editedName)
            editingID = nil; error = nil
        } catch {
            self.error = (error as? CustomProviderError)?.errorDescription ?? "Could not rename this provider."
        }
    }
}

struct CustomProvidersView: View {
    let store: KeyStore
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Custom providers").font(.headline)
                Spacer()
            }.padding(20)
            List { CustomProviderRows(store: store) }
            HStack {
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }.padding(20)
        }
        .frame(width: 360, height: 300)
    }
}
