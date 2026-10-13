import Foundation
import Darwin

public enum ProcessRunner {
    public static func run(executable: String, arguments: [String], input: String? = nil,
                           timeout: TimeInterval = 120) async throws -> String {
        let invocation = Invocation()
        return try await withTaskCancellationHandler(operation: {
            try await withCheckedThrowingContinuation { continuation in
                invocation.start(executable: executable, arguments: arguments, input: input,
                                 timeout: timeout, continuation: continuation)
            }
        }, onCancel: { invocation.cancel() })
    }

    private final class Invocation: @unchecked Sendable {
        private let lock = NSLock()
        private var pid: pid_t?
        private var cancellation: Error?

        func cancel() { stop(error: CancellationError()) }
        private func stop(error: Error) {
            lock.lock()
            if cancellation == nil { cancellation = error }
            let running = pid
            lock.unlock()
            guard let running else { return }
            // Each CLI owns a process group, so cancellation also stops wrapper children.
            kill(-running, SIGTERM)
            DispatchQueue.global().asyncAfter(deadline: .now() + 1) { [self] in
                lock.lock(); let stillRunning = pid == running; lock.unlock()
                if stillRunning { kill(-running, SIGKILL) }
            }
        }

        func start(executable: String, arguments: [String], input: String?, timeout: TimeInterval,
                   continuation: CheckedContinuation<String, Error>) {
            DispatchQueue.global(qos: .userInitiated).async { [self] in
                let path = (executable as NSString).expandingTildeInPath
                guard path.hasPrefix("/"), !path.contains("\0"), !arguments.contains(where: { $0.contains("\0") }),
                      FileManager.default.isExecutableFile(atPath: path) else {
                    continuation.resume(throwing: TalkError("找不到可執行的 CLI。請選擇工具的完整路徑。")); return
                }
                let stdout = Pipe(); let stderr = Pipe(); let stdin = Pipe()
                _ = fcntl(stdin.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)
                // GUI apps inherit a minimal PATH; allow the installed tool to find its own dependencies.
                var environment = ProcessInfo.processInfo.environment
                environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:" + (environment["PATH"] ?? "")
                lock.lock()
                if let error = cancellation {
                    lock.unlock(); continuation.resume(throwing: error); return
                }
                var child: pid_t = 0
                let status = Self.spawn(path: path, arguments: arguments, environment: environment,
                                        stdin: stdin, stdout: stdout, stderr: stderr, pid: &child)
                guard status == 0 else {
                    lock.unlock()
                    continuation.resume(throwing: TalkError("無法啟動 CLI。請確認工具可執行，且相依環境已安裝。")); return
                }
                pid = child
                lock.unlock()
                try? stdin.fileHandleForReading.close()
                try? stdout.fileHandleForWriting.close()
                try? stderr.fileHandleForWriting.close()
                let watchdog = DispatchWorkItem { [self] in stop(error: TalkError("CLI 執行逾時。請確認工具不會等待互動輸入。")) }
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: watchdog)
                let group = DispatchGroup(); let output = Buffer(); let diagnostics = Buffer()
                for (handle, buffer) in [(stdout.fileHandleForReading, output), (stderr.fileHandleForReading, diagnostics)] {
                    group.enter()
                    DispatchQueue.global().async { [self] in
                        defer { group.leave() }
                        while true {
                            let data = handle.availableData
                            if data.isEmpty { break }
                            guard buffer.append(data) else {
                                stop(error: TalkError("CLI 輸出過大。請設定為只輸出辨識或整理後的文字。")); break
                            }
                        }
                    }
                }
                DispatchQueue.global().async {
                    if let input { try? stdin.fileHandleForWriting.write(contentsOf: Data(input.utf8)) }
                    try? stdin.fileHandleForWriting.close()
                }
                var exitStatus: Int32 = 0
                while waitpid(child, &exitStatus, 0) == -1 && errno == EINTR {}
                group.wait(); watchdog.cancel()
                lock.lock(); let error = cancellation; pid = nil; lock.unlock()
                if let error { continuation.resume(throwing: error); return }
                let exitCode = (exitStatus >> 8) & 0xff
                let signal = exitStatus & 0x7f
                guard exitCode == 0, signal == 0 else {
                    continuation.resume(throwing: TalkError("CLI 以代碼 \(signal == 0 ? exitCode : 128 + signal) 結束。請在終端機確認路徑、模型與參數。")); return
                }
                let text = String(decoding: output.data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
                continuation.resume(returning: text)
            }
        }

        private static func spawn(path: String, arguments: [String], environment: [String: String],
                                  stdin: Pipe, stdout: Pipe, stderr: Pipe, pid: inout pid_t) -> Int32 {
            var attributes: posix_spawnattr_t?
            var actions: posix_spawn_file_actions_t?
            guard posix_spawnattr_init(&attributes) == 0 else { return ENOMEM }
            defer { posix_spawnattr_destroy(&attributes) }
            guard posix_spawn_file_actions_init(&actions) == 0 else { return ENOMEM }
            defer { posix_spawn_file_actions_destroy(&actions) }
            posix_spawnattr_setflags(&attributes, Int16(POSIX_SPAWN_SETPGROUP | POSIX_SPAWN_CLOEXEC_DEFAULT))
            posix_spawnattr_setpgroup(&attributes, 0)
            posix_spawn_file_actions_adddup2(&actions, stdin.fileHandleForReading.fileDescriptor, STDIN_FILENO)
            posix_spawn_file_actions_adddup2(&actions, stdout.fileHandleForWriting.fileDescriptor, STDOUT_FILENO)
            posix_spawn_file_actions_adddup2(&actions, stderr.fileHandleForWriting.fileDescriptor, STDERR_FILENO)
            return cStrings([path] + arguments) { argv in
                cStrings(environment.map { "\($0.key)=\($0.value)" }) { envp in
                    posix_spawn(&pid, path, &actions, &attributes, argv, envp)
                }
            }
        }
        private static func cStrings<T>(_ strings: [String], body: (UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>) -> T) -> T {
            var pointers = strings.map { strdup($0) } + [nil]
            defer { pointers.forEach { free($0) } }
            return pointers.withUnsafeMutableBufferPointer { body($0.baseAddress!) }
        }
    }

    private final class Buffer: @unchecked Sendable {
        private let lock = NSLock(); private var storage = Data()
        var data: Data { lock.lock(); defer { lock.unlock() }; return storage }
        func append(_ data: Data) -> Bool {
            lock.lock(); defer { lock.unlock() }
            guard storage.count + data.count <= 2_000_000 else { return false }
            storage.append(data); return true
        }
    }
}
