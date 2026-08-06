import SwiftUI

struct ModelPickerView: View {
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var filteredModels: [HermesModel] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !trimmed.isEmpty else { return store.capabilities.models }
        return store.capabilities.models.filter { model in
            model.id.lowercased().contains(trimmed)
                || model.displayName.lowercased().contains(trimmed)
                || model.provider.lowercased().contains(trimmed)
                || (model.providerName ?? "").lowercased().contains(trimmed)
        }
    }

    var body: some View {
        HermesMobileScreen(title: "Models", subtitle: activeSubtitle, icon: "cpu", showsDone: true) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    HermesMobileSearchField(placeholder: "Search models…", text: $query)

                    ReasoningSection(
                        effort: store.reasoningEffort,
                        onToggle: { enabled in
                            let current = store.reasoningEffort.effort
                            let target = enabled
                                ? (current == "none" || current.isEmpty ? "medium" : current)
                                : "none"
                            Task { await store.setReasoningEffort(target) }
                        },
                        onSelect: { level in
                            Task { await store.setReasoningEffort(level) }
                        }
                    )

                    ForEach(groupedProviderNames, id: \.self) { provider in
                        HermesMobileSection(title: provider, icon: "server.rack", accent: HermesTheme.primary) {
                            VStack(alignment: .leading, spacing: 2) {
                                ForEach(filteredModels.filter { displayProvider($0) == provider }) { model in
                                    let active = model.id == store.activeModelID && model.provider == store.activeProviderID
                                    Button {
                                        Task {
                                            await store.selectModel(model)
                                            dismiss()
                                        }
                                    } label: {
                                        ModelRow(model: model, active: active)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 13)
                .padding(.top, 10)
                .padding(.bottom, 28)
            }
        }
        .task {
            try? await store.refreshCapabilities()
            await store.refreshReasoningEffort()
        }
    }

    private var activeSubtitle: String {
        let count = store.capabilities.models.count
        if let active = store.activeModel {
            return count > 1 ? "active · \(active.displayName) · \(count) available" : "active · \(active.displayName)"
        }
        return count > 1 ? "\(count) models available" : "choose desktop model"
    }

    private var groupedProviderNames: [String] {
        Array(Set(filteredModels.map(displayProvider))).sorted()
    }

    private func displayProvider(_ model: HermesModel) -> String {
        model.providerName ?? model.provider
    }
}

private struct ModelRow: View {
    let model: HermesModel
    let active: Bool

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(active ? HermesTheme.primary : HermesTheme.mutedForeground.opacity(0.55))
                .frame(width: 4.5, height: 4.5)
            VStack(alignment: .leading, spacing: 2) {
                Text(model.displayName)
                    .font(.system(size: 13.5, weight: active ? .semibold : .regular))
                    .foregroundStyle(active ? HermesTheme.ink : HermesTheme.ink.opacity(0.78))
                    .lineLimit(1)
                HStack(spacing: 6) {
                    Text(model.providerName ?? model.provider)
                    if model.supportsVision { Text("vision") }
                    if model.supportsTools { Text("tools") }
                }
                .font(.system(size: 10.5))
                .foregroundStyle(HermesTheme.mutedForeground.opacity(0.78))
                .lineLimit(1)
            }
            Spacer()
            if active {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(HermesTheme.primary)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, active ? 7 : 6)
        .background(active ? HermesTheme.userBubble : Color.clear, in: RoundedRectangle(cornerRadius: 3, style: .continuous))
        .contentShape(Rectangle())
    }
}

/// Thinking + effort control, mirroring the desktop's reasoning picker.
/// "none" disables thinking; the other levels raise the budget.
private struct ReasoningSection: View {
    let effort: HermesReasoningEffort
    let onToggle: (Bool) -> Void
    let onSelect: (String) -> Void

    private var thinkingOn: Bool {
        effort.thinkingEnabled
    }

    private var selectableLevels: [String] {
        effort.options.filter { $0 != "none" }
    }

    var body: some View {
        HermesMobileSection(title: "Reasoning", icon: "brain.head.profile", accent: HermesTheme.primary) {
            VStack(alignment: .leading, spacing: 8) {
                Toggle(isOn: Binding(
                    get: { thinkingOn },
                    set: onToggle
                )) {
                    HStack(spacing: 8) {
                        Image(systemName: "sparkles")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(thinkingOn ? HermesTheme.primary : HermesTheme.mutedForeground)
                        VStack(alignment: .leading, spacing: 1) {
                            Text("Thinking")
                                .font(.system(size: 13.5, weight: .semibold))
                                .foregroundStyle(HermesTheme.ink)
                            Text(thinkingOn ? "thinking enabled" : "instant responses")
                                .font(.system(size: 11))
                                .foregroundStyle(HermesTheme.mutedForeground)
                        }
                    }
                }
                .toggleStyle(PlutoToggleStyle())

                if thinkingOn && !selectableLevels.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Effort")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(HermesTheme.mutedForeground)
                            .textCase(.uppercase)
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(selectableLevels, id: \.self) { level in
                                    let selected = level == effort.effort
                                    Button {
                                        onSelect(level)
                                    } label: {
                                        Text(level)
                                            .font(.system(size: 12, weight: selected ? .bold : .regular))
                                            .foregroundStyle(selected ? HermesTheme.primaryForeground : HermesTheme.ink.opacity(0.75))
                                            .padding(.horizontal, 11)
                                            .padding(.vertical, 6)
                                            .background(
                                                selected ? HermesTheme.primary : HermesTheme.popover,
                                                in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            )
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                                    .stroke(selected ? Color.clear : HermesTheme.stroke, lineWidth: 1)
                                            )
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                }
            }
            .padding(4)
        }
    }
}
