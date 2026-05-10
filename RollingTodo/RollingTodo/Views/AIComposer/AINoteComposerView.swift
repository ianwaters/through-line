import SwiftUI
import SwiftData
import FoundationModels

struct AINoteComposerView: View {
    var onSaved: ((UUID) -> Void)? = nil

    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var intelligence = IntelligenceService.shared

    @State private var prompt: String = ""
    @State private var draftTitle: String = ""
    @State private var draftBody: String = ""
    @State private var streamTask: Task<Void, Never>?
    @State private var isGenerating: Bool = false
    @State private var errorMessage: String?

    @FocusState private var promptFocused: Bool

    private var hasDraft: Bool {
        !draftTitle.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !draftBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var canGenerate: Bool {
        intelligence.isAvailable
            && !prompt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && !isGenerating
    }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                promptField
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 12)

                Divider().background(Color.inkHairline)

                if hasDraft || isGenerating {
                    draftPreview
                } else {
                    placeholder
                }
            }
            .navigationTitle("New Note from a Prompt")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        streamTask?.cancel()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { saveAsNote() }
                        .disabled(!hasDraft || isGenerating)
                }
            }
            #if os(macOS)
            .frame(minWidth: 480, minHeight: 520)
            #endif
            .onAppear { promptFocused = true }
            .onDisappear { streamTask?.cancel() }
        }
    }

    private var promptField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("What should the note be about?")
                .eyebrowStyle()

            TextField(
                "e.g. \"20-minute weekly 1:1 coaching template between me (coach) and my senior developer\"",
                text: $prompt,
                axis: .vertical
            )
            .lineLimit(1...6)
            .textFieldStyle(.plain)
            .font(.system(size: 15, design: .serif))
            .focused($promptFocused)
            .onSubmit { generate() }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.secondary.opacity(0.08), in: .rect(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.inkHairline, lineWidth: 0.5)
            )

            Button(action: generate) {
                Label(isGenerating ? "Generating…" : "Generate",
                      systemImage: isGenerating ? "stop.circle" : "wand.and.sparkles")
                    .labelStyle(.titleAndIcon)
                    .font(.system(size: 13, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!canGenerate && !isGenerating)

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(Color.editorialRed)
            }
        }
    }

    private var draftPreview: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                if !draftTitle.isEmpty {
                    Text(draftTitle)
                        .font(.editorialDisplay(24, weight: .semibold))
                        .foregroundStyle(Color.ink)
                }
                if !draftBody.isEmpty {
                    MarkdownView(text: draftBody)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                if isGenerating {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Streaming…")
                            .font(.editorialItalic(12))
                            .foregroundStyle(Color.inkMuted)
                    }
                    .padding(.top, 4)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var placeholder: some View {
        VStack(spacing: 14) {
            Image(systemName: "sparkles")
                .font(.system(size: 32, weight: .light))
                .foregroundStyle(Color.accentColor.opacity(0.6))
            Text("Generate a structured note from a short prompt.")
                .font(.editorialItalic(14))
                .foregroundStyle(Color.inkSoft)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }

    private func generate() {
        if isGenerating {
            streamTask?.cancel()
            return
        }
        let prompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !prompt.isEmpty else { return }
        errorMessage = nil
        draftTitle = ""
        draftBody = ""
        isGenerating = true

        streamTask = Task { @MainActor in
            defer { isGenerating = false }
            do {
                for try await partial in intelligence.streamNote(prompt: prompt) {
                    if let title = partial.title { draftTitle = title }
                    if let body = partial.body { draftBody = body }
                }
            } catch is CancellationError {
                // user-initiated; no error UI
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func saveAsNote() {
        let body = draftBody.trimmingCharacters(in: .whitespacesAndNewlines)
        let note = NoteCreator.create(in: context, title: draftTitle, body: body)
        onSaved?(note.id)
        dismiss()
    }
}
