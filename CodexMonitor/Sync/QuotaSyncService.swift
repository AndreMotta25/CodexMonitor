import Foundation
import WidgetKit

/// Each process gets an actor; the file lock also serializes the *other* process.
actor QuotaSyncService {
    static let shared = QuotaSyncService()
    private let client = CodexClient()
    private let tokens = SecureTokenStore()
    private let store = SharedSnapshotStore()

    private func sessionLock() throws -> InterprocessLock {
        guard let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: SharedSnapshotStore.groupID) else {
            throw SharedSnapshotStore.StoreError.groupUnavailable
        }
        return InterprocessLock(url: container.appendingPathComponent("session-operation.lock"))
    }

    func hasSession() async throws -> Bool {
        try await sessionLock().withLock { try self.hasSessionLocked() }
    }
    private func hasSessionLocked() throws -> Bool {
        try tokens.migrateLegacySessionIfNeeded()
        return try tokens.read() != nil
    }

    func replaceSession(_ credentials: Credentials) async throws {
        try await sessionLock().withLock { try self.replaceSessionLocked(credentials) }
        WidgetCenter.shared.reloadAllTimelines()
    }
    private func replaceSessionLocked(_ credentials: Credentials) throws {
        try tokens.save(credentials)
        try tokens.migrateLegacySessionIfNeeded()
        try store.clear()
    }

    func disconnect() async throws {
        try await sessionLock().withLock { try self.disconnectLocked() }
        WidgetCenter.shared.reloadAllTimelines()
    }
    private func disconnectLocked() throws {
        try tokens.clear()
        try store.clear()
    }

    func selectWindow(_ id: String) async throws -> QuotaSnapshot? {
        let result = try await sessionLock().withLock { try self.selectWindowLocked(id) }
        WidgetCenter.shared.reloadAllTimelines()
        return result
    }
    private func selectWindowLocked(_ id: String) throws -> QuotaSnapshot? {
        guard var snapshot = store.read() else { return nil }
        snapshot.selectedWindowID = id
        try store.write(snapshot)
        return snapshot
    }

    @discardableResult
    func refresh() async throws -> QuotaSnapshot {
        defer { WidgetCenter.shared.reloadAllTimelines() }
        return try await sessionLock().withLock { try await self.refreshLocked() }
    }
    private func refreshLocked() async throws -> QuotaSnapshot {
        do {
            try tokens.migrateLegacySessionIfNeeded()
            guard var credentials = try tokens.read() else { throw MonitorError.notConnected }
            var didRefresh = false
            if credentials.expiresAt.timeIntervalSinceNow < 60 {
                credentials = try await client.refresh(credentials)
                // Persist before proceeding; a rotated token is now the canonical token.
                try tokens.save(credentials)
                didRefresh = true
            }
            var updated: QuotaSnapshot
            do { updated = try await client.quota(using: credentials) }
            catch MonitorError.http(401) where !didRefresh {
                credentials = try await client.refresh(credentials)
                try tokens.save(credentials)
                updated = try await client.quota(using: credentials)
            }
            updated.selectedWindowID = store.read()?.selectedWindowID
            try store.write(updated)
            return updated
        } catch {
            // Preserve the last valid numbers and timestamp on failure.
            if !(error is CancellationError), var previous = store.read() {
                previous.status = Self.status(for: error)
                try? store.write(previous)
            }
            throw error
        }
    }

    static func status(for error: Error) -> SyncStatus {
        if error is QuotaDecodeError || error is DecodingError { return .parsingError }
        if error is URLError { return .offline }
        if case MonitorError.notConnected = error { return .unauthorized }
        if case MonitorError.http(401) = error { return .unauthorized }
        return .temporarilyUnavailable
    }
}
