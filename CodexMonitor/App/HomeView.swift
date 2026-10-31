import SwiftUI

struct HomeView: View {
    @Bindable var controller: QuotaController
    @State private var showSettings = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    if let snapshot = controller.snapshot {
                        ForEach(snapshot.windows) { window in
                            QuotaCard(window: window,
                                selected: snapshot.selectedWindow?.id == window.id,
                                stale: snapshot.isStale(at: Date()))
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            Label {
                                Text("Última consulta: \(snapshot.fetchedAt.formatted(date: .abbreviated, time: .shortened))")
                            } icon: { Image(systemName: "clock") }
                            if snapshot.isStale(at: Date()) {
                                Text("Dados antigos. Atualize para confirmar sua cota.").foregroundStyle(.orange)
                            }
                        }
                        .font(.footnote).foregroundStyle(.secondary)
                    } else {
                        ContentUnavailableView {
                            Label(controller.isConnected ? "Pronto para consultar" : "Sua cota, por perto", systemImage: "chart.bar.xaxis")
                        } description: {
                            Text(controller.isConnected
                                ? "Atualize para buscar os limites da sua conta."
                                : "Conecte sua conta do Codex para acompanhar o saldo de uso e a próxima renovação.")
                        }
                        .padding(.vertical, 12)
                    }
                    if let message = controller.message {
                        Label(message, systemImage: controller.lastOperationFailed ? "exclamationmark.circle" : "checkmark.circle")
                            .font(.subheadline)
                            .foregroundStyle(controller.lastOperationFailed ? Color.orange : Color.secondary)
                            .accessibilityIdentifier("sync-message")
                    }
                    actionButton
                    if controller.lastOperationFailed && controller.isConnected {
                        Button("Reconectar conta") { controller.beginLogin() }
                            .frame(maxWidth: .infinity).disabled(controller.isBusy)
                    }
                    Label("Conexão direta com a OpenAI", systemImage: "lock.shield")
                        .font(.footnote).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                }
                .padding(24)
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Codex Monitor")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Configurações", systemImage: "gearshape") { showSettings = true }
                }
            }
            .sheet(isPresented: $showSettings) { SettingsView(controller: controller) }
            .sheet(isPresented: $controller.showLogin, onDismiss: { controller.cancelLogin() }) {
                LoginView(controller: controller)
            }
            .refreshable { if controller.isConnected { await controller.refresh() } }
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 8) {
                Text("SEU USO DO CODEX").font(.caption.weight(.semibold)).tracking(1.5).foregroundStyle(.secondary)
                Text("Espaço para criar.").font(.largeTitle.bold())
                Text("Acompanhe quanto ainda está disponível.").foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if let plan = controller.snapshot?.planName {
                Text(plan.capitalized).font(.caption.bold())
                    .padding(.horizontal, 10).padding(.vertical, 6)
                    .background(.tint.opacity(0.12), in: Capsule())
            }
        }
    }

    private var actionButton: some View {
        Button {
            if controller.isConnected { Task { await controller.refresh() } }
            else { controller.beginLogin() }
        } label: {
            HStack {
                if controller.isBusy { ProgressView().tint(.white) }
                else { Image(systemName: controller.isConnected ? "arrow.clockwise" : "person.badge.key") }
                Text(controller.isBusy ? "Aguarde…" : controller.isConnected ? "Atualizar agora" : "Conectar conta")
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity, minHeight: 40)
        }
        .buttonStyle(.borderedProminent)
        .disabled(controller.isBusy)
    }
}

private struct QuotaCard: View {
    let window: QuotaWindow
    let selected: Bool
    let stale: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(window.title).font(.headline)
                Spacer()
                if selected { Image(systemName: "widget.small").foregroundStyle(.secondary).accessibilityLabel("Janela do widget") }
            }
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(window.remainingPercent / 100, format: .percent.precision(.fractionLength(0)))
                    .font(.system(size: 54, weight: .semibold, design: .rounded)).monospacedDigit()
                Text("disponível").font(.subheadline).foregroundStyle(.secondary)
            }
            ProgressView(value: window.remainingPercent, total: 100)
                .tint(window.remainingPercent <= 10 ? .orange : .accentColor)
                .accessibilityLabel("Cota disponível").accessibilityValue("\(Int(window.remainingPercent)) por cento")
            if let reset = window.resetsAt {
                if reset > Date() {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.trianglehead.2.clockwise.rotate.90")
                        Text("Renova \(reset.formatted(.relative(presentation: .named)))")
                    }.font(.footnote).foregroundStyle(.secondary)
                } else {
                    Text("Horário de renovação atingido. Consulte novamente.").font(.footnote).foregroundStyle(.secondary)
                }
            }
            if window.remainingPercent == 0 { Text("Limite atingido").font(.caption.bold()).foregroundStyle(.orange) }
        }
        .padding(22)
        .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 24))
        .overlay(alignment: .topTrailing) {
            if stale { Text("ÚLTIMA AMOSTRA").font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary).padding(.top, 6).padding(.trailing, 20) }
        }
    }
}
