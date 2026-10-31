import Foundation

struct QuotaWindow: Codable, Identifiable, Equatable, Sendable {
    let id: String
    let bucket: String
    let usedPercent: Double
    let durationSeconds: Int?
    let resetsAt: Date?

    var remainingPercent: Double { max(0, min(100, 100 - usedPercent)) }
    var durationLabel: String {
        guard let seconds = durationSeconds, seconds > 0 else { return "Janela de uso" }
        if seconds % 86400 == 0 { return "\(seconds / 86400) dias" }
        if seconds % 3600 == 0 { return "\(seconds / 3600) horas" }
        return "\(max(1, seconds / 60)) min"
    }
    var title: String { bucket == "Codex" ? durationLabel : "\(bucket) · \(durationLabel)" }
}

enum SyncStatus: String, Codable, Sendable {
    case current, unauthorized, offline, temporarilyUnavailable, parsingError

    var message: String {
        switch self {
        case .current: return "Consulta concluída"
        case .unauthorized: return "Reconecte sua conta"
        case .offline: return "Sem conexão. Exibindo a última consulta."
        case .temporarilyUnavailable: return "Não foi possível atualizar. Tente novamente."
        case .parsingError: return "A resposta de uso mudou ou não trouxe limites válidos."
        }
    }
}

struct QuotaSnapshot: Codable, Equatable, Sendable {
    let windows: [QuotaWindow]
    let planName: String?
    let fetchedAt: Date
    var status: SyncStatus
    var selectedWindowID: String?

    var selectedWindow: QuotaWindow? {
        windows.first { $0.id == selectedWindowID } ?? windows.first
    }
    func isStale(at date: Date) -> Bool {
        status != .current || date.timeIntervalSince(fetchedAt) >= 1800 ||
        selectedWindow?.resetsAt.map { $0 <= date } == true
    }
}

enum QuotaDecodeError: Error { case missingWindows, invalidWindow }

/// This adapter is the only place that knows the experimental usage response.
enum QuotaDecoder {
    static func decode(_ data: Data, at date: Date = Date()) throws -> QuotaSnapshot {
        let response = try JSONDecoder().decode(UsageResponse.self, from: data)
        var windows: [QuotaWindow] = []
        func append(_ limit: UsageResponse.Limit?, id: String, label: String) throws {
            for (key, window) in [("primary", limit?.primary_window), ("secondary", limit?.secondary_window)] {
                guard let window else { continue }
                guard let used = window.used_percent, used.isFinite, (0...100).contains(used),
                      window.limit_window_seconds.map({ $0 > 0 }) ?? true,
                      window.reset_at.map({ $0.isFinite && $0 > 0 }) ?? true else {
                    throw QuotaDecodeError.invalidWindow
                }
                windows.append(QuotaWindow(id: "\(id).\(key)", bucket: label, usedPercent: used,
                    durationSeconds: window.limit_window_seconds,
                    resetsAt: window.reset_at.map { Date(timeIntervalSince1970: $0) }))
            }
        }
        try append(response.rate_limit, id: "codex", label: "Codex")
        for (index, additional) in (response.additional_rate_limits ?? []).enumerated() {
            try append(additional.rate_limit,
                id: "additional.\(additional.limit_name ?? additional.normal_model_slug ?? String(index))",
                label: additional.limit_name ?? additional.normal_model_slug ?? "Limite adicional")
        }
        guard !windows.isEmpty else { throw QuotaDecodeError.missingWindows }
        return QuotaSnapshot(windows: windows, planName: response.plan_type, fetchedAt: date, status: .current)
    }

    private struct UsageResponse: Decodable {
        let plan_type: String?
        let rate_limit: Limit?
        let additional_rate_limits: [Additional]?
        struct Limit: Decodable {
            let primary_window: Window?
            let secondary_window: Window?
        }
        struct Window: Decodable {
            let used_percent: Double?
            let limit_window_seconds: Int?
            let reset_at: Double?
        }
        struct Additional: Decodable {
            let limit_name: String?
            let normal_model_slug: String?
            let rate_limit: Limit?
        }
    }
}
