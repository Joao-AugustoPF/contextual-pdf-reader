# Plano de implementação

Especificação lida integralmente: `PROMPT_CODEX_LEITOR_PDF_OFFLINE_AB_MINILM.md` (cópia fiel do arquivo em Downloads). Projeto criado em subdiretório para preservar os outros projetos da pasta estudos.

## Estado e evidências

- [x] Inspecionar ambiente: Windows, Python 3.12.10, Java 17, SDK Android, AVD Pixel_Android16. Flutter 3.47.7 instalado localmente; AVD iniciado, utilizado nos testes e encerrado após validação. Nenhum aparelho físico conectado.
- [x] Consultar fontes oficiais: pdfrx, ML Kit, flutter_onnxruntime, pdf_document, MiniLM e CTranslate2.
- [x] Fase 1: Flutter real, leitor, seleção, coordenadas, biblioteca, persistência, edição. Fluxo integrado Android passou, incluindo reabertura e prioridade de edição manual.
- [x] Fase 2: ML Kit mobile integrado; CTranslate2 desktop real testado e sidecar empacotado (5 testes Python passaram), NLP e modo A.
- [x] Fase 3: ONNX MiniLM real executado no host e no AVD, tokenizer com offsets/padding verificado nas 64 frases, 43 protótipos de sentidos e gerenciamento de modelos.
- [x] Fase 4: Comparar, laboratório, 64 fixtures autorais explícitas e métricas pareadas. Revisão humana pendente, sem alegação de gold humano.
- [x] Fase 5: exportação PDF incremental, 30 testes unitários, 5 Python, 3 fluxos de integração + ensaio de 1.001 páginas, builds Android debug/release e correções.
- [x] Fase 6: documentação e relatório medido, capturas e CSV/JSON, limitações por plataforma e instruções reproduzíveis.

## Estratégia verificável

Android usa ML Kit; desktop usa processo filho local CTranslate2, empacotado com runtime próprio, comunicação JSON por stdin/stdout (sem servidor). MiniLM ONNX usa pooling apenas dos tokens alvo e protótipos contextualizados separados dos exemplos de avaliação. Experimento não usará rótulos de teste no pipeline. Resultados sem validação humana serão identificados como fixtures autorais geradas pelo agente, não rótulos humanos independentes.

## Comandos planejados

`flutter doctor -v`, `flutter analyze`, `flutter test`, `flutter build apk --debug`, execução no AVD se disponível; testes Python do sidecar real, benchmark sem rede, exportar/reabrir PDF e renderizar para inspeção visual. Cada comando concluído terá resultado em `docs/TESTES_E_RESULTADOS.md`.

## Medições e problemas já resolvidos

- Flutter 3.47.7 / Dart 3.13.5 instalado localmente. Android debug x86_64 compilado: 231.608.473 bytes, 474,1 s na primeira build (incluiu download de SDKs).
- `flutter analyze` da aplicação passou após correções das APIs atuais (FilePicker 13 salva bytes e retorna Uri; pdfrx interaction retorna bool). Integração recebeu 2 lints, corrigidos em seguida.
- 29 testes reais passaram via `packages/validation` (mesmos arquivos de domínio da aplicação), evitando o hook PDFium que exige MSVC no host Windows. Não é um motor alternativo.
- Exportação incremental reabriu com 2 páginas, Highlight/FreeText, original como prefixo byte a byte. Renderização Poppler inspecionada visualmente, acentos visíveis.
- Benchmark real desktop: 35/64 A, 43/64 B, 8 ganhos / 0 perdas; p50 decisão adicional A 0,085 ms / B 55,166 ms. Relatório bruto em reports/benchmark.json e CSV. Modelo B frio 3.499,603 ms; cache não contabilizado como speedup contextual.
- Sidecar standalone PyInstaller gerado e testado, 205.389.172 bytes em 568 arquivos; não exige Python global nem servidor.
- Build Windows exige Visual Studio C++ ausente. A instalação silenciosa foi rejeitada por revisão automática da ferramenta; nenhuma tentativa de contornar essa decisão. iOS/macOS exigem Mac/Xcode.

## Encerramento da implementação e validações externas pendentes

