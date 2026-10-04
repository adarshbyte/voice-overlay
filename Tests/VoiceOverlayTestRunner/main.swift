import Foundation
import VoiceOverlayCore

@main
struct VoiceOverlayTestRunner {
    static func main() async {
        var failures = 0

        func check(_ condition: Bool, _ message: String, file: String = #fileID, line: Int = #line) {
            if !condition {
                failures += 1
                print("FAIL \(file):\(line) \(message)")
            }
        }

        func equal<T: Equatable>(_ actual: T, _ expected: T, _ message: String = "", file: String = #fileID, line: Int = #line) {
            check(actual == expected, "\(message) expected \(expected), got \(actual)", file: file, line: line)
        }

        // Fail before controller tests can clean up an unowned recording URL.
        do {
            let first = MockRecorder()
            let second = MockRecorder()
            check(first.stopURL != second.stopURL, "default mock recorders use distinct recording URLs")
            check(first.stopURL.deletingLastPathComponent() != second.stopURL.deletingLastPathComponent(),
                  "default mock recorders own distinct temporary directories")
            for recorder in [first, second] {
                let directory = recorder.stopURL.deletingLastPathComponent()
                equal(directory.deletingLastPathComponent().standardizedFileURL,
                      FileManager.default.temporaryDirectory.standardizedFileURL,
                      "mock recording directory is under the configured temporary directory")
                check(directory.lastPathComponent.hasPrefix("voice-overlay-mock-recorder-"),
                      "mock recording directory is test-owned")
                check(FileManager.default.fileExists(atPath: directory.path),
                      "mock recording directory exists")
            }
        }
        if failures > 0 {
            print("\(failures) test(s) failed")
            exit(1)
        }

        equal(ShortcutLabel.display(key: "V", control: true, option: true), "⌃⌥V", "record shortcut")
        equal(ShortcutLabel.display(key: "H", control: true, option: true), "⌃⌥H", "overlay shortcut")

        equal(Transcript.clean("  hello\n\n  world\t "), "hello world", "whitespace")
        equal(Transcript.clean("Hello, world."), "Hello, world.", "punctuation")
        equal(Transcript.clean(" \n\t "), "", "blank")
        check(!Transcript.isPasteable("   "), "blank is not pasteable")
        check(Transcript.isPasteable("go"), "text is pasteable")

        equal(
            NemoSpeechLocator.find(
                fileIsExecutable: { $0 == "/Users/me/.local/bin/nemo-speech" },
                envPath: "/usr/bin:/bin",
                home: "/Users/me"
            ),
            "/Users/me/.local/bin/nemo-speech",
            "local bin"
        )
        equal(
            NemoSpeechLocator.find(
                fileIsExecutable: { $0 == "/Users/me/Library/Application Support/NeMoSpeech/bin/nemo-speech" },
                envPath: "/usr/bin",
                home: "/Users/me"
            ),
            "/Users/me/Library/Application Support/NeMoSpeech/bin/nemo-speech",
            "app support"
        )
        equal(
            NemoSpeechLocator.find(
                fileIsExecutable: { $0 == "/opt/custom/nemo-speech" },
                envPath: "/opt/custom:/usr/bin",
                home: "/tmp/empty-home"
            ),
            "/opt/custom/nemo-speech",
            "PATH"
        )
        check(
            NemoSpeechLocator.find(fileIsExecutable: { _ in false }, envPath: "/usr/bin", home: "/tmp") == nil,
            "missing binary"
        )

        let runner = RecordingRunner(CommandResult(status: 0, stdout: "  Hello there. \n", stderr: ""))
        let transcriber = NemoSpeechTranscriber(executable: "/usr/bin/nemo-speech", runner: runner)
        do {
            let text = try transcriber.transcribe(file: URL(fileURLWithPath: "/tmp/clip.wav"))
            equal(text, "Hello there.", "transcript")
            equal(runner.lastExecutable, "/usr/bin/nemo-speech", "executable")
            equal(runner.lastArguments, ["--quiet", "transcribe", "/tmp/clip.wav"], "args")
        } catch {
            check(false, "unexpected transcribe error \(error)")
        }

        equal(TalkLanguage.auto.nemoSpeechFlags, [], "auto has no language flags")
        equal(TalkLanguage.english.nemoSpeechFlags, ["--language", "en"], "english flags")
        let englishRunner = RecordingRunner(CommandResult(status: 0, stdout: "Please find the update attached.\n", stderr: ""))
        let englishTranscriber = NemoSpeechTranscriber(executable: "/usr/bin/nemo-speech", runner: englishRunner)
        do {
            let text = try englishTranscriber.transcribe(file: URL(fileURLWithPath: "/tmp/clip.wav"), language: .english)
            equal(text, "Please find the update attached.", "english transcript")
            equal(
                englishRunner.lastArguments,
                ["--quiet", "transcribe", "/tmp/clip.wav", "--language", "en"],
                "english args"
            )
        } catch {
            check(false, "unexpected english transcribe error \(error)")
        }

        let failing = RecordingRunner(CommandResult(status: 1, stdout: "", stderr: "  model missing \n"))
        let failingTranscriber = NemoSpeechTranscriber(executable: "nemo-speech", runner: failing)
        do {
            _ = try failingTranscriber.transcribe(file: URL(fileURLWithPath: "/tmp/clip.wav"))
            check(false, "expected transcription error")
        } catch let error as TranscriptionError {
            equal(error, TranscriptionError("model missing"), "error message")
        } catch {
            check(false, "wrong error type \(error)")
        }

        let board = Store("old")
        let pasted = Store(nil)
        let paster = ClipboardPaster(
            restoreDelayNanoseconds: 0,
            readPasteboard: { board.value },
            writePasteboard: { board.value = $0 },
            poster: RecordingPoster(store: board, pasted: pasted)
        )
        do {
            try await paster.paste("hello from nemotron")
            equal(pasted.value, "hello from nemotron", "pasted value")
            equal(board.value, "old", "restored clipboard")
        } catch {
            check(false, "paste failed \(error)")
        }

        await MainActor.run {
            let recorder = MockRecorder()
            let focus = MockFocus()
            let controller = OverlayController(
                recorder: recorder,
                transcriber: MockTranscriber(result: .success("hi")),
                paster: MockPaster(),
                focus: focus
            )
            equal(controller.phase, .idle, "idle")
            controller.toggle()
            equal(controller.phase, .recording, "recording")
            equal(controller.talkLanguage, .auto, "default language")
            check(recorder.started, "recorder started")
            check(focus.remembered == 1, "remembers target app on record")
        }

        await MainActor.run {
            let controller = OverlayController(
                recorder: MockRecorder(),
                transcriber: MockTranscriber(result: .success("hi")),
                paster: MockPaster()
            )
            controller.startRecording(language: .english)
            equal(controller.talkLanguage, .english, "english recording language")
            controller.cancel()
            equal(controller.talkLanguage, .auto, "cancel clears language")
        }

        await MainActor.run {
            let recorder = MockRecorder()
            let mockPaster = MockPaster()
            let controller = OverlayController(
                recorder: recorder,
                transcriber: MockTranscriber(result: .success("hi")),
                paster: mockPaster
            )
            controller.toggle()
            controller.cancel()
            equal(controller.phase, .idle, "cancelled idle")
            check(recorder.cancelled, "cancelled recorder")
            check(mockPaster.pasted.isEmpty, "cancel does not paste")
        }

        let pasteRecorder = MockRecorder()
        let pastePaster = MockPaster()
        let pasteFocus = MockFocus()
        let pasteController = await MainActor.run {
            OverlayController(
                recorder: pasteRecorder,
                transcriber: MockTranscriber(result: .success("  Hello world \n")),
                paster: pastePaster,
                focus: pasteFocus
            )
        }
        await MainActor.run { pasteController.startRecording() }
        await pasteController.stopAndTranscribe()
        await MainActor.run {
            equal(pastePaster.pasted, ["Hello world"], "pasted transcript")
            equal(pasteController.lastTranscript, "Hello world", "last transcript")
            equal(pasteController.phase, .idle, "back to idle")
            equal(pasteFocus.restored, 1, "restores target before paste")
        }

        let englishSpy = MockTranscriber(result: .success("Please review the attached update."))
        let englishController = await MainActor.run {
            OverlayController(
                recorder: MockRecorder(),
                transcriber: englishSpy,
                paster: MockPaster()
            )
        }
        await MainActor.run { englishController.startRecording(language: .english) }
        await englishController.stopAndTranscribe()
        await MainActor.run {
            equal(englishSpy.lastLanguage, .english, "stop uses english language")
            equal(englishController.talkLanguage, .auto, "language resets after paste")
        }

        let silentPaster = MockPaster()
        let silentController = await MainActor.run {
            OverlayController(
                recorder: MockRecorder(),
                transcriber: MockTranscriber(result: .success("   ")),
                paster: silentPaster
            )
        }
        await MainActor.run { silentController.startRecording() }
        await silentController.stopAndTranscribe()
        await MainActor.run {
            check(silentPaster.pasted.isEmpty, "silence does not paste")
            equal(silentController.phase, .failed("Heard silence. Try again."), "silence failure")
        }

        let errorPaster = MockPaster()
        let errorController = await MainActor.run {
            OverlayController(
                recorder: MockRecorder(),
                transcriber: MockTranscriber(result: .failure(TranscriptionError("model missing"))),
                paster: errorPaster
            )
        }
        await MainActor.run { errorController.startRecording() }
        await errorController.stopAndTranscribe()
        await MainActor.run {
            check(errorPaster.pasted.isEmpty, "error does not paste")
            equal(errorController.phase, .failed("model missing"), "error phase")
        }

        // Recordings and prepared audio must not accumulate after any outcome.
        let cleanupDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("voice-overlay-tests-\(UUID().uuidString)", isDirectory: true)
        try! FileManager.default.createDirectory(at: cleanupDirectory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: cleanupDirectory) }
        for outcome in ["success", "transcriber-error", "silence"] {
            let rawURL = cleanupDirectory.appendingPathComponent("\(outcome).wav")
            let preparedURL = cleanupDirectory.appendingPathComponent("\(outcome)-prep.wav")
            let samples: [Int16] = outcome == "silence" ? [0, 0, 0] : [2000, -2000, 2000]
            try! PcmWav(sampleRate: 16000, channels: 1, samples: samples).write(to: rawURL)
            let cleanupController = await MainActor.run {
                let recorder = MockRecorder()
                recorder.stopURL = rawURL
                return OverlayController(
                    recorder: recorder,
                    transcriber: MockTranscriber(result: outcome == "transcriber-error"
                        ? .failure(TranscriptionError("model missing")) : .success("hello")),
                    paster: MockPaster(),
                    prep: WavSilencePrep()
                )
            }
            await MainActor.run { cleanupController.startRecording() }
            await cleanupController.stopAndTranscribe()
            check(!FileManager.default.fileExists(atPath: rawURL.path), "\(outcome) removes recording")
            check(!FileManager.default.fileExists(atPath: preparedURL.path), "\(outcome) removes prepared audio")
        }

