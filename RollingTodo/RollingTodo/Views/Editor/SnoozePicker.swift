import SwiftUI

/// A reusable Menu that lists time-aware snooze presets and a custom-date sheet.
struct SnoozeMenu<Label: View>: View {
    let label: () -> Label
    let onPick: (Date) -> Void

    @State private var customDate: Date = .now
    @State private var showingCustom: Bool = false

    var body: some View {
        Menu {
            ForEach(SnoozePresets.options(for: .now)) { opt in
                Button(opt.title) { onPick(opt.date) }
            }
            Divider()
            Button("Pick a date…") {
                customDate = defaultCustomDate()
                showingCustom = true
            }
        } label: {
            label()
        }
        .sheet(isPresented: $showingCustom) {
            CustomSnoozeSheet(initial: customDate) { date in
                showingCustom = false
                onPick(date)
            } onCancel: {
                showingCustom = false
            }
        }
    }

    private func defaultCustomDate() -> Date {
        let cal = Calendar.current
        let tomorrow = cal.date(byAdding: .day, value: 1, to: cal.startOfDay(for: .now)) ?? .now
        var comps = cal.dateComponents([.year, .month, .day], from: tomorrow)
        comps.hour = 9
        return cal.date(from: comps) ?? tomorrow
    }
}

private struct CustomSnoozeSheet: View {
    let initial: Date
    let onConfirm: (Date) -> Void
    let onCancel: () -> Void

    @State private var date: Date

    init(initial: Date, onConfirm: @escaping (Date) -> Void, onCancel: @escaping () -> Void) {
        self.initial = initial
        self.onConfirm = onConfirm
        self.onCancel = onCancel
        self._date = State(initialValue: initial)
    }

    var body: some View {
        NavigationStack {
            Form {
                DatePicker(
                    "Snooze until",
                    selection: $date,
                    in: Date.now...,
                    displayedComponents: [.date, .hourAndMinute]
                )
            }
            .navigationTitle("Snooze")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Snooze") { onConfirm(date) }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 360, minHeight: 220)
        #endif
    }
}
