import Foundation

public struct TranscriptionError: Error, Equatable, LocalizedError {
    public let message: String
    public var errorDescription: String? { message }

    public init(_ message: String) {
        self.message = message
    }
}

public enum TalkLanguage: Equatable, Sendable {
    case auto
    case english

    public var nemoSpeechFlags: [String] {
        switch self {
        case .auto:
            []
        case .english:
            ["--language", "en"]
        }
    }
}

public protocol SpeechTranscriber: Sendable {
    func transcribe(file: URL, language: TalkLanguage) throws -> String
}

/// Wraps NVIDIA `nemo-speech` (Nemotron ASR) for file transcription.
public struct NemoSpeechTranscriber: SpeechTranscriber {
    public var executable: String
    public var extraArguments: [String]
    public var runner: any CommandRunning

    public init(
        executable: String,
        extraArguments: [String] = ["--quiet"],
        runner: any CommandRunning = ProcessCommandRunner()
    ) {
        self.executable = executable
        self.extraArguments = extraArguments
        self.runner = runner
    }

    public func transcribe(file: URL, language: TalkLanguage = .auto) throws -> String {
        let arguments = extraArguments + ["transcribe", file.path] + language.nemoSpeechFlags
        let result = try runner.run(executable: executable, arguments: arguments)
        if result.status != 0 {
            let detail = Transcript.clean(result.stderr.isEmpty ? result.stdout : result.stderr)
            throw TranscriptionError(detail.isEmpty ? "Nemotron transcription failed." : detail)
        }
        return Transcript.clean(result.stdout)
    }
}
