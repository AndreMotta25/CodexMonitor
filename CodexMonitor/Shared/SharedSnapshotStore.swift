import Foundation

struct SharedSnapshotStore {
    static let groupID = "group.com.andremotta.codexmonitor"
    private var fileURL: URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: Self.groupID)?
            .appendingPathComponent("quota-snapshot.json")
    }

    func read() -> QuotaSnapshot? {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(QuotaSnapshot.self, from: data)
    }

    func write(_ snapshot: QuotaSnapshot) throws {
        guard let url = fileURL else { throw StoreError.groupUnavailable }
        try JSONEncoder().encode(snapshot).write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    func clear() throws {
        guard let url = fileURL else { throw StoreError.groupUnavailable }
        if FileManager.default.fileExists(atPath: url.path) { try FileManager.default.removeItem(at: url) }
    }

    enum StoreError: LocalizedError {
        case groupUnavailable
        var errorDescription: String? { "O compartilhamento com o widget não está habilitado na assinatura do app." }
    }
}
