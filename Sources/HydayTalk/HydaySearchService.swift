import Foundation
import TalkCore

/// Searches through the `hyday-kb` MCP server bundled in Hyday.app, launched the
/// same way as hyday-cli: Hyday's Electron binary runs as Node over stdio, with a
/// throwaway data folder, and only the read-only `search_notes` tool is called.
enum HydaySearchService {
    struct Unavailable: Error {}

    static func installation() -> (executable: URL, bundle: URL)? {
        for path in ["/Applications/Hyday.app", NSHomeDirectory() + "/Applications/Hyday.app"] {
            let app = URL(fileURLWithPath: path).resolvingSymlinksInPath()
            guard let info = NSDictionary(contentsOf: app.appendingPathComponent("Contents/Info.plist")),
                  info["CFBundleIdentifier"] as? String == "com.hyday.app" else { continue }
            let executable = app.appendingPathComponent("Contents/MacOS/Hyday")
            let bundle = app.appendingPathComponent("Contents/Resources/app.asar.unpacked/electron/dist/hyday-mcp.cjs")
            if FileManager.default.isExecutableFile(atPath: executable.path), FileManager.default.fileExists(atPath: bundle.path) {
                return (executable, bundle)
            }
        }
        return nil
    }

    /// Hyday's search first; the built-in keyword search when Hyday is missing or fails.
    static func notes(root: URL, query: String, limit: Int = 5) async -> [HydayNote] {
        if let notes = try? await search(root: root, query: query, timeout: 6), !notes.isEmpty {
            return Array(notes.prefix(limit))
        }
        return (try? await Task.detached(priority: .userInitiated) {
            try HydayNoteSearch.search(root: root, query: query, limit: limit)
        }.value) ?? []
    }

    static func search(root: URL, query: String, timeout: TimeInterval) async throws -> [HydayNote] {
        guard let (executable, bundle) = installation() else { throw Unavailable() }
        let runtime = FileManager.default.temporaryDirectory.appendingPathComponent("hyday-talk-mcp-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: runtime, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: runtime) }
        let process = Process()
        process.executableURL = executable
        process.arguments = [bundle.path, root.path]
        process.currentDirectoryURL = runtime
        process.environment = ["PATH": "/usr/bin:/bin", "LANG": "en_US.UTF-8",
                               "ELECTRON_RUN_AS_NODE": "1", "HYDAY_USER_DATA": runtime.path]
        let input = Pipe(), output = Pipe()
        process.standardInput = input; process.standardOutput = output
        process.standardError = FileHandle.nullDevice

        let text: String = try await withCheckedThrowingContinuation { continuation in
            final class State: @unchecked Sendable { let lock = NSLock(); var buffer = Data(); var done = false }
            let state = State()
            @Sendable func finish(_ result: Result<String, Error>) {
                state.lock.lock(); defer { state.lock.unlock() }
                guard !state.done else { return }
                state.done = true
                output.fileHandleForReading.readabilityHandler = nil
                if process.isRunning { process.terminate() }
                continuation.resume(with: result)
            }
            output.fileHandleForReading.readabilityHandler = { handle in
                let chunk = handle.availableData
                guard !chunk.isEmpty else { finish(.failure(Unavailable())); return }
                state.lock.lock(); state.buffer.append(chunk)
                var lines: [Data] = []
                while let newline = state.buffer.firstIndex(of: 0x0A) {
                    lines.append(state.buffer[state.buffer.startIndex..<newline])
                    state.buffer.removeSubrange(state.buffer.startIndex...newline)
                }
                let tooLarge = state.buffer.count > 8_000_000
                state.lock.unlock()
                if tooLarge { finish(.failure(Unavailable())); return }
                for line in lines {
                    guard let message = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                          message["id"] as? Int == 2 else { continue }
                    guard message["error"] == nil, let result = message["result"] as? [String: Any],
                          result["isError"] as? Bool != true, let blocks = result["content"] as? [[String: Any]]
                    else { finish(.failure(Unavailable())); return }
                    finish(.success(blocks.compactMap { $0["type"] as? String == "text" ? $0["text"] as? String : nil }
                        .joined(separator: "\n")))
                    return
                }
            }
            process.terminationHandler = { _ in finish(.failure(Unavailable())) }
            do { try process.run() } catch { finish(.failure(Unavailable())); return }
            // The server answers in order, so initialize and the search can go out together.
            let messages: [[String: Any]] = [
                ["jsonrpc": "2.0", "id": 1, "method": "initialize",
                 "params": ["protocolVersion": "2024-11-05", "capabilities": [:] as [String: Any],
                            "clientInfo": ["name": "hyday-talk", "version": "1"]]],
                ["jsonrpc": "2.0", "method": "notifications/initialized", "params": [:] as [String: Any]],
                ["jsonrpc": "2.0", "id": 2, "method": "tools/call",
                 "params": ["name": "search_notes", "arguments": ["query": query]]],
            ]
            var data = Data()
            for message in messages {
                guard let line = try? JSONSerialization.data(withJSONObject: message) else { continue }
                data.append(line); data.append(0x0A)
            }
            try? input.fileHandleForWriting.write(contentsOf: data)
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { finish(.failure(Unavailable())) }
        }
        try? input.fileHandleForWriting.close()

        guard let hits = try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [[String: Any]] else { throw Unavailable() }
        return hits.compactMap { hit in
            guard let path = hit["relPath"] as? String, path.lowercased().hasSuffix(".md"),
                  !path.split(separator: "/").contains(where: { $0 == "hyday-wiki" || $0 == ".." || $0.hasPrefix(".") })
            else { return nil }
            let name = ((path as NSString).lastPathComponent as NSString).deletingPathExtension
            let lines = (hit["lines"] as? [String])?.joined(separator: " ")
            let snippet = (hit["excerpt"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? lines ?? ""
            let title = (hit["title"] as? String).flatMap { $0.isEmpty ? nil : $0 } ?? name
            return HydayNote(title: title, path: path, snippet: String(snippet.prefix(240)))
        }
    }
}
