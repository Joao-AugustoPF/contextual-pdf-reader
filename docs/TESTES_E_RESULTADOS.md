# Testes e resultados medidos — 23/10/2026

## Verificação para publicação dos fontes — 23/10/2026

README atualizado com instruções para clone limpo, recursos atuais, captura sintética, estados de plataforma e resultados A/B. Incluídos guia de contribuição e workflow GitHub de análise/testes compartilhados, com ações fixadas por SHA. Modelos, runtimes, SDKs, bancos e credenciais ficam fora do Git; o repositório distribui fontes, não instaladores assinados.

Verificação local repetida: **56 testes Dart passaram**, `flutter analyze --no-pub` sem problemas (103,3 s com concorrência de ferramentas), **cinco testes Python passaram em 7,90 s**, incluindo o processo PyInstaller e modelos reais já instalados. Nenhum download de modelos, ensaio iOS ou nova medição A/B foi feito nesta etapa. Os resultados abaixo preservam seu contexto histórico; versões anteriores do plano/relatórios descrevem o estado daquele momento.

## Ambiente e verificações

Windows 11, Flutter 3.47.7, Dart 3.13.5, Python 3.12.10, CPU (duas threads para inferência), SDK Android com AVD Pixel_Android16 x86_64. Sem dispositivo físico e sem Visual Studio C++. Não foram medidos resultados iOS/macOS/Linux.

- `flutter analyze`: **sem problemas**, execução final em 11,8 s, após ajustes das APIs e `dart fix`.
- `packages/validation: flutter test --reporter expanded`: **30 testes passaram**. Exercitam os mesmos arquivos da aplicação: NLP, isolamento A/B, cache, cancelamento, erro encoder/modelo ausente, tokenizer/offsets, coordenadas em quatro escalas, colisões, hash, Drift, persistência manual/progresso e exportação.
- `python -m pytest ml/tests -q`: **5 testes passaram** em 8,71 s. CTranslate2 real, ONNX real de tokens, offsets, norma, truncamento, hash corrompido e executável PyInstaller sem Python global.
- `flutter build apk --debug --target-platform android-x64`: compilou; primeira build 474,1 s, 231.608.473 bytes. Build de integração multi-ABI posterior: 273.078.193 bytes. São APKs debug, não tamanho release otimizado.
- PDF: duas páginas exportadas e reabertas, Highlight/FreeText presentes, original preservado byte a byte como prefixo. Render Poppler inspecionado, sem texto original rasterizado. `output/pdf/exportado-teste.pdf` / `.png`.
- Integração Android: três testes passaram após corrigir inicialização precoce de busca, lifecycle e preservação de edições manuais. A auditoria offline final usa confirmação de rede nativa antes da inferência.
- Release ARM64: `flutter build apk --release --split-per-abi --target-platform android-arm64` compilou em 23,6 s (build incremental após release universal de 161,6 s). APK final **74.634.011 bytes**, somente `arm64-v8a`, SHA-256 `18df973006064eff5864b53ab4e74d41f0a7b0633e08490b797151cac0750ab1`. Caminho: `app/build/app/outputs/flutter-apk/app-arm64-v8a-release.apk`. Assinado com chave debug para instalação local; não é assinatura de loja. Execução validada no AVD foi debug x86_64, não esta release ARM64.
- Smoke CLI Dart com sidecar real: passou, confirmando isolamento A, descarte/reinício de processo e offsets UTF-16 com emoji contra a saída oficial. Evidência: `reports/runtime-smoke.json`.

## Comparação desktop real

Fonte: `reports/benchmark.json`, execução do pipeline Dart da aplicação com Argos en_pb 1.9/CTranslate2 INT8 + all-MiniLM-L6-v2 ONNX QUInt8, tokenizer oficial, sockets bloqueados no sidecar. **64 exemplos autorais do agente, não gold humano validado.**

| Métrica | A | B |
|---|---:|---:|
| Tradução curta correta, incluindo abstenções esperadas | 35/64 (54,69%) | 43/64 (67,19%) |
| Sentido correto entre os 60 definidos | 40/60 | 60/60 |
| Abstenções de tradução curta | 19/64 | 16/64 |
| Decisão adicional p50 | 0,085 ms | 55,166 ms |
| Decisão adicional p95 | 0,210 ms | 101,504 ms |

Diferença pareada: **+8 acertos, +12,50 pontos percentuais**; 8 ganhos / 0 perdas no critério curto deste corpus. Reconhecimento da expressão: 64/64 exact match lexical; isso não mede todos os offsets sobre PDFs do mundo real. Tradução comum p50 56,734 ms, p95 86,553 ms. Há 21 erros/abstenções não esperadas em B. Não inferir melhoria generalizável ou significância confirmatória de corpus pequeno/curado pelo mesmo autor.

| Categoria | N | A correto | B correto |
|---|---:|---:|---:|
| Phrasal verbs | 11 | 7 | 7 |
| Polissemia | 20 | 14 | 16 |
| Técnico | 13 | 4 | 7 |
| Idioms | 6 | 4 | 4 |
| Flexão | 5 | 2 | 2 |
| Negação | 2 | 2 | 2 |
| Pontuação | 3 | 1 | 2 |
| Abstenção esperada | 4 | 1 | 3 |

## Cold start, warm start, cache e memória

Primeiro A: auditoria `encoderCalls=0`, `onnxImported=false`. Depois B executou ONNX; final 145 chamadas ao encoder (inclui protótipos/repetições), 68 chamadas ao tradutor. Não foram usadas respostas pré-computadas como inferência.

| Situação | Tradução comum | Decisão A | Decisão B |
|---|---:|---:|---:|
| Primeiro encoder frio | 27,569 ms | 0,112 ms | 3.499,603 ms |
| Repetição quente | 34,708 ms | 0,057 ms | 53,789 ms |
| Cache hit de frase | 0,011 ms | 0,012 ms | 40,670 ms |

