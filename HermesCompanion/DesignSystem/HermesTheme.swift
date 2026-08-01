import SwiftUI

enum HermesTheme {
    static let background = Color(red: 0.035, green: 0.039, blue: 0.055)
    static let panel = Color.white.opacity(0.065)
    static let elevated = Color.white.opacity(0.095)
    static let stroke = Color.white.opacity(0.12)
    static let muted = Color.white.opacity(0.62)
    static let gold = Color(red: 0.96, green: 0.72, blue: 0.33)
    static let blue = Color(red: 0.29, green: 0.52, blue: 1.0)
    static let green = Color(red: 0.32, green: 0.86, blue: 0.52)
    static let red = Color(red: 1.0, green: 0.36, blue: 0.34)
}

struct GlassPanel: ViewModifier {
    var cornerRadius: CGFloat = 24

    func body(content: Content) -> some View {
        content
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(HermesTheme.stroke, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.22), radius: 24, x: 0, y: 18)
    }
}

extension View {
    func glassPanel(cornerRadius: CGFloat = 24) -> some View {
        modifier(GlassPanel(cornerRadius: cornerRadius))
    }
}

struct StatusDot: View {
    var color: Color

    var body: some View {
        Circle()
            .fill(color)
            .frame(width: 9, height: 9)
            .overlay(Circle().stroke(.white.opacity(0.28), lineWidth: 1))
    }
}
