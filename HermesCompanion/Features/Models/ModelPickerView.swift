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
        .task { try? await store.refreshCapabilities() }
    }

    private var activeSubtitle: String {
        if let active = store.activeModel { return "active · \(active.displayName)" }
        return "choose desktop model"
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
