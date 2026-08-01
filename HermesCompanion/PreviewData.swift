import Foundation

enum PreviewData {
    static let sessions: [HermesSession] = [
        HermesSession(id: "ios", title: "Hermes iOS Companion", subtitle: "desktop · running · mobile UI", updatedAt: .now, status: .running, source: "desktop"),
        HermesSession(id: "cleaner", title: "Demande de nettoyage à finaliser", subtitle: "default · desktop · 14 messages", updatedAt: .now, status: .idle, source: "desktop"),
        HermesSession(id: "pr-clean", title: "PR Discord permissions", subtitle: "desktop · docs · completed", updatedAt: .now, status: .completed, source: "desktop"),
        HermesSession(id: "approval", title: "Release review", subtitle: "desktop · waiting for approval", updatedAt: .now, status: .waitingApproval, source: "desktop"),
        HermesSession(id: "claude-model", title: "Ajout du modèle Claude", subtitle: "default · cli · yesterday", updatedAt: .now, status: .completed, source: "cli"),
        HermesSession(id: "reply-only", title: "Réponds uniquement par patch", subtitle: "default · cli · earlier this week", updatedAt: .now, status: .idle, source: "cli"),
        HermesSession(id: "image-generation", title: "Use the image generation tool", subtitle: "default · desktop · tool run", updatedAt: .now, status: .completed, source: "desktop"),
        HermesSession(id: "github-account", title: "Accès à mon compte GitHub", subtitle: "default · desktop · last week", updatedAt: .now, status: .completed, source: "desktop"),
        HermesSession(id: "telegram-cleaner", title: "Demande de nettoyage à distance", subtitle: "telegram · gateway · 9 messages", updatedAt: .now, status: .running, source: "telegram"),
        HermesSession(id: "telegram-replies", title: "Nouvelles réponses aux PR", subtitle: "telegram · gateway · unread", updatedAt: .now, status: .idle, source: "telegram"),
        HermesSession(id: "telegram-notes", title: "Validation finale Notes Cleaner", subtitle: "telegram · gateway · completed", updatedAt: .now, status: .completed, source: "telegram")
    ]

    static let messages: [HermesMessage] = [
        HermesMessage(id: UUID().uuidString, role: .assistant, text: "Connecté au Mac. Je peux piloter Hermes, lire les sessions, suivre les tools et lancer les validations.", createdAt: .now, toolCalls: []),
        HermesMessage(id: UUID().uuidString, role: .user, text: "Trouve un PR méga clean facile", createdAt: .now, toolCalls: []),
        HermesMessage(
            id: UUID().uuidString,
            role: .assistant,
            text: "J’ai trouvé un candidat docs ciblé et sans duplicate. Je patch minimalement puis je build le site.",
            createdAt: .now,
            toolCalls: [
                HermesToolCall(id: UUID().uuidString, name: "github", command: "gh issue view", status: .succeeded, summary: "Issue open, no assignee, no duplicate PR"),
                HermesToolCall(id: UUID().uuidString, name: "terminal", command: "npm run build", status: .succeeded, summary: "Docusaurus build completed")
            ]
        )
    ]

    static let capabilities = HermesCapabilitySnapshot(
        models: [
            HermesModel(id: "gpt-5.5", displayName: "GPT-5.5", provider: "openai", providerName: "OpenAI", supportsVision: true, supportsTools: true, isActive: true),
            HermesModel(id: "hermes-4", displayName: "Hermes 4", provider: "nous", providerName: "Nous", supportsVision: false, supportsTools: true, isActive: false)
        ],
        profiles: [
            HermesProfile(id: "default", displayName: "Default", isActive: true),
            HermesProfile(id: "work", displayName: "Work", isActive: false)
        ],
        files: [
            HermesFileArtifact(id: UUID(), label: "mobile-api-contract.md", path: "docs/mobile-api-contract.md", kind: .text),
            HermesFileArtifact(id: UUID(), label: "HermesCompanion.xcodeproj", path: "HermesCompanion.xcodeproj", kind: .directory),
            HermesFileArtifact(id: UUID(), label: "latest screenshot", path: "screenshots/connect.png", kind: .image)
        ],
        jobs: [
            HermesJob(id: "agent-run", title: "iOS UI polish", detail: "Running SwiftUI build + screenshot pass", status: .running),
            HermesJob(id: "cron", title: "Daily repo audit", detail: "Scheduled", status: .scheduled),
            HermesJob(id: "tests", title: "Unit tests", detail: "2 passed", status: .completed)
        ],
        approvals: [
            HermesApproval(id: "sim", title: "Open iOS Simulator", detail: "Install and capture the app UI", risk: .low),
            HermesApproval(id: "publish", title: "Publish repo", detail: "Create public GitHub repository", risk: .medium)
        ],
        tools: ["terminal", "files", "browser", "github", "cron", "skills", "memory", "subagents"]
    )
}
