import SwiftUI
import AppKit
import KeyBarCore

struct AgentAccessView: View {
    @Bindable var store: KeyStore
    let record: KeyRecord
    @State private var copied = false
    @State private var pending: LoadDestination?
    @State private var completed: String?

    private enum LoadDestination: Identifiable {
        case dotenv(URL), shell(URL)
        var id: String {
            switch self { case .dotenv(let url): "env:\(url.path)"; case .shell(let url): "shell:\(url.path)" }
        }
        var title: String {
            switch self { case .dotenv: "Load key into .env?"; case .shell: "Enable key in .zshrc?" }
        }
        var message: String {
            switch self {
            case .dotenv(let url):
                "\(url.path)\n\nStores the key as plain text. Replaces this variable if present, preserves other entries, and adds the file to .gitignore."
            case .shell(let url):
                "\(url.path)\n\nAdds a Keychain reference. Every new interactive zsh session and its children will have access to this key."
            }
        }
    }

    var body: some View {
        Section {
            Picker("Agent access", selection: $store.handoffMode) {
                ForEach(HandoffMode.allCases) { Text($0.label).tag($0) }
            }
            .help("Choose which instructions to share. Agent chooses includes all three methods; no secret is copied.")
            NativeActionGroup {
                HStack(spacing: 12) {
                    Label("Drag to agent", systemImage: "hand.draw")
                        .padding(.horizontal, 14).padding(.vertical, 9)
                        .keybarDragSurface()
                        .draggable(store.handoff(record))
                        .help("Drag usage instructions into a chat or AGENTS.md. Processes given access can read the key.")
                        .accessibilityHint("Drag usage instructions to an agent. No secret is included.")
                    Button(copied ? "Copied" : "Copy instructions", systemImage: copied ? "checkmark" : "doc.on.doc") {
                        store.copyInstructions(record)
                        copied = true
                    }
                    .keybarPrimaryButton()
                    .help("Copy the selected instructions, without the secret.")
                }
                .controlSize(.regular)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            HStack {
                Menu("Load key…", systemImage: "square.and.arrow.down") {
                    Button("Load into .env…", systemImage: "doc.badge.plus", action: chooseProject)
                    Button("Enable in .zshrc…", systemImage: "terminal") { pending = .shell(store.shellProfile) }
                }
                .menuStyle(.borderlessButton).fixedSize()
                .disabled(store.demo)
                .help("Write this key to a project’s .env, or enable it for new zsh sessions.")
                Spacer()
                if let completed { Label(completed, systemImage: "checkmark").font(.caption).foregroundStyle(.secondary) }
            }
        }
        .confirmationDialog(pending?.title ?? "Load key?", isPresented: Binding(
            get: { pending != nil }, set: { if !$0 { pending = nil } }), titleVisibility: .visible) {
            if let destination = pending {
                Button("Load \(record.variable)") { load(destination) }
            }
            Button("Cancel", role: .cancel) { pending = nil }
        } message: { Text(pending?.message ?? "") }
        .onChange(of: record.id) { copied = false; completed = nil; pending = nil }
        .onChange(of: store.handoffMode) { copied = false }
    }

    private func chooseProject() {
        let panel = NSOpenPanel()
        panel.title = "Choose project for .env"
        panel.message = "KeyBar will add the selected key to this folder’s .env."
        panel.prompt = "Choose project"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let directory = panel.url {
            pending = .dotenv(directory.appendingPathComponent(".env"))
        }
    }

    private func load(_ destination: LoadDestination) {
        pending = nil
        do {
            switch destination {
            case .dotenv(let url): try store.loadDotenv(record, to: url); completed = "Saved to .env"
            case .shell(let url): try store.enableShell(record, at: url); completed = "Enabled for new shells"
            }
        } catch { store.report(error) }
    }
}
