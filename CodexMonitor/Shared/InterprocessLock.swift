import Foundation
import Darwin

/// Advisory lock shared by app and widget processes. The kernel releases it on process exit.
struct InterprocessLock: Sendable {
    let url: URL
    var timeout: TimeInterval = 4

    func withLock<T>(_ operation: () async throws -> T) async throws -> T {
        let descriptor = open(url.path, O_CREAT | O_RDWR | O_CLOEXEC | O_NOFOLLOW, S_IRUSR | S_IWUSR)
        guard descriptor >= 0 else { throw LockError.unavailable }
        defer { close(descriptor) }
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(timeout))
        while flock(descriptor, LOCK_EX | LOCK_NB) != 0 {
            guard errno == EWOULDBLOCK || errno == EAGAIN || errno == EINTR else { throw LockError.unavailable }
            try Task.checkCancellation()
            guard clock.now < deadline else { throw LockError.busy }
            try await Task.sleep(for: .milliseconds(80))
        }
        defer { flock(descriptor, LOCK_UN) }
        try Task.checkCancellation()
        return try await operation()
    }

    enum LockError: LocalizedError {
        case unavailable, busy
        var errorDescription: String? {
            switch self {
            case .unavailable: return "Não foi possível acessar a sessão compartilhada. Abra o app e tente novamente."
            case .busy: return "Uma atualização já está em andamento. Aguarde um instante."
            }
        }
    }
}