RSS observado do processo filho: inicial 22.331.392 B, após A 135.192.576 B, após B frio 217.714.688 B; final 222.150.656 B, pico observado 222.261.248 B. Incremento após A→B frio ~78,70 MiB. Estes números são working set do host, não RAM adicional em celular nem memória total da interface Flutter. Variações de cache do SO afetam cold start.

Pesos/tokenizadores/metadados instalados: 106.703.016 B. Download compactado total: 89.923.745 B. Sidecar empacotado: 205.389.172 B / 568 arquivos na build medida. Manifest com SHA-256 completo em `ml/manifests/models.lock.json`.

## Erros observados e métricas ausentes

- Tradução de `race condition` pode virar “condição racial”; B não fabrica âncora “condição de corrida”.
- `thread` pode ser traduzido como “linha”; A aceita sentido de costura; B resolve computação, mas abstém na tradução curta quando falta âncora adequada.
- `lock` técnico virou “fechadura”; B identifica mutex e recusa alinhamento, preservando a frase para revisão.
- “procure”, “abaixe”, “corri” não estão em todas as listas de equivalências gold; o avaliador estrito pode penalizar traduções linguisticamente aceitáveis. Não ajustamos rótulos após olhar o teste para inflar números.
- Nenhuma amostra perdeu acerto curto A→B neste conjunto. Isso não implica ausência de regressões: o relatório expõe rankings e casos em que B remove uma resposta A errada ou dá sentido indevido em contexto insuficiente.
- Acurácia independente de alinhamento, erro de alta confiança, equivalência PyTorch/ONNX e RAM/latência Android físico: **não medidos**, por falta de rótulos/calibração/ambiente. Cosseno não é probabilidade.

## Roteiro manual pendente

Após baixar modelos por Preferências, ativar modo avião e traduzir `light` nos dois sentidos, `give`→`give up`; conferir os três modos, edição manual após reabrir, cinco cores, zoom/orientação, busca/sumário e exportação num leitor externo. Testar PDF de 1.000+ páginas, escaneado, protegido, rotacionado/CropBox e 0/50 anotações em telefone de 4 GB; capturar `adb shell dumpsys meminfo br.com.estudos.contextual_pdf_reader` e latências do laboratório. Não registrar resultados desses passos antes de executá-los.

## Android: resultado final e auditoria offline

Fonte: `reports/benchmark-android.json` / `.csv`. Três testes de integração reais passaram: reader/persistência/exportação; modelos/64 pares; Comparar pela UI e salvar somente a escolha. O teste também verifica que cálculo automático não substitui uma tradução manual existente. Nenhum dado real de usuário foi utilizado.

Auditoria reproduzível: `python scripts/test_android_offline.py`. O script desligou a rede **antes** do cálculo; `ConnectivityManager` retornou `connected=false, validated=false`; `reports/network-audit.json` registra modo avião ativo, Wi-Fi desativado, sucesso e restauração do estado anterior. Tradução de frase sem cache durante o lote. A primeira tentativa de auditoria por callback de screenshot foi inválida e não é usada como evidência de offline.

| Métrica | A (ML Kit + heurística) | B (mesma frase + MiniLM ONNX) |
|---|---:|---:|
| Acertos curtos / 64 | 34 | 43 |
| Acurácia curta | 53.12% | 67.19% |
| Sentido correto / 60 | 36 | 59 |
| Abstenções | 22 | 19 |
| Decisão adicional p50 (ms) | 0.147 | 69.080 |
| Decisão adicional p95 (ms) | 0.674 | 140.154 |

Ganho pareado final: 9 ganhos / 0 perdas, 14.06 pontos percentuais. Tradução comum p50 40.657 ms / p95 54.159 ms. Primeiro uso B: 2354.108 ms; não confundir com latência quente.

RSS total do processo Android debug no AVD: antes de inferir 574,746,624 B; após lote 665,387,008 B (incremento observado 86.44 MiB). Inclui Flutter/SDKs/GC e não isola somente MiniLM nem mede telefone físico.

O teste de conformidade detectou padding fixo 128 no tokenizer upstream que faltava no adaptador mobile. Corrigimos padding e attention mask a partir do tokenizer pinado; **30 testes unitários passam**, incluindo IDs e offsets idênticos ao tokenizer oficial nas 64 frases. Não houve alteração dos rótulos/protótipos para melhorar os números.

A execução antiga com comprimento variável fica em `reports/benchmark-android-variable-length.json`: A 34/64, B 40/64, 7 ganhos e **1 perda real**, `bank` em “The fisherman sat on the river bank.”: A escolheu “margem”; B escolheu sentido financeiro e se absteve. Esse arquivo é histórico de um adaptador anterior; seu flag offline não foi confirmado pela instrumentação antiga. A versão final resolve esse caso, mas ainda erra/abstém em 21/64 seleções. Não interpretar a correção como prova de generalização do MiniLM.

Capturas reais: `reports/reader-android.png` e `reports/compare-android.png`. PDF exportado pelo fluxo Android: `output/pdf/exportado-android.pdf`, reaberto/renderizado com destaques, FreeText, acentos e badge oficial Google Translate quando aplicável.

Teste sintético de 1001 páginas: passou, página sem texto detectada; abertura + espera explícita de 1 s para primeiro render 2695.829 ms. RSS com 0 anotações 523,587,584 B / com 50 526,823,424 B (diferença 3.09 MiB, sem isolar GC/cache). Evidência em `reports/large-document.json`; não é teste de livro real em aparelho físico.

## Retomada do build Windows — 23/10/2026

Visual Studio Community 2026 18.11.1 e SDK 10.0.26100.0 reconhecidos pelo `flutter doctor -v`. O log fornecido pelo usuário confirma PyInstaller concluído e Flutter bloqueado em `Building with plugins requires symlink support`, antes da compilação da interface. Falha reproduzida localmente; `pub get` sozinho pode concluir sem recriar os links. O Modo de Desenvolvedor precisa ser ativado nas configurações Windows. O script passou a verificar a criação real de link via Dart e executar `flutter pub get` antes do empacotamento do motor, sem atribuir todo erro de build ao Visual Studio. Interface Windows ainda não compilada/executada; avisos de dependências mais novas não são o bloqueio observado.

