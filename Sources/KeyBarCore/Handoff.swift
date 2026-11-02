import Foundation

public enum HandoffMode: String, CaseIterable, Identifiable, Sendable {
    case choose, keychain, dotenv, shell
    public var id: Self { self }
    public var label: String {
        switch self {
        case .choose: "Agent chooses"
        case .keychain: "Keychain"
        case .dotenv: ".env"
        case .shell: ".zshrc"
        }
    }
}

extension InputRules {
    public static func handoff(_ record: KeyRecord, executable: String, mode: HandoffMode = .keychain) -> String {
        let tool = shellQuote(executable)
        let direct = "Keychain: \(tool) exec --key \(record.variable) -- <command> [arguments]"
        let dotenv = ".env: in the project directory run \(tool) env --key \(record.variable) --file .env. This writes a plaintext key, adds .env to .gitignore, and refuses tracked files. Existing values require --replace. Load it with your app’s dotenv loader."
        let shell = ".zshrc: if \(record.variable) is already configured, use /bin/zsh -ic 'exec <command> [arguments]'. Otherwise enable it with \(tool) shell --key \(record.variable) --file \"${ZDOTDIR:-$HOME}/.zshrc\". Setup adds a Keychain reference, not a secret; new interactive zsh sessions receive the key."
        let instructions: String
        switch mode {
        case .choose: instructions = "Choose one method:\n\(direct)\n\(dotenv)\n\(shell)"
        case .keychain: instructions = direct
        case .dotenv: instructions = dotenv
        case .shell: instructions = shell
        }
        return """
        Use \(record.variable) from KeyBar.
        \(instructions)
        Do not print, echo, log, or commit the secret. Only the .env option writes its value to a file. Processes given access can read it; existing sessions do not gain it automatically.
        """
    }
}
