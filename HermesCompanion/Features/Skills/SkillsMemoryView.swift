import SwiftUI

/// Skills catalog (read-only) + persistent memory (read + append) straight
/// from the desktop backend.
struct SkillsMemoryView: View {
    @EnvironmentObject private var store: AppStore
    @State private var selectedSkill: HermesSkill?
    @State private var showingAddMemory = false
    @State private var addMemoryTarget = "memory"
    @State private var memoryDraft = ""
    @State private var actionStatus: String?

    var body: some View {
        HermesMobileScreen(title: "Skills & memory", subtitle: "Desktop agent state", icon: "brain.head.profile", showsDone: true) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    skillsSection
                    memorySection
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
        }
        .sheet(item: $selectedSkill) { skill in
            SkillDetailView(skill: skill)
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
            memoryGroup(title: "Agent notes", entries: store.memory.memory)
            Divider().overlay(HermesTheme.border.opacity(0.5)).padding(.vertical, 4)
            memoryGroup(title: "Your profile", entries: store.memory.user)

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

    private func memoryGroup(title: String, entries: [HermesMemoryEntry]) -> some View {
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
                    Text(entry.content)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(HermesTheme.ink.opacity(0.85))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 7)
                        .background(HermesTheme.card.opacity(0.3), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
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
