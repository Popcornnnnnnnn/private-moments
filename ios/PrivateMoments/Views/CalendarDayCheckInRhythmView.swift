import SwiftUI

struct CalendarDayCheckInRhythmStrip: View {
    @Environment(\.appLanguage) private var appLanguage

    let checkIns: [CheckInFeedEntry]
    let calendar: Calendar
    let onOpen: (CheckInFeedEntry) -> Void

    var body: some View {
        if !checkIns.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(L10n.t("Check-ins rhythm", appLanguage))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(checkIns) { checkIn in
                            Button {
                                onOpen(checkIn)
                            } label: {
                                HStack(spacing: 6) {
                                    Image(systemName: checkIn.item.symbolName)
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(dotColor(for: checkIn))

                                    Text(timeTitle(for: checkIn))
                                        .font(.caption.monospacedDigit())
                                        .foregroundStyle(.primary)

                                    Text(checkIn.item.name)
                                        .font(.caption.weight(.semibold))
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }
                                .padding(.horizontal, 10)
                                .frame(height: 30)
                                .background(dotColor(for: checkIn).opacity(0.11), in: Capsule())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(timeTitle(for: checkIn)), \(checkIn.item.name)")
                        }
                    }
                    .padding(.horizontal, 1)
                }
            }
        }
    }

    private func dotColor(for checkIn: CheckInFeedEntry) -> Color {
        Color(hex: checkIn.item.colorHex) ?? .accentColor
    }

    private func timeTitle(for checkIn: CheckInFeedEntry) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.locale = calendar.locale ?? .current
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: checkIn.occurredAt)
    }
}
