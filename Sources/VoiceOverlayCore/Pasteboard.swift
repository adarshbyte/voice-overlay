public protocol StringPasteboard: AnyObject {
    var string: String? { get set }
}

public protocol CommandVPoster: Sendable {
    func pasteCommandV()
}

public protocol TextPaster: Sendable {
    func paste(_ text: String) async throws
}

public struct ClipboardPaster: TextPaster {
    public let restoreDelayNanoseconds: UInt64
    private let readPasteboard: @Sendable () -> String?
    private let writePasteboard: @Sendable (String?) -> Void
    private let poster: any CommandVPoster

    public init(
        restoreDelayNanoseconds: UInt64 = 400_000_000,
        readPasteboard: @escaping @Sendable () -> String?,
        writePasteboard: @escaping @Sendable (String?) -> Void,
        poster: any CommandVPoster
    ) {
        self.restoreDelayNanoseconds = restoreDelayNanoseconds
        self.readPasteboard = readPasteboard
        self.writePasteboard = writePasteboard
        self.poster = poster
    }

    public func paste(_ text: String) async throws {
        let previous = readPasteboard()
        writePasteboard(text)
        poster.pasteCommandV()
        if restoreDelayNanoseconds > 0 {
            try await Task.sleep(nanoseconds: restoreDelayNanoseconds)
        }
        writePasteboard(previous)
    }
}
