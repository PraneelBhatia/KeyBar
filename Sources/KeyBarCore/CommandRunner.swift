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
        case .usage: """
        Usage:
          KeyBar exec --key NAME_API_KEY [--key OTHER_TOKEN] -- command [arguments]
          KeyBar env --key NAME_API_KEY --file .env [--replace]
          KeyBar shell --key NAME_API_KEY --file /path/to/.zshrc
        """
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

public struct FileCommandArguments: Equatable, Sendable {
    public enum Operation: String, Sendable { case env, shell }
    public let operation: Operation
    public let variable: String
    public let file: String
    public let replace: Bool

    public static func parse(_ arguments: [String]) throws -> Self {
        guard let first = arguments.first, let operation = Operation(rawValue: first) else { throw CommandError.usage }
        var variable: String?
        var file: String?
        var replace = false
        var index = 1
        while index < arguments.count {
            let flag = arguments[index]
            if flag == "--replace" {
                guard operation == .env, !replace else { throw CommandError.usage }
                replace = true
                index += 1
            } else {
                guard index + 1 < arguments.count else { throw CommandError.usage }
                let value = arguments[index + 1]
                switch flag {
                case "--key": guard variable == nil else { throw CommandError.usage }; variable = value
                case "--file": guard file == nil else { throw CommandError.usage }; file = value
                default: throw CommandError.usage
                }
                index += 2
            }
        }
        guard let variable, InputRules.validVariable(variable), let file, !file.isEmpty,
              !file.contains("\0"), !file.contains("\n"), !file.contains("\r") else { throw CommandError.usage }
        return Self(operation: operation, variable: variable, file: file, replace: replace)
    }
}

extension CommandRunner {
    public static func writeFile(_ arguments: FileCommandArguments, vault: KeychainVault = KeychainVault()) throws {
        let url = URL(fileURLWithPath: arguments.file)
        guard try vault.list().contains(where: { $0.variable == arguments.variable }) else { throw VaultError.missing }
        switch arguments.operation {
        case .env:
            try EnvironmentFiles.writeDotenv(variable: arguments.variable, secret: vault.secret(for: arguments.variable),
                                              to: url, replace: arguments.replace)
        case .shell:
            try EnvironmentFiles.enableShell(variable: arguments.variable, at: url, service: vault.serviceName)
        }
    }
}
