# Compilar iOS sem Mac próprio

É possível desenvolver no Windows e usar um Mac remoto para compilar. O Xcode/macOS continuam presentes no servidor. Para este app Flutter, o projeto inclui `codemagic.yaml`; não é necessário migrar para Expo/React Native.

Os fontes estão disponíveis no [GitHub](https://github.com/Joao-AugustoPF/contextual-pdf-reader). Os fluxos iOS abaixo **ainda não foram executados**: é necessário conectar o repositório à sua conta Codemagic e, para distribuir, configurar a assinatura Apple.

## Primeiro: verificar a compilação sem assinatura

1. Use o repositório `Joao-AugustoPF/contextual-pdf-reader`, ou um fork seu. `codemagic.yaml` já fica na raiz, ao lado de `app`, `docs` e `packages`. A alternativa continua sendo extrair o ZIP e publicar os fontes em outro repositório seu.
2. No Codemagic, conecte esse repositório, selecione configuração por YAML e escolha **ios-verificar**. Inicie manualmente.
3. O servidor macOS instala as dependências, analisa Dart, roda os testes compartilhados, compila para iPhone e executa `RunnerTests` no simulador. Baixe os logs e o `.xcresult` se houver falha.
4. O `.app` sem assinatura **não pode ser instalado no seu iPhone/iPad**. Esse fluxo verifica a compilação e os testes nativos locais, sem exigir uma identidade de distribuição Apple.

O projeto fixa Flutter 3.47.7 e usa Xcode disponível no serviço. A oferta de máquinas/minutos e os custos dependem do plano vigente; confira a conta antes de iniciar. Referência: [Codemagic para Flutter](https://docs.codemagic.io/yaml-quick-start/building-a-flutter-app/).

## Depois: receber no iPhone e iPad pelo TestFlight

1. Tenha uma assinatura ativa do Apple Developer Program. Crie o Bundle ID e o registro do app no App Store Connect.
2. Crie uma chave App Store Connect com permissões adequadas e cadastre-a na integração Apple do Codemagic com o nome **entrelinhas-apple**. A chave e os certificados ficam no serviço, fora do ZIP/repositório.
3. Em **Code signing identities**, gere ou importe o certificado Apple Distribution e obtenha o provisioning profile App Store do app. O workflow seleciona esses arquivos por tipo `app_store` e Bundle ID.
4. O identificador padrão é `br.com.estudos.contextualPdfReader`. Se ele não estiver disponível na sua conta, troque-o no alvo Runner do projeto Xcode e no `bundle_identifier` de `codemagic.yaml`; faça a troca correspondente em RunnerTests quando necessário.
5. Execute **ios-verificar** e resolva eventuais falhas. Só então escolha **ios-testflight** manualmente. Esse segundo fluxo gera um IPA assinado, envia ao App Store Connect e solicita processamento/revisão beta; não publica na App Store.
6. Complete no App Store Connect as informações solicitadas pela Apple, configure testadores/grupos e aceite o convite pelo TestFlight nos dois aparelhos. Teste externo pode precisar de revisão beta. Cada build beta vale até 90 dias; novas compilações usam números de build crescentes no serviço.

O upload não dispensa conta Apple, assinatura, certificados nem análise da Apple. O equivalente ao build na nuvem do Expo é usar a infraestrutura macOS do Codemagic para o Flutter. GitHub Actions com runner macOS também é uma alternativa; o workflow GitHub incluído verifica somente análise e testes Dart, sem compilar iOS.

Fontes: [assinatura iOS no Codemagic](https://docs.codemagic.io/flutter-code-signing/ios-code-signing/), [distribuição Flutter/iOS](https://docs.flutter.dev/deployment/ios), [Apple/TestFlight](https://developer.apple.com/help/app-store-connect/test-a-beta-version/testflight-overview/).

## O que ainda precisa ser validado nos aparelhos

Os testes Dart com adaptador simulado validam o protocolo de salvamento, os hashes, conflitos e a persistência no banco. Os XCTest incluídos verificam bookmarks e escrita coordenada no sandbox do simulador quando executados no Mac. Nenhum deles substitui abrir um documento real do app Arquivos, salvar e conferir a alteração no mesmo arquivo em outro leitor.

Faça esse ensaio no iPhone e iPad, incluindo **No Meu iPhone/iPad**, **iCloud Drive**, reabertura após encerrar o app, edição/remoção, um arquivo de outro provedor e uma origem sem permissão de escrita. Se o provedor negar acesso, o app deve mostrar erro, preservar as anotações locais e não declarar que o original foi salvo. O app não implementa sincronização própria entre dispositivos; eventual sincronização de arquivos depende do provedor escolhido.
