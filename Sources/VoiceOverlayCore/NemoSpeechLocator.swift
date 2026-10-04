import Foundation

public enum NemoSpeechLocator {
    public static let binaryName = "nemo-speech"

    public static func find(
        fileIsExecutable: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) },
        envPath: String? = ProcessInfo.processInfo.environment["PATH"],
        home: String = NSHomeDirectory()
    ) -> String? {
        var candidates: [String] = [
            "\(home)/.local/bin/\(binaryName)",
            "\(home)/Library/Application Support/NeMoSpeech/bin/\(binaryName)",
            "/opt/homebrew/bin/\(binaryName)",
            "/usr/local/bin/\(binaryName)",
        ]

        let pathParts = (envPath ?? "").split(separator: ":").map(String.init)
        for dir in pathParts {
            candidates.append("\(dir)/\(binaryName)")
        }

        var seen = Set<String>()
        for path in candidates where seen.insert(path).inserted {
            if fileIsExecutable(path) {
                return path
            }
        }
        return nil
    }
}
