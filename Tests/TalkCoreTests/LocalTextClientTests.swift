import XCTest
@testable import TalkCore

private final class LocalTextStub: URLProtocol {
    static var handler: ((URLRequest) throws -> (Int, String))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (status, body) = try Self.handler!(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: Data(body.utf8)); client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}

final class LocalTextClientTests: XCTestCase {
    private var session: URLSession!
    override func setUp() {
        let configuration = URLSessionConfiguration.ephemeral; configuration.protocolClasses = [LocalTextStub.self]
        session = URLSession(configuration: configuration)
    }
    override func tearDown() { session.invalidateAndCancel(); LocalTextStub.handler = nil }

    func testDiscoveryKeepsReasoningButExcludesEmbeddingAndRemoteModels() async throws {
        LocalTextStub.handler = { request in
            XCTAssertEqual(request.url?.host, "127.0.0.1")
            if request.url?.lastPathComponent == "tags" {
                return (200, #"{"models":[{"name":"text"},{"name":"embedding"},{"name":"reasoning"},{"name":"remote"},{"name":"name-cloud"}]}"#)
            }
            let model = try Self.body(request)["model"] as! String
            if model == "embedding" { return (200, #"{"capabilities":["embedding"]}"#) }
            if model == "reasoning" { return (200, #"{"capabilities":["completion","thinking"]}"#) }
            if model == "remote" { return (200, #"{"capabilities":["completion"],"remote_host":"https://remote.example"}"#) }
            XCTAssertEqual(model, "text"); return (200, #"{"capabilities":["completion"]}"#)
        }
        let models = try await LocalTextClient.models(session: session)
        XCTAssertEqual(models, ["reasoning", "text"])
    }

    func testPullReportsProgressAndRequiresSuccess() async throws {
        LocalTextStub.handler = { request in
            XCTAssertEqual(request.url?.path, "/api/pull")
            return (200, #"{"status":"pulling manifest"}"# + "\n" + #"{"status":"pulling","total":200,"completed":50}"# + "\n" + #"{"status":"success"}"#)
        }
        let seen = LockedValues()
        try await LocalTextClient.pull("qwen3.5:9b", session: session) { seen.append($0) }
        XCTAssertEqual(seen.values, [nil, 0.25, nil])

        LocalTextStub.handler = { _ in (200, #"{"status":"pulling","total":200,"completed":50}"#) }
        do { try await LocalTextClient.pull("qwen3.5:9b", session: session) { _ in }; XCTFail("expected interrupted pull") }
        catch let error as TalkError { XCTAssertEqual(error.localizedDescription, "模型下載中斷，請重試。") }
    }

    func testPunctuationAndListsAreReturnedThroughLocalChat() async throws {
        LocalTextStub.handler = { request in
            if request.url?.lastPathComponent == "show" { return (200, #"{"capabilities":["completion"]}"#) }
            XCTAssertEqual(request.url?.path, "/api/chat")
            XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
            let body = try Self.body(request)
            XCTAssertEqual(body["stream"] as? Bool, false)
            XCTAssertEqual(body["think"] as? Bool, false)
            let messages = body["messages"] as! [[String: String]]
            let prompt = messages.last!["content"]!
            let payload = try JSONSerialization.jsonObject(with: Data(prompt.components(separatedBy: "\n").last!.utf8)) as! [String: Any]
            XCTAssertEqual(payload["transcript"] as? String, "第一確認權限第二測試錄音")
            return (200, #"{"done":true,"done_reason":"stop","message":{"content":"1. 確認權限。\n2. 測試錄音。"}}"#)
        }
        var settings = TalkSettings(); settings.textBackend = .local; settings.dictationLayout = .list
        let prompt = try TextProcessing.prompt(action: .dictate, transcript: "第一確認權限第二測試錄音", selection: "", settings: settings)
        let output = try await LocalTextClient.complete(prompt: prompt, model: "text", session: session)
        XCTAssertEqual(TextProcessing.formatOutput(output, action: .dictate, settings: settings), "1. 確認權限。\n2. 測試錄音。")
    }

    func testRemoteAndTruncatedResponsesDoNotBecomeDictation() async throws {
        LocalTextStub.handler = { request in
            XCTAssertEqual(request.url?.lastPathComponent, "show", "A remote model must be rejected before sending the transcript")
            return (200, #"{"capabilities":["completion"],"remote_model":"remote"}"#)
        }
        do { _ = try await LocalTextClient.complete(prompt: "fixture", model: "text", session: session); XCTFail("Remote model accepted") }
        catch { XCTAssertTrue(error is TalkError) }
        LocalTextStub.handler = { request in
            if request.url?.lastPathComponent == "show" { return (200, #"{"capabilities":["completion"]}"#) }
            return (200, #"{"done":true,"done_reason":"length","message":{"content":"未完成的文字"}}"#)
        }
        do { _ = try await LocalTextClient.complete(prompt: "fixture", model: "text", session: session); XCTFail("Truncated text accepted") }
        catch { XCTAssertTrue(error.localizedDescription.contains("未完成")) }
    }

    func testLegacySettingsStillDecodeAndVerbatimSkipsFormatting() throws {
        var settings = TalkSettings()
        let decoded = try JSONDecoder().decode(TalkSettings.self, from: JSONEncoder().encode(settings))
        XCTAssertNil(decoded.localTextModel); XCTAssertNil(decoded.dictationLayout)
        settings.textBackend = .local; settings.writingStyle = .verbatim
        XCTAssertFalse(settings.requiresTextModel(for: .dictate))
        settings.writingStyle = .natural
        XCTAssertTrue(settings.requiresTextModel(for: .dictate))
    }

    func testOllamaCLISettingsMigrateWithoutChangingSpeechSource() {
        var settings = TalkSettings(); settings.textBackend = .cli; settings.speechBackend = .api
        settings.textCLIExecutable = "/usr/local/bin/ollama"; settings.textCLIArguments = "run gemma3:4b"
        LocalTextConfiguration.migrate(&settings)
        XCTAssertEqual(settings.textBackend, .local); XCTAssertEqual(settings.localTextModel, "gemma3:4b")
        XCTAssertEqual(settings.speechBackend, .api)
    }

    func testFormattingPreservesNumericLiteralsAndNormalizesRealListMarkers() throws {
        let source = "明天3點通知Amy預算2,000元"
        XCTAssertThrowsError(try TextProcessing.checkedDictationOutput("明天三點通知Amy，預算兩千元。", source: source))
        XCTAssertThrowsError(try TextProcessing.checkedDictationOutput("明天3點通知艾米，預算2,000元。", source: source))
        XCTAssertThrowsError(try TextProcessing.checkedDictationOutput(String(repeating: "分析內容", count: 100), source: source))
        XCTAssertThrowsError(try TextProcessing.checkedDictationOutput("<think>分析</think>明天3點通知Amy，預算2,000元。", source: source))
        XCTAssertEqual(try TextProcessing.checkedDictationOutput("明天3點通知Amy，預算2,000元。", source: source), "明天3點通知Amy，預算2,000元。")
        // Whisper writes a full-width percent sign; the text model often switches to the ASCII one.
        XCTAssertEqual(try TextProcessing.checkedDictationOutput("段落中，22% 的停頓。", source: "段落中 22％ 的停頓"), "段落中，22% 的停頓。")
        XCTAssertThrowsError(try TextProcessing.checkedDictationOutput("段落中，23% 的停頓。", source: "段落中 22％ 的停頓"))
        let list = "今天有三件事：\n第一，確認權限。\n第二，測試錄音。\n第三，檢查文字插入。"
        var settings = TalkSettings(); settings.textBackend = .local
        XCTAssertEqual(TextProcessing.formatOutput(list, action: .dictate, settings: settings),
                       "今天有三件事：\n1. 確認權限。\n2. 測試錄音。\n3. 檢查文字插入。")
        settings.writingStyle = .verbatim
        XCTAssertEqual(TextProcessing.formatOutput(list, action: .dictate, settings: settings), list)
        settings.writingStyle = .natural; settings.textBackend = .basic
        XCTAssertEqual(TextProcessing.formatOutput(list, action: .dictate, settings: settings), list)
    }

    private static func body(_ request: URLRequest) throws -> [String: Any] {
        var data = request.httpBody ?? Data()
        if data.isEmpty, let stream = request.httpBodyStream {
            stream.open(); defer { stream.close() }; var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let count = stream.read(&buffer, maxLength: buffer.count)
                if count <= 0 { break }; data.append(contentsOf: buffer.prefix(count))
            }
        }
        return try JSONSerialization.jsonObject(with: data) as! [String: Any]
    }
}

private final class LockedValues: @unchecked Sendable {
    private let lock = NSLock(); private var stored: [Double?] = []
    func append(_ value: Double?) { lock.lock(); stored.append(value); lock.unlock() }
    var values: [Double?] { lock.lock(); defer { lock.unlock() }; return stored }
}