- Android: os três testes de reader/modelos/comparador passaram. O teste de 1.001 páginas com 50 marcações distintas também passou. `reports/network-audit.json` comprova rede desligada **antes** das inferências, com confirmação Android e restauração do estado.
- Qualidade final Android: A 34/64, B 43/64; 9 ganhos, 0 perdas no corpus. Resultado anterior B 40/64, incluindo perda em `bank`, preservado como histórico do adaptador com padding diferente. Nenhum rótulo/protótipo foi ajustado para corrigir esses resultados.
- Auditoria encontrou telemetria do SDK ML Kit; transporte CCT/Firelog removido do manifest, ausência confirmada nos logs. SDK debug imprime frases no logcat; limitação registrada em PRIVACIDADE.md. Sem telemetria própria ou IA remota.
- Smoke test CLI real confirmou zero chamadas/import ONNX em A, reinício do sidecar e conversão de offsets UTF-16 com emoji contra tokenizer oficial.
- Correções adicionais verificadas: seleção obsoleta descartada; tensor int64; padding/attention mask; busca criada após ready; provider fora de dispose; nenhuma substituição automática de edição manual; upsert para a mesma faixa evita duplicatas; badge oficial no leitor/comparador/exportação; backup Android desativado.
- [ ] Android físico de 4 GB: latência, memória/energia, gestos/orientação e longa leitura em livro real (exige aparelho).
- [x] Windows UI: build release gerado e aberto pelo usuário após configurar Visual Studio e links simbólicos. Motor do bundle verificado com modelos instalados na pasta de suporte real (`reports/windows-installed-runtime.json`).
- [ ] Windows UI: roteiro interativo completo de seleção/comparação, persistência e exportação na interface Windows. A abertura observada e o smoke test do motor não substituem essa validação.
- [ ] iOS/macOS: build/assinatura e privacidade do SDK em Mac/Xcode. Linux: build e empacotamento no alvo.
- [ ] Revisão humana independente do corpus, rótulos de alinhamento PT e calibração. Não há confiança percentual publicada.
- [ ] Conferência humana em Edge/Acrobat, corpus amplo de PDFs protegidos/rotacionados/CropBox/colunas, OCR futuro.

Essas dependências externas e limitações não foram declaradas como testes executados. Todos os módulos independentes e testes viáveis deste ambiente foram implementados/executados; não houve publicação remota.

### Retomada Windows — 23/10/2026

O usuário instalou Visual Studio C++ e repetiu o empacotamento. PyInstaller concluiu; Flutter interrompeu na preparação dos links dos plugins, solicitando Modo de Desenvolvedor. Reproduzido localmente: `pub get` pode concluir sem recriar os links; por isso o script agora testa a criação real de um link via Dart antes de reempacotar o runtime, além de executar `pub get` e preservar o diagnóstico original. Não atribui todas as falhas ao Visual Studio. Configuração do sistema não foi alterada automaticamente. Compilação e execução da interface seguem pendentes até habilitar links simbólicos.

Atualização posterior: o usuário concluiu a compilação e abriu a interface Windows (captura do leitor e processo release confirmados). A primeira tradução falhou porque a pasta de suporte continha somente o manifest, enquanto os pesos estavam em `models` no repositório. Instalados por cópia local 11 arquivos de tradução/MiniLM (106.703.016 B), com todos os hashes verificados na origem e no destino, sem novo download. Motor incluído no bundle executou duas traduções corretas e embedding de 384 dimensões; zero chamadas/import ONNX antes de solicitar o encoder. Relatório: `reports/windows-installed-runtime.json`. PDFs e banco de anotações não foram modificados.

### Ajustes de destaque e mouse no Windows — 23/10/2026

- [x] Destaques com intensidade 0,85 no canvas da página, composição Multiply preservando o texto escuro. A intensidade também vale para marcações existentes e para a exportação PDF nativa.
- [x] Duplo clique seleciona palavra pelo delegate oficial do pdfrx, inclusive em marcações de expressões. Clique simples mantém detalhes da anotação e arraste continua selecionando texto.
- [x] Integração real Windows com banco em memória e PDF sintético: palavra sem marcação, palavra marcada, palavra dentro de expressão marcada, arraste, duplo clique após zoom e clique simples nos detalhes. Passou em 11 s após build. Comparação de pixels preservou 290/290 pixels de letras escuras e detectou 729 pixels de fundo com intensidade maior. Capturas `reports/windows-highlight-before.png` e `reports/windows-highlight-after.png`; dados em `reports/windows-reader-interaction.json`.
- [x] 30 testes de domínio/exportação passaram, incluindo intensidade 0,85 e Multiply no PDF reaberto. `flutter analyze --no-pub` sem problemas.
- [x] Release atualizado compilado em 40,8 s; bundle conferido com `data/app.so`, Flutter DLL e runtime local. Hashes em `reports/windows-desktop-build.json`.