        check(OverlayPhase.transcribing.isBusy, "transcribing busy")
        check(OverlayPhase.pasting.isBusy, "pasting busy")
        check(!OverlayPhase.idle.isBusy, "idle not busy")
        equal(OverlayPhase.idle.statusText, "Click to talk")
        equal(OverlayPhase.recording.statusText, "Listening…")

        await MainActor.run {
            struct Boom: LocalizedError {
                var errorDescription: String? { "mic denied" }
            }
            let recorder = MockRecorder()
            recorder.startError = Boom()
            let controller = OverlayController(
                recorder: recorder,
                transcriber: MockTranscriber(result: .success("hi")),
                paster: MockPaster()
            )
            controller.toggle()
            equal(controller.phase, .failed("mic denied"), "mic failure")
        }

        let quiet = [Int16](repeating: 40, count: 16000)
        let speech = (0..<8000).map { Int16(($0 * 13) % 4000) }
        let padded = quiet + speech + quiet
        let trimmed = SampleTrim.trim(padded, frameSize: 320, threshold: 800, padSamples: 320)
        check(!trimmed.isEmpty, "trim keeps speech")
        check(trimmed.count < padded.count, "trim shortens padded audio")
        check(SampleTrim.trim(quiet, threshold: 800).isEmpty, "quiet audio trims to empty")

