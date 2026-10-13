import Foundation

public enum SpeechCLIConfiguration {
    public static func isWhisper(_ executable: String) -> Bool {
        URL(fileURLWithPath: executable).lastPathComponent == "whisper-cli"
    }

    public static func whisperArguments(modelPath: String) -> String {
        let expanded = (modelPath as NSString).expandingTildeInPath
        let escaped = expanded.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return "-m \"\(escaped)\" -f \"{audio}\" -l {language} -nt -np"
    }

    public static func whisperModelPath(arguments: String) -> String? {
        guard let parsed = try? CLIArguments.parse(arguments) else { return nil }
        return modelPath(in: parsed)
    }

    public static func isReadableModel(_ path: String) -> Bool {
        let expanded = (path as NSString).expandingTildeInPath
        guard expanded.hasPrefix("/"), FileManager.default.isReadableFile(atPath: expanded) else { return false }
        let values = try? URL(fileURLWithPath: expanded).resolvingSymlinksInPath()
            .resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey])
        return values?.isRegularFile == true && (values?.fileSize ?? 0) > 0
    }

    public static func validate(_ settings: TalkSettings) throws {
        guard CLIExecutableDiscovery.isExecutable(settings.speechCLIExecutable) else {
            throw TalkError("請先選擇辨識 CLI 的可執行檔。")
        }
        let arguments = try CLIArguments.parse(settings.speechCLIArguments)
        guard arguments.contains(where: { $0.contains("{audio}") }) else {
            throw TalkError("辨識 CLI 參數需包含 {audio}，以接收錄音檔。")
        }
        guard isWhisper(settings.speechCLIExecutable) else { return }
        guard let model = modelPath(in: arguments), !model.isEmpty else {
            throw TalkError("Whisper 尚未指定模型，請選擇模型檔後套用建議參數。")
        }
        guard model.hasPrefix("/"), isReadableModel(model) else {
            throw TalkError("Whisper 模型檔無法讀取，請選擇有效模型並套用建議參數。")
        }
    }

    private static func modelPath(in arguments: [String]) -> String? {
        var result: String?
        for index in arguments.indices where ["-m", "--model"].contains(arguments[index]) {
            guard index + 1 < arguments.count, !arguments[index + 1].hasPrefix("-") else { return nil }
            result = arguments[index + 1]
        }
        return result
    }
}