## Windows release aberto e modelos instalados — 23/10/2026

Posteriormente o usuário concluiu o build e abriu `app/build/windows/x64/runner/Release/contextual_pdf_reader.exe` (processo ativo e captura do leitor). A tradução retornou `Modelo não instalado: ...translator/metadata.json`: a pasta de suporte tinha apenas `models.lock.json`; os modelos existentes no repositório não estavam instalados para o executável.

Copiados 11 arquivos locais (106.703.016 B), com tamanho/SHA-256 verificados na origem e SHA-256 no destino, para `%APPDATA%/br.com.estudos/contextual_pdf_reader/models`. Nenhum download novo, alteração no banco ou nos documentos. O teste usou o `reader-runtime.exe` do próprio bundle release e o manifest da pasta de suporte, retornando “Decidi desistir da programação.” e “Acenda a luz.”. Após essas traduções: `encoderCalls=0`, `onnxImported=false`; solicitação posterior de embedding retornou 384 dimensões. Evidências completas em `reports/windows-installed-runtime.json`. A interface abriu; o fluxo interativo Windows completo ainda precisa ser testado e não está coberto por este smoke test do motor.

## Destaque e seleção por mouse no Windows — 23/10/2026

O destaque agora usa opacidade 0,85 com composição Multiply no mesmo canvas da página, preservando letras escuras. A camada de interação permanece transparente, mantendo os gestos do leitor. Exportação usa a mesma intensidade e Highlight nativo com Multiply; o texto original permanece intacto. Duplo clique passa a chamar a seleção de palavra oficial do pdfrx.

Comando executado em `app`: `flutter test integration_test/reader_interaction_test.dart -d windows --no-pub --dart-define=TEST_REPORT_DIR=C:/src/estudos/contextual-pdf-reader/reports`. Um ensaio integrado passou em 11 s após compilação, cobrindo duplo clique em palavra comum, palavra marcada e palavra dentro de expressão marcada; arraste através de anotação; duplo clique após zoom; clique simples para abrir detalhes. Banco isolado em memória, sem abrir documentos pessoais nem instalar/invocar modelos.

Comparação automática de capturas preservou **290/290 pixels escuros de letras**, enquanto **729 pixels de fundo** ficaram mais intensos (canal azul inferior a 140 em pixels originalmente brancos). Evidências: `reports/windows-reader-interaction.json`, `reports/windows-highlight-before.png` e `reports/windows-highlight-after.png`, com inspeção visual do destaque. Primeira tentativa do ensaio falhou por apontar para fora do viewport após zoom; o teste passou após centralizar o zoom na palavra visível.

Os 30 testes compartilhados passaram, incluindo reabertura do PDF exportado com opacidade 0,85, Multiply e original preservado. `flutter analyze --no-pub`: sem problemas. Isso verifica o pedido de desenho/gestos no Windows; não substitui o roteiro completo de tradução e exportação pela interface.

Release atualizado compilado com `flutter build windows --release --no-pub` em 40,8 s. Conferidos executável, `data/app.so` atualizado, `flutter_windows.dll` e runtime local preservado no bundle. Tamanhos/hashes em `reports/windows-desktop-build.json`.

## Sugestão isolada e revisão no Windows — 23/10/2026

Caso relatado: `rippling` fora do léxico, com frase completa traduzida, mas sem tradução curta confirmada. O leitor passou a solicitar uma sugestão da seleção isolada ao mesmo tradutor local, somente quando nenhum modo retorna tradução curta. A sugestão exige revisão explícita antes de salvar e fica fora das decisões/métricas A/B, com latência separada. O léxico, os protótipos e os rótulos da avaliação não foram alterados. Não se apresenta tradução isolada como desambiguação contextual.

**32 testes compartilhados passaram**, incluindo ausência de chamadas de encoder no auxílio básico, decisões A/B preservadas e propagação de falha sem converter abstenção em acerto. `flutter analyze --no-pub`: sem problemas.

Integração Windows real: `flutter test integration_test/reader_fallback_test.dart -d windows --no-pub --dart-define=TEST_PROJECT_ROOT=C:/src/estudos/contextual-pdf-reader --dart-define=TEST_REPORT_DIR=C:/src/estudos/contextual-pdf-reader/reports`. Passou em 6 s após compilação. Usou o tradutor real do bundle, pesos locais e banco em memória, sem tocar documentos pessoais. Seleção `programming` (fora do léxico) retornou `Programação`; cancelar não criou anotação. Reabrir revisão, editar e salvar produziu `programação revisada`, `manualOverride=true`, `userReviewed=true`, mantendo a evidência isolada com `contextVerified=false` e `alignmentResolved=false`. Status real: duas traduções, zero chamadas de encoder, ONNX não importado. Tempo adicional observado da sugestão: 244,861 ms em debug; não é percentil de benchmark. Evidências em `reports/windows-isolated-suggestion.json` e captura `.png`, inspecionada visualmente.

O ensaio também revelou barra indeterminada ativa durante a revisão mesmo depois de terminar a tradução; corrigida para encerrar antes de abrir o painel. A nova sugestão possui indicador próprio enquanto aguarda o tradutor.

Smoke test com cinco palavras isoladas pelo runtime do bundle: `rippling` → `Ondulação`, `coupled` → `Acoplada.`, `axioms` → `Axiomas`, `equilibrium` → `equilíbrio`, `unpredictable` → `Imprevisível.`. Relatório `reports/windows-isolated-words.json`, zero chamadas/import ONNX. Esses resultados não atestam que a tradução serve ao contexto de cada palavra. As métricas A/B anteriores continuam referentes ao experimento sem esta ajuda de revisão.

