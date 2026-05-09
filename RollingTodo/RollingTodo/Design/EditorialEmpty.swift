import SwiftUI

/// Editorial empty-state view. Replaces ContentUnavailableView in places where
/// we want the app's typographic voice to come through.
struct EditorialEmpty: View {
    let eyebrow: String
    let title: String
    let detail: String
    let symbol: String

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: symbol)
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(Color.accentColor.opacity(0.6))
                .frame(width: 64, height: 64)
                .background(
                    Circle()
                        .strokeBorder(Color.accentColor.opacity(0.2), lineWidth: 0.5)
                )
                .padding(.bottom, 6)

            VStack(spacing: 8) {
                Text(eyebrow)
                    .eyebrowStyle()
                    .multilineTextAlignment(.center)
                Text(title)
                    .font(.editorialDisplay(26, weight: .semibold))
                    .foregroundStyle(Color.ink)
                    .multilineTextAlignment(.center)
                Text(detail)
                    .font(.editorialItalic(14))
                    .foregroundStyle(Color.inkSoft)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 280)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }
}

#Preview {
    EditorialEmpty(
        eyebrow: "Notes",
        title: "A blank page",
        detail: "Press ⌘N to begin.",
        symbol: "doc.text"
    )
}
