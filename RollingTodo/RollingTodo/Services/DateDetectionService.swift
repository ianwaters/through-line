import Foundation

/// Detects natural-language dates in a stretch of text using `NSDataDetector`.
/// Pure, side-effect free — easy to unit-test against a fixed `now`.
enum DateDetectionService {
    /// Returns the earliest *future* date detected in `text`, or `nil` if none.
    /// Filters out:
    ///   - past dates (relative to `now`),
    ///   - range matches whose start is in the past (`duration > 0` with stale start).
    static func detect(in text: String, now: Date = .now) -> Date? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) else {
            return nil
        }
        let range = NSRange(trimmed.startIndex..., in: trimmed)
        let matches = detector.matches(in: trimmed, options: [], range: range)

        var candidates: [Date] = []
        for match in matches {
            guard match.resultType == .date, let d = match.date else { continue }
            // Range matches: ignore if the range's start is already past — the
            // user is referencing history.
            if match.duration > 0 && d < now { continue }
            // Single dates strictly in the past are dropped.
            if d <= now { continue }
            candidates.append(d)
        }

        return candidates.min()
    }
}
