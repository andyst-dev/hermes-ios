import SwiftUI

struct HermesMobileScreen<Content: View>: View {
    let title: String
    var subtitle: String?
    var icon: String?
    var showsDone: Bool = false
    /// Optional leading action button ("+" style) shown before the xmark.
    var onAdd: (() -> Void)? = nil
    @ViewBuilder var content: Content
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack(alignment: .center, spacing: 12) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(HermesTheme.primary)
                        .frame(width: 32, height: 32)
                        .background(HermesTheme.userBubble, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                }
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(HermesTheme.brandTitle(size: 25))
                        .foregroundStyle(HermesTheme.ink)
                    if let subtitle {
                        Text(subtitle)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(HermesTheme.mutedForeground)
                            .lineLimit(1)
                    }
                }
                Spacer()
                if let onAdd {
                    Button(action: onAdd) {
                        Image(systemName: "plus")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(HermesTheme.primary)
                            .frame(width: 32, height: 32)
                            .background(HermesTheme.userBubble, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
                if showsDone {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(HermesTheme.mutedForeground)
                            .frame(width: 32, height: 32)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
            .padding(.bottom, 10)

            content
        }
        .background(HermesTheme.sidebar.ignoresSafeArea())
    }
}

struct HermesMobileSection<Content: View>: View {
    let title: String
    var icon: String?
    var accent: Color = HermesTheme.mutedForeground
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(spacing: 8) {
                if let icon {
                    Image(systemName: icon)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(accent)
                }
                Text(title.uppercased())
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .tracking(2.0)
                    .foregroundStyle(HermesTheme.ink.opacity(0.88))
                Rectangle()
                    .fill(HermesTheme.border.opacity(0.55))
                    .frame(height: 1)
            }
            content
        }
    }
}

struct HermesMobileRow: View {
    let title: String
    var subtitle: String? = nil
    var icon: String? = nil
    var accent: Color = HermesTheme.mutedForeground
    var selected: Bool = false
    var trailing: String? = nil

    var body: some View {
        HStack(spacing: 10) {
            if let icon {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(accent)
                    .frame(width: 18)
            } else {
                Circle()
                    .fill(accent.opacity(selected ? 1.0 : 0.55))
                    .frame(width: 4.5, height: 4.5)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13.5, weight: selected ? .semibold : .regular))
                    .foregroundStyle(selected ? HermesTheme.ink : HermesTheme.ink.opacity(0.78))
                    .lineLimit(1)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.system(size: 10.5))
                        .foregroundStyle(HermesTheme.mutedForeground.opacity(0.78))
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            if let trailing {
                Text(trailing)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(HermesTheme.mutedForeground.opacity(0.72))
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, selected ? 7 : 6)
        .background(selected ? HermesTheme.userBubble : Color.clear, in: RoundedRectangle(cornerRadius: 3, style: .continuous))
        .contentShape(Rectangle())
    }
}

struct HermesMobileSearchField: View {
    let placeholder: String
    @Binding var text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(HermesTheme.mutedForeground.opacity(0.55))
            TextField(placeholder, text: $text)
                .font(.system(size: 13))
                .foregroundStyle(HermesTheme.ink)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 9)
        .background(HermesTheme.background.opacity(0.34), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}
