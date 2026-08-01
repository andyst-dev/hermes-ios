import Foundation

enum PreviewData {
    static let sessions: [HermesSession] = [
        HermesSession(id: "pr-clean", title: "PR Discord permissions", subtitle: "NousResearch/hermes-agent · docs", updatedAt: .now, status: .completed),
        HermesSession(id: "ios", title: "Hermes iOS Companion", subtitle: "SwiftUI prototype · running", updatedAt: .now, status: .running),
        HermesSession(id: "approval", title: "Release review", subtitle: "Waiting for approval", updatedAt: .now, status: .waitingApproval)
    ]

    static let messages: [HermesMessage] = [
        HermesMessage(id: UUID(), role: .assistant, text: "Connecté au Mac. Je peux piloter Hermes, lire les sessions, suivre les tools et lancer les validations.", createdAt: .now, toolCalls: []),
        HermesMessage(id: UUID(), role: .user, text: "Trouve un PR méga clean facile", createdAt: .now, toolCalls: []),
        HermesMessage(
            id: UUID(),
            role: .assistant,
            text: "J’ai trouvé un candidat docs ciblé et sans duplicate. Je patch minimalement puis je build le site.",
            createdAt: .now,
            toolCalls: [
                HermesToolCall(id: UUID(), name: "github", command: "gh issue view", status: .succeeded, summary: "Issue open, no assignee, no duplicate PR"),
                HermesToolCall(id: UUID(), name: "terminal", command: "npm run build", status: .succeeded, summary: "Docusaurus build completed")
            ]
        )
    ]

    static let capabilities = HermesCapabilitySnapshot(
        models: [
            HermesModel(id: "gpt-5.5", displayName: "GPT-5.5", provider: "OpenAI", supportsVision: true, supportsTools: true),
            HermesModel(id: "hermes-4", displayName: "Hermes 4", provider: "Nous", supportsVision: false, supportsTools: true)
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