        let wav = PcmWav(sampleRate: 16000, channels: 1, samples: speech)
        let encoded = wav.encode()
        let decoded = try! PcmWav.decode(encoded)
        equal(decoded.sampleRate, 16000, "wav rate")
        equal(decoded.channels, 1, "wav channels")
        equal(decoded.samples, speech, "wav roundtrip")

        let extremes: [Int16] = [Int16.min, Int16.max, 0]
        equal(SampleTrim.trim(extremes, frameSize: 1, padSamples: 0), [Int16.min, Int16.max], "full-scale PCM does not overflow")
        equal(SampleTrim.normalize(extremes), extremes, "full-scale PCM normalization does not overflow")

        let boosted = SampleTrim.normalize([0, 1000, -1000], targetPeak: 28000)
        check(abs(Int(boosted.map { abs($0) }.max() ?? 0) - 28000) < 5, "normalize reaches target peak")

        do {
            let chunk = String(repeating: "x", count: 128)
            let script = "i=0; while [ $i -lt 2048 ]; do printf '%s' '\(chunk)'; printf '%s' '\(chunk)' >&2; i=$((i + 1)); done"
            let result = try ProcessCommandRunner().run(executable: "/bin/sh", arguments: ["-c", script])
            equal(result.status, 0, "large-output subprocess exits")
            check(result.stdout == String(repeating: "x", count: 262144), "captures complete large stdout")
            check(result.stderr == String(repeating: "x", count: 262144), "captures complete large stderr")
        } catch {
            check(false, "large-output subprocess failed: \(error)")
        }

