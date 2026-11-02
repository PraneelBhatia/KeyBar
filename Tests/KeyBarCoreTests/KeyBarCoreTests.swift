import Testing
import Foundation
@testable import KeyBarCore

struct KeyBarCoreTests {
    @Test func testVariablesAllowCustomNamesAndRejectInjectionAndProcessControls() {
        for name in ["OPENAI_API_KEY", "CUSTOM_SECRET", "SERVICE_TOKEN", "MY_KEY_2", "_PRIVATE"] {
            #expect(InputRules.validVariable(name))
        }
        for name in ["", "lowercase", "1KEY", "KEY=X", "KEY;echo", "KEY\n", "PATH", "BASH_ENV",
                     "DYLD_INSERT_LIBRARIES", "PYTHONPATH", "NODE_OPTIONS", "LD_PRELOAD", "SSLKEYLOGFILE", "HOME"] {
            #expect(!(InputRules.validVariable(name)))
        }
    }
    @Test func testSecretsRejectWhitespaceControlCharactersAndExcessiveInput() {
        #expect(InputRules.validSecret("synthetic-test-key!$'"))
        for value in ["", " x", "x\n", "x\0y", "x y", String(repeating: "x", count: 16_385)] {
            #expect(!(InputRules.validSecret(value)))
        }
    }
    @Test func testDetectionDoesNotSendUnknownOrGenericGoogleKeysToAnAssumedProvider() {
        #expect(Provider.detect(secret: "sk-or-synthetic") == .openrouter)
        #expect(Provider.detect(secret: "sk-ant-synthetic") == .anthropic)
        #expect(Provider.detect(secret: "sk-proj-synthetic") == .openai)
        #expect(Provider.detect(secret: "AIza-synthetic") == .custom)
        #expect(Provider.detect(secret: "sk-unknown") == .custom)
        #expect(Provider.detect(secret: "synthetic", variable: "GEMINI_API_KEY") == .gemini)
    }
    @Test func testRequestsKeepSecretOutOfURLsAndUseFixedProviderHosts() throws {
        let secret = "synthetic-test-credential"
        let hosts: [Provider: String] = [.gemini: "generativelanguage.googleapis.com", .openrouter: "openrouter.ai",
                                        .anthropic: "api.anthropic.com", .openai: "api.openai.com"]
        for (provider, host) in hosts {
            let request = try #require(ProviderChecker.request(provider: provider, secret: secret))
            #expect(request.url?.host == host)
            #expect(request.url?.scheme == "https")
            #expect(!(request.url!.absoluteString.contains(secret)))
            #expect(request.httpMethod == "GET")
            #expect(request.httpBody == nil)
            #expect(request.allHTTPHeaderFields!.values.contains { $0.contains(secret) })
        }
        #expect(ProviderChecker.request(provider: .custom, secret: secret) == nil)
        #expect(ProviderChecker.request(provider: .openai, secret: "bad\nheader") == nil)
    }
    @Test func testStatusClassificationDoesNotCallOutagesOrRestrictionsInvalid() {
        for provider in Provider.allCases where provider != .custom {
            let expected: [(Int, KeyStatus)] = [(401, .invalid), (403, .restricted), (402, .restricted),
                                                (429, .rateLimited), (500, .unavailable), (302, .unavailable), (400, .unavailable)]
            for (code, status) in expected {
                #expect(ProviderChecker.interpret(provider: provider, code: code, data: Data()).status == status)
            }
            #expect(ProviderChecker.interpret(provider: provider, code: 200, data: Data("{}".utf8)).status == .unavailable)
        }
    }
    @Test func testSuccessRequiresExpectedProviderResponseShape() {
        #expect(ProviderChecker.interpret(provider: .openai, code: 200, data: Data(#"{"data":[]}"#.utf8)).status == .valid)
        #expect(ProviderChecker.interpret(provider: .anthropic, code: 200, data: Data(#"{"data":[]}"#.utf8)).status == .valid)
        #expect(ProviderChecker.interpret(provider: .gemini, code: 200, data: Data(#"{"models":[]}"#.utf8)).status == .valid)
        let result = ProviderChecker.interpret(provider: .openrouter, code: 200, data: Data(#"{"data":{"usage":5,"limit_remaining":12.5}}"#.utf8))
        #expect(result.status == .valid)
        #expect(result.remainingLimit == 12.5)
        let unlimited = ProviderChecker.interpret(provider: .openrouter, code: 200, data: Data(#"{"data":{"usage":5,"limit_remaining":null}}"#.utf8))
        #expect(unlimited.remainingLimit == nil)
    }
    @Test func testGeminiInvalidCredentialReasonIsRecognizedWithoutSurfacingBody() {
        let body = Data(#"{"error":{"message":"sensitive-provider-text","details":[{"reason":"API_KEY_INVALID"}]}}"#.utf8)
        let result = ProviderChecker.interpret(provider: .gemini, code: 400, data: body)
        #expect(result.status == .invalid)
        #expect(!(result.status.explanation.contains("sensitive-provider-text")))
    }
    @Test func testExecParsingPreservesLiteralArgumentsAndScopesSelectedKeys() throws {
        let args = try ExecArguments.parse(["exec", "--key", "ONE_KEY", "--key", "TWO_KEY", "--key", "ONE_KEY", "--", "python3", "a script.py", "$(touch injected)"])
        #expect(args.variables == ["ONE_KEY", "TWO_KEY"])
        #expect(args.command == ["python3", "a script.py", "$(touch injected)"])
        for input in [["exec"], ["exec", "--", "env"], ["exec", "--key", "PATH", "--", "env"],
                      ["exec", "--key", "X_KEY", "--"], ["exec", "--all", "X_KEY", "--", "env"]] {
            #expect(throws: (any Error).self) { try ExecArguments.parse(input) }
        }
    }
    @Test func testHandoffContainsOnlyMetadataAndQuotesExecutablePaths() {
        let record = KeyRecord(name: "Personal", variable: "CUSTOM_KEY", provider: .custom)
        let text = InputRules.handoff(record, executable: "/A user's folder/KeyBar")
        #expect(text.contains("exec --key CUSTOM_KEY -- <command>"))
        #expect(text.contains("'/A user'\"'\"'s folder/KeyBar'"))
        #expect(text.contains("Do not print"))
        #expect(!(text.contains("export CUSTOM_KEY=")))
    }
    @Test func testMetadataRoundTripHasNoSecretField() throws {
        let record = KeyRecord(name: "Work", variable: "WORK_KEY", provider: .custom)
        let data = try JSONEncoder().encode(record)
        #expect(try JSONDecoder().decode(KeyRecord.self, from: data) == record)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["secret"] == nil)
        #expect(object["value"] == nil)
    }
}
