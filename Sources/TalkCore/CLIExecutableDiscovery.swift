import Foundation

public struct CLIExecutableChoice: Identifiable, Equatable, Sendable {
    public let path: String
    public var id: String { path }
    public var name: String { URL(fileURLWithPath: path).lastPathComponent }
    public var directory: String { URL(fileURLWithPath: path).deletingLastPathComponent().path }
    public init(path: String) { self.path = path }
}

public enum CLIExecutableDiscovery {
    // Only speech tools belong here; macOS's "asr" is a disk restore utility.
    public static let speechToolNames = ["whisper-cli", "parakeet-cli", "whisper", "mlx_whisper", "parakeet-mlx"]

    public static func searchDirectories(environment: [String: String] = ProcessInfo.processInfo.environment,
                                         home: URL = FileManager.default.homeDirectoryForCurrentUser) -> [String] {
        let paths = (environment["PATH"] ?? "").components(separatedBy: ":")
            + ["/opt/homebrew/bin", "/usr/local/bin", home.appendingPathComponent(".local/bin").path,
               home.appendingPathComponent("bin").path, home.appendingPathComponent(".cargo/bin").path]
        var seen = Set<String>()
        return paths.compactMap { path in
            guard path.hasPrefix("/") else { return nil }
            let normalized = URL(fileURLWithPath: path).standardizedFileURL.path
            return seen.insert(normalized).inserted ? normalized : nil
        }
    }

    public static func isExecutable(_ path: String, fileManager: FileManager = .default) -> Bool {
        let expanded = (path as NSString).expandingTildeInPath
        guard expanded.hasPrefix("/"), fileManager.isExecutableFile(atPath: expanded) else { return false }
        // Executable permissions on directories do not make them runnable files.
        let values = try? URL(fileURLWithPath: expanded).resolvingSymlinksInPath().resourceValues(forKeys: [.isRegularFileKey])
        return values?.isRegularFile == true
    }

    public static func speechTools(in directories: [String] = searchDirectories(),
                                   including configuredPath: String = "") -> [CLIExecutableChoice] {
        var paths: [String] = []
        var seen = Set<String>()
        func include(_ path: String) {
            let expanded = (path as NSString).expandingTildeInPath
            guard isExecutable(expanded) else { return }
            let normalized = URL(fileURLWithPath: expanded).standardizedFileURL.path
            if seen.insert(normalized).inserted { paths.append(normalized) }
        }
        // Preserve a user's custom wrapper even if it is outside the search directories.
        include(configuredPath)
        for directory in directories where directory.hasPrefix("/") {
            for name in speechToolNames {
                include(URL(fileURLWithPath: directory).appendingPathComponent(name).path)
            }
        }
        // Keep stable symlink paths (e.g. Homebrew's bin directory) across tool updates.
        return paths.map(CLIExecutableChoice.init(path:))
    }
}
