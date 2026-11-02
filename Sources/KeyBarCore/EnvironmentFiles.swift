import Foundation
import Darwin

public enum EnvironmentFileError: LocalizedError {
    case invalidInput, unsupportedSecret, unsafeFile, unreadable, tooLarge, existingVariable, malformed, tracked, gitCheck, changed, write
    public var errorDescription: String? {
        switch self {
        case .invalidInput: "Choose a .env file or .zshrc and a valid variable name."
        case .unsupportedSecret: "This key contains characters that .env readers handle differently. Use Keychain access instead."
        case .unsafeFile: "Choose a regular file owned by you, without symbolic or hard links."
        case .unreadable: "Could not read the file as UTF-8. Its contents were not changed."
        case .tooLarge: "The file is too large to edit safely. Its contents were not changed."
        case .existingVariable: "This variable already exists. Confirm replacement in the app, or use --replace for a .env export."
        case .malformed: "This file contains an ambiguous entry or an incomplete KeyBar block. Edit it manually first."
        case .tracked: "This .env file is already tracked by Git. Untrack it before exporting a key."
        case .gitCheck: "Could not check Git tracking. Make sure Git is installed and this repository is accessible."
        case .changed: "The file changed while KeyBar was preparing the update. Try again."
        case .write: "Could not save the file. Check the folder permissions and try again."
        }
    }
}

public enum EnvironmentFiles {
    private static let maximumSize = 1_048_576

    /// A deliberately portable subset: no interpolation, escaping, or command substitution.
    public static func dotenvValue(_ secret: String) throws -> String {
        guard InputRules.validSecret(secret) else { throw EnvironmentFileError.invalidInput }
        guard !secret.contains("$"), !secret.contains("\\"), !secret.contains("`"),
              !(secret.contains("'") && secret.contains("\"")) else { throw EnvironmentFileError.unsupportedSecret }
        return secret.contains("'") ? "\"\(secret)\"" : "'\(secret)'"
    }