Release com o novo fluxo compilado em 56,3 s e reaberto após fechamento normal da janela anterior. Bundle conferido com Flutter DLL, `data/app.so` atualizado e runtime local. Manifest de artefatos atualizado em `reports/windows-desktop-build.json`.

## Barra e rolagem suave no Windows — 23/10/2026

Implementada barra vertical com trilha visível, indicador proporcional/arrastável, página no tooltip e clique na trilha para navegar. Controle oficial `PdfViewerScrollThumb` acompanha as coordenadas e o zoom. A roda passou de multiplicador 0,2/instantâneo para 4,0/delegate de suavização com fricção 18. Eventos rápidos acumulam deslocamento. O caminho específico de trackpad da biblioteca foi preservado; não houve ensaio com trackpad físico.

Executado em `app`: `flutter test integration_test/reader_scroll_test.dart -d windows --no-pub --dart-define=TEST_REPORT_DIR=C:/src/estudos/contextual-pdf-reader/reports`. Passou em 11 s após compilação. Mesmo PDF sintético e zoom 2,0678: evento de roda com delta 20 produziu **8,271 px antes** e **80,000 px depois**, com deslocamento intermediário de **20,735 px**, verificando movimento distribuído em frames. Medida de deslocamento lógico, não teste de FPS ou medição de mouse físico.

Página 2 alcançada em 20 eventos de delta 20 neste PDF/zoom. Verificados arraste da barra até o início, clique na trilha (progresso 0,616), arraste até o fim depois de ampliar e preservação da ampliação durante o arraste. Relatório `reports/windows-reader-scroll.json`; captura `reports/windows-reader-scroll.png`. Banco em memória e PDF sintético; sem invocar modelos ou alterar dados pessoais.

O teste identificou que a região de clique transparente não recebia eventos na borda externa do documento; a trilha passou a tratar o toque diretamente e o ensaio foi repetido com sucesso. A análise estática passou sem problemas. A sensação com mouse/trackpad físico ainda depende da avaliação do usuário; Android/iOS não foram reexecutados para este ajuste.

Regressão `reader_interaction_test.dart` repetida no Windows e aprovada em 11 s: duplo clique, arraste de seleção, zoom e detalhes de anotação preservados, assim como 290/290 pixels de letras escuras. Captura atualizada `reports/windows-highlight-after.png` mostra a barra junto do texto. Release compilado em 44,4 s, bundle conferido e aplicativo reaberto. Manifest atualizado em `reports/windows-desktop-build.json`.

## Tradução direta sem painel — 23/10/2026

O usuário pediu aplicação direta para palavras comuns. O fluxo padrão Básico/Contextual passou a salvar a tradução automaticamente sobre a seleção; o painel só abre ao escolher **Detalhes** ou **Comparar**. No Básico, seleções fora do léxico usam diretamente o tradutor local, sem traduzir a frase inteira. Se a decisão contextual não tiver resposta curta, a tradução isolada é aplicada com origem registrada, `contextVerified=false`, `userReviewed=false`, `requiresReview=false` e `manualOverride=false`. Isso substitui a revisão obrigatória descrita anteriormente para o fluxo de leitura; decisões e métricas do experimento A/B continuam inalteradas.

Pontuação externa de palavras é retirada da seleção/rótulo, preservando offsets UTF-16 e apóstrofos/hífens internos. Faixas antigas com pontuação são reconhecidas ao proteger edições manuais e fazer upsert. Seleções com várias palavras mantêm a pontuação original.

**34 testes compartilhados passaram**; `flutter analyze --no-pub` sem problemas. Integração `reader_quick_translation_test.dart` no Windows, com motor real, passou em 8 s após build. Selecionou `programming.` no PDF sintético, salvou `Programação` sem painel e sem ponto no rótulo/faixa. Status: uma chamada de tradução, zero encoder e ONNX não importado. `computer,` pelo mesmo serviço/motor real retornou `computador` (23,014 ms quente nesta execução; não é percentil). O fluxo completo da primeira palavra, com inicialização fria do processo/modelo e UI debug, levou 1.117,448 ms.

Verificadas proteção de anotação manual antiga incluindo pontuação, ausência de duplicata e abertura do painel somente pelo botão Detalhes. Banco isolado, sem uso de documentos pessoais. Evidências: `reports/windows-quick-translation.json` e `.png`. Inspeção visual encontrou remontagem do PDF ao inserir o progresso; corrigida com slot fixo e chave estável do viewport. A execução final manteve o zoom e detectou 862 pixels escuros do texto original depois de salvar, sem recarregar o documento.

Regressão `reader_fallback_test.dart`, agora explicitamente em Comparar: passou em 14 s com tradutor e encoder reais. Cancelar revisão não salvou nada; revisão manual foi preservada. Status: duas traduções e uma chamada de encoder; ONNX importado no modo Comparar. Relatório `reports/windows-comparison-suggestion.json` e `.png`. Os relatórios antigos `windows-isolated-suggestion` documentam o fluxo anterior de revisão no Básico, não a experiência atual.

Release com tradução direta compilado em 79,7 s, com conferência dos arquivos do bundle e reabertura do aplicativo. Hashes atualizados em `reports/windows-desktop-build.json`.

## Salvar no arquivo original — 23/10/2026

Pedido explícito do usuário substitui a preservação obrigatória do original no fluxo Salvar. Exportar cópia continua sendo uma ação separada que preserva a origem. Implementados botão **Salvar** e **Ctrl+S**, vínculo persistido ao arquivo original, migração v1 → v2 e identidade estável ao reabrir o mesmo caminho após mudar o hash.

**40 testes compartilhados passaram.** Seis cenários novos cobrem salvamentos sucessivos sem duplicação/aumento quando não há mudanças, edição/remoção, preservação de notas externas, duas cópias iguais em caminhos diferentes, vínculo de importação antiga com rejeição de arquivo incorreto, migração preservando biblioteca/progresso/anotações, mudança externa e bloqueio real de destino no Windows. O bloqueio usa processo PowerShell com handle de leitura sem compartilhamento de escrita/exclusão: falha de renomeação preservou os bytes originais e limpou o temporário. Banco/PDFs isolados; nenhum documento pessoal usado.

