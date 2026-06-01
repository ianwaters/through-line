import Foundation
import FoundationModels
import os

/// Wraps Apple's on-device Foundation Models. Singleton, MainActor, @Observable
/// so views can hide AI affordances on devices that don't support Apple
/// Intelligence (`isAvailable == false`) without showing broken UI.
@MainActor
@Observable
final class IntelligenceService {
    static let shared = IntelligenceService()

    private(set) var availability: SystemLanguageModel.Availability = .unavailable(.modelNotReady)

    /// Mirrors `CloudSyncMonitor.RecheckPhase` so the Settings re-check button
    /// can show the same spinner / "Result unchanged" / "Updated" feedback.
    enum RecheckPhase: Equatable {
        case idle
        case checking
        case settled(unchanged: Bool)
    }

    private(set) var recheckPhase: RecheckPhase = .idle
    private var recheckResetTask: Task<Void, Never>?

    var isAvailable: Bool {
        if case .available = availability { return true }
        return false
    }

    /// Human-readable note explaining why intelligence isn't available, or nil
    /// when it is. Surfaced in Settings so users can self-diagnose missing
    /// AI affordances.
    var availabilityNote: String? {
        switch availability {
        case .available:
            return nil
        case .unavailable(let reason):
            switch reason {
            case .deviceNotEligible:
                return "This device doesn't support Apple Intelligence."
            case .appleIntelligenceNotEnabled:
                return "Apple Intelligence is turned off. Enable it in System Settings → Apple Intelligence & Siri."
            case .modelNotReady:
                return "Apple Intelligence is still preparing. Model assets may be downloading — check back in a few minutes."
            @unknown default:
                return "Apple Intelligence isn't available on this device."
            }
        @unknown default:
            return "Apple Intelligence status couldn't be determined."
        }
    }

    private init() {
        // Read availability off the main actor — `SystemLanguageModel.default`
        // can synchronously block on first access while the FoundationModels
        // service registers the app's entitlement (observed on iOS TestFlight
        // builds; long enough to risk the launch watchdog). Doing this on a
        // detached utility-priority task keeps the main thread free during
        // launch; the cached result is published back via `MainActor.run`.
        Task.detached(priority: .utility) { [weak self] in
            let value = SystemLanguageModel.default.availability
            await MainActor.run { [weak self] in
                self?.availability = value
            }
        }
    }

    /// Re-reads availability from FoundationModels. Always runs the
    /// (synchronous) property read on a detached task — even post-launch
    /// re-checks have been seen to block briefly on the main actor.
    func refreshAvailability() async {
        let value = await Task.detached(priority: .utility) {
            SystemLanguageModel.default.availability
        }.value
        availability = value
    }

