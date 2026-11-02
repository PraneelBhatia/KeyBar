import SwiftUI
import KeyBarCore

struct VaultView: View {
    @Bindable var store: KeyStore
    @State private var selection: UUID?
    @State private var search = ""
    @State private var showAdd = false
    @State private var showProviders = false
    @State private var editing: KeyRecord?
    @State private var deleting: KeyRecord?
    @Environment(\.scenePhase) private var scenePhase

    private var filtered: [KeyRecord] {
        store.records.filter { search.isEmpty || "\($0.name) \($0.variable) \(store.providerName(for: $0))".localizedCaseInsensitiveContains(search) }
    }
    private var selected: KeyRecord? { store.records.first { $0.id == selection } }

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                Section("Keys") {
                    ForEach(filtered) { record in
                        HStack(spacing: 10) {
                            ProviderIcon(provider: record.provider)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(record.name).lineLimit(1)
                                Text(store.providerName(for: record)).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        .tag(record.id)
                        .draggable(store.handoff(record))
                        .help("Drag to an agent to share usage instructions, without the secret.")
                    }
                }
            }
            .listStyle(.sidebar)
            .searchable(text: $search, prompt: "Find a key")
            .navigationTitle(store.demo ? "KeyBar (Demo)" : "KeyBar")
            .navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 280)
            .overlay {
                if filtered.isEmpty && !search.isEmpty {
                    Text("No matching keys").foregroundStyle(.secondary)
                }
            }
        } detail: {
            if let selected {
                KeyDetail(store: store, record: selected)
            } else {
                ContentUnavailableView {
                    Label(store.records.isEmpty ? "No API keys" : "Select a key", systemImage: "key.horizontal")
                } actions: {
                    if store.records.isEmpty {
                        Button("Add a key") { showAdd = true }
                            .keybarPrimaryButton().disabled(store.demo)
                    }
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Add key", systemImage: "plus") { showAdd = true }
                    .keyboardShortcut("n").disabled(store.demo)
                    .help("Add an API key (⌘N)")
            }
            ToolbarItem(placement: .primaryAction) {
                Button("Edit key", systemImage: "pencil") { editing = selected }
                    .disabled(selected == nil || selected.map { store.checking.contains($0.id) } == true)
                    .help("Edit name, provider, variable, or API key")
            }
            ToolbarItem(placement: .primaryAction) {
                Menu("Manage key", systemImage: "ellipsis") {
                    Button("Edit key…") { editing = selected }
                        .disabled(selected == nil || selected.map { store.checking.contains($0.id) } == true)
                    Button("Remove key…", role: .destructive) { deleting = selected }
                        .disabled(selected == nil || store.demo)
                    Divider()
                    Button("Custom providers…") { showProviders = true }
                }
                .help("Manage keys and custom providers")
            }
        }
        .frame(minWidth: 620, minHeight: 420)
        .sheet(isPresented: $showProviders) { CustomProvidersView(store: store) }
        .sheet(isPresented: $showAdd) {
            AddKeyView(store: store) { selection = $0 }
        }
        .sheet(item: $editing) { record in
            AddKeyView(store: store, editing: record) { selection = $0 }
        }
        .confirmationDialog("Remove this key?", isPresented: Binding(
            get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
            Button("Remove key", role: .destructive) {
                if let deleting { store.delete(deleting) }
                deleting = nil
            }
        } message: { Text("Deletes the Keychain item. Exported .env files and running shells keep their values.") }
        .alert("KeyBar", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {
            Button("OK") { store.error = nil }
        } message: { Text(store.error ?? "") }
        .onChange(of: scenePhase) { if scenePhase == .active { store.refresh() } }
        .onChange(of: store.records.map(\.id), initial: true) {
            if !store.records.contains(where: { $0.id == selection }) { selection = store.records.first?.id }
        }
    }
}

private struct KeyDetail: View {
    let store: KeyStore
    let record: KeyRecord
    private var busy: Bool { store.checking.contains(record.id) }

    var body: some View {
        Form {
            Section {
                HStack(spacing: 12) {
                    ProviderIcon(provider: record.provider, size: 40)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(record.name).font(.title2.weight(.semibold)).textSelection(.enabled)
                        Text(store.providerName(for: record)).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 0)
                }
                LabeledContent("Status") {
                    HStack(spacing: 12) {
                        StatusBadge(status: record.status, checking: busy)
                        if record.provider != .custom {
                            Button("Check", systemImage: "arrow.clockwise") { Task { await store.check(record) } }
                                .labelStyle(.iconOnly).buttonStyle(.borderless)
                                .disabled(busy || store.demo)
                                .help("Check access at \(record.provider.endpoint?.host ?? record.providerName)")
                        }
                    }
                }
                if let remaining = record.remainingLimit {
                    LabeledContent("Limit left") { Text(remaining, format: .currency(code: "USD")) }
                        .help("Remaining spending limit for this OpenRouter key, not the account balance.")
                }
                LabeledContent("Variable") {
                    Text(record.variable).font(.system(.body, design: .monospaced))
                        .textSelection(.enabled).lineLimit(2)
                }
                .help("Stored in macOS Keychain. The command in the agent instructions receives this variable.")
                LabeledContent("Added") { Text(record.addedAt, format: .dateTime.day().month().year()) }
                    .help("When this key was saved in KeyBar, not when the provider created it.")
                if let checked = record.checkedAt {
                    LabeledContent("Checked") { Text(checked, style: .relative) }
                        .help(checked.formatted(date: .abbreviated, time: .shortened))
                }
            }
            AgentAccessView(store: store, record: record)
        }
        .formStyle(.grouped)
    }
}
