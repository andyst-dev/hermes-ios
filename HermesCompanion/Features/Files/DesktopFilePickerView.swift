import SwiftUI

struct DesktopFilePickerView: View {
    @ObservedObject private var theme = ThemeManager.shared
    @EnvironmentObject private var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var pathStack: [String] = []
    @State private var entries: [HermesFileEntry] = []
    @State private var currentPath = ""
    @State private var loading = true
    @State private var errorMessage: String?
    @State private var attachingPath: String?

    var body: some View {
        HermesMobileScreen(title: "Attach from Desktop", subtitle: "Images managed by Desktop", icon: "folder.badge.plus", showsDone: true) {
            VStack(spacing: 0) {
                if !pathStack.isEmpty {
                    HStack {
                        Button {
                            goBack()
                        } label: {
                            Label("Up", systemImage: "chevron.left")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(HermesTheme.primary)
                        }
                        .buttonStyle(.plain)
                        Spacer()
                    }
                    .padding(.horizontal, 13)
                    .padding(.bottom, 6)
                }

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 8) {
                        if loading {
                            ProgressView().tint(HermesTheme.primary)
                                .frame(maxWidth: .infinity)
                                .padding(.top, 40)
                        } else if let errorMessage {
                            Text(errorMessage)
                                .font(.system(size: 12))
                                .foregroundStyle(HermesTheme.red)
                                .padding(.top, 18)
                        } else if entries.isEmpty {
                            Text("No images in this folder")
                                .font(.system(size: 12.5))
                                .foregroundStyle(HermesTheme.mutedForeground)
                                .padding(.top, 24)
                        } else {
                            ForEach(entries) { entry in
                                pickerRow(entry)
                            }
                        }
                    }
                    .padding(.horizontal, 13)
                    .padding(.top, 6)
                    .padding(.bottom, 28)
                }
            }
        }
        .task { await load(path: nil) }
    }

    @ViewBuilder
    private func pickerRow(_ entry: HermesFileEntry) -> some View {
        Button {
            if entry.isDirectory {
                pathStack.append(currentPath)
                Task { await load(path: entry.path) }
            } else if isAttachableImage(entry) {
                attachingPath = entry.path
                Task {
                    do {
                        try await store.attachDesktopFile(path: entry.path)
                        dismiss()
                    } catch {
                        errorMessage = "Could not attach this Desktop image."
                    }
                    attachingPath = nil
                }
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: entry.isDirectory ? "folder" : "photo")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(entry.isDirectory ? HermesTheme.primary : HermesTheme.mutedForeground)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.name)
                        .font(.system(size: 13.5, weight: .medium))
                        .foregroundStyle(HermesTheme.ink)
                        .lineLimit(1)
                    Text(entry.isDirectory ? "Folder" : formattedSize(entry.size ?? 0))
                        .font(.system(size: 10.5))
                        .foregroundStyle(HermesTheme.mutedForeground.opacity(0.7))
                }
                Spacer(minLength: 0)
                if attachingPath == entry.path {
                    ProgressView().tint(HermesTheme.primary)
                } else {
                    Image(systemName: entry.isDirectory ? "chevron.right" : "plus.circle")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(entry.isDirectory ? HermesTheme.mutedForeground.opacity(0.45) : HermesTheme.primary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(HermesTheme.card.opacity(0.26), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!entry.isDirectory && !isAttachableImage(entry))
        .opacity(entry.isDirectory || isAttachableImage(entry) ? 1 : 0.42)
    }

    private func load(path: String?) async {
        loading = true
        errorMessage = nil
        do {
            let listing = try await store.files(path: path)
            entries = listing.entries
            currentPath = listing.path
        } catch {
            entries = []
            errorMessage = "Could not load Desktop files."
        }
        loading = false
    }

    private func goBack() {
        guard let previous = pathStack.popLast() else { return }
        Task { await load(path: previous.isEmpty ? nil : previous) }
    }

    private func isAttachableImage(_ entry: HermesFileEntry) -> Bool {
        guard !entry.isDirectory else { return false }
        if entry.mimeType?.hasPrefix("image/") == true { return true }
        return ["png", "jpg", "jpeg", "gif", "webp", "bmp"].contains(URL(fileURLWithPath: entry.name).pathExtension.lowercased())
    }

    private func formattedSize(_ bytes: Int) -> String {
        if bytes < 1024 { return "\(bytes) B" }
        if bytes < 1024 * 1024 { return String(format: "%.1f KB", Double(bytes) / 1024) }
        return String(format: "%.1f MB", Double(bytes) / (1024 * 1024))
    }
}