Integração **`reader_save_test.dart` no Windows passou em 16 s** após build de 51,9 s. Pela interface: marcar `programming`, editar para `programação`, clicar Salvar, salvar novamente, editar para `programação revisada` e gravar por Ctrl+S; voltar à biblioteca, reabrir o mesmo documento, remover a marcação e salvar. O primeiro salvamento completo levou **436,412 ms**, medição única em debug sobre PDF sintético de 2.848 B, não benchmark de documentos reais. Arquivo foi a 5.634 B e depois a 8.437 B com a edição incremental; salvar sem alterações manteve bytes idênticos. Permaneceram duas anotações nativas (Highlight + FreeText) após editar e zero após remover/salvar. Um único PDF na pasta de origem, sem `-anotado.pdf` ou temporários ao concluir.

Conferidos documento/zoom preservados durante Salvar, mesmo ID da biblioteca após reabrir, anotações editáveis recuperadas do banco e base interna com zero anotações nossas por baixo dos overlays. Teste encontrou e corrigiu o foco do atalho depois de editar; o harness foi ajustado para aguardar as transições de navegação e usar o tooltip localizado Voltar. Relatório `reports/windows-save-original.json`; captura `reports/windows-save-original.png`.

Validação independente por **pypdf** confirmou duas páginas, frase inglesa original extraível e FreeText `programação revisada`. Poppler renderizou a página com destaque forte, letras escuras e tradução vermelha; imagem inspecionada. Evidências `reports/windows-save-original.pdf`, `reports/windows-save-original-render.png`, `reports/windows-save-pdf-validation.json`. Renderizador emitiu avisos de fontes Symbol/ArialUnicode; o português do ensaio apareceu corretamente. A conferência humana em Edge/Acrobat continua pendente.

Regressão **`reader_quick_translation_test.dart` passou em 9 s**, com tradutor real do bundle. Além do fluxo de leitura sem painel, a tradução automática `Programação` foi gravada no original com duas anotações nativas e reaberta pelo parser PDF. Foram uma chamada de tradução no caminho rápido, zero encoder/ONNX e 862 pixels escuros de texto preservados no viewer; `computer,` → `computador` pelo mesmo motor em 24,742 ms quente. Primeiro fluxo de tradução, incluindo inicialização fria e UI debug: 1.204,852 ms nesta nova execução. Proteção da edição manual e Detalhes explícitos continuaram passando. O relatório `reports/windows-quick-translation.json` foi atualizado com essa execução.

`flutter analyze --no-pub` final sem problemas e `git diff --check` passaram. Release Windows compilou em **91,3 s**; executável, `data/app.so`, Flutter DLL e sidecar conferidos por tamanho/SHA-256. Aplicativo atualizado reaberto. Manifest em `reports/windows-desktop-build.json`. A build APK anterior não foi substituída neste ajuste.

Limitações detalhadas em `LIMITACOES.md` e `EXPORTACAO_PDF.md`: mobile mantém exportação pelo seletor; revisões incrementais não expurgam bytes antigos; edição completa em outra instalação depende do banco; originais alterados externamente exigem reabertura; nenhuma nova validação física/mobile neste ajuste.

## Retirar marcações pela seleção e pela lista — 23/10/2026

Adicionado **Remover marcação** à barra, habilitado quando a seleção cruza marcações da página atual, inclusive parcialmente. Remove o conjunto completo de destaque/tradução correspondente e limpa a seleção azul para tornar o resultado visível. A lista **Anotações** ganhou lixeira por item, sem exigir seleção no texto. **Remover** nos detalhes foi mantido; todos usam a mesma rotina transacional com **Desfazer**. Traduções pendentes são invalidadas para não recriar a marcação removida. Avisos antigos são descartados para que Desfazer apareça imediatamente.

**41 testes compartilhados passaram**, incluindo limites de faixa com fim exclusivo, seleção parcial, múltiplas interseções, preservação de outra página, faixa vazia/inválida e anotação sem offsets. Os testes existentes de salvar/editar/remover no original, migração e bloqueio continuam passando.

Integração ampliada **`reader_save_test.dart` no Windows passou em 15 s**, após build de 26,2 s. Selecionar parte de `programming` e clicar Remover marcação apagou o destaque e a tradução; Desfazer restaurou tanto o banco quanto o rótulo `programação revisada`. Criada outra marcação em `light`; ao apagar apenas `programming` e salvar, permaneceu exatamente um Highlight nativo em `light`. A lixeira da lista apagou o restante sem seleção; depois de Salvar, o PDF original reabriu com **zero anotações**, e a pasta de origem continuou com um único PDF. Não foram usados documentos/banco pessoais nem modelos. Relatório atualizado `reports/windows-save-original.json`; captura `reports/windows-save-original.png` mostra o novo controle.

O primeiro salvamento deste ensaio levou 271,366 ms em debug sobre o mesmo PDF sintético, medição única; não é benchmark de remoção nem de arquivos reais. O relato de 436,412 ms da seção anterior corresponde à execução anterior. A implementação é compartilhada, mas o novo fluxo foi validado no Windows; nenhum novo teste físico/mobile foi executado.

Análise estática final sem problemas e `git diff --check` passou. Release Windows com remoção acessível compilado em **42,8 s**, bundle conferido e aplicativo reaberto. Hashes/tamanhos atualizados em `reports/windows-desktop-build.json`; o APK anterior não foi substituído.

## Significado visível e edição manual — 23/10/2026

O relato de salvar sem aparecer foi diagnosticado por consulta somente leitura ao registro da palavra indicada: `Ondulação` estava persistida, porém o layout antigo havia usado uma nota no topo da página, cerca de 615 pontos acima do alvo. Não foi ausência de tradução/gravação. O algoritmo começava sua busca de margem pelo topo e afastava o rótulo da área de leitura.

