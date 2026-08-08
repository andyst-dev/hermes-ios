import SwiftUI

/// App theme: "ember" (Hermes Desktop Ember skin, warm orange on
/// near-black) or "cream" (Hermès-style light: cream paper, chocolate
/// ink, saddle-orange accents). Persisted in UserDefaults.
enum ThemeMode: String {
    case ember
    case cream
}

final class ThemeManager: ObservableObject {
    // Singleton: theme mode is read from many nonisolated contexts
    // (HermesTheme computed colors), always mutated on the main actor
    // by the Settings toggle. Safe by construction.
    nonisolated(unsafe) static let shared = ThemeManager()

    @Published var mode: ThemeMode {
        didSet { UserDefaults.standard.set(mode.rawValue, forKey: "hermes.theme") }
    }

    private init() {
        let raw = UserDefaults.standard.string(forKey: "hermes.theme")
        mode = (raw == ThemeMode.cream.rawValue) ? .cream : .ember
    }
}

enum HermesTheme {
    static var isCream: Bool { ThemeManager.shared.mode == .cream }

    // MARK: Ember — Hermes Desktop "Ember" skin (apps/desktop/src/themes/presets.ts)
    private static let emberBackground = Color(red: 0.086, green: 0.031, blue: 0.000)       // #160800
    private static let emberForeground = Color(red: 1.000, green: 0.847, blue: 0.690)       // #ffd8b0
    private static let emberCard = Color(red: 0.118, green: 0.055, blue: 0.016)             // #1e0e04
    private static let emberMuted = Color(red: 0.165, green: 0.078, blue: 0.031)            // #2a1408
    private static let emberMutedForeground = Color(red: 0.667, green: 0.478, blue: 0.337)  // #aa7a56
    private static let emberPopover = Color(red: 0.133, green: 0.063, blue: 0.031)          // #221008
    private static let emberPrimary = Color(red: 1.000, green: 0.847, blue: 0.690)          // #ffd8b0
    private static let emberPrimaryForeground = Color(red: 0.086, green: 0.031, blue: 0.000)
    private static let emberSecondary = Color(red: 0.204, green: 0.094, blue: 0.000)        // #341800
    private static let emberAccent = Color(red: 0.188, green: 0.086, blue: 0.000)           // #301600
    private static let emberBorder = Color(red: 0.227, green: 0.110, blue: 0.031)           // #3a1c08
    private static let emberRing = Color(red: 0.851, green: 0.451, blue: 0.086)             // #d97316
    private static let emberSidebar = Color(red: 0.063, green: 0.024, blue: 0.000)          // #100600
    private static let emberSidebarBorder = Color(red: 0.165, green: 0.063, blue: 0.016)    // #2a1004
    private static let emberUserBubble = Color(red: 0.165, green: 0.106, blue: 0.071)       // #2a1b12 — chocolate brown
    private static let emberUserBubbleBorder = Color(red: 0.290, green: 0.196, blue: 0.122) // #4a321f
    private static let emberDestructive = Color(red: 0.769, green: 0.188, blue: 0.063)      // #c43010
    private static let emberGreen = Color(red: 0.384, green: 0.765, blue: 0.478)
    private static let emberPluto = Color(red: 0.490, green: 0.322, blue: 0.161)            // #7d5229
    private static let emberPlutoThumb = Color(red: 0.918, green: 0.851, blue: 0.745)       // #ead9be
    private static let emberSendReady = Color(red: 0.851, green: 0.659, blue: 0.471)        // #d9a878
    private static let emberSendIdle = Color(red: 0.420, green: 0.290, blue: 0.180)         // #6b4a2e