Limite deste ensaio: os testes de gestos não invocam tradutor/encoder e usam dados isolados. A inferência desktop real continua coberta pelo smoke test separado; isso não equivale à validação do fluxo Windows completo de tradução/exportação pela interface. A primeira tentativa do novo ensaio tentou clicar em coordenada fora do viewport após zoom; corrigido o centro do zoom do próprio teste e repetido com sucesso.

### Seleções fora do léxico — 23/10/2026

- [x] Diagnosticar `rippling`: frase traduzida normalmente, mas seleção fora do léxico restrito; MiniLM não supre sentidos ausentes.
- [x] Oferecer sugestão isolada do tradutor local quando nenhum modo produz tradução curta, com aviso de contexto não confirmado e botão de revisão. Não acrescentar respostas específicas nem alterar fixtures/protótipos.
- [x] Revisão obrigatória antes de gravar; cancelar não grava. Anotação registra edição manual, origem da sugestão, revisão pelo usuário e `contextVerified=false`/`alignmentResolved=false` para a evidência isolada.
- [x] Manter decisões/métricas A/B intactas: sugestão suplementar fora do experimento, tempo separado, nenhuma chamada MiniLM em A. Corrigida indicação de carregamento durante o painel de revisão.
- [x] 32 testes compartilhados e análise estática sem problemas. Integração real Windows passou em 6 s após build: `programming` fora do léxico → `Programação`, cancelar, revisar e salvar como `programação revisada`, banco isolado, duas traduções e zero chamadas/import ONNX. Relatório `reports/windows-isolated-suggestion.json`; captura `.png` correspondente.
- [x] Tradutor empacotado verificou cinco palavras isoladas, incluindo `rippling` → `Ondulação`; resultados em `reports/windows-isolated-words.json`. São sugestões isoladas, não validação contextual dessas palavras.
- [x] Release atualizado compilado em 56,3 s, bundle conferido e aplicativo reaberto. Hashes atualizados em `reports/windows-desktop-build.json`.

Limitação preservada: o léxico de sentidos continua pequeno; a sugestão não resolve automaticamente ambiguidades ou omissões na tradução da frase. As medições A/B anteriores não incluem esta ajuda suplementar para revisão humana.

### Barra de rolagem e fluidez — 23/10/2026

- [x] Barra visível à direita, indicador proporcional/arrastável e clique na trilha. Usa coordenadas do documento e controle oficial de arraste do pdfrx, acompanhando zoom.
- [x] Trocar avanço reduzido/instantâneo por multiplicador de roda 4,0 e delegate de suavização com fricção 18. Eventos rápidos acumulam deslocamento; Ctrl+roda continua no caminho de zoom e eventos de trackpad mantêm o tratamento próprio da biblioteca.
- [x] Integração Windows passou em 11 s após build: evento de roda idêntico deslocou 8,27 px antes e 80,00 px depois (zoom 2,068), com frame intermediário em 20,73 px. Foram 20 eventos de delta 20 para alcançar a página 2 no PDF sintético. Arraste ao início/fim, clique na trilha e manutenção do zoom passaram. Dados isolados em `reports/windows-reader-scroll.json`, captura `.png` correspondente.
- [x] Regressão Windows de seleção/destaques passou em 11 s: duplo clique, arraste, zoom, clique simples e 290/290 pixels escuros preservados. Análise estática sem problemas. Release atualizado compilado em 44,4 s, bundle conferido e aplicativo reaberto; hashes em `reports/windows-desktop-build.json`.

Limite de validação: a configuração de gestos é compartilhada, mas os testes deste ajuste serão executados no Windows; não equivalem a ensaio físico de trackpad ou novo teste em telefone.

### Tradução direta durante a leitura — 23/10/2026

A pedido explícito do usuário, substituída a revisão obrigatória do fluxo padrão por aplicação direta. A revisão descrita na seção anterior passa a ser opcional, acessível por Detalhes/Comparar.

