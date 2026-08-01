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
        NavigationStack {
            VStack(spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(HermesTheme.mutedForeground)
                    TextField("Search models", text: $query)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
                .padding(12)
                .background(HermesTheme.card, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(HermesTheme.stroke, lineWidth: 1))
                .padding(.horizontal)

                List {
                    ForEach(groupedProviderNames, id: \.self) { provider in
                        Section(provider) {
                            ForEach(filteredModels.filter { displayProvider($0) == provider }) { model in
                                Button {
                                    Task {
                                        await store.selectModel(model)
                                        dismiss()
                                    }
                                } label: {
                                    ModelRow(model: model, active: model.id == store.activeModelID && model.provider == store.activeProviderID)
                                }
                                .buttonStyle(.plain)
                                .listRowBackground(Color.clear)
                            }
                        }
                    }
                }
                .scrollContentBackground(.hidden)
            }
            .background(HermesTheme.background.ignoresSafeArea())
            .navigationTitle("Change model")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
            .task { try? await store.refreshCapabilities() }
        }
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
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(model.displayName)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(HermesTheme.ink)
                    .lineLimit(1)
                HStack(spacing: 8) {
                    Text(model.providerName ?? model.provider)
                    if model.supportsVision { Label("Vision", systemImage: "eye") }
                    if model.supportsTools { Label("Tools", systemImage: "wrench.and.screwdriver") }
                }
                .font(.caption2)
                .foregroundStyle(HermesTheme.mutedForeground)
                .lineLimit(1)
            }
            Spacer()
            if active {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(HermesTheme.primary)
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(active ? HermesTheme.elevated : HermesTheme.card.opacity(0.65), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(active ? HermesTheme.primary.opacity(0.55) : HermesTheme.stroke, lineWidth: 1))
    }
}
