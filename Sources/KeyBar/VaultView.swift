import SwiftUI
import KeyBarCore

struct VaultView: View {
    @Bindable var store: KeyStore
    @State private var selection: UUID?
    @State private var search = ""
    @State private var showAdd = false
    @State private var replacing: KeyRecord?
    @State private var deleting: KeyRecord?
    @Environment(\.scenePhase) private var scenePhase

    private var filtered: [KeyRecord] {
        store.records.filter { search.isEmpty || "\($0.name) \($0.variable) \($0.provider.name)".localizedCaseInsensitiveContains(search) }
    }
    private var selected: KeyRecord? { store.records.first { $0.id == selection } }
    var body: some View {
        HStack(spacing: 0) {
            sidebar.frame(width: 270)
            Rectangle().fill(Palette.line).frame(width: 1)
            Group {
                if let selected {
                    KeyDetail(store: store, record: selected,
                              replace: { replacing = selected }, delete: { deleting = selected })
                } else { emptyState }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(minWidth: 760, minHeight: 540)
        .background(Palette.paper)
        .foregroundStyle(Palette.ink)
        .tint(Palette.accent)
        .preferredColorScheme(.light)
        .sheet(isPresented: $showAdd) {
            AddKeyView(store: store) { selection = $0 }
        }
        .sheet(item: $replacing) { record in
            AddKeyView(store: store, replacing: record) { selection = $0 }
        }
        .confirmationDialog("Remove this key from KeyBar?", isPresented: Binding(
            get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
            Button("Remove key", role: .destructive) {
                if let deleting { store.delete(deleting) }
                deleting = nil
            }
        } message: { Text("This deletes the local Keychain item. It does not revoke the key with its provider.") }
        .alert("KeyBar", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) {
            Button("OK") { store.error = nil }
        } message: { Text(store.error ?? "") }
        .onChange(of: scenePhase) { if scenePhase == .active { store.refresh() } }
        .onAppear { if selection == nil { selection = store.records.first?.id } }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 9) {
                Image(systemName: "key.horizontal.fill").font(.system(size: 22)).foregroundStyle(Palette.accent)
                Text("KeyBar").font(.system(size: 23, weight: .semibold, design: .rounded)).tracking(-0.8)
                Spacer()
                Text(store.demo ? "DEMO" : "LOCAL").font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(Palette.secondary).padding(5).overlay(RoundedRectangle(cornerRadius: 4).stroke(Palette.line))
            }
            .padding(.top, 45).padding(.bottom, 27)
            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass").foregroundStyle(Palette.secondary)
                TextField("Find a key", text: $search).textFieldStyle(.plain)
            }
            .font(.system(size: 12)).padding(10).background(.white.opacity(0.65), in: RoundedRectangle(cornerRadius: 8))
            HStack { SectionCaption(title: "Your keys"); Spacer(); Text("\(store.records.count)").font(.system(size: 11, design: .monospaced)).foregroundStyle(Palette.secondary) }
                .padding(.top, 26).padding(.bottom, 12)
            ScrollView {
                LazyVStack(spacing: 5) {
                    ForEach(filtered) { record in
                        Button { selection = record.id } label: {
                            HStack(spacing: 10) {
                                ProviderIcon(provider: record.provider, size: 32)
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(record.name).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                                    Text(record.provider.name).font(.system(size: 11)).foregroundStyle(Palette.secondary)
                                }
                                Spacer(minLength: 4)
                                Image(systemName: "line.3.horizontal").font(.system(size: 10)).foregroundStyle(Palette.secondary.opacity(0.6))
                            }
                            .padding(10).background(selection == record.id ? .white : .clear, in: RoundedRectangle(cornerRadius: 10))
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .draggable(store.handoff(record))
                        .help("Drag instructions to your agent. The key stays in Keychain.")
                    }
                    if filtered.isEmpty && !search.isEmpty { Text("No matching keys").font(.caption).foregroundStyle(Palette.secondary).padding() }
                }
            }
            Spacer(minLength: 16)
            Button { showAdd = true } label: { Label("Add a key", systemImage: "plus").frame(maxWidth: .infinity) }
                .buttonStyle(PrimaryButtonStyle()).disabled(store.demo).keyboardShortcut("n")
            Label("Stored on this Mac", systemImage: "lock.shield")
                .font(.system(size: 10)).foregroundStyle(Palette.secondary)
                .frame(maxWidth: .infinity).padding(.top, 15).padding(.bottom, 20)
        }
        .padding(.horizontal, 18).background(Palette.sidebar)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(store.records.isEmpty ? "No API keys" : "Select a key")
                .font(.system(size: 23, weight: .semibold))
            Text("Store API keys in Keychain, check access, and share usage instructions with agents.")
                .font(.system(size: 13)).foregroundStyle(Palette.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Add a key") { showAdd = true }.buttonStyle(PrimaryButtonStyle()).disabled(store.demo)
            HStack(spacing: 13) {
                ForEach([Provider.gemini, .openrouter, .anthropic, .openai]) { ProviderIcon(provider: $0, size: 28) }
                Text("+ any API key").font(.system(size: 10)).foregroundStyle(Palette.secondary)
            }.padding(.top, 8)
        }.frame(maxWidth: .infinity, alignment: .leading).padding(44)
    }
}

