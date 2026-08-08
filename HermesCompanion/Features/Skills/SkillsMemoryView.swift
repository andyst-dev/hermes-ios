import SwiftUI

/// Skills catalog (read-only) + persistent memory (read + append) straight
/// from the desktop backend.
struct SkillsMemoryView: View {
    @EnvironmentObject private var store: AppStore
    @State private var selectedSkill: HermesSkill?
    @State private var showingAddMemory = false
    @State private var addMemoryTarget = "memory"
    @State private var memoryDraft = ""
    @State private var editingEntry: HermesMemoryEntry?
    @State private var editingTarget = "memory"
    @State private var editDraft = ""
    @State private var actionStatus: String?
    @State private var selectedTab = 0  // 0 = Skills, 1 = Memory

    var body: some View {
        HermesMobileScreen(title: "Skills & memory", subtitle: "Desktop agent state", icon: "brain.head.profile", showsDone: true) {
            VStack(spacing: 0) {
                tabBar
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 18) {
                        if selectedTab == 0 {
                            skillsSection
                        } else {
                            memorySection
                        }
                        if let actionStatus {
                            Text(actionStatus)
                                .font(.system(size: 11, weight: .medium))
                                .foregroundStyle(HermesTheme.green)
                                .padding(.horizontal, 10)
                        }
                    }
                    .padding(.horizontal, 13)
                    .padding(.top, 10)
                    .padding(.bottom, 28)
                }
                .refreshable {
                    await store.refreshSkillsMemory()
                }
            }
        }
        .sheet(item: $selectedSkill) { skill in
            SkillDetailView(skill: skill)
                .environmentObject(store)
        }
        .sheet(item: $editingEntry) { entry in
            MemoryEditSheet(
                target: editingTarget,
                entry: entry,
                draft: editDraft,
                onSave: { content in
                    let ok = await store.memoryUpdate(target: editingTarget, index: entry.index, content: content)
                    actionStatus = ok ? "Memory updated on the desktop." : "Could not update memory."
                },
                onDelete: {
                    let ok = await store.memoryDelete(target: editingTarget, index: entry.index)
                    actionStatus = ok ? "Memory entry removed." : "Could not remove memory."
                }
            )
            .environmentObject(store)
        }
        .alert("Add memory entry", isPresented: $showingAddMemory) {
            TextField("Fact to remember…", text: $memoryDraft)
            Button("Cancel", role: .cancel) {
                memoryDraft = ""
            }
            Button("Add") {
                Task {
                    let ok = await store.memoryAppend(target: addMemoryTarget, content: memoryDraft)
                    actionStatus = ok ? "Memory updated on the desktop." : "Could not write memory."
                    memoryDraft = ""
                }
            }
        } message: {
            Text(addMemoryTarget == "user"
                 ? "Added to your user profile (who you are, your preferences)."
                 : "Added to the agent notes (environment, conventions, lessons).")
        }
        .task {
            await store.refreshSkillsMemory()
        }
    }

    private var tabBar: some View {
        HStack(spacing: 8) {
            tabChip("Skills", tab: 0, icon: "books.vertical")
            tabChip("Memory", tab: 1, icon: "brain.head.profile")
            Spacer()
        }
        .padding(.horizontal, 13)
        .padding(.top, 8)
    }

    private func tabChip(_ title: String, tab: Int, icon: String) -> some View {
        Button {
            selectedTab = tab
        } label: {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                Text(title)
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundStyle(selectedTab == tab ? HermesTheme.primary : HermesTheme.mutedForeground)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(selectedTab == tab ? HermesTheme.userBubble : HermesTheme.card.opacity(0.42), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var skillsSection: some View {
        HermesMobileSection(title: "Skills", icon: "square.stack.3d.up", accent: HermesTheme.primary) {
            if store.skills.isEmpty {
                Text("No skills listed on this backend.")
                    .font(.system(size: 12.5, weight: .medium))
                    .foregroundStyle(HermesTheme.mutedForeground)
            } else {
                ForEach(store.skills) { skill in
                    Button {
                        Task {
                            if let detail = await store.skillDetail(name: skill.name) {
                                selectedSkill = detail
                            }
                        }
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "sparkles")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(HermesTheme.primary)
                                .frame(width: 18)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(skill.name)
                                    .font(.system(size: 13.5, weight: .semibold))
                                    .foregroundStyle(HermesTheme.ink)
                                    .lineLimit(1)
                                if !skill.description.isEmpty {
                                    Text(skill.description)
                                        .font(.system(size: 10.5))
                                        .foregroundStyle(HermesTheme.mutedForeground.opacity(0.78))
                                        .lineLimit(1)
                                }
                            }
                            Spacer(minLength: 0)
                            Text(skill.category)
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .tracking(0.8)
                                .foregroundStyle(HermesTheme.mutedForeground.opacity(0.7))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(HermesTheme.border.opacity(0.4), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
                            Image(systemName: "chevron.right")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(HermesTheme.mutedForeground.opacity(0.5))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var memorySection: some View {
        HermesMobileSection(title: "Memory", icon: "brain", accent: HermesTheme.green) {
            memoryGroup(title: "Agent notes", target: "memory", entries: store.memory.memory)
            Divider().overlay(HermesTheme.border.opacity(0.5)).padding(.vertical, 4)
            memoryGroup(title: "Your profile", target: "user", entries: store.memory.user)

            HStack(spacing: 8) {
                Button {
                    addMemoryTarget = "memory"
                    showingAddMemory = true
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "plus.circle")
                            .font(.system(size: 10, weight: .bold))
                        Text("Add agent note")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(HermesTheme.primary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(HermesTheme.primary.opacity(0.12), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .buttonStyle(.plain)

                Button {
                    addMemoryTarget = "user"
                    showingAddMemory = true
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: "person.crop.circle.badge.plus")
                            .font(.system(size: 10, weight: .bold))
                        Text("Add profile fact")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    .foregroundStyle(HermesTheme.green)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(HermesTheme.green.opacity(0.12), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
                .buttonStyle(.plain)
                Spacer()
            }
            .padding(.top, 4)
        }
    }

    private func memoryGroup(title: String, target: String, entries: [HermesMemoryEntry]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .tracking(1.6)
                .foregroundStyle(HermesTheme.mutedForeground.opacity(0.8))
            if entries.isEmpty {
                Text("Empty")
                    .font(.system(size: 11))
                    .foregroundStyle(HermesTheme.mutedForeground.opacity(0.6))
            } else {
                ForEach(entries) { entry in
                    Button {
                        editingTarget = target
                        editDraft = entry.content
                        editingEntry = entry
                    } label: {
                        HStack(alignment: .top, spacing: 6) {
                            Text(entry.content)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(HermesTheme.ink.opacity(0.85))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .multilineTextAlignment(.leading)
                            Image(systemName: "pencil")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(HermesTheme.mutedForeground.opacity(0.5))
                                .padding(.top, 2)
                        }
                        .padding(.horizontal, 9)
                        .padding(.vertical, 7)
                        .background(HermesTheme.card.opacity(0.3), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button {
                            editingTarget = target
                            editDraft = entry.content
                            editingEntry = entry
                        } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                        Button(role: .destructive) {
                            Task {
                                let ok = await store.memoryDelete(target: target, index: entry.index)
                                actionStatus = ok ? "Memory entry removed." : "Could not remove memory."
                            }
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
        }
    }
}

/// Full SKILL.md content of one skill.
private struct SkillDetailView: View {
    @Environment(\.dismiss) private var dismiss
    let skill: HermesSkill

    var body: some View {
        NavigationStack {
            HermesMobileScreen(title: skill.name, subtitle: skill.category, icon: "sparkles", showsDone: true) {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 12) {
                        if !skill.description.isEmpty {
                            Text(skill.description)
                                .font(.system(size: 13, weight: .medium))
                                .foregroundStyle(HermesTheme.ink.opacity(0.85))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        if let body = skill.body, !body.isEmpty {
                            Text(body)
                                .font(.system(size: 11.5, design: .monospaced))
                                .foregroundStyle(HermesTheme.ink.opacity(0.75))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(10)
                                .background(HermesTheme.card.opacity(0.35), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(HermesTheme.border.opacity(0.7), lineWidth: 1))
                        }
                    }
                    .padding(.horizontal, 13)
                    .padding(.top, 10)
                    .padding(.bottom, 28)
                }
            }
        }
    }
}

/// Edit or delete one persistent-memory entry.
private struct MemoryEditSheet: View {
    @Environment(\.dismiss) private var dismiss
    let target: String
    let entry: HermesMemoryEntry
    @State var draft: String
    var onSave: (String) async -> Void
    var onDelete: () async -> Void

    @State private var saving = false

    var body: some View {
        NavigationStack {
            HermesMobileScreen(title: "Edit memory", subtitle: target == "user" ? "Your profile" : "Agent notes", icon: "pencil", showsDone: true) {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 14) {
                        TextEditor(text: $draft)
                            .font(.system(size: 13.5, weight: .medium))
                            .foregroundStyle(HermesTheme.ink)
                            .scrollContentBackground(.hidden)
                            .padding(8)
                            .frame(minHeight: 120)
                            .background(HermesTheme.card.opacity(0.35), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).stroke(HermesTheme.border.opacity(0.7), lineWidth: 1))

                        Button {
                            save()
                        } label: {
                            HStack(spacing: 8) {
                                if saving {
                                    ProgressView().tint(HermesTheme.ink)
                                } else {
                                    Image(systemName: "checkmark.circle.fill")
                                }
                                Text(saving ? "Saving…" : "Save changes")
                                    .font(.system(size: 14, weight: .bold))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                            .foregroundStyle(HermesTheme.ink)
                            .background(HermesTheme.primary, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .disabled(saving)

                        Button(role: .destructive) {
                            Task {
                                await onDelete()
                                dismiss()
                            }
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "trash")
                                    .font(.system(size: 11, weight: .bold))
                                Text("Delete this entry")
                                    .font(.system(size: 12.5, weight: .semibold))
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 11)
                            .foregroundStyle(HermesTheme.red)
                            .background(HermesTheme.red.opacity(0.1), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 13)
                    .padding(.top, 10)
                    .padding(.bottom, 28)
                }
            }
        }
    }

    private func save() {
        let content = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty else { return }
        saving = true
        Task {
            await onSave(content)
            saving = false
            dismiss()
        }
    }
}