        if failures > 0 {
            print("\(failures) test(s) failed")
            exit(1)
        }
        print("All tests passed")
    }
}

private final class RecordingRunner: CommandRunning, @unchecked Sendable {
    var result: CommandResult
    var lastExecutable: String?
    var lastArguments: [String]?

    init(_ result: CommandResult) {
        self.result = result
    }

    func run(executable: String, arguments: [String]) throws -> CommandResult {
        lastExecutable = executable
        lastArguments = arguments
        return result
    }
}

private final class Store: @unchecked Sendable {
    var value: String?
    init(_ value: String?) { self.value = value }
}

private struct RecordingPoster: CommandVPoster {
    let store: Store
    let pasted: Store
    func pasteCommandV() {
        pasted.value = store.value
    }
}

private final class MockRecorder: AudioRecorder {
    private let recordingDirectory: URL
    var started = false
    var cancelled = false
    var stopURL: URL
    var startError: Error?

    init() {
        recordingDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("voice-overlay-mock-recorder-\(UUID().uuidString)", isDirectory: true)
        try! FileManager.default.createDirectory(at: recordingDirectory, withIntermediateDirectories: true)
        stopURL = recordingDirectory.appendingPathComponent("\(UUID().uuidString).wav")
    }

    deinit {
        try? FileManager.default.removeItem(at: recordingDirectory)
    }

    func start() throws {
        if let startError { throw startError }
        started = true
        cancelled = false
    }

    func stop() throws -> URL {
        started = false
        return stopURL
    }

    func cancel() {
        started = false
        cancelled = true
    }
}

private final class MockTranscriber: SpeechTranscriber, @unchecked Sendable {
    var result: Result<String, Error>
    var lastLanguage: TalkLanguage?
    init(result: Result<String, Error>) {
        self.result = result
    }
    func transcribe(file: URL, language: TalkLanguage) throws -> String {
        lastLanguage = language
        return try result.get()
    }
}

private final class MockPaster: TextPaster, @unchecked Sendable {
    var pasted: [String] = []
    func paste(_ text: String) async throws {
        pasted.append(text)
    }
}

private final class MockFocus: FocusPreserver {
    var remembered = 0
    var restored = 0
    func rememberTarget() { remembered += 1 }
    func restoreTarget() { restored += 1 }
}
