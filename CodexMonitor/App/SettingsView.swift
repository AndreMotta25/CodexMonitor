import SwiftUI

struct SettingsView: View {
    let controller: QuotaController
    @Environment(\.dismiss) private var dismiss
    @State private var confirmDisconnect = false

    var body: some View {
        NavigationStack {
            Form {
                Section("Conta") {
                    LabeledContent("Sessão", value: controller.isConnected ? "Conectada neste iPhone" : "Desconectada")
                    if let plan = controller.snapshot?.planName { LabeledContent("Plano", value: plan.capitalized) }
                    if controller.isConnected {
                        Button("Desconectar deste iPhone", role: .destructive) { confirmDisconnect = true }.disabled(controller.isBusy)
                    }
                }
                if let snapshot = controller.snapshot {
                    Section("Janela principal do widget") {
                        ForEach(snapshot.windows) { window in
                            Button { Task { await controller.selectWindow(window.id) } } label: {
                                HStack {
                                    Text(window.title).foregroundStyle(.primary)
                                    Spacer()
                                    if snapshot.selectedWindow?.id == window.id { Image(systemName: "checkmark") }
                                }
                            }.disabled(controller.isBusy)
                        }
                    }
                }
                Section("Como atualizar") {
                    Text("O iOS decide quando atualizar o widget. O botão de atualizar consulta a cota em segundo plano sem abrir o app. Na tela bloqueada, o iOS pode exigir autenticação antes de executar a ação.")
                    Text("Dados com mais de 30 minutos ou com renovação já atingida aparecem como antigos. A renovação prevista nunca altera o saldo automaticamente.")
                }
                Section("Sobre esta versão") {
                    Text("Protótipo pessoal · 0.2.0")
                    Text("Usa uma interface interna da OpenAI para consultar a cota. A integração ainda está em validação e pode ficar indisponível se o serviço mudar.")
                    Text("App e widget acessam a sessão pelo Keychain compartilhado deste aparelho, somente quando desbloqueado. O arquivo de cota contém apenas números e horários. Nenhum servidor próprio é utilizado.")
                    Link("Abrir painel oficial de uso", destination: URL(string: "https://chatgpt.com/codex/settings/usage")!)
                }
            }
            .navigationTitle("Configurações")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Concluir") { dismiss() } } }
            .confirmationDialog("Desconectar a conta?", isPresented: $confirmDisconnect, titleVisibility: .visible) {
                Button("Apagar sessão e cota deste iPhone", role: .destructive) { Task { await controller.disconnect() } }
            } message: { Text("Para encerrar também a autorização na OpenAI, gerencie suas sessões nas configurações da conta.") }
        }
    }
}
