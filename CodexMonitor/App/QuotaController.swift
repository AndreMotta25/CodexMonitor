import Foundation
import Observation
import WidgetKit

@MainActor
@Observable
final class QuotaController {
    static let shared = QuotaController()
    private(set) var snapshot: QuotaSnapshot?
    private(set) var isConnected = false
    private(set) var isBusy = false
    private(set) var authorization: DeviceAuthorization?
    private(set) var message: String?
    private(set) var lastOperationFailed = false
    var showLogin = false
    @ObservationIgnored private let client = CodexClient()
    @ObservationIgnored private let service = QuotaSyncService.shared
    @ObservationIgnored private let store = SharedSnapshotStore()
    @ObservationIgnored private var loginTask: Task<Void, Never>?
    @ObservationIgnored private var isActivating = false
    @ObservationIgnored private var refreshAfterActivation = false

    private init() { snapshot = store.read() }

    /// Migrates the existing session and reads any changes made by the widget.
    func activate() async {
        guard !isBusy else { return }
        isBusy = true
        isActivating = true
        do {
            isConnected = try await service.hasSession()
            snapshot = store.read()
            WidgetCenter.shared.reloadAllTimelines()
        } catch { fail(error) }
        isActivating = false
        isBusy = false
        let requested = refreshAfterActivation
        refreshAfterActivation = false
        if isConnected, requested || snapshot?.isStale(at: Date()) != false { await refresh() }
    }

    func beginLogin() {
        guard !isBusy else { return }
        isBusy = true
        message = nil
        authorization = nil
        showLogin = true
        lastOperationFailed = false
        loginTask = Task {
            defer { isBusy = false; loginTask = nil }
            do {
                let pending = try await client.requestDeviceAuthorization()
                try Task.checkCancellation()
                authorization = pending
                let credentials = try await client.waitForAuthorization(pending)
                try Task.checkCancellation()
                try await service.replaceSession(credentials)
                snapshot = nil
                isConnected = true
                authorization = nil
                showLogin = false
                isBusy = false
                Task { await refresh() }
            } catch is CancellationError {
                authorization = nil
            } catch {
                if !Task.isCancelled { fail(error) }
            }
        }
    }

    func cancelLogin() {
        loginTask?.cancel()
        authorization = nil
        showLogin = false
    }

    func refresh() async {
        guard !isBusy else {
            if isActivating { refreshAfterActivation = true }
            return
        }
        isBusy = true
        lastOperationFailed = false
        message = nil
        defer { isBusy = false }
        do {
            snapshot = try await service.refresh()
            isConnected = true
            message = "Cota atualizada"
        } catch {
            snapshot = store.read()
            fail(error)
        }
    }

    func selectWindow(_ id: String) async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        do { snapshot = try await service.selectWindow(id) }
        catch { fail(error) }
    }

    func disconnect() async {
        guard !isBusy else { return }
        isBusy = true
        defer { isBusy = false }
        do {
            try await service.disconnect()
            isConnected = false
            snapshot = nil
            message = nil
            lastOperationFailed = false
        } catch { fail(error) }
    }

    private func fail(_ error: Error) {
        lastOperationFailed = true
        message = error.localizedDescription
        if error is QuotaDecodeError || error is DecodingError {
            message = SyncStatus.parsingError.message
        } else if error is URLError {
            message = "Não foi possível alcançar a OpenAI. Confira sua conexão e tente novamente."
        }
    }
}
