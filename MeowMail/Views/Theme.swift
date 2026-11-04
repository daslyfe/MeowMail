import CoreText
import ImageIO
import SwiftUI

/// Grey paper, black ink, dashed rules and pastel tags: a mix of melaniehoff.com,
/// the c-dashboard and time.hexhouse.studio.
enum Theme {
    static let rail = Color(white: 0xBF / 255)        // melaniehoff.com page
    static let sidebar = Color(white: 0xD9 / 255)     // dashboard page
    static let content = Color(white: 0xE6 / 255)     // dashboard cards
    static let field = Color(white: 0xC4 / 255)       // dashboard "on" state
    static let paper = Color(white: 0xF2 / 255)       // reading surface for a selected row
    static let ink = Color.black
    static let accent = Color(red: 2 / 255, green: 15 / 255, blue: 187 / 255)  // melaniehoff.com links
    static let unread = Color.black                   // black tags, not red dots
    static let alert = Color(red: 0xD0 / 255, green: 0, blue: 0)               // dashboard sync problems
    static let muted = Color(white: 0x55 / 255)
    static let faint = Color(white: 0x88 / 255)

    // The dashboard's pastel section colors, half see-through over the grey.
    private static let palette: [Color] = [
        Color(red: 255 / 255, green: 140 / 255, blue: 130 / 255).opacity(0.55),
        Color(red: 255 / 255, green: 196 / 255, blue: 130 / 255).opacity(0.55),
        Color(red: 255 / 255, green: 240 / 255, blue: 150 / 255).opacity(0.6),
        Color(red: 150 / 255, green: 235 / 255, blue: 180 / 255).opacity(0.55),
        Color(red: 140 / 255, green: 230 / 255, blue: 225 / 255).opacity(0.55),
        Color(red: 255 / 255, green: 175 / 255, blue: 230 / 255).opacity(0.55),
        Color(red: 170 / 255, green: 195 / 255, blue: 255 / 255).opacity(0.55),
        Color(red: 210 / 255, green: 180 / 255, blue: 255 / 255).opacity(0.55),
    ]

    static func color(for text: String) -> Color {
        palette[text.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF } % palette.count]
    }

    // MARK: Type

    /// Bold display face for headings and channel names (dashboard group titles).
    static func display(_ size: CGFloat) -> Font { Fonts.font("Monor_Bold", size: size, fallback: .system(size: size, weight: .bold, design: .serif)) }
    /// Garamond for subjects and message text (dashboard body, melaniehoff.com titles).
    static func serif(_ size: CGFloat, bold: Bool = false) -> Font {
        Fonts.font(bold ? "MXWimGaramond-Bold" : "MXWimGaramond-Regular", size: size,
                   fallback: .system(size: size, weight: bold ? .bold : .regular, design: .serif))
    }
    /// Thin Nanum for small print: dates, snippets, recipients (melaniehoff.com body).
    static func thin(_ size: CGFloat) -> Font { Fonts.font("NanumMyeongjo", size: size, fallback: .system(size: size, design: .serif)) }
    /// Courier for typing, like hextime's inputs.
    static func typewriter(_ size: CGFloat) -> Font { .custom("Courier", size: size) }
}

/// Registers the fonts bundled in the Fonts folder. Any that are missing (MXWim isn't
/// in git, since it's a paid font) fall back to the system serif.
enum Fonts {
    private static let available: Set<String> = {
        var names: Set<String> = []
        let urls = ["otf", "ttf"].flatMap { Bundle.main.urls(forResourcesWithExtension: $0, subdirectory: nil) ?? [] }
        for url in urls {
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            if let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor] {
                for descriptor in descriptors {
                    if let name = CTFontDescriptorCopyAttribute(descriptor, kCTFontNameAttribute) as? String { names.insert(name) }
                }
            }
        }
        return names
    }()

    static func font(_ name: String, size: CGFloat, fallback: Font) -> Font {
        available.contains(name) ? .custom(name, size: size) : fallback
    }
}

/// The dashboard's pixel border, as a strip down the edge of the sidebar.
struct PixelStrip: View {
    private static let image: CGImage? = {
        guard let url = Bundle.main.url(forResource: "pixel-strip", withExtension: "png"),
              let source = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }()

    var body: some View {
        if let image = Self.image {
            Image(decorative: image, scale: 1)
                .resizable(resizingMode: .tile)
                .interpolation(.none)
                .frame(width: 14)
        } else {
            DashedRule(axis: .vertical)
        }
    }
}

/// A straight horizontal line across its frame, for dotted input underlines.
struct Line: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.minX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        }
    }
}

/// A half-point dashed rule, as on melaniehoff.com.
struct DashedRule: View {
    var axis: Axis = .horizontal

    var body: some View {
        GeometryReader { geo in
            Path { path in
                if axis == .horizontal {
                    path.move(to: CGPoint(x: 0, y: 0.5))
                    path.addLine(to: CGPoint(x: geo.size.width, y: 0.5))
                } else {
                    path.move(to: CGPoint(x: 0.5, y: 0))
                    path.addLine(to: CGPoint(x: 0.5, y: geo.size.height))
                }
            }
            .stroke(Theme.ink, style: StrokeStyle(lineWidth: 0.5, dash: [3, 2]))
        }
        .frame(width: axis == .vertical ? 1 : nil, height: axis == .horizontal ? 1 : nil)
    }
}

struct Avatar: View {
    var address: Address
    var size: CGFloat = 40
    /// Grey instead of the pastel color, for old mail in all-mail.
    var colorful = true

    var body: some View {
        Rectangle()
            .fill(colorful ? Theme.color(for: address.email) : Theme.field)
            .frame(width: size, height: size)
            .overlay(Rectangle().stroke(Theme.ink, lineWidth: 1))
            .overlay {
                Text(address.display.prefix(1).uppercased())
                    .font(Theme.display(size * 0.5))
                    .foregroundStyle(Theme.ink)
            }
    }
}

/// A small black tag with white type, like the dashboard's "new" markers.
struct CountBadge: View {
    var count: Int

    var body: some View {
        Text(count > 99 ? "99+" : "\(count)")
            .font(Theme.thin(11))
            .foregroundStyle(.white)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(Theme.unread)
    }
}

/// hextime's retro silver button.
struct SilverButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.custom("Times New Roman", size: 15).bold())
            .foregroundStyle(.black)
            .padding(.horizontal, 12)
            .padding(.vertical, 3)
            .background(Color(white: 0xC0 / 255))
            .overlay {
                // Light top-left edge and dark bottom-right edge; swapped while pressed.
                let light = Color.white, dark = Color(white: 0x80 / 255)
                let top = configuration.isPressed ? dark : light
                let bottom = configuration.isPressed ? light : dark
                VStack(spacing: 0) {
                    top.frame(height: 1)
                    Spacer(minLength: 0)
                    bottom.frame(height: 1)
                }
                HStack(spacing: 0) {
                    top.frame(width: 1)
                    Spacer(minLength: 0)
                    bottom.frame(width: 1)
                }
            }
            .overlay(Rectangle().stroke(Color(white: 0x40 / 255), lineWidth: 1).padding(-1))
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
