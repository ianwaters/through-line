import Foundation
import FoundationModels

@Generable
struct NoteDraft {
    @Guide(description: "A short, specific title (2-6 words). No quotes, no trailing punctuation.")
    let title: String

    @Guide(description: "Markdown-formatted body. Use headers, bullet points, and `- [ ]` checklist items where appropriate. Write the actual content the user asked for; do not include meta-commentary.")
    let body: String
}
