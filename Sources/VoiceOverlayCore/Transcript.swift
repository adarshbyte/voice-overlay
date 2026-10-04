import Foundation

public enum Transcript {
    /// Normalizes ASR output into a single pasteable line of text.
    public static func clean(_ raw: String) -> String {
        let collapsed = raw
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return collapsed
    }

    public static func isPasteable(_ text: String) -> Bool {
        !clean(text).isEmpty
    }
}
