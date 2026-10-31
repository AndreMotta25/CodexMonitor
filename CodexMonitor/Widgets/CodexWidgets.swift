import SwiftUI
import WidgetKit

struct QuotaEntry: TimelineEntry {
    let date: Date
    let snapshot: QuotaSnapshot?
    var stale: Bool { snapshot?.isStale(at: date) ?? true }
}

struct QuotaProvider: TimelineProvider {
    func placeholder(in context: Context) -> QuotaEntry { QuotaEntry(date: Date(), snapshot: nil) }
    func getSnapshot(in context: Context, completion: @escaping (QuotaEntry) -> Void) {
        completion(QuotaEntry(date: Date(), snapshot: SharedSnapshotStore().read()))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<QuotaEntry>) -> Void) {
        let now = Date()
        let snapshot = SharedSnapshotStore().read()
        var dates = [now]
        if let fetched = snapshot?.fetchedAt {
            let staleAt = fetched.addingTimeInterval(1800)
            if staleAt > now { dates.append(staleAt) }
        }
        if let reset = snapshot?.selectedWindow?.resetsAt, reset > now { dates.append(reset) }
        let entries = Array(Set(dates)).sorted().map { QuotaEntry(date: $0, snapshot: snapshot) }
        // Cache-only: these visual updates never imply a fresh network query.
        completion(Timeline(entries: entries, policy: .after(now.addingTimeInterval(1800))))
    }
}

struct QuotaWidgetView: View {
    let entry: QuotaEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        Group {
            if let window = entry.snapshot?.selectedWindow {
                switch family {
                case .accessoryCircular: circular(window)
                case .accessoryRectangular: rectangular(window)
                default: home(window)
                }
            } else {
                VStack(spacing: 3) {
                    Image(systemName: "chart.bar.xaxis")
                    Text(family == .accessoryCircular ? "Abrir" : "Conecte no app").font(.caption)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .containerBackground(for: .widget) { Color(.systemBackground) }
        .widgetURL(URL(string: "codexmonitor://refresh")!)
        .privacySensitive()
    }

    private var statusLabel: String {
        switch entry.snapshot?.status {
        case .unauthorized: return "Reconecte no app"
        case .offline: return "Sem rede"
        case .temporarilyUnavailable, .parsingError: return "Falha na consulta"
        default: return entry.stale ? "Antigo" : "Consulta"
        }
    }

    private func circular(_ window: QuotaWindow) -> some View {
        Gauge(value: window.remainingPercent, in: 0...100) {
            Image(systemName: entry.stale ? "clock.badge.exclamationmark" : "chart.bar.xaxis")
        } currentValueLabel: {
            Text("\(Int(window.remainingPercent))%").font(.caption.bold()).minimumScaleFactor(0.6)
        }
        .gaugeStyle(.accessoryCircular)
        .accessibilityLabel("Codex, \(Int(window.remainingPercent)) por cento disponível. \(entry.stale ? "Dados antigos" : "Última consulta")")
    }

    private func rectangular(_ window: QuotaWindow) -> some View {
        HStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Codex · \(window.durationLabel)").font(.caption.weight(.semibold)).lineLimit(1)
                Text("\(Int(window.remainingPercent))% disponível").invalidatableContent().font(.headline).minimumScaleFactor(0.7).lineLimit(1)
                if let reset = window.resetsAt {
                    Text(reset > entry.date ? "Renova \(reset.formatted(date: .omitted, time: .shortened))" : "Consulte a renovação")
                        .font(.system(size: 10)).lineLimit(1)
                }
                if let fetched = entry.snapshot?.fetchedAt {
                    Text("\(statusLabel) \(fetched.formatted(date: .omitted, time: .shortened))")
                        .font(.system(size: 9)).lineLimit(1)
                }
            }
            Spacer(minLength: 0)
            Button(intent: RefreshQuotaIntent()) {
                Image(systemName: "arrow.clockwise")
                    .frame(minWidth: 32, minHeight: 44)
                    .contentShape(Rectangle())
            }
                .buttonStyle(.plain).accessibilityLabel("Atualizar cota sem abrir o app")
        }
    }

    private func home(_ window: QuotaWindow) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Codex").font(.headline)
                Spacer()
                Button(intent: RefreshQuotaIntent()) {
                    Image(systemName: "arrow.clockwise")
                        .frame(minWidth: 36, minHeight: 28)
                        .contentShape(Rectangle())
                }
                    .buttonStyle(.plain).accessibilityLabel("Atualizar cota sem abrir o app")
            }
            Text("\(Int(window.remainingPercent))%").invalidatableContent().font(.system(size: 36, weight: .semibold, design: .rounded))
            Text("disponível · \(window.durationLabel)").font(.caption).foregroundStyle(.secondary)
            ProgressView(value: window.remainingPercent, total: 100).tint(.green)
            if let reset = window.resetsAt {
                Text(reset > entry.date ? "Renova \(reset.formatted(date: .omitted, time: .shortened))" : "Consulte a renovação")
                    .font(.caption2).foregroundStyle(.secondary)
            }
            if let fetched = entry.snapshot?.fetchedAt {
                Text("\(statusLabel) · \(fetched.formatted(date: .omitted, time: .shortened))")
                    .font(.system(size: 9)).foregroundStyle(.secondary)
            }
        }
    }
}

@main
struct CodexQuotaWidget: Widget {
    let kind = "CodexQuotaWidget"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: QuotaProvider()) { entry in QuotaWidgetView(entry: entry) }
            .configurationDisplayName("Cota do Codex")
            .description("Última cota consultada. Atualize pelo botão sem abrir o app. Pode exigir desbloqueio.")
            .supportedFamilies([.accessoryRectangular, .accessoryCircular, .systemSmall, .systemMedium])
    }
}
