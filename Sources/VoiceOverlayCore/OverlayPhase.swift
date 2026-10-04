public enum OverlayPhase: Equatable, Sendable {
    case idle
    case recording
    case transcribing
    case pasting
    case failed(String)

    public var isBusy: Bool {
        switch self {
        case .transcribing, .pasting: true
        default: false
        }
    }

    public var statusText: String {
        switch self {
        case .idle: "Click to talk"
        case .recording: "Listening…"
        case .transcribing: "Transcribing…"
        case .pasting: "Pasting…"
        case .failed(let message): message
        }
    }
}