    public static func dotenvContents(_ original: String, variable: String, secret: String, replace: Bool = false) throws -> String {
        guard InputRules.validVariable(variable) else { throw EnvironmentFileError.invalidInput }
        let value = try dotenvValue(secret)
        let newline = original.contains("\r\n") ? "\r\n" : "\n"
        var lines = original.components(separatedBy: newline)
        let pattern = "^[ \\t]*(?:export[ \\t]+)?" + variable + "[ \\t]*="
        var matches: [Int] = []
        var quote: Character?
        func closesQuote(_ text: Substring, quote: Character) -> Bool {
            var escaped = false
            for character in text {
                if escaped { escaped = false; continue }
                if character == "\\" { escaped = true; continue }
                if character == quote { return true }
            }
            return false
        }
        for index in lines.indices {
            let line = index == 0 ? lines[index].replacingOccurrences(of: "\u{FEFF}", with: "") : lines[index]
            if let current = quote {
                if closesQuote(line[...], quote: current) { quote = nil }
                continue
            }
            let assignment = "^[ \\t]*(?:export[ \\t]+)?[A-Za-z_][A-Za-z0-9_]*[ \\t]*="
            guard line.range(of: assignment, options: .regularExpression) != nil else { continue }
            let isTarget = line.range(of: pattern, options: .regularExpression) != nil
            if isTarget { matches.append(index) }
            let oldValue = String(line.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)[1])
                .trimmingCharacters(in: .whitespaces)
            if let first = oldValue.first, first == "'" || first == "\"" || first == "`",
               !closesQuote(oldValue.dropFirst(), quote: first) {
                if isTarget { throw EnvironmentFileError.malformed }
                quote = first
            }
        }
        guard quote == nil, matches.count <= 1 else { throw EnvironmentFileError.malformed }
        let entry = "\(variable)=\(value)"
        if let index = matches.first {
            guard replace else { throw EnvironmentFileError.existingVariable }
            lines[index] = entry
            return lines.joined(separator: newline)
        }
        return original + (original.isEmpty || original.hasSuffix("\n") ? "" : newline) + entry + newline
    }

    public static func shellContents(_ original: String, variable: String, service: String = KeychainVault.defaultService) throws -> String {
        guard InputRules.validVariable(variable), !service.contains("\n"), !service.contains("\r") else { throw EnvironmentFileError.invalidInput }
        let start = "# >>> KeyBar: \(variable) >>>"
        let end = "# <<< KeyBar: \(variable) <<<"
        let block = """
        \(start)
        () {
          setopt localoptions noxtrace noverbose
          local keybar_value
          if keybar_value="$(/usr/bin/security find-generic-password -s \(InputRules.shellQuote(service)) -a \(InputRules.shellQuote(variable)) -w 2>/dev/null)"; then
            export \(variable)="$keybar_value"
          fi
        }
        \(end)
        """
        let newline = original.contains("\r\n") ? "\r\n" : "\n"
        let lines = original.components(separatedBy: newline)
        let starts = lines.indices.filter { lines[$0] == start }
        let ends = lines.indices.filter { lines[$0] == end }
        guard starts.count == ends.count, starts.count <= 1 else { throw EnvironmentFileError.malformed }
        let managed: ClosedRange<Int>?
        if let first = starts.first, let last = ends.first {
            guard first < last else { throw EnvironmentFileError.malformed }
            managed = first...last
        } else { managed = nil }
        let assignment = "(?:^|[; \\t])(?:export[ \\t]+)?" + variable + "[ \\t]*="
        for index in lines.indices where managed?.contains(index) != true {
            if lines[index].trimmingCharacters(in: .whitespaces).hasPrefix("#") { continue }
            guard lines[index].range(of: assignment, options: .regularExpression) == nil else { throw EnvironmentFileError.existingVariable }
        }
        let formatted = block.replacingOccurrences(of: "\n", with: newline)
        if let managed {
            var updated = lines
            updated.replaceSubrange(managed, with: [formatted])
            return updated.joined(separator: newline)
        }
        return original + (original.isEmpty || original.hasSuffix("\n") ? "" : newline) + formatted + newline
    }

    /// Adds one selected key; all unrelated entries are preserved. The secret never enters argv or logs.
    public static func writeDotenv(variable: String, secret: String, to url: URL, replace: Bool = false) throws {
        guard !url.path.contains("\0"), url.lastPathComponent.range(of: "\\A\\.env(?:\\.[A-Za-z0-9_-]+)*\\z", options: .regularExpression) != nil else { throw EnvironmentFileError.invalidInput }
        let current = try snapshot(url)
        let updated = try dotenvContents(current.text, variable: variable, secret: secret, replace: replace)
        try ensureNotTracked(url)
        // Ignore the file before placing a secret in it. This never untracks an existing Git file.
        let ignoreURL = url.deletingLastPathComponent().appendingPathComponent(".gitignore")
        let ignore = try snapshot(ignoreURL)
        let rule = "/" + url.lastPathComponent
        let rules = "/.keybar-*.tmp\n" + rule + "\n"
        // Exclude both destination and staging files before any secret is written.
        // Append after negation rules so a concurrent git add cannot stage a temporary key file.
        if !ignore.text.hasSuffix(rules) {
            let text = ignore.text + (ignore.text.isEmpty || ignore.text.hasSuffix("\n") ? "" : "\n") + rules
            try write(text, to: ignoreURL, original: ignore, mode: ignore.mode ?? 0o644)
        }
        try write(updated, to: url, original: current, mode: 0o600, privateFile: true)
    }

    public static func enableShell(variable: String, at url: URL, service: String = KeychainVault.defaultService) throws {
        guard !url.path.contains("\0"), url.lastPathComponent == ".zshrc" else { throw EnvironmentFileError.invalidInput }
        let current = try snapshot(url)
        let updated = try shellContents(current.text, variable: variable, service: service)
        if updated != current.text {
            try write(updated, to: url, original: current, mode: current.mode ?? 0o600, validateShellSyntax: true)
        }
    }

    private struct Snapshot {
        let text: String
        let data: Data
        let inode: ino_t?
        let mode: mode_t?
    }

    private static func snapshot(_ url: URL) throws -> Snapshot {
        let fd = open(url.path, O_RDONLY | O_NOFOLLOW | O_NONBLOCK | O_CLOEXEC)
        if fd < 0 {
            if errno == ENOENT { return Snapshot(text: "", data: Data(), inode: nil, mode: nil) }
            throw EnvironmentFileError.unsafeFile
        }
        defer { close(fd) }
        var info = stat()
        guard fstat(fd, &info) == 0, (info.st_mode & S_IFMT) == S_IFREG,
              info.st_uid == getuid(), info.st_nlink == 1 else { throw EnvironmentFileError.unsafeFile }
        guard info.st_size <= maximumSize else { throw EnvironmentFileError.tooLarge }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 8192)
        while true {
            let count = Darwin.read(fd, &buffer, buffer.count)
            if count < 0 { if errno == EINTR { continue }; throw EnvironmentFileError.unreadable }
            if count == 0 { break }
            data.append(contentsOf: buffer.prefix(count))
            guard data.count <= maximumSize else { throw EnvironmentFileError.tooLarge }
        }
        guard let text = String(data: data, encoding: .utf8), !text.contains("\0") else { throw EnvironmentFileError.unreadable }
        return Snapshot(text: text, data: data, inode: info.st_ino, mode: info.st_mode & 0o777)
    }

    private static func write(_ text: String, to url: URL, original: Snapshot, mode: mode_t, validateShellSyntax: Bool = false, privateFile: Bool = false) throws {
        let temporary = url.deletingLastPathComponent().appendingPathComponent(".keybar-\(UUID().uuidString).tmp")
        let fd = open(temporary.path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw EnvironmentFileError.write }
        defer { close(fd); unlink(temporary.path) }
        if privateFile {
            // Directory ACLs can otherwise grant access even when the POSIX mode is 0600.
            guard let acl = acl_init(0) else { throw EnvironmentFileError.write }
            defer { acl_free(UnsafeMutableRawPointer(acl)) }
            guard acl_set_fd(fd, acl) == 0 else { throw EnvironmentFileError.write }
        }
        let data = Data(text.utf8)
        try data.withUnsafeBytes { bytes in
            var offset = 0
            while offset < bytes.count {
                let count = Darwin.write(fd, bytes.baseAddress!.advanced(by: offset), bytes.count - offset)
                if count < 0 { if errno == EINTR { continue }; throw EnvironmentFileError.write }
                guard count > 0 else { throw EnvironmentFileError.write }
                offset += count
            }
        }
        guard fchmod(fd, mode) == 0, fsync(fd) == 0 else { throw EnvironmentFileError.write }
        if validateShellSyntax { try validateShell(at: temporary) }
        let latest = try snapshot(url)
        guard latest.inode == original.inode, latest.data == original.data, latest.mode == original.mode else { throw EnvironmentFileError.changed }
        if original.inode == nil {
            // Exclusive publication prevents overwriting a file created after the read.
            guard link(temporary.path, url.path) == 0 else { throw EnvironmentFileError.changed }
        } else {
            guard rename(temporary.path, url.path) == 0 else { throw EnvironmentFileError.write }
        }
    }

    private static func validateShell(at url: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-f", "-n", url.path]
        process.environment = ["PATH": "/usr/bin:/bin"]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do { try process.run(); process.waitUntilExit() } catch { throw EnvironmentFileError.malformed }
        guard process.terminationStatus == 0 else { throw EnvironmentFileError.malformed }
    }

    private static func ensureNotTracked(_ url: URL) throws {
        var directory = url.deletingLastPathComponent()
        var repository = false
        while directory.path != "/" {
            if FileManager.default.fileExists(atPath: directory.appendingPathComponent(".git").path) { repository = true; break }
            directory.deleteLastPathComponent()
        }
        guard repository else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-c", "core.fsmonitor=false", "-c", "core.hooksPath=/dev/null", "--literal-pathspecs", "-C", url.deletingLastPathComponent().path, "ls-files", "--error-unmatch", "--", url.lastPathComponent]
        process.environment = ["PATH": "/usr/bin:/bin", "HOME": FileManager.default.homeDirectoryForCurrentUser.path, "GIT_CONFIG_NOSYSTEM": "1", "GIT_CONFIG_GLOBAL": "/dev/null"]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do { try process.run(); process.waitUntilExit() } catch { throw EnvironmentFileError.gitCheck }
        if process.terminationStatus == 0 { throw EnvironmentFileError.tracked }
        guard process.terminationStatus == 1 else { throw EnvironmentFileError.gitCheck }
    }
}