    /// Re-checks availability and drives the Settings button feedback. The
    /// underlying read is synchronous; we hold `.checking` for ~250ms so the
    /// spinner is always visible.
    func recheckAvailability() async {
        recheckResetTask?.cancel()
        let priorIsAvailable = isAvailable
        let priorNote = availabilityNote
        recheckPhase = .checking
        let startedAt = Date()

        await refreshAvailability()

        let elapsed = Date().timeIntervalSince(startedAt)
        let minSpinnerDuration: TimeInterval = 0.25
        if elapsed < minSpinnerDuration {
            try? await Task.sleep(for: .milliseconds(Int((minSpinnerDuration - elapsed) * 1000)))
        }

        let unchanged = priorIsAvailable == isAvailable && priorNote == availabilityNote
        recheckPhase = .settled(unchanged: unchanged)
        recheckResetTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(1500))
            if Task.isCancelled { return }
            self?.recheckPhase = .idle
        }
    }

    // MARK: - Smart title

    func suggestTitle(for body: String) async -> String? {
        guard isAvailable else { return nil }
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let session = LanguageModelSession(instructions: """
            You name notes. Read the note body and return a short, specific title — \
            2 to 6 words, no quotes, no trailing punctuation. Just the title text.
            """)
        do {
            let response = try await session.respond(to: "Body:\n\(trimmed)")
            let title = response.content
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .trimmingCharacters(in: CharacterSet(charactersIn: "\"'.“”‘’"))
            return title.isEmpty ? nil : title
        } catch {
            return nil
        }
    }

    // MARK: - Daily summary

    struct DailySummaryInput {
        let timeOfDayNoun: String     // "morning", "afternoon", "evening", "night"
        let urgentCount: Int
        let dueTodayCount: Int
        let overdueCount: Int
        let upcomingEvents: [(time: String, title: String)]   // already formatted
    }

    /// Cached daily summary keyed by an opaque hash the caller computes from
    /// its inputs. Survives view lifecycle so the home screen doesn't re-run
    /// the model when the user tab-switches back to it on iOS.
    private var cachedSummary: (hash: Int, text: String)?
    /// In-flight summary task, if one is currently running. We dedupe by hash
    /// so a re-entrant call (view recreated mid-generation) joins the existing
    /// task instead of spawning a parallel `LanguageModelSession` that would
    /// race against — and on Foundation Models often hang behind — the first.
    private var summaryTask: (hash: Int, task: Task<String?, Never>)?

    /// Synchronous cache lookup. View calls this first to render instantly on
    /// re-appearance when nothing has changed.
    func cachedDailySummary(matching hash: Int) -> String? {
        guard let cached = cachedSummary, cached.hash == hash else { return nil }
        return cached.text
    }

    /// Returns a daily summary for `input`, hitting the cache or joining an
    /// in-flight task when possible. `hash` should uniquely identify the
    /// input set the caller cares about (urgent counts, events, time-of-day).
    ///
    /// The model call is raced against an 8-second wall-clock timeout. On
    /// some configurations (notably TestFlight builds on iOS) Foundation
    /// Models has been observed to hang indefinitely inside `respond(to:)`,
    /// which previously left the home screen stuck on
    /// "Composing your summary…" forever. The timeout guarantees the caller
    /// sees `nil` within 8 seconds in the worst case, so the view can fall
    /// back to the rule-based summary.
    func dailySummary(_ input: DailySummaryInput, hash: Int) async -> String? {
        if let cached = cachedSummary, cached.hash == hash {
            return cached.text
        }
        if let existing = summaryTask, existing.hash == hash {
            return await existing.task.value
        }
        // A different hash is in flight — let it finish and discard its
        // result (its observer is gone or about to be replaced anyway).
        summaryTask?.task.cancel()

        let task = Task<String?, Never> { [weak self] in
            await self?.generateDailySummary(input)
        }
        summaryTask = (hash, task)

        let result = await Self.firstResult(timeoutSeconds: 8) {
            await task.value
        }
        if result == nil {
            // Foundation Models doesn't actually cancel mid-generation, but
            // we cancel anyway so the bookkeeping is honest. The stale
            // completion will be dropped by the hash check below if it
            // eventually lands.
            task.cancel()
            Self.summaryTimeoutLogger.error("dailySummary timed out after 8s; falling back")
        }
        if summaryTask?.hash == hash {
            summaryTask = nil
            if let result {
                cachedSummary = (hash, result)
            }
        }
        return result
    }

    private static let summaryTimeoutLogger = Logger(subsystem: "com.ianwaters.RollingTodo4", category: "intelligence")

    // MARK: - Tomorrow summary (evening preview)

    struct TomorrowSummaryInput {
        let weekdayNoun: String           // "Wednesday"
        let eventCount: Int
        let firstEventTime: String?       // "8am"
        let firstEventTitle: String?
        let dueCount: Int
        let urgentDueCount: Int
    }

    private var cachedTomorrowSummary: (hash: Int, text: String)?
    private var tomorrowSummaryTask: (hash: Int, task: Task<String?, Never>)?

    func cachedTomorrowSummary(matching hash: Int) -> String? {
        guard let cached = cachedTomorrowSummary, cached.hash == hash else { return nil }
        return cached.text
    }

    func tomorrowSummary(_ input: TomorrowSummaryInput, hash: Int) async -> String? {
        if let cached = cachedTomorrowSummary, cached.hash == hash {
            return cached.text
        }
        if let existing = tomorrowSummaryTask, existing.hash == hash {
            return await existing.task.value
        }
        tomorrowSummaryTask?.task.cancel()

        let task = Task<String?, Never> { [weak self] in
            await self?.generateTomorrowSummary(input)
        }
        tomorrowSummaryTask = (hash, task)

        let result = await Self.firstResult(timeoutSeconds: 8) {
            await task.value
        }
        if result == nil {
            task.cancel()
            Self.summaryTimeoutLogger.error("tomorrowSummary timed out after 8s; falling back")
        }
        if tomorrowSummaryTask?.hash == hash {
            tomorrowSummaryTask = nil
            if let result {
                cachedTomorrowSummary = (hash, result)
            }
        }
        return result
    }

    private func generateTomorrowSummary(_ input: TomorrowSummaryInput) async -> String? {
        guard isAvailable else { return nil }

        var facts: [String] = []
        if input.eventCount > 0 {
            if let time = input.firstEventTime, let title = input.firstEventTitle {
                facts.append("\(input.eventCount) calendar event\(input.eventCount == 1 ? "" : "s"), starting at \(time) with \(title)")
            } else {
                facts.append("\(input.eventCount) calendar event\(input.eventCount == 1 ? "" : "s")")
            }
        }
        if input.dueCount > 0 {
            facts.append("\(input.dueCount) thing\(input.dueCount == 1 ? "" : "s") due")
        }
        if input.urgentDueCount > 0 {
            facts.append("\(input.urgentDueCount) marked urgent")
        }
        let factsLine = facts.isEmpty ? "the day looks clear" : facts.joined(separator: "; ")

        let prompt = """
            You are previewing tomorrow for a professional.
            Create a single sentence summarising tomorrow (\(input.weekdayNoun)).
            Maximum 24 words. Friendly, no emoji, no exclamation marks.
            Address the user in the second person.
            Use future or modal verbs ("You'll have", "You can").
            DO NOT reference today. DO NOT use the past tense.
            If the day is busy, set expectations briefly. If quiet, say so.
            Don't assert what the user is feeling or doing.

            Facts:
            - \(factsLine)

            Respond with JUST the sentence.
            """

        let session = LanguageModelSession()
        do {
            let response = try await session.respond(to: prompt)
            let text = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : text
        } catch {
            return nil
        }
    }

    /// Race a producer against a wall-clock timeout. Returns `nil` if the
    /// timeout wins. The producer's task is *not* cancelled here — callers
    /// should cancel separately if they want to stop further work.
    private static func firstResult(
        timeoutSeconds: Double,
        producer: @escaping @Sendable () async -> String?
    ) async -> String? {
        await withTaskGroup(of: String?.self) { group in
            group.addTask { await producer() }
            group.addTask {
                try? await Task.sleep(for: .seconds(timeoutSeconds))
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
    }

    private func generateDailySummary(_ input: DailySummaryInput) async -> String? {
        guard isAvailable else { return nil }

        let eventsLine: String
        if input.upcomingEvents.isEmpty {
            eventsLine = "no remaining calendar events today"
        } else {
            let listed = input.upcomingEvents
                .prefix(4)
                .map { "\($0.time) \($0.title)" }
                .joined(separator: ".\n")
            eventsLine = "upcoming events: \(listed)"
        }

        let quietExamples: String
        switch input.timeOfDayNoun {
        case "morning", "afternoon":
            quietExamples = "\"You can enjoy a relaxed \(input.timeOfDayNoun)\", \"You have time for deep work\""
        case "evening":
            quietExamples = "\"You can enjoy a relaxed evening\", \"You have time to unwind\""
        default: // "night"
            quietExamples = "\"You can enjoy a quiet night\", \"You have time to rest\""
        }

        let prompt = """
            You are a personal assistant assisting a professional.
            Create a single sentence summarising the user's \(input.timeOfDayNoun). \
            Maximum 24 words. Friendly in tone, no emoji, no exclamation marks. \
            If everything is quiet, say so. Events are distinct.
            Address the user in the second person.
            Use the present tense. Use modal verbs. DO NOT USE THE PAST TENSE.
            Use simple English.
            When there's nothing pressing, suggest what the user could do with the
            quiet (e.g. \(quietExamples)). Match the time of day in your phrasing — do
            not mention any other part of the day. Don't assert what the user is
            feeling or doing.

            Facts to weave in (omit any that are zero/empty):
            - Urgent todos: \(input.urgentCount)
            - Due today: \(input.dueTodayCount)
            - Overdue: \(input.overdueCount)
            - \(eventsLine)
            
            Respond with JUST the summary.
            """

        let session = LanguageModelSession()
        do {
            let response = try await session.respond(to: prompt)
            let text = response.content.trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : text
        } catch {
            return nil
        }
    }

    // MARK: - Note generation

    /// Streams a partial NoteDraft as it's generated. Yields refinements; the
    /// final yield contains the complete draft.
    func streamNote(prompt: String) -> AsyncThrowingStream<NoteDraft.PartiallyGenerated, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                guard isAvailable else {
                    continuation.finish(throwing: IntelligenceError.unavailable)
                    return
                }
                let session = LanguageModelSession(instructions: """
                    You generate well-structured notes. Given a user request, produce a note \
                    with a short title and a markdown body. Use headers, bullet lists, and \
                    `- [ ]` checklist items where they help structure the content. Keep the body \
                    focused and useful — no meta-commentary about being an AI, no apologies.
                    """)
                do {
                    let stream = session.streamResponse(to: prompt, generating: NoteDraft.self)
                    for try await partial in stream {
                        continuation.yield(partial.content)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    enum IntelligenceError: Error, LocalizedError {
        case unavailable

        var errorDescription: String? {
            switch self {
            case .unavailable:
                "Apple Intelligence isn't available on this device."
            }
        }
    }
}
