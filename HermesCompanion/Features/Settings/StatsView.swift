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
                        totalsGrid(stats.total)
                        dailyChart(stats.daily)
                        modelBreakdown(stats.byModel)
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

    // MARK: - Per-model breakdown

    private func modelBreakdown(_ models: [HermesModelStat]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("BY MODEL", "Tokens & cost")
            let maxTokens = models.map(\.totalTokens).max() ?? 1
            ForEach(models) { stat in
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Text(displayName(stat.model))
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(HermesTheme.ink)
                            .lineLimit(1)
                        Spacer()
                        Text(money(stat.estimatedCostUsd))
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(stat.estimatedCostUsd > 0 ? HermesTheme.primary : HermesTheme.mutedText)
                    }
                    HStack(spacing: 8) {
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule().fill(HermesTheme.muted.opacity(0.7))
                                Capsule()
                                    .fill(HermesTheme.ring.gradient)
                                    .frame(width: max(4, geo.size.width * CGFloat(stat.totalTokens) / CGFloat(maxTokens)))
                            }
                        }
                        .frame(height: 7)
                        Text("\(compact(stat.totalTokens)) tok · \(stat.sessions) sess")
                            .font(.system(size: 10))
                            .foregroundStyle(HermesTheme.mutedText)
                            .fixedSize()
                    }
                }
            }
            if models.isEmpty {
                Text("No sessions yet")
                    .font(.system(size: 12))
                    .foregroundStyle(HermesTheme.mutedText)
            }
        }
        .padding(12)
        .background(HermesTheme.card, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(HermesTheme.stroke, lineWidth: 1))
    }

    private func costNote(_ stats: HermesStatsReport) -> some View {
        let billed = stats.total.estimatedCostUsd > stats.total.actualCostUsd
        return Text(billed
            ? "Estimated cost is computed from per-provider pricing; subscription-included usage shows $0.00."
            : "All usage is billed per token. Actual cost: \(money(stats.total.actualCostUsd)).")
            .font(.system(size: 10.5))
            .foregroundStyle(HermesTheme.mutedText.opacity(0.85))
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
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

    private func displayName(_ model: String) -> String {
        model.split(separator: "/").last.map(String.init) ?? model
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
