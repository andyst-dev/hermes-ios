import Charts
import SwiftUI

/// Desktop usage stats: totals, tokens per model, estimated cost and the
/// last 14 days of activity (from the desktop's local state DB).
struct StatsView: View {
    @EnvironmentObject private var store: AppStore

    var body: some View {
        HermesMobileScreen(title: "Usage stats", subtitle: "Desktop · all sessions", icon: "chart.bar.xaxis", showsDone: true) {
            ScrollView {
                VStack(spacing: 14) {
                    if let stats = store.stats {
                        if let portal = stats.nousPortal {
                            nousPortalCard(portal)
                        }
                        totalsGrid(stats.total)
                        dailyChart(stats.daily)
                        breakdown(eyebrow: "BY PROVIDER", title: "Where the money goes", rows: stats.byProvider.map(StatRow.init(provider:)))
                        breakdown(eyebrow: "BY MODEL", title: "Tokens & cost", rows: stats.byModel.map(StatRow.init(model:)))
                        costNote(stats)
                    } else if let error = store.statsError {
                        Text(error)
                            .font(.system(size: 12.5))
                            .foregroundStyle(HermesTheme.mutedText)
                            .multilineTextAlignment(.center)
                            .padding(.top, 60)
                            .padding(.horizontal, 30)
                    } else {
                        ProgressView()
                            .tint(HermesTheme.primary)
                            .padding(.top, 60)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 28)
            }
        }
        .task { await store.refreshStats() }
    }

    // MARK: - Nous portal

    private func nousPortalCard(_ portal: HermesNousPortal) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Image(systemName: "building.columns")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(HermesTheme.warm)
                Text("Nous portal\(portal.org.map { " · \($0)" } ?? "")")
                    .font(HermesTheme.brandSerif(size: 15))
                    .foregroundStyle(HermesTheme.ink)
                Spacer()
                if portal.ok {
                    Text("LIVE")
                        .font(.system(size: 8.5, weight: .bold))
                        .foregroundStyle(HermesTheme.green)
                        .tracking(1)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(HermesTheme.green.opacity(0.12), in: Capsule())
                }
            }
            if portal.ok {
                if let balance = parseUsd(portal.balanceUsd) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(money(balance))
                            .font(.system(size: 26, weight: .bold))
                            .foregroundStyle(balance < 0 ? HermesTheme.warm : HermesTheme.green)
                        Text(balance < 0 ? "solde négatif — crédits dépassés, la facturation suit sur la carte enregistrée" : "solde de crédits")
                            .font(.system(size: 10.5))
                            .foregroundStyle(HermesTheme.mutedText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                if let limit = parseUsd(portal.monthlyCapLimitUsd) {
                    HStack(spacing: 6) {
                        Image(systemName: "gauge.with.dots.needle.bottom.50percent")
                            .font(.system(size: 10))
                            .foregroundStyle(HermesTheme.mutedText)
                        Text("Cap mensuel : \(money(parseUsd(portal.monthlyCapSpentUsd) ?? 0)) / \(money(limit))")
                            .font(.system(size: 10.5))
                            .foregroundStyle(HermesTheme.mutedText)
                        if portal.autoReload == false {
                            Text("· auto-reload off")
                                .font(.system(size: 10))
                                .foregroundStyle(HermesTheme.mutedText.opacity(0.7))
                        }
                    }
                }
            } else {
                Text("Portail indisponible : \(portal.error ?? "inconnu")")
                    .font(.system(size: 10.5))
                    .foregroundStyle(HermesTheme.mutedText)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(HermesTheme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(portal.ok && (parseUsd(portal.balanceUsd) ?? 0) < 0 ? HermesTheme.warm.opacity(0.6) : HermesTheme.stroke, lineWidth: 1)
        )
    }

    private func parseUsd(_ raw: String?) -> Double? {
        raw.flatMap(Double.init)
    }

    // MARK: - Totals

    private func totalsGrid(_ total: HermesStatsTotal) -> some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 10) {
            statCard("Sessions", "\(total.sessions)", "clock")
            statCard("Messages", compact(total.messages), "text.bubble")
            statCard("Tokens", compact(total.totalTokens), "number")
            statCard("Est. cost", money(total.estimatedCostUsd), "dollarsign.circle")
        }
    }

    private func statCard(_ label: String, _ value: String, _ icon: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(HermesTheme.primary)
            Text(value)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(HermesTheme.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label.uppercased())
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(HermesTheme.mutedText)
                .tracking(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(HermesTheme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(HermesTheme.stroke, lineWidth: 1))
    }

    // MARK: - Daily activity

    private func dailyChart(_ daily: [HermesDailyStat]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("LAST 14 DAYS", "Sessions per day")
            if daily.isEmpty {
                Text("No activity in the last 14 days")
                    .font(.system(size: 12))
                    .foregroundStyle(HermesTheme.mutedText)
                    .padding(.vertical, 8)
            } else {
                Chart(daily) { day in
                    BarMark(
                        x: .value("Day", shortDay(day.day)),
                        y: .value("Sessions", day.sessions)
                    )
                    .foregroundStyle(HermesTheme.ring.gradient)
                    .cornerRadius(3)
                }
                .chartYAxis {
                    AxisMarks(position: .leading) { _ in
                        AxisGridLine().foregroundStyle(HermesTheme.stroke.opacity(0.6))
                        AxisTick().foregroundStyle(HermesTheme.stroke)
                        AxisValueLabel().foregroundStyle(HermesTheme.mutedText)
                    }
                }
                .chartXAxis {
                    AxisMarks { _ in
                        AxisValueLabel().foregroundStyle(HermesTheme.mutedText)
                    }
                }
                .frame(height: 130)
            }
        }
        .padding(12)
        .background(HermesTheme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(HermesTheme.stroke, lineWidth: 1))
    }

    // MARK: - Per-model / per-provider breakdown

    private func breakdown(eyebrow: String, title: String, rows: [StatRow]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle(eyebrow, title)
            let maxTokens = rows.map(\.tokens).max() ?? 1
            ForEach(rows) { stat in
                if stat.children.isEmpty {
                    rowView(stat, maxTokens: maxTokens)
                } else {
                    DisclosureGroup {
                        ForEach(stat.children) { child in
                            childRow(child)
                        }
                        .padding(.leading, 12)
                        .padding(.top, 6)
                    } label: {
                        rowView(stat, maxTokens: maxTokens)
                    }
                    .disclosureGroupStyle(StatDisclosureStyle())
                }
            }
            if rows.isEmpty {
                Text("No sessions yet")
                    .font(.system(size: 12))
                    .foregroundStyle(HermesTheme.mutedText)
            }
        }
        .padding(12)
        .background(HermesTheme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(HermesTheme.stroke, lineWidth: 1))
    }

    private func rowView(_ stat: StatRow, maxTokens: Int) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(stat.name)
                    .font(.system(size: 12.5, weight: .semibold))
                    .foregroundStyle(HermesTheme.ink)
                    .lineLimit(1)
                Spacer()
                costBadge(for: stat)
            }
            HStack(spacing: 8) {
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(HermesTheme.muted.opacity(0.7))
                        Capsule()
                            .fill(HermesTheme.ring.gradient)
                            .frame(width: max(4, geo.size.width * CGFloat(stat.tokens) / CGFloat(maxTokens)))
                    }
                }
                .frame(height: 7)
                Text("\(compact(stat.tokens)) tok · \(stat.sessions) sess")
                    .font(.system(size: 10))
                    .foregroundStyle(HermesTheme.mutedText)
                    .fixedSize()
            }
        }
    }

    private func childRow(_ child: StatRow) -> some View {
        HStack(spacing: 8) {
            Text(child.name)
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(HermesTheme.ink.opacity(0.9))
                .lineLimit(1)
            Spacer()
            Text("\(compact(child.tokens)) tok · \(child.sessions) sess")
                .font(.system(size: 10))
                .foregroundStyle(HermesTheme.mutedText)
                .fixedSize()
            Text(money(child.cost))
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(child.cost > 0 ? HermesTheme.primary : HermesTheme.mutedText)
        }
    }

    @ViewBuilder
    private func costBadge(for stat: StatRow) -> some View {
        if stat.isSubscriptionIncluded {
            Label("Inclus (abonnement)", systemImage: "checkmark.seal")
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(HermesTheme.mutedText)
                .fixedSize()
        } else if stat.isFullyUntracked {
            Label("Coût non tracé", systemImage: "questionmark.circle")
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(HermesTheme.warm)
                .fixedSize()
        } else if stat.isPartiallyTracked {
            Label("≈ \(money(stat.cost)) · partiel", systemImage: "exclamationmark.triangle")
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundStyle(HermesTheme.warm)
                .fixedSize()
        } else {
            Text(money(stat.cost))
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(HermesTheme.primary)
        }
    }

    private func costNote(_ stats: HermesStatsReport) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            noteRow("dollarsign.circle", "Estimé = tokens × tarifs fournisseur, calculé par le desktop (facturation au token).")
            noteRow("checkmark.seal", "« Inclus (abonnement) » = pas facturé au token → coût estimé 0.")
            noteRow("questionmark.circle", "« Coût non tracé » = le desktop n'enregistre pas les tokens (ex. Codex/terra-pro) → consulte la facture du fournisseur.")
            noteRow("exclamationmark.triangle", "« Partiel » = certaines sessions du modèle n'ont pas de tokens enregistrés → le coût affiché est sous-évalué.")
            noteRow("building.2", "Coût réel Nous portal = crédits sur portal.nousresearch.com — l'estimation utilise les tarifs configurés du desktop.")
        }
        .font(.system(size: 10.5))
        .foregroundStyle(HermesTheme.mutedText.opacity(0.85))
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 4)
    }

    private func noteRow(_ icon: String, _ text: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(HermesTheme.warm.opacity(0.8))
                .frame(width: 14)
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: - Helpers

    private func sectionTitle(_ eyebrow: String, _ title: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(eyebrow)
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(HermesTheme.mutedText)
                .tracking(1.1)
            Text(title)
                .font(HermesTheme.brandSerif(size: 15))
                .foregroundStyle(HermesTheme.ink)
        }
    }

    private func shortDay(_ day: String) -> String {
        day.count >= 10 ? String(day.suffix(5)) : day
    }

    private func compact(_ n: Int) -> String {
        if n >= 1_000_000 { return String(format: "%.1fM", Double(n) / 1_000_000) }
        if n >= 1_000 { return String(format: "%.0fK", Double(n) / 1_000) }
        return "\(n)"
    }

    private func money(_ value: Double) -> String {
        String(format: "$%.2f", value)
    }
}