- [x] Básico/Contextual aplicam a tradução no documento sem abrir o painel; Comparar e o novo botão Detalhes mantêm acesso explícito às evidências.
- [x] Atalho Básico para palavras fora do léxico traduz somente a seleção, evitando a tradução completa da frase. Nenhum MiniLM nesse caminho.
- [x] Remover pontuação externa de seleções de uma palavra e dos rótulos, preservando offsets UTF-16 e apóstrofos/hífens internos. Seleções de várias palavras mantêm a pontuação original para cópia.
- [x] Registrar tradução automática isolada como tal, sem marcar revisão humana, sem alegar confirmação contextual, sem alterar as decisões/métricas A/B. Preservar anotações manuais antigas mesmo quando incluíam pontuação na faixa.
- [x] 34 testes compartilhados passaram.
- [x] Integração Windows real passou em 8 s: salvar sem painel, remover pontuação, `computer,` → `computador`, proteger anotação manual antiga com pontuação e abrir Detalhes somente a pedido. Uma chamada de tradução no caminho rápido, zero encoder/ONNX; zoom preservado e 862 pixels escuros de texto presentes após salvar. Relatório `reports/windows-quick-translation.json`, captura `.png` correspondente.
- [x] Regressão Comparar com revisão opcional passou em 14 s, com tradutor e encoder reais. Relatório `reports/windows-comparison-suggestion.json`; análise estática sem problemas.
- [x] Release atualizado compilado em 79,7 s; bundle conferido e aplicativo reaberto. Hashes em `reports/windows-desktop-build.json`.

Conferência visual revelou remontagem do PdfViewer ao inserir/remover o indicador de progresso, antes encoberta pelo painel. Corrigido com espaço de progresso constante e chave estável do viewport; acrescentadas verificações de zoom e pixels do texto no ensaio de tradução direta.

Artefato final: APK release ARM64 separado por ABI, 74.634.011 B, SHA-256 `18df973006064eff5864b53ab4e74d41f0a7b0633e08490b797151cac0750ab1`. Release universal também compilou (159.039.771 B), mas a entrega preferida é o APK ARM64 de ~71,2 MiB. Assinatura de desenvolvimento; não publicado em loja. `flutter analyze` final sem problemas; `git diff --check` passou. PDF Android final re-renderizado e inspecionado, com “ação: desistir” e “luz” sobre os trechos correspondentes, sem sobrescrever a edição manual.

### Salvar no próprio PDF — 23/10/2026

Pedido explícito do usuário autoriza atualizar o original. A regra de preservar original continua aplicável à opção separada Exportar cópia.

- [x] Botão Salvar/Ctrl+S no desktop atualiza o caminho original, sem seletor de destino recorrente.
- [x] Schema v2 guarda origem/hash, migra v1 sem perda de biblioteca/anotações/progresso e mantém identidade após mudar os bytes. Cópias iguais em caminhos diferentes são independentes.
- [x] Importações antigas vinculam original uma vez por seletor/verificação de hash ou reabertura do original na biblioteca.
- [x] Reconciliar anotações pertencentes ao documento por namespace, preservando notas externas; editar/remover propaga ao PDF. Salvar sem mudanças não regrava nem aumenta bytes.
- [x] Base interna limpa evita destaque/rótulo em dobro e bloqueio do original pelo PDFium; Salvar mantém documento/zoom abertos.
- [x] Temporário na mesma pasta + flush + renomeação, limpeza em falha, detecção de alteração externa e mensagem de bloqueio/permissão.
- [x] 40 testes compartilhados passaram, incluindo migração, salvamentos repetidos, edição/remoção, notas externas, cópias independentes, conflito externo e bloqueio real do destino por processo Windows.
- [x] Integração Windows pela interface passou em 16 s: criar marcação, editar texto, Salvar, repetir sem mudar bytes, Ctrl+S, reabrir biblioteca com mesmo ID/progresso, base sem duplicação, remover e salvar com zero anotações. Um único PDF na pasta de origem. Captura e dados em `reports/windows-save-original.*`.
- [x] PDF salvo reaberto por pypdf e renderizado por Poppler; texto original extraível, Highlight/FreeText nativos e rótulo “programação revisada” conferidos. Evidências `reports/windows-save-pdf-validation.json` e `reports/windows-save-original-render.png`.
- [x] Regressão com tradutor real passou em 9 s: tradução automática `Programação` gravada no PDF original com Highlight/FreeText, sem painel obrigatório; `computer,` → `computador`, zero encoder/ONNX e edição manual preservada. Relatório `reports/windows-quick-translation.json` atualizado.
- [x] Análise estática final sem problemas; `git diff --check` passou. Release Windows atualizado compilou em 91,3 s, arquivos do bundle conferidos e aplicativo reaberto. Manifest `reports/windows-desktop-build.json`.

