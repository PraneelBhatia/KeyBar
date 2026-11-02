import Testing
import Foundation
import Darwin
@testable import KeyBarCore

struct EnvironmentFilesTests {
    private func folder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("keybar-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func dotenvPreservesCommentsOtherKeysAndLineEndings() throws {
        let original = "# local settings\r\nOTHER='keep#this'\r\nexport TEST_KEY = old # prior value\r\n"
        let updated = try EnvironmentFiles.dotenvContents(original, variable: "TEST_KEY", secret: "synthetic#token", replace: true)
        #expect(updated == "# local settings\r\nOTHER='keep#this'\r\nTEST_KEY='synthetic#token'\r\n")
        #expect(throws: EnvironmentFileError.self) {
            try EnvironmentFiles.dotenvContents(original, variable: "TEST_KEY", secret: "synthetic")
        }
        let appended = try EnvironmentFiles.dotenvContents("OTHER=value", variable: "NEW_KEY", secret: "synthetic")
        #expect(appended == "OTHER=value\nNEW_KEY='synthetic'\n")
    }

    @Test func dotenvRejectsAmbiguousValuesWithoutPartialReplacement() throws {
        for original in ["TEST_KEY=a\nTEST_KEY=b\n", "TEST_KEY='first\nsecond'\n", "OTHER='unterminated\n"] {
            #expect(throws: EnvironmentFileError.self) {
                try EnvironmentFiles.dotenvContents(original, variable: "TEST_KEY", secret: "synthetic", replace: true)
            }
        }
        let multiline = "OTHER='first\nTEST_KEY=inside\nlast'\n"
        let updated = try EnvironmentFiles.dotenvContents(multiline, variable: "TEST_KEY", secret: "synthetic")
        #expect(updated == multiline + "TEST_KEY='synthetic'\n")
    }

    @Test func dotenvQuotingPreventsInterpolationAndPreservesLiteralValues() throws {
        #expect(try EnvironmentFiles.dotenvValue("synthetic#value") == "'synthetic#value'")
        #expect(try EnvironmentFiles.dotenvValue("synthetic'value") == "\"synthetic'value\"")
        #expect(try EnvironmentFiles.dotenvValue("synthetic\"value") == "'synthetic\"value'")
        for secret in ["${HOME}", "$(touch-no)", "a\\nb", "`command`", "a'\"b"] {
            #expect(throws: EnvironmentFileError.self) { try EnvironmentFiles.dotenvValue(secret) }
        }
    }

    @Test func dotenvWriteProtectsPermissionsAndIgnoresFileBeforeExport() throws {
        let directory = try folder()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent(".env")
        let ignore = directory.appendingPathComponent(".gitignore")
        try "other\n!.env\n".write(to: ignore, atomically: true, encoding: .utf8)
        try EnvironmentFiles.writeDotenv(variable: "TEST_KEY", secret: "synthetic", to: url)
        #expect(try String(contentsOf: url, encoding: .utf8) == "TEST_KEY='synthetic'\n")
        #expect(try String(contentsOf: ignore, encoding: .utf8) == "other\n!.env\n/.keybar-*.tmp\n/.env\n")
        let permissions = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber
        #expect(permissions?.intValue == 0o600)
        try EnvironmentFiles.writeDotenv(variable: "SECOND_KEY", secret: "second-synthetic", to: url)
        #expect(try String(contentsOf: ignore, encoding: .utf8) == "other\n!.env\n/.keybar-*.tmp\n/.env\n")
        #expect(try String(contentsOf: url, encoding: .utf8).contains("SECOND_KEY='second-synthetic'"))
        let before = try Data(contentsOf: url)
        #expect(throws: EnvironmentFileError.self) {
            try EnvironmentFiles.writeDotenv(variable: "TEST_KEY", secret: "replacement", to: url)
        }
        #expect(try Data(contentsOf: url) == before)
    }

    @Test func dotenvWriteRefusesSymlinksHardlinksAndUnsafeIgnoreFile() throws {
        let directory = try folder()
        defer { try? FileManager.default.removeItem(at: directory) }
        let victim = directory.appendingPathComponent("untouched")
        try "untouched".write(to: victim, atomically: true, encoding: .utf8)
        let url = directory.appendingPathComponent(".env")
        try FileManager.default.createSymbolicLink(at: url, withDestinationURL: victim)
        #expect(throws: EnvironmentFileError.self) { try EnvironmentFiles.writeDotenv(variable: "TEST_KEY", secret: "synthetic", to: url) }
        try FileManager.default.removeItem(at: url)
        #expect(link(victim.path, url.path) == 0)
        #expect(throws: EnvironmentFileError.self) { try EnvironmentFiles.writeDotenv(variable: "TEST_KEY", secret: "synthetic", to: url) }
        try FileManager.default.removeItem(at: url)
        try FileManager.default.createSymbolicLink(at: directory.appendingPathComponent(".gitignore"), withDestinationURL: victim)
        #expect(throws: EnvironmentFileError.self) { try EnvironmentFiles.writeDotenv(variable: "TEST_KEY", secret: "synthetic", to: url) }
        #expect(!FileManager.default.fileExists(atPath: url.path))
        #expect(try String(contentsOf: victim, encoding: .utf8) == "untouched")
    }

    @Test func dotenvWriteRefusesTrackedFiles() throws {
        let directory = try folder()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent(".env")
        try "TEST_KEY=old\n".write(to: url, atomically: true, encoding: .utf8)
        for args in [["init", "--quiet", directory.path], ["-C", directory.path, "add", "--", ".env"]] {
            let git = Process()
            git.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            git.arguments = args
            git.standardOutput = FileHandle.nullDevice
            git.standardError = FileHandle.nullDevice
            try git.run(); git.waitUntilExit()
            #expect(git.terminationStatus == 0)
        }
        #expect(throws: EnvironmentFileError.self) {
            try EnvironmentFiles.writeDotenv(variable: "TEST_KEY", secret: "synthetic", to: url, replace: true)
        }
        #expect(try String(contentsOf: url, encoding: .utf8) == "TEST_KEY=old\n")
        #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent(".gitignore").path))
    }

    @Test func gitIgnoresBothExportAndTemporarySecretFiles() throws {
        let directory = try folder()
        defer { try? FileManager.default.removeItem(at: directory) }
        func git(_ args: [String]) throws -> Int32 {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            process.arguments = ["-C", directory.path] + args
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            try process.run(); process.waitUntilExit()
            return process.terminationStatus
        }
        #expect(try git(["init", "--quiet"]) == 0)
        try EnvironmentFiles.writeDotenv(variable: "TEST_KEY", secret: "synthetic", to: directory.appendingPathComponent(".env"))
        #expect(try git(["check-ignore", "--quiet", "--", ".env"]) == 0)
        #expect(try git(["check-ignore", "--quiet", "--", ".keybar-synthetic.tmp"]) == 0)
    }

    @Test func shellIntegrationIsIdempotentAndPreservesUnmanagedSettings() throws {
        let original = "# my settings\nexport EDITOR=vim\n"
        let once = try EnvironmentFiles.shellContents(original, variable: "TEST_KEY")
        #expect(once.hasPrefix(original))
        #expect(once.contains("/usr/bin/security find-generic-password"))
        #expect(once.contains("setopt localoptions noxtrace noverbose"))
        #expect(try EnvironmentFiles.shellContents(once, variable: "TEST_KEY") == once)
        #expect(throws: EnvironmentFileError.self) { try EnvironmentFiles.shellContents("export TEST_KEY=existing\n", variable: "TEST_KEY") }
        #expect(throws: EnvironmentFileError.self) { try EnvironmentFiles.shellContents("# >>> KeyBar: TEST_KEY >>>\n", variable: "TEST_KEY") }
        let other = try EnvironmentFiles.shellContents(once, variable: "OTHER_KEY")
        #expect(other.contains("KeyBar: TEST_KEY"))
        #expect(other.contains("KeyBar: OTHER_KEY"))
    }

    @Test func shellReferenceRunsWithoutLeakingToTraceOrKeepingTemporaryVariable() throws {
        let directory = try folder()
        defer { try? FileManager.default.removeItem(at: directory) }
        var reference = try EnvironmentFiles.shellContents("", variable: "TEST_KEY")
        let lookup = "/usr/bin/security find-generic-password -s 'app.keybar.vault.v1' -a 'TEST_KEY' -w 2>/dev/null"
        reference = reference.replacingOccurrences(of: lookup, with: "printf %s synthetic-value")
        let script = directory.appendingPathComponent(".zshrc")
        try reference.write(to: script, atomically: true, encoding: .utf8)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-f", "-c", "set -x; source \(InputRules.shellQuote(script.path)); set +x; [[ $TEST_KEY == synthetic-value && -z $keybar_value ]] && /bin/sh -c 'test \"$TEST_KEY\" = synthetic-value'"]
        process.environment = ["PATH": "/usr/bin:/bin", "HOME": directory.path, "ZDOTDIR": directory.path]
        let output = Pipe()
        process.standardOutput = output
        process.standardError = output
        try process.run()
        let captured = output.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        #expect(process.terminationStatus == 0)
        #expect(!String(decoding: captured, as: UTF8.self).contains("synthetic-value"))
    }

    @Test func shellFileWritesAreValidatedAndIdempotent() throws {
        let directory = try folder()
        defer { try? FileManager.default.removeItem(at: directory) }
        let profile = directory.appendingPathComponent(".zshrc")
        try "export EDITOR=vim\n".write(to: profile, atomically: true, encoding: .utf8)
        try EnvironmentFiles.enableShell(variable: "TEST_KEY", at: profile)
        let once = try Data(contentsOf: profile)
        try EnvironmentFiles.enableShell(variable: "TEST_KEY", at: profile)
        #expect(try Data(contentsOf: profile) == once)
        try "if true; then\n".write(to: profile, atomically: true, encoding: .utf8)
        #expect(throws: EnvironmentFileError.self) { try EnvironmentFiles.enableShell(variable: "TEST_KEY", at: profile) }
        #expect(try String(contentsOf: profile, encoding: .utf8) == "if true; then\n")
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path) == [".zshrc"])
    }

    @Test func unsafeNamesAndOversizedOrInvalidFilesAreRefused() throws {
        let directory = try folder()
        defer { try? FileManager.default.removeItem(at: directory) }
        for name in ["README.md", ".zshrc", ".env.\nother", ".env.*"] {
            #expect(throws: EnvironmentFileError.self) {
                try EnvironmentFiles.writeDotenv(variable: "TEST_KEY", secret: "synthetic", to: directory.appendingPathComponent(name))
            }
        }
        let url = directory.appendingPathComponent(".env")
        try Data([0xff, 0xfe, 0]).write(to: url)
        #expect(throws: EnvironmentFileError.self) { try EnvironmentFiles.writeDotenv(variable: "TEST_KEY", secret: "synthetic", to: url) }
        try Data(repeating: 65, count: 1_048_577).write(to: url)
        #expect(throws: EnvironmentFileError.self) { try EnvironmentFiles.writeDotenv(variable: "TEST_KEY", secret: "synthetic", to: url) }
        #expect(!FileManager.default.fileExists(atPath: directory.appendingPathComponent(".gitignore").path))
    }

    @Test func fileCommandParsingAndHandoffsContainNoSecret() throws {
        let args = try FileCommandArguments.parse(["env", "--file", "project folder/.env", "--key", "TEST_KEY", "--replace"])
        #expect(args.operation == .env && args.file == "project folder/.env" && args.replace)
        for values in [["env", "--key", "PATH", "--file", ".env"], ["shell", "--key", "TEST_KEY", "--file", ".zshrc", "--replace"], ["env", "--key", "TEST_KEY"], ["env", "--key", "TEST_KEY", "--file", ".env", "--file", "other"]] {
            #expect(throws: CommandError.self) { try FileCommandArguments.parse(values) }
        }
        let record = KeyRecord(name: "Test", variable: "TEST_KEY", provider: .custom)
        for mode in HandoffMode.allCases {
            let note = InputRules.handoff(record, executable: "/A user's folder/KeyBar", mode: mode)
            #expect(note.contains("TEST_KEY"))
            #expect(note.contains("'/A user'\"'\"'s folder/KeyBar'"))
            #expect(!note.contains("synthetic-value"))
        }
        let note = InputRules.handoff(record, executable: "/KeyBar", mode: .choose)
        #expect(note.contains(" exec --key TEST_KEY --"))
        #expect(note.contains(" env --key TEST_KEY --file .env"))
        #expect(note.contains(" shell --key TEST_KEY --file"))
    }
}
