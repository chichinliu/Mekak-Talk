import Foundation

public enum APIClient {
    public static func endpoint(base: String, path: String) throws -> URL {
        guard let url = URL(string: base.trimmingCharacters(in: .whitespacesAndNewlines)),
              let host = url.host, !host.isEmpty, url.user == nil, url.password == nil,
              url.query == nil, url.fragment == nil,
              url.scheme == "https" || (url.scheme == "http" && ["localhost", "127.0.0.1", "::1", "[::1]"].contains(host))
        else { throw TalkError("服務網址需使用 HTTPS；本機服務可使用 http://localhost。請填入包含 /v1 的基底網址。") }
        return url.appendingPathComponent(path)
    }

    public static func transcription(audio: Data, settings: APISettings, key: String, language: String,
                                     dictionary: [String], session: URLSession = .shared) async throws -> String {
        guard !settings.model.trimmingCharacters(in: .whitespaces).isEmpty else { throw TalkError("請填入辨識模型名稱。") }
        let boundary = "HydayTalk-" + UUID().uuidString
        var body = Data()
        func field(_ name: String, _ value: String) {
            body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"\(name)\"\r\n\r\n\(value)\r\n".utf8))
        }
        field("model", settings.model)
        field("response_format", "json")
        // New gpt-transcribe uses a languages array; older compatible models use language.
        field(settings.model == "gpt-transcribe" ? "languages[]" : "language", language)
        if !dictionary.isEmpty { field("prompt", dictionary.joined(separator: ", ").prefix(800).description) }
        body.append(Data("--\(boundary)\r\nContent-Disposition: form-data; name=\"file\"; filename=\"dictation.wav\"\r\nContent-Type: audio/wav\r\n\r\n".utf8))
        body.append(audio); body.append(Data("\r\n--\(boundary)--\r\n".utf8))
        var request = URLRequest(url: try endpoint(base: settings.baseURL, path: "audio/transcriptions"))
        request.httpMethod = "POST"; request.timeoutInterval = 120
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        if !key.isEmpty { request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization") }
        request.httpBody = body
        let data = try await send(request, session: session)
        struct Response: Decodable { let text: String }
        guard let response = try? JSONDecoder().decode(Response.self, from: data),
              !response.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { throw TalkError("辨識服務未回傳文字。請確認模型與音訊辨識端點。") }
        return response.text
    }

    public static func complete(prompt: String, settings: APISettings, key: String,
                                session: URLSession = .shared) async throws -> String {
        guard !settings.model.trimmingCharacters(in: .whitespaces).isEmpty else { throw TalkError("請填入文字模型名稱。") }
        var request = URLRequest(url: try endpoint(base: settings.baseURL, path: "chat/completions"))
        request.httpMethod = "POST"; request.timeoutInterval = 60
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !key.isEmpty { request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization") }
        request.httpBody = try JSONSerialization.data(withJSONObject: ["model": settings.model,
            "messages": [["role": "system", "content": "You are a careful writing assistant. Follow the task and return only the requested text."],
                         ["role": "user", "content": prompt]]])
        let data = try await send(request, session: session)
        struct Response: Decodable {
            struct Choice: Decodable { struct Message: Decodable { let content: String? }; let message: Message }
            let choices: [Choice]
        }
        guard let response = try? JSONDecoder().decode(Response.self, from: data),
              let text = response.choices.first?.message.content?.trimmingCharacters(in: .whitespacesAndNewlines),
              !text.isEmpty else { throw TalkError("文字服務未回傳內容。請確認模型支援 chat/completions。") }
        return text
    }

    private static func send(_ request: URLRequest, session: URLSession) async throws -> Data {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw TalkError("服務沒有回傳有效回應。") }
        guard (200..<300).contains(http.statusCode) else {
            let message: String
            switch http.statusCode {
            case 401, 403: message = "服務拒絕存取。請確認 API Key 與模型權限。"
            case 404: message = "找不到端點或模型。請確認服務網址包含 /v1 與模型名稱。"
            case 429: message = "服務額度或請求次數已達上限，請稍後重試。"
            default: message = "服務回應 HTTP \(http.statusCode)，請稍後重試。"
            }
            throw TalkError(message)
        }
        guard data.count <= 2_000_000 else { throw TalkError("服務回傳的內容過大。") }
        return data
    }
}
