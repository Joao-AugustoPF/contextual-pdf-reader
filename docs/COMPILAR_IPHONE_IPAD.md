# Compilar no Mac e instalar no iPhone/iPad

Roteiro preparado em 23/10/2026. O código tem alvo universal iPhone/iPad (`TARGETED_DEVICE_FAMILY = 1,2`) e mínimo iOS/iPadOS 16.0. Ainda não houve compilação nem teste iOS neste projeto: os passos abaixo precisam ser executados no Mac para verificar plugins, assinatura e funcionamento real.

Sem Mac próprio, use o roteiro [Build iOS na nuvem](BUILD_IOS_NUVEM.md). O ZIP já inclui dois workflows manuais do Codemagic: verificação sem assinatura e distribuição assinada pelo TestFlight.

## O que enviar

O projeto também está disponível no [GitHub](https://github.com/Joao-AugustoPF/contextual-pdf-reader). Seu amigo pode executar `git clone https://github.com/Joao-AugustoPF/contextual-pdf-reader.git` e seguir os mesmos passos abaixo a partir da pasta clonada, sem precisar receber um ZIP a cada atualização.

Envie `contextual-pdf-reader-ios-fontes.zip`, gerado em `dist`, e peça para começar por este arquivo, dentro da pasta `docs`. O pacote inclui código Dart, assets, projeto Xcode, versões das dependências e testes compartilhados. Não inclui seus PDFs, banco de anotações, credenciais, modelos instalados, executáveis Windows ou SDK Flutter. Não é um IPA instalável.

## Preparar o Mac

Instale Xcode completo e o suporte à plataforma iOS, Flutter **3.47.7 stable** (Dart 3.13.5, versão usada aqui) e CocoaPods. O macOS precisa ser compatível com o Xcode escolhido, e esse Xcode precisa suportar a versão do sistema dos seus aparelhos. Se essa versão do Flutter não puder ser instalada no ambiente, registre a versão utilizada antes de ajustar dependências; não rode `pub upgrade` como primeiro passo.

Abra o Xcode uma vez e conclua a configuração/licenças. Para selecionar as ferramentas e instalar suporte iOS, use no Terminal do Mac:

```bash
sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
sudo xcodebuild -runFirstLaunch
xcodebuild -downloadPlatform iOS
flutter --version
flutter doctor -v
pod --version
```

Siga a [configuração oficial do Flutter para iOS](https://docs.flutter.dev/platform-integration/ios/setup) para corrigir o que aparecer no diagnóstico. Não é necessário Python, PyInstaller ou CTranslate2 no iPhone: a tradução mobile usa ML Kit nativo; MiniLM usa ONNX nativo.

## Preparar e verificar o projeto

Extraia o ZIP. No Terminal, entre na pasta `app` do conteúdo extraído:

```bash
cd contextual-pdf-reader/app
flutter pub get
flutter analyze
flutter build ios --release --config-only --no-codesign
open ios/Runner.xcworkspace
```

O comando de configuração prepara os arquivos gerados e as dependências nativas. O projeto usa Swift Package Manager; Flutter pode também preparar CocoaPods para plugins que precisem dele. O ZIP não leva arquivos gerados com caminhos do Windows. Não abra apenas o `.xcodeproj` e não tente usar o build Windows no Mac.

Se falhar nesta etapa, guarde o erro completo. Este pacote não é uma build iOS já validada. Confirme mínimo 16.0 também nos Pods/configurações geradas quando houver erro de deployment target. Não reduza o mínimo: o plugin ONNX exige iOS 16.

## Instalar diretamente, usando conta gratuita

Leve **seu iPhone e seu iPad**, com os cabos, ao Mac. Faça os passos em cada aparelho:

1. Conecte por USB, desbloqueie e aceite confiar no computador.
2. Ative **Ajustes → Privacidade e Segurança → Modo de Desenvolvedor**, reinicie e confirme. Se a opção não aparecer, abra o aparelho no Xcode após conectar/confiar.
3. No Xcode, adicione a conta Apple em **Settings → Accounts**. Para teste pessoal, pode usar sua conta como **Personal Team**, com você fazendo o login.
4. Selecione projeto **Runner**, alvo **Runner**, **Signing & Capabilities**, ative **Automatically manage signing** e escolha o Team. Se o Bundle Identifier estiver indisponível, troque por um identificador exclusivo, por exemplo `br.com.seunome.leitorpdf`, e mantenha-o nas próximas instalações.
5. Confirme mínimo **16.0**, destinos iPhone/iPad e selecione seu aparelho como destino no Xcode.
6. Volte ao Terminal para instalar uma versão release que possa ser aberta normalmente, sem depender de uma sessão de depuração:

```bash
flutter devices
flutter run --release -d ID_DO_APARELHO
```

Troque `ID_DO_APARELHO` pelo ID listado. Repita para o outro aparelho. Se o sistema pedir confiança no desenvolvedor, autorize em **Ajustes → Geral → VPN e Gerenciamento de Dispositivo**. Após a instalação, encerre a execução no Terminal, desconecte e confirme que o app abre pelo ícone.

A conta gratuita permite teste pessoal, mas o provisionamento expira **sete dias após a emissão**; será preciso renovar/reinstalar pelo Mac. Não basta seu amigo mandar um IPA por mensagem para instalar livremente. Regras: [conta e Personal Team da Apple](https://developer.apple.com/help/account/basics/about-your-developer-account).

## Receber e atualizar à distância pelo TestFlight

Para evitar depender do Mac emprestado a cada semana, use uma conta inscrita no **Apple Developer Program**, com assinatura paga, e publique uma build beta no App Store Connect. O usuário que recebe pelo TestFlight não precisa comprar uma assinatura de desenvolvedor.

Depois de configurar assinatura e cadastrar o app com o mesmo Bundle ID:

```bash
flutter build ipa --release --build-number=1
```

O Flutter gera o archive em `build/ios/archive` e o IPA em `build/ios/ipa`. Abra o archive no Organizer do Xcode e use **Distribute App → App Store Connect**. Na próxima atualização, aumente `--build-number`.

No App Store Connect, configure o TestFlight, adicione o usuário como testador e disponibilize a build. Teste externo pode exigir revisão beta da Apple. Instale TestFlight no iPhone e iPad e aceite o convite nos dois. Cada build beta fica disponível por **até 90 dias**, exigindo outra build depois. Não é uma instalação definitiva de App Store. Referências: [Flutter: archive/IPA e distribuição](https://docs.flutter.dev/deployment/ios), [Apple: TestFlight](https://developer.apple.com/help/app-store-connect/test-a-beta-version/testflight-overview/).

## Verificar o funcionamento em cada aparelho

Abra o PDF de exemplo; selecione uma palavra; marque; escreva um significado acima; edite e remova; navegue e amplie; feche/reabra o app. Em Preferências, autorize o download dos modelos de tradução inglês/português. MiniLM é opcional para Contextual/Comparar. Só depois desligue a rede e confira a tradução offline. Não copie os modelos CTranslate2 do Windows para o iPhone.

No iOS, **Abrir PDF local** usa o seletor Arquivos em modo de abertura no lugar, sem importar uma cópia como origem. O novo **Salvar** atualiza o PDF autorizado, incluindo edição/remoção de marcações e significados. A autorização é guardada por bookmark para a biblioteca recente; o leitor usa internamente uma base separada para renderizar, sem confundi-la com o original. **Exportar cópia PDF** continua opcional. Importações da versão antiga pedem a seleção do original uma vez. Cmd+S também aciona Salvar no iPad com teclado.

O provedor precisa permitir escrita. Arquivo removido, acesso revogado, origem somente leitura ou alteração externa produz erro; o app não salva silenciosamente em outro PDF. A conferência de hash ocorre também dentro da operação nativa coordenada. No iCloud Drive, o app atualiza o arquivo do provedor, enquanto o envio/sincronização com a nuvem fica a cargo do sistema. A implementação foi adicionada, mas ainda precisa de compilação e teste real em iPhone/iPad, incluindo arquivos locais, iCloud e outro provedor.

Não há sincronização própria de PDFs/anotações entre Windows, iPhone e iPad. Transferir um PDF anotado permite ver suas notas, mas não reconstitui toda a edição/proveniência do banco desta instalação.

Para executar os testes compartilhados, a partir da raiz extraída:

```bash
cd packages/validation
flutter pub get
flutter test --reporter expanded
```

Os testes `reader_*` de integração Windows não constituem testes iOS. Registre modelo/versão dos aparelhos, Flutter/Xcode, logs da compilação e resultados reais antes de declarar iOS validado. Capturar `flutter build ios --release --no-codesign -v` pode ajudar a diagnosticar falha de compilação; esse comando não produz um app assinado instalável.