Corrigido `placeLabel`: tenta fontes 8, 7 e 6 acima do alvo; quando falta entrelinha, busca margem na mesma altura, priorizando o lado próximo mesmo que precise de fonte compacta, e expande por distância. Preserva obstáculos de texto/rótulos. Notas de margem antigas são recalculadas ao visitar a página, mantendo significado e revisão manual; recebem `labelLayoutVersion=2`. A gravação do original aguarda o reposicionamento em andamento. O viewport é ajustado para mostrar palavra/rótulo depois de aplicar, sem depender de uma animação para concluir a gravação.

Adicionado **Escrever significado**, independente do modelo. O editor preenche o significado existente e valida texto não vazio por Form; a persistência também rejeita pedidos de significado em branco. Em Detalhes/Comparar, **Usar esta tradução** aplica a sugestão isolada diretamente, e **Editar significado** continua disponível. **Escrever outro significado** inicia com a sugestão já obtida, quando houver. Isso mantém a origem isolada e a ausência de confirmação contextual explícitas, sem alterar o experimento A/B. Salvar no topo grava a versão atual no PDF original.

**43 testes compartilhados passaram**. Novos casos confirmam fonte compacta em entrelinha estreita e margem próxima sem cobrir texto, incluindo preferir a margem próxima compacta ao lado oposto com fonte maior.

**`reader_meaning_test.dart` no Windows passou em 6 s** após build de 32,6 s. PDF sintético denso reproduziu uma nota antiga com caixa `[4,762,55.2,774]`; a migração a moveu para `[4,161.196,55.2,173.196]`. Selecionar `rippling` e Escrever significado preencheu `Ondulação`; tentar salvar espaços exibiu erro e preservou o registro. Digitar `em cascata` aplicou o rótulo sem painel, com caixa `[4,161.196,54,171.796]`, **1 ponto acima do topo do alvo**, fonte 7 na margem próxima e **133 pixels vermelhos detectados na tela**. O rótulo não cruzou as caixas de texto. Salvar gravou Highlight + FreeText no original; reabrir preservou significado e posição. Nenhum modelo instalado/invocado; banco/PDF sintéticos isolados. O harness precisou devolver o foco ao campo depois de provocar o erro de validação para simular a digitação nativa corretamente.

Evidências: `reports/windows-word-meaning.json`, `.png` e `.pdf`, além de `windows-meaning-editor.png`. **pypdf** confirmou FreeText `em cascata`, retângulo na mesma posição e frase original extraível. **Poppler** renderizou o resultado com significado vermelho na margem próxima, sem cobrir texto; captura inspecionada em `reports/windows-word-meaning-render.png`, metadados em `windows-word-meaning-pdf.json`. Avisos Symbol/ArialUnicode do renderizador não impediram a renderização do ensaio.

**`reader_fallback_test.dart` passou em 12 s** com tradutor e encoder reais do bundle. Cancelar edição não gravou; Usar esta tradução aplicou `Programação` sem diálogo; reabrir Detalhes e editar salvou `programação revisada`, preservando revisão humana e `contextVerified=false`. Três traduções e duas chamadas de encoder no Comparar; ONNX importado. Relatório e captura `reports/windows-comparison-suggestion.*` atualizados. Análise estática final sem problemas.

Limites: texto muito denso pode precisar de margem, pois não existe espaço físico suficiente acima da palavra sem cobrir a linha anterior. Páginas totalmente ocupadas, imagens e tipografia complexa continuam exigindo revisão; não há reconstrução/refluxo do conteúdo original. Só Windows foi revalidado neste ajuste; conferência humana em Edge/Acrobat e novos testes mobile/físicos permanecem pendentes.

Release Windows com significado visível compilado em **45,5 s** (47,226 s no comando completo), bundle conferido por tamanho/SHA-256 e aplicativo atualizado reaberto. Manifest `reports/windows-desktop-build.json`; `git diff --check` passou. O APK anterior não foi substituído.

## Tradução centralizada diretamente acima da palavra — 23/10/2026

O usuário confirmou que a posição na margem não atende ao fluxo desejado. O layout 3 mantém o rótulo centrado horizontalmente no alvo e imediatamente acima, ajustando a fonte entre 8 e 4 pontos. Não busca outra área da página. Posições de versões anteriores são recalculadas ao visitar a página, preservando o texto editado; Salvar grava a nova posição no original. Overlay usa linha compacta; no PDF, os 3 pontos de padding interno do FreeText são compensados por um retângulo ampliado e texto centralizado, para que a tinta fique na posição ancorada.

**43 testes compartilhados passaram** e análise estática sem problemas. Testes geométricos verificam a âncora inclusive quando faltam áreas livres e centralização em texto denso. **`reader_meaning_test.dart` passou no Windows em 6 s**, após build de 29,4 s: caixa antiga de margem migrou para a palavra, edição manual validada, resultado visível e original salvo/reaberto. Caixa do alvo `[155.692,149.396,193.276,160.196]`; caixa do significado `[161.484,160.496,187.484,165.296]`: **diferença horizontal de centro 0 pt e distância acima de 0,3 pt**. Fonte compacta 4 pt neste exemplo denso; 12 pixels vermelhos acima do limiar de detecção, conferência visual adicional feita. Arquivos `reports/windows-word-meaning.*` atualizados.

**pypdf** confirmou o FreeText `em cascata`, texto original extraível e centro do retângulo de anotação alinhado ao alvo com diferença menor que 0,001 pt. Verificados os 3 pontos adicionais em cada lado para compensar o padding. **Poppler** renderizou a tradução diretamente sobre `rippling`; captura `reports/windows-word-meaning-render.png` inspecionada, assim como a captura Flutter. A leitura de campos no PDF é independente da detecção de pixels na tela. Nenhum documento pessoal foi usado no ensaio, sem invocar modelos. Não houve nova validação mobile.

