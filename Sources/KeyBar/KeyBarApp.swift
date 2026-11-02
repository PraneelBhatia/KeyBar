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
            print("KeyBar stores API keys in macOS Keychain and supplies them to commands as environment variables.\n\n\(CommandError.usage.localizedDescription)\n\nOpen the app to add keys. This tool never prints stored secrets.")
            return
        }
        do { try CommandRunner.run(ExecArguments.parse(arguments)) }
        catch {
            let message = (error as? VaultError)?.errorDescription ?? (error as? CommandError)?.errorDescription ?? "The command failed."
            FileHandle.standardError.write(Data("KeyBar: \(message)\n".utf8))
            exit(1)
        }
    }
}

struct KeyBarApp: App {
    @State private var store = KeyStore(demo: CommandLine.arguments.contains("--demo"))
    var body: some Scene {
        Window("KeyBar", id: "vault") {
            VaultView(store: store)
        }
        .defaultSize(width: 800, height: 570)
        .windowResizability(.contentMinSize)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) { }
        }
        MenuBarExtra("KeyBar", systemImage: "key.horizontal") {
            MenuPanel(store: store)
        }
        .menuBarExtraStyle(.window)
    }
}
