import SwiftUI
import KeyBarCore

struct CustomProviderRows: View {
    let store: KeyStore
    var body: some View {
        if store.customProviders.isEmpty {
            Text("No custom providers").foregroundStyle(.secondary)
        } else {
            ForEach(store.customProviders) { provider in
                HStack {
                    Text(provider.name)
                    Spacer()
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
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }.padding(20)
        }
        .frame(width: 360, height: 300)
    }
}
