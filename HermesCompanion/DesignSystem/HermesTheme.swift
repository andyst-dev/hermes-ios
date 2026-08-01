import SwiftUI

enum HermesTheme {
    // Mirrored from the Desktop default theme tokens in apps/desktop/src/styles.css.
    static let ink = Color(red: 0.090, green: 0.090, blue: 0.102)          // #17171a
    static let primary = Color(red: 0.000, green: 0.325, blue: 0.992)      // #0053fd
    static let warm = Color(red: 0.812, green: 0.502, blue: 0.427)         // #cf806d
    static let chrome = Color(red: 0.973, green: 0.980, blue: 1.000)       // #f8faff
    static let sidebar = Color(red: 0.953, green: 0.969, blue: 1.000)      // #f3f7ff
    static let card = Color.white
    static let elevated = Color(red: 0.988, green: 0.988, blue: 0.992)
    static let stroke = Color.black.opacity(0.08)
    static let muted = Color.black.opacity(0.54)
    static let green = Color(red: 0.122, green: 0.541, blue: 0.396)
    static let red = Color(red: 0.812, green: 0.176, blue: 0.337)

    static let mono = Font.system(.caption, design: .monospaced)

    static func brandTitle(size: CGFloat) -> Font {
        .custom("Collapse-Bold", size: size)
    }

    static func brandRegular(size: CGFloat) -> Font {
        .custom("Collapse-Regular", size: size)
    }
}

struct DesktopPanel: ViewModifier {
    var cornerRadius: CGFloat = 22

    func body(content: Content) -> some View {
        content
            .background(HermesTheme.card, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(HermesTheme.stroke, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.06), radius: 24, x: 0, y: 18)
    }
}

extension View {
    func desktopPanel(cornerRadius: CGFloat = 22) -> some View {
        modifier(DesktopPanel(cornerRadius: cornerRadius))
    }
}

struct StatusDot: View {
    var color: Color

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 8, height: 8)
            .overlay(Circle().stroke(.white.opacity(0.85), lineWidth: 1))
    }
}

struct HermesMark: View {
    var size: CGFloat = 72

    var body: some View {
        Image("HermesIcon")
            .resizable()
            .scaledToFill()
            .frame(width: size, height: size)
            .clipShape(RoundedRectangle(cornerRadius: size * 0.23, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: size * 0.23, style: .continuous)
                    .stroke(Color.black.opacity(0.08), lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.12), radius: 18, x: 0, y: 10)
    }
}

struct HermesWordmark: View {
    var compact = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: compact ? 5 : 8) {
            Text("Hermes")
                .font(HermesTheme.brandTitle(size: compact ? 22 : 38))
                .tracking(compact ? -0.6 : -1.4)
                .foregroundStyle(HermesTheme.ink)
            Text("Agent")
                .font(.system(size: compact ? 12 : 15, weight: .semibold, design: .monospaced))
                .tracking(1.4)
                .textCase(.uppercase)
                .foregroundStyle(HermesTheme.primary)
        }
    }
}
