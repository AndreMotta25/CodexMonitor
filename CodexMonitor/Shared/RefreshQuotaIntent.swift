import AppIntents
import WidgetKit

struct RefreshQuotaIntent: AppIntent {
    static var title: LocalizedStringResource = "Atualizar cota do Codex"
    static var description = IntentDescription("Consulta a cota em segundo plano sem abrir o aplicativo.")
    static var supportedModes: IntentModes { .background }
    static var authenticationPolicy: IntentAuthenticationPolicy { .requiresAuthentication }
    static var isDiscoverable: Bool { false }

    func perform() async throws -> some IntentResult {
        do {
            try await QuotaSyncService.shared.refresh()
        } catch {
            // The service persists a safe error status for the widget to display.
            // Do not throw: WidgetKit must render the preserved sample and its status.
        }
        return .result()
    }
}
