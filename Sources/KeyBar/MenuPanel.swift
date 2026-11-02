import SwiftUI
import AppKit
import KeyBarCore

struct MenuPanel: View {
    let store: KeyStore
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "key.horizontal.fill").foregroundStyle(Palette.accent)
                Text("KeyBar").font(.system(size: 18, weight: .semibold, design: .rounded))
                Spacer()
                Text("\(store.records.count) keys").font(.system(size: 11)).foregroundStyle(Palette.secondary)
            }
            if store.records.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("No API keys").font(.system(size: 16, weight: .semibold))
                    Text("Open KeyBar to add a key.").font(.system(size: 12)).foregroundStyle(Palette.secondary)
                }.padding(.vertical, 20)
            } else {
                Text("Drag a key to share instructions with an agent.")
                    .font(.system(size: 11)).foregroundStyle(Palette.secondary)
                ScrollView {
                    VStack(spacing: 7) {
                        ForEach(store.records) { record in
                            HStack(spacing: 10) {
                                ProviderIcon(provider: record.provider, size: 30)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(record.name).font(.system(size: 12, weight: .semibold))
                                    Text(record.variable).font(.system(size: 9, design: .monospaced)).foregroundStyle(Palette.secondary).lineLimit(1)
                                }
                                Spacer(minLength: 3)
                                Button { store.copyInstructions(record) } label: { Image(systemName: "doc.on.doc") }
                                    .buttonStyle(.plain).help("Copy instructions for \(record.name)")
                                    .accessibilityLabel("Copy instructions for \(record.name)")
                                StatusBadge(status: record.status, checking: store.checking.contains(record.id))
                            }
                            .padding(9).background(.white.opacity(0.7), in: RoundedRectangle(cornerRadius: 8))
                            .draggable(store.handoff(record))
                        }
                    }
                }.frame(maxHeight: 290)
            }
            Divider()
            HStack {
                Button("Open KeyBar", systemImage: "arrow.up.right") {
                    openWindow(id: "vault")
                    NSApplication.shared.activate(ignoringOtherApps: true)
                }.buttonStyle(.plain).font(.system(size: 12, weight: .medium))
                Spacer()
                Button("Quit") { NSApplication.shared.terminate(nil) }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(Palette.secondary)
            }
        }
        .padding(20).frame(width: 390).background(Palette.paper).foregroundStyle(Palette.ink)
        .preferredColorScheme(.light)
        .onAppear { store.refresh() }
    }
}