Limites: novo Salvar validado no Windows; mobile continua exportando pelo seletor, sem escrita no URI original. Revisões incrementais não fazem expurgo de bytes antigos. Edição completa em outra instalação depende de transportar o banco local; anotações continuam visíveis nativamente no PDF.

### Remoção acessível de marcações — 23/10/2026

- [x] Ação Remover marcação na barra para trechos selecionados que cruzem marcações existentes, inclusive seleção parcial. Remove destaque e tradução associados; preserva outras faixas/páginas.
- [x] Lixeira na lista Anotações e manutenção do Remover nos detalhes. Uma única rotina transacional com Desfazer e limpeza da seleção azul; invalidação de tradução pendente para não recriar a marcação removida.
- [x] 41 testes compartilhados passaram; teste de limites exclusivos, seleção parcial, múltiplas sobreposições, outra página, faixa vazia/inválida e anotação sem offsets.
- [x] Integração Windows ampliada passou em 15 s: seleção parcial remove o destaque e sua tradução; Desfazer restaura banco/rótulo; marcação em `light` permanece ao remover `programming`; lixeira da lista remove sem seleção; Salvar reabre com zero anotações no original. Um único PDF na origem. Evidências em `reports/windows-save-original.json` e captura correspondente.
- [x] Análise estática final sem problemas; `git diff --check` passou. Release Windows compilado em 42,8 s, bundle conferido e aplicativo atualizado reaberto. Manifest `reports/windows-desktop-build.json`.

### Significado visível junto da palavra — 23/10/2026

- [x] Diagnóstico em leitura somente: a tradução de `rippling` estava salva, mas o layout antigo a colocou no topo da página, a cerca de 615 pontos do alvo. O problema era posição distante, não ausência da gravação.
- [x] Tentar fontes 8/7/6 acima do alvo e, se não houver entrelinha livre, procurar primeiro na margem próxima da seleção; preservar o texto original. Exibir o resultado no viewport depois de aplicar.
- [x] Reposicionar notas antigas ao visitar sua página, preservando significado/proveniência e registrando versão de layout. Salvar original aguarda esse reposicionamento.
- [x] Botão Escrever significado independente de modelo; editor preenche texto existente e recusa vazio. Sugestões têm Usar esta tradução direto e Editar significado opcional; editor alternativo preenche a sugestão disponível.
- [x] 43 testes compartilhados passaram, incluindo entrelinha estreita e margem próxima sem cobrir texto.
- [x] Integração Windows com PDF sintético denso passou em 6 s: nota antiga migrou de y=762 para y=161,196; significado manual `em cascata` ficou a 1 ponto acima do topo do alvo, na margem próxima, com 133 pixels vermelhos visíveis. Vazio recusado, banco/PDF/reabertura preservados e nenhum modelo necessário. Evidências `reports/windows-word-meaning.*`.
- [x] Painel com motores reais passou em 12 s: cancelar não grava; Usar esta tradução aplica sem diálogo; edição posterior salva manualmente. Três traduções e duas invocações de encoder no Comparar. Relatório atualizado `reports/windows-comparison-suggestion.json`.
- [x] PDF salvo validado por pypdf e renderizado com Poppler; rótulo visível e texto original extraível. Fonte 7 na margem próxima em vez de mandar a nota para o outro lado da página; análise estática sem problemas.
- [x] Release Windows compilado em 45,5 s, bundle conferido por tamanho/hash e aplicativo atualizado reaberto. Manifest `reports/windows-desktop-build.json`; `git diff --check` passou. APK anterior não foi substituído.

### Tradução diretamente acima da palavra — 23/10/2026

- [x] A pedido do usuário, manter o rótulo centralizado sobre a palavra e retirar a busca de margem. Ajustar fonte 8/7/6/5/4 à entrelinha, mantendo a âncora mesmo sem área livre.
- [x] Versão de layout 3 corrige posições antigas ao visitar a página, inclusive notas da versão 2. Preservar significado e revisão manual.
- [x] Linha compacta no overlay; compensação do padding interno do FreeText para reproduzir o alinhamento no PDF salvo.
- [x] 43 testes compartilhados passaram; análise estática sem problemas. Integração Windows passou em 6 s: centro horizontal idêntico ao alvo (diferença 0 pt), caixa 0,3 pt acima, pixels vermelhos presentes, salvar/reabrir preservados. Captura/PDF `reports/windows-word-meaning.*` conferidos visualmente.
- [x] PDF validado por pypdf (centro com diferença menor que 0,001 pt), renderizado com Poppler e inspecionado. Release compilado em 42,6 s, bundle conferido e aplicativo atualizado reaberto. Manifest `reports/windows-desktop-build.json`; `git diff --check` passou.