Esta regra substitui a busca de margem descrita na seção anterior. Limites reais: fonte compacta pode exigir zoom, página sem vão pode ter sobreposição, e borda superior pode recortar o rótulo. O documento original não é refluído. A prioridade explícita passa a ser manter a tradução acima da palavra.

Release Windows compilado em **42,6 s**, bundle conferido por tamanho/SHA-256 e aplicativo atualizado reaberto. Manifest `reports/windows-desktop-build.json`; `git diff --check` passou. APK anterior mantido.

## Nitidez em uso repetido — 23/10/2026

A investigação distinguiu renderização na tela e gravação do arquivo. No ensaio inicial (`windows-sharpness-before.json`), 24 alterações/salvamentos e seis ciclos de zoom/navegação não causaram perda cumulativa. A captura do usuário não foi reproduzida integralmente. A base interna permaneceu inalterada e renderizações PDFium do texto antes/depois da gravação foram idênticas.

O pdfrx usava uma prévia fixa de 200 dpi, redimensionada para o viewport. A nova política acompanha zoom e densidade do monitor com duas amostras por pixel físico. Prévia limitada a 4096 pixels por lado e 12 Mi pixels (até 48 MiB RGBA por página); acima desse teto o pdfrx renderiza a região visível na resolução real. O limite global de cache de 48 MiB continua uma meta de descarte, não um teto garantido da RAM total.

`reader_sharpness_test.dart` passou no Windows em **11 s** após compilação de 32,2 s. PDF sintético de seis páginas, 12 notas, 24 gravações, seis ciclos de zoom/navegação. No trecho intacto de 8568 pixels, **zero pixels mudaram**, diferença média absoluta zero; **951/951 pixels escuros** preservados. PDF salvo mantém texto extraível; renderizações sem anotações em 1224×1584 da base/salvo tiveram o mesmo SHA-256 `f9924bde5b3069858db9d9d25aff15b269db4a42bac24691844139459f385885`. Nenhum documento pessoal ou modelo usado.

Comparação das capturas no mesmo trecho de Times-Italic e zoom 2,01273885: energia média local de bordas **6515,51 → 9639,87 (+47,95%)**, pixels escuros **765 → 951**, cinzas intermediários **1089 → 704**. Capturas inspecionadas visualmente. Energia de bordas mede contraste local, não é nota universal de legibilidade nem prova de que o defeito progressivo foi reproduzido/corrigido em todas as máquinas. O ensaio inicial editou uma nota; o final acumulou 12 notas, mantendo o trecho comparado intacto.

Reprodução: `scripts/create_rendering_fixture.py`, integração `reader_sharpness_test.dart` com `TEST_PROJECT_ROOT`/`TEST_REPORT_DIR`, e `scripts/compare_rendering_quality.py`. Evidências `reports/windows-sharpness-before.json`, `windows-sharpness-after.json`, `windows-sharpness-comparison.json` e capturas correspondentes. Não houve nova validação mobile nem matriz de monitores/GPUs.

Validação final: **44 testes compartilhados passaram**, análise estática sem problemas. Integração de significado repetida com a política final passou em **7 s**: caixa 0,3 pt acima do alvo, centro horizontal idêntico, 12 pixels vermelhos detectados, significado salvo/reaberto. Release Windows compilado em **45,6 s** (47,2 s com invocação), artefatos conferidos por SHA-256 e aplicativo atualizado reaberto com janela nativa. `reports/windows-desktop-build.json` e `windows-sharpness-build-timing.json`; `git diff --check` passou.

## Pacote de fontes para Mac/iOS — 23/10/2026

Conferência estática: projeto Xcode com `TARGETED_DEVICE_FAMILY = 1,2`, mínimo 16.0, assinatura a configurar no Mac; `AppServices` seleciona ML Kit/ONNX nativos em iOS. `docs/COMPILAR_IPHONE_IPAD.md` traz os passos de preparação/instalação e as limitações atuais. O pacote `dist/contextual-pdf-reader-ios-fontes.zip` inclui fontes/assets/lock/iOS/testes compartilhados e documentação, sem ambientes Windows/modelos instalados/dados pessoais. O empacotador verifica CRC, entradas essenciais e exclusão de builds/credenciais/bancos; tamanho/SHA-256/inventário quantitativo em `reports/ios-source-package.json`.

Isso valida o **pacote de fontes**, não a compilação iOS. Nenhum Xcode, simulador Apple, iPhone ou iPad foi executado neste ambiente Windows. Assinatura, plugins e instalação real precisam ser conferidos no Mac. Salvamento direto no PDF original continua exclusivo do Windows; iOS usa exportação pelo seletor.

## Implementação de Salvar original no iOS e build remoto — 23/10/2026

Esta atualização substitui a limitação de iOS da seção anterior. A abertura usa seletor nativo `asCopy:false`, guarda bookmark de acesso e retorna um identificador `ios-pdf://...`. `DocumentFiles` lê o original pelo canal nativo, prepara as anotações em Dart e solicita a atualização desse mesmo documento. O iOS confere o SHA-256 esperado sob `NSFileCoordinator` antes da escrita atômica. A autorização é adquirida/liberada em cada operação, bookmarks obsoletos são renovados e erros não marcam o salvamento como concluído. Importações antigas pedem a seleção do original. Salvar e Cmd+S estão habilitados no iOS.

**49 testes compartilhados passaram no Windows**, com cinco novos testes de canal/armazenamento iOS **simulados**. Foram exercitados aplicar, editar, remover e reabrir, ID persistente, dois documentos iguais com identidades distintas, salvar sem mudanças, vínculo de importação antiga, recusa de arquivo errado, conflito de hash antes e durante a gravação e perda de permissão. O teste verifica que falha não modifica o original/base nem atualiza o hash de sucesso no banco. O mock de MethodChannel confere token, bytes, hash, cancelamento e propagação de erro. Esses testes executam o código Dart real; não executam APIs Apple.

