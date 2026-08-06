import SwiftUI

enum HermesTheme {
    // Hermes Desktop "Ember" skin: warm orange on near-black.
    // Source: apps/desktop/src/themes/presets.ts.
    static let background = Color(red: 0.086, green: 0.031, blue: 0.000)       // #160800
    static let foreground = Color(red: 1.000, green: 0.847, blue: 0.690)       // #ffd8b0
    static let card = Color(red: 0.118, green: 0.055, blue: 0.016)             // #1e0e04
    static let muted = Color(red: 0.165, green: 0.078, blue: 0.031)            // #2a1408
    static let mutedForeground = Color(red: 0.667, green: 0.478, blue: 0.337)  // #aa7a56
    static let popover = Color(red: 0.133, green: 0.063, blue: 0.031)          // #221008
    static let primary = Color(red: 1.000, green: 0.847, blue: 0.690)          // #ffd8b0
    static let primaryForeground = Color(red: 0.086, green: 0.031, blue: 0.000)
    static let secondary = Color(red: 0.204, green: 0.094, blue: 0.000)        // #341800
    static let accent = Color(red: 0.188, green: 0.086, blue: 0.000)           // #301600
    static let border = Color(red: 0.227, green: 0.110, blue: 0.031)           // #3a1c08
    static let input = border
    static let ring = Color(red: 0.851, green: 0.451, blue: 0.086)             // #d97316
    static let midground = ring
    static let sidebar = Color(red: 0.063, green: 0.024, blue: 0.000)          // #100600
    static let sidebarBorder = Color(red: 0.165, green: 0.063, blue: 0.016)    // #2a1004
    static let userBubble = Color(red: 0.165, green: 0.063, blue: 0.000)       // #2a1000
    static let userBubbleBorder = Color(red: 0.290, green: 0.125, blue: 0.063) // #4a2010
    static let destructive = Color(red: 0.769, green: 0.188, blue: 0.063)      // #c43010
    static let green = Color(red: 0.384, green: 0.765, blue: 0.478)

    // Pluto brown: the warm tan of the dwarf planet's surface (New Horizons).
    static let pluto = Color(red: 0.690, green: 0.506, blue: 0.310)            // #b0814f
    static let plutoThumb = Color(red: 0.918, green: 0.851, blue: 0.745)       // #ead9be

    // Legacy aliases used by feature views.
    static let ink = foreground
    static let chrome = background
    static let elevated = card
    static let stroke = border
    static let mutedText = mutedForeground
    static let red = destructive
    static let warm = ring

    static let mono = Font.system(.caption, design: .monospaced)

    static func brandTitle(size: CGFloat) -> Font { .custom("Collapse-Bold", size: size) }
    static func brandRegular(size: CGFloat) -> Font { .custom("Collapse-Regular", size: size) }
}

struct DesktopPanel: ViewModifier {
    var cornerRadius: CGFloat = 22

    func body(content: Content) -> some View {
        content
            .background(
                LinearGradient(
                    colors: [HermesTheme.card, HermesTheme.popover],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                ),
                in: RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .stroke(HermesTheme.border, lineWidth: 1)
            )
            .shadow(color: .black.opacity(0.38), radius: 28, x: 0, y: 18)
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
            .overlay(Circle().stroke(HermesTheme.background.opacity(0.9), lineWidth: 1))
    }
}

/// Pluto toggle: warm Pluto-brown track with a cream thumb.
/// Replaces the default iOS switch (gray capsule + white thumb), which reads
/// as a blank/white slab on the Ember background. Shared by every toggle in
/// the app so they all look identical.
struct PlutoToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 10) {
            configuration.label
            Spacer(minLength: 0)
            Button {
                withAnimation(.snappy(duration: 0.18)) {
                    configuration.isOn.toggle()
                }
            } label: {
                ZStack(alignment: configuration.isOn ? .trailing : .leading) {
                    Capsule()
                        .fill(configuration.isOn ? HermesTheme.pluto : HermesTheme.muted)
                        .overlay(
                            Capsule().stroke(
                                configuration.isOn ? HermesTheme.pluto.opacity(0.85) : HermesTheme.border,
                                lineWidth: 1
                            )
                        )
                    Circle()
                        .fill(configuration.isOn ? HermesTheme.plutoThumb : HermesTheme.mutedForeground)
                        .frame(width: 22, height: 22)
                        .padding(3)
                }
                .frame(width: 46, height: 28)
            }
            .buttonStyle(.plain)
            .accessibilityValue(configuration.isOn ? "1" : "0")
        }
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
                    .stroke(HermesTheme.ring.opacity(0.45), lineWidth: 1)
            )
            .shadow(color: HermesTheme.ring.opacity(0.18), radius: 24, x: 0, y: 12)
    }
}

struct HermesWordmark: View {
    var compact = false

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: compact ? 5 : 8) {
            Text("Hermes")
                .font(HermesTheme.brandTitle(size: compact ? 22 : 38))
                .tracking(compact ? -0.6 : -1.4)
                .foregroundStyle(HermesTheme.foreground)
            Text("Agent")
                .font(.system(size: compact ? 12 : 15, weight: .semibold, design: .monospaced))
                .tracking(1.4)
                .textCase(.uppercase)
                .foregroundStyle(HermesTheme.ring)
        }
    }
}