Limite real: letra compacta pode exigir zoom; em página sem qualquer vão ou alvo colado no topo pode ocorrer sobreposição/recorte. Não há refluxo do PDF. Novo ajuste verificado no Windows, sem nova execução mobile.

### Nitidez durante a leitura repetida — 23/10/2026

- [x] Separar qualidade da visualização e integridade da gravação. Ensaio inicial com 24 edições/salvamentos e seis ciclos de zoom/navegação não reproduziu degradação cumulativa; renderização do texto salvo idêntica à base.
- [x] Substituir a prévia fixa de 200 dpi por escala ligada ao zoom e à densidade do monitor, com duas amostras por pixel físico. Limitar a prévia a 4096 pixels por lado/12 Mi pixels; o pdfrx completa regiões visíveis acima do teto na resolução real.
- [x] Teste Windows com PDF vetorial sintético de seis páginas, 12 notas, 24 gravações e seis ciclos de zoom/navegação: 8568 pixels intactos idênticos antes/depois, 951 pixels escuros preservados. Texto extraível e renderizações PDFium da base/salvo com SHA-256 idêntico.
- [x] Comparação visual no mesmo trecho/zoom: energia local de bordas 6515,51 → 9639,87 (+47,95%); pixels intermediários de cinza 1089 → 704. Medida local, sem extrapolar para todos os PDFs/monitores. Relatórios `windows-sharpness-*.json/png`.
- [x] 44 testes compartilhados passaram; análise estática sem problemas. Integração final de significado passou em 7 s, mantendo alinhamento, edição e PDF/reabertura. Release Windows compilado em 45,6 s (47,2 s com invocação), artefatos conferidos por SHA-256, aplicativo atualizado reaberto. Manifest `reports/windows-desktop-build.json`; `git diff --check` passou.

Limite: o defeito progressivo específico da captura não foi reproduzido no ensaio sintético. A alteração melhora a amostragem da tela; não recupera detalhes ausentes em imagens escaneadas. Sem nova execução mobile ou ensaio em todos os DPIs/GPUs.

### Entrega dos fontes para compilar no Mac — 23/10/2026

- [x] Conferir alvo universal iPhone/iPad, deployment target 16.0, dependências e seleção do motor mobile no código.
- [x] Documentar preparação do Mac/Xcode/Flutter, assinatura Personal Team, instalação release nos dois aparelhos e alternativa TestFlight. Conferir regras de sete dias e 90 dias em fontes oficiais da Apple.
- [x] Preparar `scripts/package_ios_sources.py` e ZIP com fontes/lock/assets/iOS/guia/testes compartilhados; excluir SDKs, builds, modelos instalados, banco pessoal e credenciais. Verificar integridade ZIP e presença das entradas essenciais; evidência `reports/ios-source-package.json`.
- [x] Explicitar que compilar/testar no Mac continua pendente e que salvar diretamente no PDF original ainda não foi implementado no iOS. Não declarar build iOS validada.

### Salvar no PDF original no iPhone/iPad e build na nuvem — 23/10/2026

