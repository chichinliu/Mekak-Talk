import XCTest
@testable import TalkCore

private final class StubProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (Int, Data))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (status, data) = try Self.handler!(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data); client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

final class APITests: XCTestCase {
    private var session: URLSession!
    override func setUp() {
        let config = URLSessionConfiguration.ephemeral; config.protocolClasses = [StubProtocol.self]
        session = URLSession(configuration: config)
    }
    override func tearDown() { session.invalidateAndCancel(); StubProtocol.handler = nil }

    func testEndpointValidation() throws {
        XCTAssertEqual(try APIClient.endpoint(base: "https://api.example.com/v1/", path: "audio/transcriptions").absoluteString, "https://api.example.com/v1/audio/transcriptions")
        XCTAssertNoThrow(try APIClient.endpoint(base: "http://localhost:8080/v1", path: "chat/completions"))
        for invalid in ["http://remote.example.com/v1", "https://user:key@example.com/v1", "https://example.com/v1?key=secret", "file:///etc/passwd"] {
            XCTAssertThrowsError(try APIClient.endpoint(base: invalid, path: "audio/transcriptions"))
        }
    }
    func testTranscriptionMultipartAndNewLanguageField() async throws {
        StubProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/v1/audio/transcriptions")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-key")
            let body = String(decoding: Self.body(request), as: UTF8.self)
            XCTAssertTrue(body.contains("name=\"languages[]\"\r\n\r\nzh"))
            XCTAssertFalse(body.contains("name=\"language\""))
            XCTAssertTrue(body.contains("filename=\"dictation.wav\""))
            XCTAssertTrue(body.contains("RIFFtest"))
            return (200, Data("{\"text\":\"這是測試\"}".utf8))
        }
        let result = try await APIClient.transcription(audio: Data("RIFFtest".utf8), settings: APISettings(model: "gpt-transcribe"), key: "test-key", language: "zh", dictionary: [], session: session)
        XCTAssertEqual(result, "這是測試")
    }
    func testCompatibleTranscriptionLanguageField() async throws {
        StubProtocol.handler = { request in
            XCTAssertTrue(String(decoding: Self.body(request), as: UTF8.self).contains("name=\"language\"\r\n\r\nen"))
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
            return (200, Data("{\"text\":\"hello\"}".utf8))
        }
        _ = try await APIClient.transcription(audio: Data(), settings: APISettings(baseURL: "http://localhost:8080/v1", model: "whisper-1"), key: "", language: "en", dictionary: [], session: session)
    }
    func testCompletionAndProviderErrorsAreRedacted() async throws {
        StubProtocol.handler = { request in
            let payload = try JSONSerialization.jsonObject(with: Self.body(request)) as! [String: Any]
            XCTAssertEqual(payload["model"] as? String, "example-model")
            return (200, Data("{\"choices\":[{\"message\":{\"content\":\"完成的文字\"}}]}".utf8))
        }
        let output = try await APIClient.complete(prompt: "test", settings: APISettings(model: "example-model"), key: "test", session: session)
        XCTAssertEqual(output, "完成的文字")
        StubProtocol.handler = { _ in (401, Data("secret-provider-diagnostic".utf8)) }
        do {
            _ = try await APIClient.complete(prompt: "test", settings: APISettings(model: "example"), key: "test", session: session)
            XCTFail("Expected rejection")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("API Key"))
            XCTAssertFalse(error.localizedDescription.contains("secret-provider-diagnostic"))
        }
    }
    func testEmptyTranscriptFails() async {
        StubProtocol.handler = { _ in (200, Data("{\"text\":\"   \"}".utf8)) }
        do {
            _ = try await APIClient.transcription(audio: Data(), settings: APISettings(model: "whisper-1"), key: "test", language: "zh", dictionary: [], session: session)
            XCTFail("Expected empty transcription error")
        } catch { XCTAssertTrue(error is TalkError) }
    }
    private static func body(_ request: URLRequest) -> Data {
        if let data = request.httpBody { return data }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open(); defer { stream.close() }
        var data = Data(); var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            if count <= 0 { break }; data.append(contentsOf: buffer.prefix(count))
        }
        return data
    }
}
