import Foundation
import TranslationCore

// Small executable test harness: runs with Command Line Tools as well as Xcode.
private class TestCase {}
private func expectEqual<T: Equatable>(_ lhs: T, _ rhs: T, file: StaticString = #file, line: UInt = #line) {
    precondition(lhs == rhs, "Values differ", file: file, line: line)
}
private func expectNotEqual<T: Equatable>(_ lhs: T, _ rhs: T, file: StaticString = #file, line: UInt = #line) {
    precondition(lhs != rhs, "Values must differ", file: file, line: line)
}
private func expectTrue(_ value: Bool, file: StaticString = #file, line: UInt = #line) {
    precondition(value, "Expected true", file: file, line: line)
}
private func expectFalse(_ value: Bool, file: StaticString = #file, line: UInt = #line) { expectTrue(!value, file: file, line: line) }
private func expectNil<T>(_ value: T?, file: StaticString = #file, line: UInt = #line) { expectTrue(value == nil, file: file, line: line) }
private func unwrap<T>(_ value: T?, file: StaticString = #file, line: UInt = #line) throws -> T {
    guard let value else { fatalError("Unexpected nil", file: file, line: line) }
    return value
}
private func expectThrows<T>(_ expression: @autoclosure () throws -> T, file: StaticString = #file, line: UInt = #line) {
    do { _ = try expression() } catch { return }
    fatalError("Expected error", file: file, line: line)
}
private func fail(_ message: String, file: StaticString = #file, line: UInt = #line) { fatalError(message, file: file, line: line) }

private final class StubTransport: HTTPTransport {
    var requests: [URLRequest] = []
    var status = 200
    var response = Data(#"{"choices":[{"finish_reason":"stop","message":{"content":"Hello."}}]}"#.utf8)
    var failure: Error?
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        requests.append(request)
        if let failure { throw failure }
        return (response, HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!)
    }
}

private final class ConfigurationTests: TestCase {
    func testEndpointNormalizesBaseAndFullURL() throws {
        for base in ["https://api.example.invalid/v1", "https://api.example.invalid/v1/", "https://api.example.invalid/v1/chat/completions"] {
            expectEqual(try APIConfiguration(baseURL: base, model: "model").endpoint().absoluteString,
                           "https://api.example.invalid/v1/chat/completions")
        }
    }
    func testRejectsInsecureOrSecretBearingURLs() {
        for base in ["http://example.invalid", "https://user:password@example.invalid", "https://example.invalid?key=fake", "https://example.invalid#fake", "not a url"] {
            expectThrows(try APIConfiguration(baseURL: base).endpoint())
        }
    }
    func testCredentialScopeIncludesProfileAndOrigin() throws {
        let id = UUID()
        let first = LLMProfile(id: id, configuration: .init(baseURL: "https://first.example.invalid"))
        let otherOrigin = LLMProfile(id: id, configuration: .init(baseURL: "https://second.example.invalid"))
        let otherProfile = LLMProfile(configuration: first.configuration)
        expectNotEqual(try first.credentialAccount(), try otherOrigin.credentialAccount())
        expectNotEqual(try first.credentialAccount(), try otherProfile.credentialAccount())
    }
    func testProfileDeletionDoesNotSilentlyEnableAnotherProvider() {
        let first = LLMProfile(), second = LLMProfile(name: "Other")
        var collection = ProfileCollection(profiles: [first, second], activeID: first.id)
        collection.remove(id: first.id)
        expectNil(collection.active)
        expectEqual(collection.profiles, [second])
    }
    func testPreferencesSerializationContainsNoCredentials() throws {
        let initial = ProfileCollection.initial()
        let data = try JSONEncoder().encode(initial)
        expectEqual(try JSONDecoder().decode(ProfileCollection.self, from: data), initial)
        let object = try unwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        expectEqual(Set(object.keys), ["profiles", "activeID"])
        let profile = try unwrap((object["profiles"] as? [[String: Any]])?.first)
        expectEqual(Set(profile.keys), ["id", "name", "configuration"])
    }
    func testDeepSeekOffersDocumentedEfforts() {
        expectEqual(ReasoningEffort.supported(for: "https://api.deepseek.com/v1"), [.providerDefault, .none, .low, .high, .max])
    }
}

private final class ClientTests: TestCase {
    func testRequestAndTranslation() async throws {
        let stub = StubTransport()
        let translated = try await TranslationClient(transport: stub).translate("你好。", configuration: .init(), key: "synthetic-test-key")
        expectEqual(translated, "Hello.")
        let request = try unwrap(stub.requests.first)
        expectEqual(request.httpMethod, "POST")
        expectEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer synthetic-test-key")
        let json = try unwrap(JSONSerialization.jsonObject(with: unwrap(request.httpBody)) as? [String: Any])
        expectNil(json["reasoning_effort"])
        let messages = try unwrap(json["messages"] as? [[String: String]])
        expectEqual(messages.last?["content"], "你好。")
        expectEqual(messages.first?["role"], "system")
    }
    func testExplicitEffortIsSentAndReasoningIsNotReturned() async throws {
        let stub = StubTransport()
        stub.response = Data(#"{"choices":[{"finish_reason":"stop","message":{"content":"Hello.","reasoning_content":"private reasoning"}}]}"#.utf8)
        let result = try await TranslationClient(transport: stub).translate("你好。", configuration: .init(effort: .low), key: "synthetic-test-key")
        expectEqual(result, "Hello.")
        let json = try unwrap(JSONSerialization.jsonObject(with: unwrap(stub.requests.first?.httpBody)) as? [String: Any])
        expectEqual(json["reasoning_effort"] as? String, "low")
    }
    func testInvalidInputDoesNotSendRequest() async {
        let stub = StubTransport()
        for text in ["  \n", String(repeating: "a", count: 30_001)] {
            do { _ = try await TranslationClient(transport: stub).translate(text, configuration: .init(), key: "synthetic-test-key"); fail("Expected rejection") }
            catch {}
        }
        expectTrue(stub.requests.isEmpty)
    }
    func testHTTPFailuresAreSanitized() async {
        let stub = StubTransport()
        stub.status = 401
        stub.response = Data("server body must never appear in error".utf8)
        do { _ = try await TranslationClient(transport: stub).translate("你好", configuration: .init(), key: "synthetic-test-key"); fail("Expected HTTP error") }
        catch { expectEqual(error as? TranslationError, .http(401)); expectFalse(error.localizedDescription.contains("server body")) }
    }
    func testRejectsTruncatedRefusedEmptyAndMalformedResponses() async {
        for response in [
            #"{"choices":[{"finish_reason":"length","message":{"content":"partial"}}]}"#,
            #"{"choices":[{"finish_reason":"stop","message":{"content":" ","refusal":null}}]}"#,
            #"{"choices":[{"finish_reason":"stop","message":{"content":null,"refusal":"refused"}}]}"#,
            #"{"choices":[]}"#, "not JSON"
        ] {
            let stub = StubTransport(); stub.response = Data(response.utf8)
            do { _ = try await TranslationClient(transport: stub).translate("你好", configuration: .init(), key: "synthetic-test-key"); fail("Expected rejection") }
            catch {}
        }
    }
    func testNetworkFailuresAreSanitized() async {
        let stub = StubTransport(); stub.failure = URLError(.timedOut)
        do { _ = try await TranslationClient(transport: stub).translate("你好", configuration: .init(), key: "synthetic-test-key"); fail("Expected error") }
        catch { expectEqual(error as? TranslationError, .network) }
    }
}

private final class DeliveryTests: TestCase {
    private func snapshot(pid: Int32 = 1, element: String = "field", window: String? = "window", range: NSRange? = NSRange(location: 2, length: 2),
                          selected: String = "你好", full: String? = "xx你好yy", editable: Bool = true) -> TextSnapshot {
        .init(processID: pid, elementID: element, windowID: window, range: range, selectedText: selected, fullText: full, isEditable: editable)
    }
    func testOnlyUnchangedEditableSelectionIsReplaced() {
        let source = snapshot()
        expectEqual(DeliveryPolicy.decide(original: source, current: source), .replaceSelection)
    }
    func testClipboardAndReadOnlyInputNeverModifyField() {
        expectEqual(DeliveryPolicy.decide(original: nil, current: snapshot()), .clipboard)
        expectEqual(DeliveryPolicy.decide(original: snapshot(editable: false), current: snapshot()), .clipboard)
    }
    func testEveryContextChangeFallsBackToClipboard() {
        let source = snapshot()
        for current: TextSnapshot? in [nil, snapshot(pid: 2), snapshot(element: "other"), snapshot(window: "other"),
                                      snapshot(range: NSRange(location: 0, length: 2)), snapshot(selected: "再见"), snapshot(full: "changed outside selection")] {
            expectEqual(DeliveryPolicy.decide(original: source, current: current), .clipboardBecauseTargetChanged)
        }
    }
    func testSwitchingAwayAndBackStillFallsBack() {
        let source = snapshot()
        expectEqual(DeliveryPolicy.decide(original: source, current: source, contextWasInterrupted: true), .clipboardBecauseTargetChanged)
    }
    func testUnverifiableTargetAndEmptySelectionCannotBeReplaced() {
        for source in [snapshot(full: nil), snapshot(window: nil), snapshot(range: nil), snapshot(range: NSRange(location: 2, length: 0))] {
            expectEqual(DeliveryPolicy.decide(original: source, current: source), .clipboardBecauseTargetChanged)
        }
    }
}

private final class StreamingTests: TestCase {
    private func transport(_ lines: [String]) -> StubTransport {
        let result = StubTransport()
        result.response = Data(lines.joined(separator: "\n").utf8)
        return result
    }
    func testChineseDirectionAndIncrementalOutput() async throws {
        let stub = transport([
            ": keepalive", "",
            #"data: {"choices":[{"delta":{"reasoning_content":"not visible"},"finish_reason":null}]}"#,
            #"data: {"choices":[{"delta":{"content":"你好"},"finish_reason":null}]}"#,
            #"data: {"choices":[{"delta":{"content":"，世界。🌍"},"finish_reason":null}]}"#,
            #"data: {"choices":[{"delta":{},"finish_reason":"stop"}]}"#,
            #"data: {"choices":[],"usage":{"total_tokens":10}}"#,
            "data: [DONE]"
        ])
        var pieces: [String] = []
        let result = try await TranslationClient(transport: stub).translate("Hello, world.", configuration: .init(), key: "synthetic-test-key", direction: .toChinese) { pieces.append($0) }
        expectEqual(pieces, ["你好", "，世界。🌍"])
        expectEqual(result, "你好，世界。🌍")
        let json = try unwrap(JSONSerialization.jsonObject(with: unwrap(stub.requests.first?.httpBody)) as? [String: Any])
        expectEqual(json["stream"] as? Bool, true)
        let messages = try unwrap(json["messages"] as? [[String: String]])
        expectTrue(messages[0]["content"]!.contains("Simplified Chinese"))
    }
    func testDisconnectedStreamCannotReturnPartialResult() async {
        for lines in [
            [#"data: {"choices":[{"delta":{"content":"partial"},"finish_reason":null}]}"#],
            [#"data: {"choices":[{"delta":{"content":"partial"},"finish_reason":"stop"}]}"#],
            [#"data: {"choices":[{"delta":{"content":"partial"},"finish_reason":null}]}"#, "data: [DONE]"],
            [#"data: {"choices":[{"delta":{"content":"partial"},"finish_reason":"length"}]}"#, "data: [DONE]"]
        ] {
            do {
                _ = try await TranslationClient(transport: transport(lines)).translate("hello", configuration: .init(), key: "synthetic-test-key")
                fail("Partial stream was incorrectly accepted")
            } catch { expectEqual(error as? TranslationError, .incompleteResponse) }
        }
    }
    func testMalformedStreamDoesNotExposeResponseBody() async {
        let stub = transport(["data: server-private-body"])
        do {
            _ = try await TranslationClient(transport: stub).translate("hello", configuration: .init(), key: "synthetic-test-key")
            fail("Expected malformed stream failure")
        } catch { expectEqual(error as? TranslationError, .invalidResponse); expectFalse(error.localizedDescription.contains("server-private-body")) }
    }
    func testStreamingOutputLimit() async {
        let content = String(repeating: "a", count: 120_001)
        let event = try! JSONSerialization.data(withJSONObject: ["choices": [["delta": ["content": content]]]])
        let stub = transport(["data: " + String(decoding: event, as: UTF8.self)])
        do { _ = try await TranslationClient(transport: stub).translate("hello", configuration: .init(), key: "synthetic-test-key"); fail("Expected output limit") }
        catch { expectEqual(error as? TranslationError, .outputTooLong) }
    }
    func testCancellationIsPreserved() async {
        let stub = StubTransport(); stub.failure = CancellationError()
        do { _ = try await TranslationClient(transport: stub).translate("hello", configuration: .init(), key: "synthetic-test-key"); fail("Expected cancellation") }
        catch { expectTrue(error is CancellationError) }
    }
}


@main
struct CoreChecks {
    static func main() async throws {
        let configuration = ConfigurationTests()
        try configuration.testEndpointNormalizesBaseAndFullURL()
        configuration.testRejectsInsecureOrSecretBearingURLs()
        try configuration.testCredentialScopeIncludesProfileAndOrigin()
        configuration.testProfileDeletionDoesNotSilentlyEnableAnotherProvider()
        try configuration.testPreferencesSerializationContainsNoCredentials()
        configuration.testDeepSeekOffersDocumentedEfforts()
        print("PASS: 6 configuration and profile checks")
        let client = ClientTests()
        try await client.testRequestAndTranslation()
        try await client.testExplicitEffortIsSentAndReasoningIsNotReturned()
        await client.testInvalidInputDoesNotSendRequest()
        await client.testHTTPFailuresAreSanitized()
        await client.testRejectsTruncatedRefusedEmptyAndMalformedResponses()
        await client.testNetworkFailuresAreSanitized()
        print("PASS: 6 API checks (synthetic in-memory transport only)")
        let delivery = DeliveryTests()
        delivery.testOnlyUnchangedEditableSelectionIsReplaced()
        delivery.testClipboardAndReadOnlyInputNeverModifyField()
        delivery.testEveryContextChangeFallsBackToClipboard()
        delivery.testSwitchingAwayAndBackStillFallsBack()
        delivery.testUnverifiableTargetAndEmptySelectionCannotBeReplaced()
        print("PASS: 5 delivery and target-change checks")
        let streaming = StreamingTests()
        try await streaming.testChineseDirectionAndIncrementalOutput()
        await streaming.testDisconnectedStreamCannotReturnPartialResult()
        await streaming.testMalformedStreamDoesNotExposeResponseBody()
        await streaming.testStreamingOutputLimit()
        await streaming.testCancellationIsPreserved()
        print("PASS: 5 bidirectional streaming checks")
        runSelectionChecks()
        try runCredentialChecks()
        print("All core checks passed (22 existing cases plus selection and local credential regressions).")
    }
}
