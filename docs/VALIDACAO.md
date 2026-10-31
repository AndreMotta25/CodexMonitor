# Validação — 30/10/2026

## Confirmado neste ambiente

- Xcode 26.3 (17C529), SDK iPhoneOS 26.2.
- iPhone 12 pareado e disponível, com modo de desenvolvedor habilitado.
- Build de desenvolvimento para iOS concluído com sucesso: aplicativo e Widget Extension.
- Assinatura automática concluída; os dois targets incluem o mesmo App Group.
- Aplicativo com extensão instalado no iPhone pelo serviço de dispositivos do Xcode.
- Cinco testes de núcleo passaram, sem falhas: múltiplas janelas, consumo/restante, campos ausentes e inválidos, timestamps em segundos, cache e expiração sem inventar saldo.

## Ainda depende do teste interativo no iPhone

- Autorização da conta pelo fluxo de código de dispositivo e consulta real.
- Comparação do saldo e da renovação com o painel oficial do Codex.
- Interação do controle de atualização na tela bloqueada e execução da consulta no app.
- Renovação de sessão após expiração, reinício, modo avião e retorno da rede.

Não foram acessadas as credenciais existentes do Codex no Mac. Não foi usado servidor próprio. O usuário conclui a autorização no site da OpenAI, pelo navegador do iPhone.

## Observação sobre recursos visuais

O serviço de compilação de catálogos de imagens do Xcode ficou aguardando seu agente de Simulator. Para permitir o teste diretamente no iPhone, o build usa ícones PNG independentes, gerados a partir do desenho original no script `scripts/generate_icon.py`. O catálogo também foi preservado como fonte, mas não faz parte da fase de recursos deste build. Uma futura distribuição pela App Store deve revisar o empacotamento do ícone e os requisitos de cadastro e autorização da integração.

## Correção do recarregamento — versão 0.1.1

O usuário confirmou que a consulta pelo app funciona e enviou uma imagem do widget exibindo o snapshot na tela bloqueada. O controle de atualização original tinha uma implementação que lançava erro quando executada na extensão. A versão 0.1.1 remove esse caminho e usa `Link` e `widgetURL` com `codexmonitor://refresh`, já tratado pelo app para consultar a cota sem depender da idade da amostra. O comportamento esperado continua sendo desbloquear, abrir o app e atualizar.

A compilação e a assinatura da correção devem preceder a instalação. A verificação final requer tocar no widget no iPhone e conferir a mudança do horário da consulta; a compilação, sozinha, não comprova esse comportamento.

### Teste da correção no aparelho

Versão 0.1.1 (build 2) instalada pela rede no iPhone 12. A abertura de `codexmonitor://refresh` pelo serviço de dispositivos iniciou a consulta: o snapshot avançou de 14:36:50 para 14:46:23 (America/Sao_Paulo), com status final `current`. Não foi necessário novo login. Esse teste valida o tratamento da URL e a consulta, mas o toque físico no controle do widget ainda precisa ser confirmado pelo usuário.

## Atualização em segundo plano — versão 0.2.0

- Build 3 compilado, assinado e instalado pela rede no iPhone 12.
- O app migrou a sessão existente para o Keychain do App Group; a consulta pelo serviço compartilhado foi concluída às 14:55:59 (America/Sao_Paulo), com status `current`, sem pedir novo login.
- O usuário testou fisicamente a seta do widget e confirmou: **atualizou sem abrir o app**.
- O AppIntent usa somente modo de execução em segundo plano, sem `openAppWhenRun`, e exige autenticação. A leitura da sessão permanece protegida por `WhenUnlockedThisDeviceOnly`.
- App e extensão usam a mesma trava de arquivo, incluindo renovação de token, troca de conta, logout e gravação do snapshot. A migração só apaga a cópia antiga após salvar a sessão compartilhada.
- Oito testes passaram: os cinco de parsing/cota/cache e três de exclusão mútua, liberação após erro e disputa com outro processo real.

Ainda não foram reproduzidos no aparelho: expiração/rotação real de token, revogação remota, modo avião e operações simultâneas de widget e app. O teste do botão foi confirmado pelo usuário; não foi automatizado por toque remoto.
