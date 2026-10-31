import SwiftUI

enum Theme {
    static let rail = Color(red: 0.11, green: 0.12, blue: 0.13)
    static let sidebar = Color(red: 0.17, green: 0.18, blue: 0.20)
    static let content = Color(red: 0.20, green: 0.21, blue: 0.24)
    static let field = Color(red: 0.25, green: 0.27, blue: 0.29)
    static let accent = Color(red: 0.35, green: 0.40, blue: 0.95)
    static let unread = Color(red: 0.93, green: 0.26, blue: 0.27)
    static let muted = Color(red: 0.58, green: 0.61, blue: 0.64)

    private static let palette: [Color] = [
        Color(red: 0.35, green: 0.40, blue: 0.95), Color(red: 0.23, green: 0.65, blue: 0.36),
        Color(red: 0.93, green: 0.55, blue: 0.20), Color(red: 0.80, green: 0.30, blue: 0.55),
        Color(red: 0.20, green: 0.60, blue: 0.75), Color(red: 0.60, green: 0.40, blue: 0.85),
    ]

    static func color(for text: String) -> Color {
        palette[text.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF } % palette.count]
    }
}

struct Avatar: View {
    var address: Address
    var size: CGFloat = 40

    var body: some View {
        Circle()
            .fill(Theme.color(for: address.email))
            .frame(width: size, height: size)
            .overlay {
                Text(address.display.prefix(1).uppercased())
                    .font(.system(size: size * 0.45, weight: .semibold))
                    .foregroundStyle(.white)
            }
    }
}

struct CountBadge: View {
    var count: Int

    var body: some View {
        Text(count > 99 ? "99+" : "\(count)")
            .font(.caption2.bold())
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(Theme.unread, in: Capsule())
    }
}

extension Date {
    var chatStamp: String {
        let calendar = Calendar.current
        if calendar.isDateInToday(self) { return formatted(date: .omitted, time: .shortened) }
        if calendar.isDateInYesterday(self) { return "Yesterday" }
        return formatted(date: .abbreviated, time: .omitted)
    }
}
