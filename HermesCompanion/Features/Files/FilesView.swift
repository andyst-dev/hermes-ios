import SwiftUI

struct FilesView: View {
    @ObservedObject private var theme = ThemeManager.shared
    @EnvironmentObject private var store: AppStore
    @State private var pathStack: [String] = []
    @State private var entries: [HermesFileEntry] = []
    @State private var currentPath = ""
    @State private var loading = true
    @State private var errorMessage: String?
    @State private var openFile: HermesFileEntry?

    var body: some View {
        HermesMobileScreen(title: "Files", subtitle: currentPath.isEmpty ? "Desktop managed files" : currentPath, icon: "folder", showsDone: true) {
            VStack(spacing: 0) {
                if !pathStack.isEmpty {
                    HStack(spacing: 8) {
                        Button {
                            goBack()
                        } label: {
                            HStack(spacing: 5) {
                                Image(systemName: "chevron.left")
                                    .font(.system(size: 11, weight: .bold))
                                Text("Up")
                                    .font(.system(size: 12, weight: .semibold))
                            }
                            .foregroundStyle(HermesTheme.primary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(HermesTheme.card.opacity(0.58), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
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
                            ProgressView()
                                .tint(HermesTheme.primary)
                                .frame(maxWidth: .infinity)
                                .padding(.top, 40)
                        } else if let errorMessage {
                            Text(errorMessage)
                                .font(.system(size: 12))
                                .foregroundStyle(HermesTheme.red)
                                .padding(.horizontal, 4)
                                .padding(.top, 12)
                        } else if entries.isEmpty {
                            Text("Empty folder")
                                .font(.system(size: 12.5))
                                .foregroundStyle(HermesTheme.mutedForeground)
                                .padding(.top, 24)
                        } else {
                            ForEach(entries) { entry in
                                Button {
                                    if entry.isDirectory {
                                        open(directory: entry)
                                    } else {
                                        openFile = entry
                                    }
                                } label: {
                                    HStack(spacing: 10) {
                                        Image(systemName: entry.isDirectory ? "folder" : "doc.text")
                                            .font(.system(size: 13, weight: .semibold))
                                            .foregroundStyle(entry.isDirectory ? HermesTheme.primary : HermesTheme.mutedForeground)
                                            .frame(width: 22)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(entry.name)
                                                .font(.system(size: 13.5, weight: .medium))
                                                .foregroundStyle(HermesTheme.ink)
                                                .lineLimit(1)
                                            if let size = entry.size {
                                                Text(formattedSize(size))
                                                    .font(.system(size: 10.5))
                                                    .foregroundStyle(HermesTheme.mutedForeground.opacity(0.7))
                                            }
                                        }
                                        Spacer(minLength: 0)
                                        Image(systemName: entry.isDirectory ? "chevron.right" : "chevron.right")
                                            .font(.system(size: 10, weight: .bold))
                                            .foregroundStyle(HermesTheme.mutedForeground.opacity(0.4))
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 8)
                                    .background(HermesTheme.card.opacity(0.26), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.horizontal, 13)
                    .padding(.top, 6)
                    .padding(.bottom, 28)
                }
                .refreshable {
                    await load(path: currentPath.isEmpty ? nil : currentPath)
                }
            }
        }
        .sheet(item: $openFile) { entry in
            FilePreviewView(entry: entry)
                .environmentObject(store)
        }
        .task { await load(path: nil) }
    }

    private func open(directory: HermesFileEntry) {
        pathStack.append(currentPath)
        Task { await load(path: directory.path) }
    }

    private func goBack() {
        guard let previous = pathStack.popLast() else { return }
        Task { await load(path: previous.isEmpty ? nil : previous) }
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
            errorMessage = "Could not load files. Is the app paired with Desktop?"
        }
        loading = false
    }

    private func formattedSize(_ bytes: Int) -> String {
        if bytes < 1024 { return "\(bytes) B" }
        if bytes < 1024 * 1024 { return String(format: "%.1f KB", Double(bytes) / 1024) }
        return String(format: "%.1f MB", Double(bytes) / (1024 * 1024))
    }
}

private struct FilePreviewView: View {
    @ObservedObject private var theme = ThemeManager.shared
    @EnvironmentObject private var store: AppStore
    let entry: HermesFileEntry
    @State private var content = "Loading…"
    @State private var failed = false

    var body: some View {
        HermesMobileScreen(title: entry.name, subtitle: "Desktop file preview", icon: "doc.text", showsDone: true) {
            ScrollView(showsIndicators: false) {
                if failed {
                    Text("This file is not a readable text file on Desktop.")
                        .font(.system(size: 12.5))
                        .foregroundStyle(HermesTheme.mutedForeground)
                        .padding(.top, 24)
                } else {
                    Text(content)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(HermesTheme.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 13)
                        .padding(.top, 8)
                        .padding(.bottom, 28)
                }
            }
        }
        .task {
            do {
                let file = try await store.readFile(path: entry.path)
                content = file.content
            } catch {
                failed = true
            }
        }
    }
}
