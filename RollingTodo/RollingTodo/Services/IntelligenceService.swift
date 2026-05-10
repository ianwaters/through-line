import Foundation
import FoundationModels

/// Wraps Apple's on-device Foundation Models. Singleton, MainActor, @Observable
/// so views can hide AI affordances on devices that don't support Apple
/// Intelligence (`isAvailable == false`) without showing broken UI.
@MainActor
@Observable
final class IntelligenceService {
    static let shared = IntelligenceService()

    private(set) var availability: SystemLanguageModel.Availability = .unavailable(.modelNotReady)

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
        refreshAvailability()
    }

    func refreshAvailability() {
        availability = SystemLanguageModel.default.availability
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

    func dailySummary(_ input: DailySummaryInput) async -> String? {
        guard isAvailable else { return nil }

        let eventsLine: String
        if input.upcomingEvents.isEmpty {
            eventsLine = "no remaining calendar events today"
        } else {
            let listed = input.upcomingEvents
                .prefix(4)
                .map { "\($0.time) \($0.title)" }
                .joined(separator: "; ")
            eventsLine = "upcoming events: \(listed)"
        }

        let prompt = """
            You are a personal assistant assiting a professional.
            Create a single sentence summarising the user's \(input.timeOfDayNoun). \
            Maximum 24 words. Friendly in tone, no emoji, no exclamation marks. \
            If everything is quiet, say so. Events are distinct. 
            Address the user in the second person.
            Use the present tense. Use modal verbs. DO NOT USE THE PAST TENSE.
            Use simple English.
            When there's nothing pressing, suggest what the user could do with the
            quiet (e.g. "You can enjoy a relaxed morning", "You have time for deep
            work"). Don't assert what the user is feeling or doing.

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