/// One row in a stats breakdown — shared between the BY MODEL and
/// BY PROVIDER sections so both get identical badges and bars.
private struct StatRow: Identifiable {
    let id: String
    let name: String
    let sessions: Int
    let tokens: Int
    let cost: Double
    let costStatus: String
    let untrackedSessions: Int
    let children: [StatRow]

    init(model: HermesModelStat) {
        id = model.id
        name = model.model.split(separator: "/").last.map(String.init) ?? model.model
        sessions = model.sessions
        tokens = model.totalTokens
        cost = model.estimatedCostUsd
        costStatus = model.costStatus
        untrackedSessions = model.untrackedSessions
        children = []
    }

    init(provider: HermesProviderStat) {
        id = provider.id
        name = Self.providerName(provider.provider)
        sessions = provider.sessions
        tokens = provider.totalTokens
        cost = provider.estimatedCostUsd
        costStatus = provider.costStatus
        untrackedSessions = provider.untrackedSessions
        children = provider.models.map(StatRow.init(providerModel:))
    }

    init(providerModel: HermesProviderModel) {
        id = providerModel.id
        name = providerModel.model.split(separator: "/").last.map(String.init) ?? providerModel.model
        sessions = providerModel.sessions
        tokens = providerModel.tokens
        cost = providerModel.estimatedCostUsd
        costStatus = providerModel.costStatus
        untrackedSessions = providerModel.untrackedSessions
        children = []
    }

    var isSubscriptionIncluded: Bool { costStatus.lowercased().contains("included") }
    var isFullyUntracked: Bool { untrackedSessions >= sessions && tokens == 0 }
    var isPartiallyTracked: Bool { untrackedSessions > 0 && !isFullyUntracked }

    static func providerName(_ raw: String) -> String {
        switch raw.lowercased() {
        case "nous": return "Nous portal"
        case "deepseek": return "DeepSeek (direct)"
        case "openai-codex": return "OpenAI Codex"
        case "openai": return "OpenAI"
        case "anthropic": return "Anthropic"
        default: return "(non renseigné)"
        }
    }
}

/// Minimal themed disclosure: label + small chevron on the right,
/// expanded content below — no default list chrome.
private struct StatDisclosureStyle: DisclosureGroupStyle {
    func makeBody(configuration: Configuration) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation(.easeInOut(duration: 0.15)) {
                    configuration.isExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    configuration.label
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(HermesTheme.mutedText)
                        .rotationEffect(.degrees(configuration.isExpanded ? 90 : 0))
                }
            }
            .buttonStyle(.plain)
            if configuration.isExpanded {
                configuration.content
                    .transition(.opacity)
            }
        }
    }
}
