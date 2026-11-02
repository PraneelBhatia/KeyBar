import Foundation
import Darwin

public struct ExecArguments: Equatable, Sendable {
    public let variables: [String]
    public let command: [String]
    public static func parse(_ arguments: [String]) throws -> Self {
        guard arguments.first == "exec", let split = arguments.firstIndex(of: "--"), split > 1 else { throw CommandError.usage }
        let options = Array(arguments[1..<split])
        guard options.count.isMultiple(of: 2) else { throw CommandError.usage }
        var variables: [String] = []
        for i in stride(from: 0, to: options.count, by: 2) {
            guard options[i] == "--key", InputRules.validVariable(options[i + 1]) else { throw CommandError.usage }
            variables.append(options[i + 1])
        }
        let command = Array(arguments.dropFirst(split + 1))
        guard !variables.isEmpty, let executable = command.first, !executable.isEmpty else { throw CommandError.usage }
        return Self(variables: Array(Set(variables)).sorted(), command: command)
    }
}

public enum CommandError: LocalizedError {
    case usage, launch
    public var errorDescription: String? {
        switch self {
        case .usage: "Usage: KeyBar exec --key NAME_API_KEY [--key OTHER_TOKEN] -- command [arguments]"
        case .launch: "Could not launch the command. Check its executable name and PATH."
        }
    }
}

public enum CommandRunner {
    /// Replace this process, preserving terminal input, exit status, and signals.
    /// No shell interpolation; secret values never become command-line arguments.
    public static func run(_ arguments: ExecArguments, vault: KeychainVault = KeychainVault()) throws -> Never {
        for variable in arguments.variables {
            let secret = try vault.secret(for: variable)
            guard InputRules.validSecret(secret), setenv(variable, secret, 1) == 0 else { throw CommandError.launch }
        }
        let argv = arguments.command.map { strdup($0) } + [nil]
        defer { for pointer in argv { free(pointer) } }
        argv.withUnsafeBufferPointer { buffer in
            _ = execvp(arguments.command[0], buffer.baseAddress!)
        }
        // exec only returns on failure. No secret is included in this error.
        throw CommandError.launch
    }
}