- [x] Substituir a importação iOS por seletor Arquivos com `asCopy:false`; manter autorização por bookmark e identidade persistente na biblioteca.
- [x] Adicionar canal nativo registrado no ciclo UIScene, leitura/escrita por `NSFileCoordinator`, escopo adquirido/liberado por operação, escrita atômica e hash esperado conferido dentro da coordenação. Erros de provedor não viram sucesso nem cópia exportada silenciosamente.
- [x] Habilitar Salvar/Cmd+S no iOS; vincular o original das importações antigas. Integrar `DocumentFiles` ao identificador externo sem tratar token como caminho e sem alterar a base interna da renderização.
- [x] 49 testes compartilhados passaram, incluindo cinco testes novos de armazenamento/canal simulados: aplicar/editar/remover/reabrir, idempotência, conflito antes/durante a escrita, acesso negado, identidade e migração. Integração Windows de Salvar/Ctrl+S/editar/reabrir/remover passou em 16 s após compilação de 55,3 s.
- [x] Incluir três XCTest nativos de escrita coordenada/bookmark/conflito no alvo RunnerTests. Estes testes não foram executados no Windows; não representam validação iOS.
- [x] Preparar `codemagic.yaml` com workflows manuais `ios-verificar` e `ios-testflight`, sem credenciais no projeto, e guia `docs/BUILD_IOS_NUVEM.md`. Nenhum repositório foi enviado nem workflow remoto executado.
- [x] Análise estática final sem problemas; `git diff --check` passou. YAML dos dois workflows interpretado e sete scripts conferidos com `bash -n`; plist de abertura no lugar e registro/participação do Swift no build Xcode conferidos. Relatório `reports/ios-original-save.json`. Documentação e ZIP atualizados com fontes nativos, testes e build na nuvem; integridade/entradas/hash em `reports/ios-source-package.json`.

Pendência externa real: compilar Swift/Xcode e executar testes nativos no macOS, depois validar Arquivos local/iCloud/provedores reais em iPhone e iPad. A implementação está nos fontes; não há IPA assinado nem validação física Apple neste ambiente.

### Flexão da tradução curta no modo Contextual — 23/10/2026

- [x] Reproduzir com o tradutor real: frase contém `se aninham entre si`, mas o fallback isolado de `nest` devolvia `ninho` porque a palavra não está no léxico.
- [x] Procurar primeiro um trecho literal único da frase, comparando prefixos/orações traduzidos com/sem alvo, preservando flexão e acentos. Recusar reescrita extensa, múltiplas ilhas/ocorrências e mudança distante. Sem tabela especial para `nest` e sem alterar o pipeline de avaliação A/B.
- [x] Registrar origem/offsets/evidência da sugestão e exibir descrição contextual no painel. Fallback isolado permanece explícito; edições manuais têm prioridade.
- [x] 56 testes compartilhados passaram, incluindo sete novos casos de flexão, substantivo, acentos, ambiguidade, fallback, deriva distante e isolamento do encoder no A. Análise estática sem problemas.
- [x] Ensaio com modelos reais em seis exemplos: cinco trechos contextuais extraídos; um fallback quando o tradutor omite a palavra. `nest` verbo → `aninham`, substantivo → `ninho`, `revolve` → `gira`. Evidência `reports/windows-contextual-labels.json`.
- [x] Integração Windows passou em 13 s: substitui anotação automática `ninho` por `aninham` sem duplicar, mantém substantivo, salva no original e reabre. CTranslate2 e MiniLM reais; captura/PDF/JSON `windows-contextual-label-ui.*`. PDF renderizado por Poppler e inspecionado.
- [x] Painel Comparar passou em 16 s com sugestão contextual, aplicar/editar/cancelar preservados. Cinco traduções, duas invocações de encoder; `reports/windows-comparison-suggestion.json`.
- [x] Release Windows compilado em 91,8 s (94,1 s com invocação), artefatos conferidos por SHA-256 e aplicativo atualizado reaberto com janela nativa. Manifest `reports/windows-desktop-build.json`; ZIP de fontes iOS atualizado com o novo alinhamento, conferido por CRC/entradas/hash; `git diff --check` passou.

Limites: heurística de leitura não equivale a desambiguação garantida; casos sem palavra correspondente na frase ainda usam tradução isolada. Primeiro uso com MiniLM frio levou cerca de 7 s no ensaio de interface; os tempos adicionais variam com frase/carga. Sem nova execução mobile.

### Preparação do repositório público no GitHub — 23/10/2026

- [x] Revisar README para clonagem em outro computador, instalação Windows, modelos, uso, Android/iOS, resultados A/B, estrutura e limitações reais. Incluir captura de teste e guia de contribuição.
- [x] Reforçar exclusões de bancos, credenciais, modelos e artefatos compilados; preservar fontes, manifests, locks, licença e evidências de teste.
- [x] Adicionar GitHub Actions para análise e testes Dart compartilhados, com ações fixadas por SHA. Build/assinatura iOS continuam nos fluxos manuais Codemagic.
- [x] Reexecutar localmente 56 testes compartilhados e cinco testes Python com modelos reais; análise estática sem problemas. Sem novo download de modelos.
- [ ] Conferir arquivos públicos, publicar na conta autorizada e verificar conteúdo remoto e CI.
