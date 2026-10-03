import AVFoundation
import Foundation
import VoiceOverlayCore

enum RecorderError: LocalizedError {
    case microphoneDenied
    case alreadyRecording
    case notRecording
    case engineFailed(String)

    var errorDescription: String? {
        switch self {
        case .microphoneDenied:
            return "Microphone access is required. Enable it in System Settings → Privacy & Security → Microphone."
        case .alreadyRecording:
            return "Already recording."
        case .notRecording:
            return "Not recording."
        case .engineFailed(let message):
            return message
        }
    }
}

@MainActor
final class AVRecorder: AudioRecorder {
    private var recorder: AVAudioRecorder?
    private var outputURL: URL?

    func start() throws {
        if recorder?.isRecording == true {
            throw RecorderError.alreadyRecording
        }
        if AVCaptureDevice.authorizationStatus(for: .audio) == .denied {
            throw RecorderError.microphoneDenied
        }

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("voice-overlay-\(UUID().uuidString).wav")
        let settings: [String: Any] = [
            AVFormatIDKey: Int(kAudioFormatLinearPCM),
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
        ]

        let rec: AVAudioRecorder
        do {
            rec = try AVAudioRecorder(url: url, settings: settings)
        } catch {
            throw RecorderError.engineFailed(error.localizedDescription)
        }
        rec.prepareToRecord()
        guard rec.record() else {
            throw RecorderError.engineFailed("Could not start the microphone.")
        }
        recorder = rec
        outputURL = url
    }

    func stop() throws -> URL {
        guard let recorder, let outputURL else {
            throw RecorderError.notRecording
        }
        recorder.stop()
        self.recorder = nil
        self.outputURL = nil
        return outputURL
    }

    func cancel() {
        recorder?.stop()
        if let outputURL {
            try? FileManager.default.removeItem(at: outputURL)
        }
        recorder = nil
        self.outputURL = nil
    }
}

enum MicrophoneAuth {
    static func ensureAllowed() async throws {
        let granted = await AVCaptureDevice.requestAccess(for: .audio)
        if !granted {
            throw RecorderError.microphoneDenied
        }
    }
}
