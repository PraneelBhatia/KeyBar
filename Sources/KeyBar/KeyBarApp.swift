import SwiftUI
import AppKit
import KeyBarCore

@main
enum KeyBarMain {
    @MainActor static func main() {
        let arguments = Array(CommandLine.arguments.dropFirst())
        if arguments.isEmpty || arguments == ["--demo"] {
            KeyBarApp.main()
            return
        }
        if arguments == ["--help"] || arguments == ["-h"] {
            print("KeyBar stores API keys in macOS Keychain and supplies them to commands as environment variables.\n\n\(CommandError.usage.localizedDescription)\n\nOpen the app to add keys. Secrets are never printed. The env command writes a selected key to a local .env file.")
            return
        }
        do {
            if arguments.first == "env" || arguments.first == "shell" {
                try CommandRunner.writeFile(FileCommandArguments.parse(arguments))
                print(arguments.first == "env" ? "KeyBar: key saved to .env; secret not printed." : "KeyBar: Keychain reference added. Open a new interactive zsh session to load it.")
                return
            }
            try CommandRunner.run(ExecArguments.parse(arguments))
        }
        catch {
            let message = (error as? VaultError)?.errorDescription ?? (error as? CommandError)?.errorDescription ?? (error as? EnvironmentFileError)?.errorDescription ?? "The command failed."
            FileHandle.standardError.write(Data("KeyBar: \(message)\n".utf8))
            exit(1)
        }
    }
}

struct KeyBarApp: App {
    @State private var store = KeyStore(demo: CommandLine.arguments.contains("--demo"))
    @AppStorage("menuBarVisible") private var menuBarVisible = true
    var body: some Scene {
        Window("KeyBar", id: "vault") {
            VaultView(store: store)
        }
        .defaultSize(width: 700, height: 460)
        .windowResizability(.contentMinSize)
        .windowToolbarStyle(.unified)
        .commands {
            CommandGroup(replacing: .newItem) { }
            CommandGroup(after: .sidebar) {
                Toggle("Show KeyBar in Menu Bar", isOn: $menuBarVisible)
            }
        }
        MenuBarExtra(isInserted: $menuBarVisible) {
            MenuPanel(store: store)
        } label: {
            Label("KeyBar", systemImage: "key.horizontal")
                .labelStyle(.titleAndIcon)
                .help("Open KeyBar")
        }
        .menuBarExtraStyle(.window)
    }
}
