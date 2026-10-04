import Foundation

@MainActor
public final class OverlayController {
    public private(set) var phase: OverlayPhase = .idle {
        didSet { onPhaseChange?(phase) }
    }
    public private(set) var lastTranscript: String = ""
    public private(set) var talkLanguage: TalkLanguage = .auto
    public var onPhaseChange: ((OverlayPhase) -> Void)?

    private let recorder: any AudioRecorder
    private let transcriber: any SpeechTranscriber
    private let paster: any TextPaster
    private let prep: any AudioPreparing
    private let focus: any FocusPreserver

    public init(
        recorder: any AudioRecorder,
        transcriber: any SpeechTranscriber,
        paster: any TextPaster,
        prep: any AudioPreparing = IdentityAudioPrep(),
        focus: any FocusPreserver = NoopFocusPreserver()
    ) {
        self.recorder = recorder
        self.transcriber = transcriber
        self.paster = paster
        self.prep = prep
        self.focus = focus
    }

    public func toggle() {
        switch phase {
        case .idle, .failed:
            startRecording()
        case .recording:
            Task { await stopAndTranscribe() }
        case .transcribing, .pasting:
            break
        }
    }

    public func cancel() {
        guard phase == .recording else { return }
        recorder.cancel()
        talkLanguage = .auto
        phase = .idle
    }

    public func startRecording(language: TalkLanguage = .auto) {
        do {
            talkLanguage = language
            focus.rememberTarget()
            try recorder.start()
            phase = .recording
        } catch {
            talkLanguage = .auto
            phase = .failed(error.localizedDescription)
        }
    }

    public func stopAndTranscribe() async {
        guard phase == .recording else { return }
        phase = .transcribing
        do {
            let url = try recorder.stop()
            var audioFiles = [url]
            defer {
                for file in Set(audioFiles) {
                    try? FileManager.default.removeItem(at: file)
                }
            }
            let prepared = try prep.prepare(url: url)
            audioFiles.append(prepared)
            let transcriber = self.transcriber
            let language = talkLanguage
            let raw = try await Task.detached {
                try transcriber.transcribe(file: prepared, language: language)
            }.value
            let text = Transcript.clean(raw)
            lastTranscript = text
            guard Transcript.isPasteable(text) else {
                fail("Heard silence. Try again.")
                return
            }
            phase = .pasting
            focus.restoreTarget()
            try await paster.paste(text)
            talkLanguage = .auto
            phase = .idle
        } catch {
            fail(error.localizedDescription)
        }
    }

    private func fail(_ message: String) {
        talkLanguage = .auto
        phase = .failed(message)
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            if case .failed = self?.phase {
                self?.phase = .idle
            }
        }
    }
}
