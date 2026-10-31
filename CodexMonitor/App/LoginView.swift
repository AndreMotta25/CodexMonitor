import SwiftUI
import SafariServices

struct LoginView: View {
    let controller: QuotaController
    @State private var showBrowser = false
    @State private var copied = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    Image(systemName: "person.badge.key").font(.system(size: 48)).foregroundStyle(.tint).padding(.top, 20)
                    Text("Conectar ao Codex").font(.title.bold())
                    Text("Este protótipo usa o login por código de dispositivo do Codex. A autorização acontece no site da OpenAI.")
                        .foregroundStyle(.secondary).multilineTextAlignment(.center)
                    if let authorization = controller.authorization {
                        VStack(spacing: 12) {
                            Text("SEU CÓDIGO").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                            Text(authorization.code).font(.system(.largeTitle, design: .monospaced).bold()).textSelection(.enabled)
                            Button(copied ? "Código copiado" : "Copiar código", systemImage: copied ? "checkmark" : "doc.on.doc") {
                                UIPasteboard.general.setItems([[UIPasteboard.typeAutomatic: authorization.code]],
                                    options: [.localOnly: true, .expirationDate: authorization.expiresAt])
                                copied = true
                            }
                        }.frame(maxWidth: .infinity).padding(24).background(.quaternary, in: RoundedRectangle(cornerRadius: 20))
                        Button("Abrir autorização na OpenAI", systemImage: "safari") { showBrowser = true }
                            .buttonStyle(.borderedProminent)
                        Text("Digite o código, autorize e volte para este app. A conexão será concluída automaticamente. O código expira em 15 minutos.")
                            .font(.footnote).foregroundStyle(.secondary).multilineTextAlignment(.center)
                        Text("Se a OpenAI informar que o login por dispositivo está desativado, confira essa opção nas configurações de segurança da conta.")
                            .font(.footnote).foregroundStyle(.secondary)
                    } else if controller.isBusy {
                        ProgressView("Gerando código…")
                    }
                    if controller.lastOperationFailed, let message = controller.message {
                        Label(message, systemImage: "exclamationmark.circle").foregroundStyle(.orange)
                        Button("Tentar novamente") { controller.beginLogin() }.disabled(controller.isBusy)
                    }
                }.padding(24)
            }
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Cancelar") { controller.cancelLogin() } } }
            .sheet(isPresented: $showBrowser) { AuthorizationBrowser() }
        }
    }
}

private struct AuthorizationBrowser: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: DeviceAuthorization.verificationURL)
    }
    func updateUIViewController(_ uiViewController: SFSafariViewController, context: Context) {}
}