private struct KeyDetail: View {
    let store: KeyStore
    let record: KeyRecord
    let replace: () -> Void
    let delete: () -> Void
    @State private var copied = false
    private var busy: Bool { store.checking.contains(record.id) }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack {
                    SectionCaption(title: "Key details")
                    Spacer()
                    Menu {
                        Button("Replace key…", action: replace).disabled(busy || store.demo)
                        Button("Remove key…", role: .destructive, action: delete).disabled(store.demo)
                    } label: { Image(systemName: "ellipsis").frame(width: 25, height: 24) }
                    .menuStyle(.borderlessButton).fixedSize().help("Manage this key")
                }
                HStack(alignment: .top, spacing: 13) {
                    ProviderIcon(provider: record.provider, size: 50)
                    VStack(alignment: .leading, spacing: 5) {
                        Text(record.name).font(.system(size: 25, weight: .semibold)).lineLimit(2)
                        Text(record.provider.name).font(.system(size: 12)).foregroundStyle(Palette.secondary)
                    }
                    Spacer(minLength: 0)
                }
                VStack(alignment: .leading, spacing: 13) {
                    HStack {
                        StatusBadge(status: record.status, checking: busy)
                        Spacer()
                        if record.provider != .custom {
                            Button("Check again", systemImage: "arrow.clockwise") { Task { await store.check(record) } }
                                .font(.system(size: 11)).buttonStyle(.plain).foregroundStyle(Palette.secondary).disabled(busy || store.demo)
                        }
                    }
                    Text(record.status.explanation).font(.system(size: 12)).foregroundStyle(Palette.secondary).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
                    if let remaining = record.remainingLimit {
                        Text("Key limit remaining: \(remaining, format: .currency(code: "USD"))")
                            .font(.system(size: 11, weight: .medium)).foregroundStyle(Palette.ink)
                    }
                    Divider().overlay(Palette.line)
                    HStack {
                        Text("Added \(record.addedAt.formatted(date: .abbreviated, time: .omitted))")
                        Spacer()
                        if let checked = record.checkedAt { Text("Checked \(checked, style: .relative) ago") }
                    }.font(.system(size: 10)).foregroundStyle(Palette.secondary)
                }
                .padding(17).background(.white.opacity(0.7), in: RoundedRectangle(cornerRadius: 12))

                VStack(alignment: .leading, spacing: 10) {
                    SectionCaption(title: "Environment variable")
                    Text(record.variable).font(.system(size: 12, weight: .medium, design: .monospaced)).textSelection(.enabled)
                    Text("Secret stored in macOS Keychain")
                        .font(.system(size: 10)).foregroundStyle(Palette.secondary)
                }
                VStack(alignment: .leading, spacing: 13) {
                    HStack { Image(systemName: "arrow.up.right.square"); Text("Agent access").fontWeight(.semibold) }.font(.system(size: 13))
                    Text("Drag this card into a chat or AGENTS.md. It shares instructions to use this key, without sharing its value.")
                        .font(.system(size: 12)).foregroundStyle(Palette.secondary).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
                    HStack {
                        Label("Drag instructions", systemImage: "hand.draw").font(.system(size: 11, weight: .medium))
                        Spacer()
                        Button(copied ? "Copied" : "Copy instructions", systemImage: copied ? "checkmark" : "doc.on.doc") {
                            store.copyInstructions(record)
                            copied = true
                        }.font(.system(size: 11)).buttonStyle(.plain)
                    }.foregroundStyle(Palette.accent)
                }
                .padding(18).background(Palette.accent.opacity(0.04), in: RoundedRectangle(cornerRadius: 12))
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Palette.accent.opacity(0.16), style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
                .draggable(store.handoff(record))
                Text("Access is given to the command you run and its children. An agent with access can still reveal the key; use agents you trust.")
                    .font(.system(size: 10)).foregroundStyle(Palette.secondary).lineSpacing(3).fixedSize(horizontal: false, vertical: true)
            }.padding(.horizontal, 34).padding(.top, 44).padding(.bottom, 24)
        }
        .onChange(of: record.id) { copied = false }
    }
}
