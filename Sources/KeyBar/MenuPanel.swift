import SwiftUI
import AppKit
import KeyBarCore

struct MenuPanel: View {
    @Bindable var store: KeyStore
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label(store.demo ? "KeyBar (Demo)" : "KeyBar", systemImage: "key.horizontal")
                    .font(.headline)
                Spacer()
                Text("\(store.records.count)").foregroundStyle(.secondary)
                    .accessibilityLabel("\(store.records.count) keys")
            }
            Picker("Agent access", selection: $store.handoffMode) {
                ForEach(HandoffMode.allCases) { Text($0.label).tag($0) }
            }
            .help("The copied or dragged note contains the selected access instructions, never a secret.")
            if store.records.isEmpty {
                Text("No API keys").foregroundStyle(.secondary).padding(.vertical)
            } else {
                ScrollView {
                    VStack(spacing: 4) {
                        ForEach(store.records) { record in
                            HStack(spacing: 10) {
                                ProviderIcon(provider: record.provider, size: 28)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(record.name).lineLimit(1)
                                    Text(record.variable).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                }
                                Spacer(minLength: 4)
                                StatusBadge(status: record.status, checking: store.checking.contains(record.id))
                                Button("Copy instructions", systemImage: "doc.on.doc") { store.copyInstructions(record) }
                                    .labelStyle(.iconOnly).buttonStyle(.borderless)
                                    .help("Copy usage instructions for \(record.name), without the secret.")
                            }
                            .padding(.vertical, 8).padding(.horizontal, 4)
                            .contentShape(Rectangle())
                            .draggable(store.handoff(record))
                            .help("Drag to an agent to share usage instructions. The receiving command can read the key.")
                        }
                    }
                }.frame(height: min(CGFloat(store.records.count) * 60, 300))
            }
            Divider()
            HStack {
                Button("Open KeyBar", systemImage: "arrow.up.right") {
                    openWindow(id: "vault")
                    NSApplication.shared.activate(ignoringOtherApps: true)
                }.keybarGlassButton()
                Spacer()
                Button("Quit") { NSApplication.shared.terminate(nil) }.buttonStyle(.borderless)
            }
        }
        .padding(16).frame(width: 380)
        .onAppear { store.refresh() }
    }
}