Regressão nativa de interface **Windows** `reader_save_test.dart` passou em **16 s**, após compilação de **55,3 s**: botão Salvar/Ctrl+S, edição, reabertura, remoção parcial/Desfazer e remoção final persistidos no original. Evidência `reports/windows-save-original.json`. Isso verifica a preservação do fluxo Windows após a integração do backend externo.

Foram incluídos **três XCTest** no RunnerTests: substituir o arquivo sem deixar cópia e resolver bookmark após recriar o store; preservar alteração externa dentro da escrita coordenada; recusar referência sem autorização. **Não executados aqui**, pois não há macOS/Xcode. A compilação Swift e o uso real de Arquivos local/iCloud/terceiros continuam pendentes.

`codemagic.yaml` inclui verificação sem assinatura com testes de simulador e workflow separado de IPA/TestFlight com configuração de assinatura. Os arquivos de configuração são conferidos localmente; nenhum workflow foi executado, credencial solicitada ou código enviado ao serviço. Guia `docs/BUILD_IOS_NUVEM.md`; inventário/hash do ZIP em `reports/ios-source-package.json`. A compilação remota e a distribuição dependem da configuração feita pelo usuário no serviço/Apple.

Conferência final: análise Dart sem problemas; `git diff --check` passou. YAML interpretado, sete scripts passaram em `bash -n` (somente sintaxe, sem executar builds remotas), plist de abertura no lugar válido e arquivo Swift incluído no build phase/registro do plugin. Resumo `reports/ios-original-save.json`. ZIP regenerado e verificado por CRC, entradas essenciais e SHA-256; inclui `OriginalPdfPlugin.swift`, RunnerTests e os dois workflows. Nada disso substitui compilação Swift, assinatura ou teste físico, que continuam pendentes.

## Rótulo contextual preserva a forma usada na frase — 23/10/2026

Reproduzido com CTranslate2 real: a frase do caso informado contém `se aninham entre si`, enquanto traduzir somente `nest` produz `ninho`. A decisão B estava inconclusiva por falta de cobertura lexical e a leitura rápida acionava o fallback isolado. O erro era a origem do rótulo, não a tradução da frase.

A sugestão agora compara prefixos/orações com e sem a seleção e aceita apenas um trecho literal único da tradução original, preservando seus caracteres/offsets. Alinhamento por subsequência exige pelo menos duas palavras comuns e retenção de 65% da sequência menor; rótulos têm até quatro palavras, ilhas de omissão exigem duas âncoras de cada lado e posição proporcional não pode diferir mais que 0,25. Esses critérios são filtros heurísticos, não probabilidades nem garantias semânticas. Origem, sondagens e offsets são registrados; `contextVerified=false` permanece. Laboratório A/B e decisões do pipeline não foram alterados, nem os exemplos gold usados na inferência.

**56 testes compartilhados passaram**, incluindo sete novos testes de flexão, substantivo, acentos, trecho inexistente/repetido, reescrita extensa, fallback em falha, rejeição de mudança distante e não invocação de encoder no A. Análise estática final sem problemas.

Ensaio real reproduzível por `app/tool/contextual_label_probe.dart`, com os modelos locais já instalados e auditoria de rede do sidecar. Seis casos adicionais de regressão, sem alegação de corpus independente:

| Caso | Isolado anterior | Sugestão atual | Tempo adicional medido |
|---|---|---|---:|
| `components often nest` no parágrafo informado | ninho | aninham | 148,861 ms |
| `revolve` no mesmo parágrafo | Revolver | gira | 1633,623 ms |
| `built a nest` | ninho | ninho | 127,253 ms |
| `The birds nest` | ninho | se aninham | 169,545 ms |
| `These components nest` | ninho | se aninham | 302,433 ms |
| `rippling side effects` | Ondulação | Ondulação, fallback isolado | 1270,973 ms |

Cinco sugestões encontraram um trecho contextual; não é uma métrica de acurácia. Em `rippling`, o modelo omite a forma na tradução completa e não foi inventado um trecho. Os tempos são de uma execução no host, incluem sondagens e variam com carga; não são benchmark estável. Relatório `reports/windows-contextual-labels.json`: seis execuções de encoder, 36 traduções (incluem as traduções isoladas de controle), sem inferência remota/download.

**Integração Windows `reader_contextual_label_test.dart` passou em 13 s**, após compilação de 52 s: PDF sintético com quebra de linhas, modo Contextual real, substituição do rótulo automático antigo sem duplicar ID, resultado `aninham`, substantivo separado `ninho`, ausência de painel automático, gravação no PDF original e reabertura com os dois rótulos. Duas execuções de encoder e seis traduções. Primeira ação de interface com motor/encoder frios levou 6995,543 ms; não é tempo adicional puro. JSON/PDF/captura `reports/windows-contextual-label-ui.*`. Poppler renderizou o PDF salvo, conferido visualmente com `aninham` diretamente acima do verbo e `ninho` acima do substantivo.

**Painel Comparar `reader_fallback_test.dart` passou em 16 s**, após compilação de 62,8 s: sugestão extraída da frase, cancelar sem gravar, aplicar direto e edição manual posterior. Cinco traduções e duas execuções de encoder; contexto não declarado como semanticamente confirmado. Relatório `reports/windows-comparison-suggestion.json` atualizado. Testes usam originais sintéticos, sem modificar banco/PDF pessoal. A implementação compartilhada será incluída no ZIP iOS, mas não houve nova execução Apple/Android/ML Kit.

Release Windows compilado em **91,8 s** (94,1 s com invocação), bundle conferido por SHA-256 e app atualizado reaberto. Manifest `reports/windows-desktop-build.json`. ZIP iOS regenerado com o módulo de alinhamento e testes compartilhados atualizados; integridade/entradas/hash em `reports/ios-source-package.json`. `git diff --check` passou. Para corrigir uma anotação automática existente, selecionar novamente o trecho e usar Marcar e traduzir em Contextual; a integração verificou substituição do mesmo ID. Edições manuais continuam protegidas.
