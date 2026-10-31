# Codex Monitor

Aplicativo SwiftUI para iPhone com widgets na tela bloqueada e na tela inicial. Consulta diretamente a OpenAI, sem servidor próprio ou computador ligado após a instalação.

## Primeiro teste no iPhone

1. Abra `CodexMonitor.xcodeproj` no Xcode e selecione o scheme **CodexMonitor** e seu iPhone.
2. Confira a equipe em **Signing & Capabilities**, nos targets do app e da extensão. Ambos usam o mesmo App Group.
3. Execute o app. Toque em **Conectar conta**.
4. Copie o código apresentado, abra a autorização na OpenAI e conclua o login. Volte ao aplicativo.
5. Confira os percentuais com o painel oficial: <https://chatgpt.com/codex/settings/usage>.
6. Adicione **Cota do Codex** à tela bloqueada (retangular ou circular) ou à tela inicial (pequeno ou médio).

O botão de atualização do widget consulta a cota em segundo plano, sem abrir o app; o iOS pode exigir autenticação. Depois de atualizar da versão 0.1.x, abra o app uma vez para migrar a sessão existente com segurança. A janela principal pode ser escolhida nas configurações. O widget circular abre o app ao ser tocado.

## Integração experimental

O login usa o protocolo de código de dispositivo publicado no código do Codex, com seu identificador público de cliente. É uma sessão separada criada pelo próprio app; não são lidas credenciais do Codex instalado no Mac. Isso não equivale ao cadastro de um cliente independente no programa Sign in with ChatGPT nem comprova suporte para distribuição.

A cota é consultada em `https://chatgpt.com/backend-api/wham/usage`. Esse endpoint é interno e pode mudar. Sua autorização efetiva precisa ser validada na conta e no aparelho. A existência do código não comprova que a conta terá acesso. Nenhum dado de demonstração é exibido como saldo real.

Se a OpenAI desabilitar o fluxo de dispositivo ou negar a consulta, o app mostra o erro; não captura senha ou cookies, não contorna recusas e não cria um servidor alternativo.

## Dados e segurança

- Sessão no Keychain compartilhado entre app e extensão por meio do App Group, disponível somente quando o iPhone está desbloqueado, sem sincronização ou migração para outro aparelho.
- Tokens rotacionados são gravados imediatamente. Uma trava de arquivo no App Group serializa leitura, renovação, consulta, troca de conta e logout entre os processos do app e do widget. A trava é liberada também quando o processo termina.
- A extensão contém o mesmo serviço de sincronização e cliente HTTP do app. Ambos acessam as credenciais pelo Keychain e compartilham um snapshot em arquivo, gravado atomicamente e sem tokens.
- O cache preserva a data da última consulta em falhas. Dados com mais de 30 minutos ou renovação atingida aparecem como antigos. O saldo nunca é renovado localmente por estimativa.
- O app não registra corpos de resposta, tokens ou códigos de login. O cliente usa sessão efêmera e recusa redirecionamentos de rede.
- Desconectar apaga os dados locais. A autorização remota pode ser encerrada nas configurações de segurança da OpenAI.

## Estrutura e desenvolvimento

- `CodexMonitor/App`: interface e coordenação das consultas.
- `CodexMonitor/Auth`: acesso ao Keychain compartilhado e migração da sessão antiga.
- `CodexMonitor/Networking`: login por dispositivo, renovação e consulta direta.
- `CodexMonitor/Shared`: modelos, cálculo, snapshot, trava entre processos e AppIntent de atualização.
- `CodexMonitor/Sync`: serviço compartilhado de consulta, renovação e gerenciamento de sessão.
- `CodexMonitor/Widgets`: timelines de leitura do cache e interfaces dos widgets.
- `Tests`: validação dos limites, parsing, timestamps, cache e estados antigos.

O projeto Xcode está versionado e não exige geradores externos. Para regenerá-lo após adicionar arquivos Swift, execute `python3 scripts/generate_project.py`. A equipe e os identificadores pessoais estão no gerador; altere-os para instalar com outra conta.

```sh
export DEVELOPER_DIR=/Users/andremotta/Desktop/Xcode.app/Contents/Developer
swift test --scratch-path build/CoreTests
xcodebuild -project CodexMonitor.xcodeproj -scheme CodexMonitor \
  -destination 'generic/platform=iOS' -derivedDataPath build/Device \
  -allowProvisioningUpdates build
```

## Validação em aparelho

O usuário confirmou o login, a consulta real e os widgets na versão 0.1.x. Para 0.2.0: validar a migração sem novo login, o toque no botão sem abrir o app, falhas de rede preservando a última amostra, renovação de sessão, acesso simultâneo pelo app/widget e o comportamento com tela bloqueada. Os testes automatizados cobrem os modelos e a trava, incluindo exclusão real com outro processo.

## Referências

- [Fluxo de dispositivo no código público do Codex](https://github.com/openai/codex/blob/main/codex-rs/login/src/device_code_auth.rs).
- [Codex App Server](https://learn.chatgpt.com/docs/app-server): consulta oficial por JSON-RPC, sem uso neste app.
- [Sign in with ChatGPT](https://developers.openai.com/siwc/quickstart).
- [Projeto comunitário que utiliza consulta direta](https://github.com/yoyocircle/codex-usage-widget).
- [Interatividade dos widgets](https://developer.apple.com/documentation/widgetkit/adding-interactivity-to-widgets-and-live-activities).

Projeto pessoal independente, sem afiliação à OpenAI.

## Histórico — correção 0.1.1

O controle de recarregar usa um link direto para `codexmonitor://refresh`. A área restante do widget usa a mesma rota como fallback. O aplicativo recebe a URL e executa a mesma consulta do botão Atualizar agora, mesmo quando a amostra ainda está recente. Foi removida a ação AppIntent que podia falhar quando executada pela extensão. O toque abre o app após o desbloqueio; as credenciais continuam exclusivas do aplicativo.

## Versão 0.2.0

O botão usa um AppIntent com modo exclusivamente em segundo plano. A extensão executa uma consulta real pelo serviço compartilhado; não existe o caminho que lançava erro por estar na extensão. O corpo do widget mantém o link para abrir e atualizar no app, como alternativa. Na primeira abertura após a atualização, o app transfere a sessão do seu Keychain privado para o grupo compartilhado e só então apaga a cópia antiga, tudo sob a mesma trava. As credenciais nunca são gravadas em arquivo.