    // MARK: Cream — Hermès-style light: warm paper, chocolate ink, saddle orange.
    private static let creamBackground = Color(red: 0.961, green: 0.925, blue: 0.867)       // #f5ecd9
    private static let creamForeground = Color(red: 0.239, green: 0.169, blue: 0.102)       // #3d2b1a
    private static let creamCard = Color(red: 0.980, green: 0.953, blue: 0.902)             // #faf3e6
    private static let creamMuted = Color(red: 0.910, green: 0.863, blue: 0.776)            // #e8dcbd
    private static let creamMutedForeground = Color(red: 0.604, green: 0.482, blue: 0.329)  // #9a7b54
    private static let creamPopover = Color(red: 0.969, green: 0.933, blue: 0.875)          // #f7eece
    private static let creamPrimary = Color(red: 0.753, green: 0.373, blue: 0.118)          // #c05f1e
    private static let creamPrimaryForeground = Color(red: 0.992, green: 0.973, blue: 0.925) // #fdf8ce
    private static let creamSecondary = Color(red: 0.851, green: 0.753, blue: 0.604)        // #d9c09a
    private static let creamAccent = Color(red: 0.910, green: 0.722, blue: 0.494)           // #e8b87e
    private static let creamBorder = Color(red: 0.863, green: 0.796, blue: 0.690)           // #dccbb0
    private static let creamRing = Color(red: 0.788, green: 0.408, blue: 0.173)             // #c9682c
    private static let creamSidebar = Color(red: 0.941, green: 0.894, blue: 0.820)          // #f0e4d1
    private static let creamSidebarBorder = Color(red: 0.890, green: 0.827, blue: 0.729)    // #e3d3ba
    private static let creamUserBubble = Color(red: 0.937, green: 0.878, blue: 0.769)       // #efe0c4
    private static let creamUserBubbleBorder = Color(red: 0.847, green: 0.761, blue: 0.612) // #d8c29c
    private static let creamDestructive = Color(red: 0.690, green: 0.227, blue: 0.118)      // #b03a1e
    private static let creamGreen = Color(red: 0.310, green: 0.478, blue: 0.290)            // #4f7a4a
    private static let creamPluto = Color(red: 0.663, green: 0.455, blue: 0.235)            // #a9743c
    private static let creamPlutoThumb = Color(red: 0.984, green: 0.957, blue: 0.902)       // #fbf4e6
    private static let creamSendReady = Color(red: 0.725, green: 0.498, blue: 0.271)        // #b97f45
    private static let creamSendIdle = Color(red: 0.788, green: 0.706, blue: 0.561)         // #c9b48f

    static var background: Color { isCream ? creamBackground : emberBackground }
    static var foreground: Color { isCream ? creamForeground : emberForeground }
    static var card: Color { isCream ? creamCard : emberCard }
    static var muted: Color { isCream ? creamMuted : emberMuted }
    static var mutedForeground: Color { isCream ? creamMutedForeground : emberMutedForeground }
    static var popover: Color { isCream ? creamPopover : emberPopover }
    static var primary: Color { isCream ? creamPrimary : emberPrimary }
    static var primaryForeground: Color { isCream ? creamPrimaryForeground : emberPrimaryForeground }
    static var secondary: Color { isCream ? creamSecondary : emberSecondary }
    static var accent: Color { isCream ? creamAccent : emberAccent }
    static var border: Color { isCream ? creamBorder : emberBorder }
    static var input: Color { border }
    static var ring: Color { isCream ? creamRing : emberRing }
    static var midground: Color { ring }
    static var sidebar: Color { isCream ? creamSidebar : emberSidebar }
    static var sidebarBorder: Color { isCream ? creamSidebarBorder : emberSidebarBorder }
    static var userBubble: Color { isCream ? creamUserBubble : emberUserBubble }
    static var userBubbleBorder: Color { isCream ? creamUserBubbleBorder : emberUserBubbleBorder }
    static var destructive: Color { isCream ? creamDestructive : emberDestructive }
    static var green: Color { isCream ? creamGreen : emberGreen }
    static var pluto: Color { isCream ? creamPluto : emberPluto }
    static var plutoThumb: Color { isCream ? creamPlutoThumb : emberPlutoThumb }
    static var sendReady: Color { isCream ? creamSendReady : emberSendReady }
    static var sendIdle: Color { isCream ? creamSendIdle : emberSendIdle }

    // Legacy aliases used by feature views.
    static var ink: Color { foreground }
    static var chrome: Color { background }
    static var elevated: Color { card }
    static var stroke: Color { border }
    static var mutedText: Color { mutedForeground }
    static var red: Color { destructive }
    static var warm: Color { ring }

    static let mono = Font.system(.caption, design: .monospaced)

    static func brandTitle(size: CGFloat) -> Font { .custom("Collapse-Bold", size: size) }
    static func brandRegular(size: CGFloat) -> Font { .custom("Collapse-Regular", size: size) }
    /// Serif heavy brand face — the same look as the "HERMES" wordmark on
    /// the home-screen widgets (system serif, heavy weight).
    static func brandSerif(size: CGFloat) -> Font { .system(size: size, weight: .heavy, design: .serif) }
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
            .shadow(
                color: .black.opacity(HermesTheme.isCream ? 0.10 : 0.38),
                radius: HermesTheme.isCream ? 18 : 28,
                x: 0,
                y: HermesTheme.isCream ? 10 : 18
            )
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
