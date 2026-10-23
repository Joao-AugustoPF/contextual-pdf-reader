# PROMPT MESTRE PARA CODEX — LEITOR DE PDF OFFLINE COM TRADUÇÃO CONTEXTUAL E EXPERIMENTO A/B

> **Modo de execução:** implementar o projeto de ponta a ponta no repositório, não somente elaborar um plano. Este é um documento de especificação e instruções operacionais para o agente de programação (Codex/Meta). Execute as fases na ordem, produza código e testes reais e mantenha um registro verificável das entregas.
>
> **Idioma da interface, mensagens, documentação e relatórios:** português brasileiro. Código, identificadores e APIs podem seguir convenções em inglês.

## 0. PAPEL, OBJETIVO E REGRAS INEGOCIÁVEIS

Você atuará como engenheiro principal de software, especialista em Flutter, processamento de PDFs, inferência on-device, NLP, qualidade e distribuição multiplataforma.

Crie, a partir de um repositório novo ou do diretório de trabalho atual se ele já for destinado a este produto, um **leitor de PDF com marcações coloridas e tradução contextual escrita em vermelho acima das palavras/expressões selecionadas**. A aparência desejada é de um leitor de livros semelhante aos leitores de PDF convencionais, com anotações sobrepostas às palavras como em livros estudados à mão.

### Requisitos não negociáveis

1. **Offline-first de verdade:** depois de os modelos de idioma serem baixados uma vez, **leitura, marcações, tradução contextual disponível, armazenamento e exportação funcionam sem internet**. Nunca chamar API remota de IA por padrão. Nenhuma VPS é necessária para o aplicativo funcionar.
2. **Comparação A/B real, com botão ou controle na interface:**
   - **Modo A — Básico:** tradutor local + reconhecimento de expressões + alinhamento/heurísticas; **sem executar MiniLM**.
   - **Modo B — Contextual:** mesmo tradutor local e componentes básicos **mais MiniLM/encoder contextual devidamente integrado para desambiguação**.
   - **Modo Comparar:** na mesma seleção, mostrar resultados dos modos A e B lado a lado, tempo, confiança estimada, decisões intermediárias e opção do usuário para escolher a melhor tradução.
   - O controle precisa alterar de fato o pipeline executado, não apenas a aparência. Gravar a configuração e oferecer uso rápido na barra da ferramenta e configuração avançada em Preferências.
3. **Prova técnica honesta:** um modelo `all-MiniLM-L6-v2` de embeddings genéricos de frases **não é, por si só, um desambiguador de sentido de palavra (WSD)**. Não afirmar que o recurso funciona só por calcular similaridade de vetores da frase inteira. Desenvolver um pipeline *target-aware*, com experimentos e métricas, ou localizar e validar uma variante especializada, com licenças adequadas. Se o MiniLM não melhorar, provar isso pelos testes e documentar.
4. **Não confundir ML Kit com MiniLM:** ML Kit é o motor de tradução local para Android/iOS; MiniLM é o modelo contextual opcional utilizado apenas no modo B. O modo A usa ML Kit no mobile, mas não roda MiniLM.
5. **Sem hardware caro:** priorizar Android com 4 GB de RAM e desktop comum. Não depender de GPU, LLM de bilhões de parâmetros, Ollama, Jev, Laya, APIs pagas nem Python rodando num servidor remoto.
6. **Não fabricar sucesso:** não usar respostas hardcoded para simular inferência real, não inventar medições, não mascarar bugs com mocks na aplicação final. Mocks somente em testes. Informar explicitamente o que depende de dispositivo físico ou ambiente ausente.
7. **Entregar implementação, não protótipo de telas:** fluxos de abrir PDF, selecionar, traduzir, editar, salvar e exportar devem estar integrados. O botão A/B deve executar os motores reais quando disponíveis.
8. **Licenças e privacidade:** identificar licenças das bibliotecas, dados, tokenizadores, modelos e fontes. Respeitar exigências de atribuição do ML Kit. Não embutir chave de API, não enviar texto do PDF para terceiros, não gravar trechos privados em telemetria.
9. **Não substituir unilateralmente o offline por uma VPS.** Um backend de sincronização será apenas possível evolução futura, fora do caminho crítico.

## 1. O QUE O USUÁRIO PRECISA CONSEGUIR FAZER

- Abrir um arquivo PDF local, inclusive livros com centenas ou mais de mil páginas; recuperar livros recentes; manter progresso de leitura.
- Rolar, navegar por páginas, usar zoom, buscar texto, acessar sumário quando existir; leitura responsiva em touchscreen e mouse.
- Selecionar palavra, expressão ou trecho. Mostrar menu com: **Marcar**, **Marcar e traduzir**, **Explicar tradução disponível**, **Copiar**, **Editar anotação** (quando pertinente).
- Escolher pelo menos cinco cores de destaque: amarelo, verde, azul, rosa e vermelho; desfazer/remover.
- Selecionar `give` na frase `I decided to give up programming.`: o sistema deve tentar reconhecer que a unidade semântica é `give up`; resultado esperado, quando corretamente resolvido, `desistir` (não `dar`). Mostrar visualmente qual faixa do original recebeu a anotação, e dar ao usuário a opção de ajustar a faixa quando a detecção de expressão for incerta.
- Selecionar `light` em `Turn on the light` versus `This framework is light`: traduzir conforme o contexto, desde que o motor produza evidências suficientes.
- Mostrar a tradução **em vermelho, curta e legível, imediatamente acima da palavra/expressão**, com destaque de cor no original. Ao tocar/clicar na anotação, abrir popover com frase original, tradução da frase inteira, tradução curta, modo utilizado, confiança calibrada (quando houver), observações e edição.
- Permitir editar manualmente a tradução e indicar origem `automática` ou `editada`. A tradução manual tem prioridade sobre futuros cálculos automáticos.
- Garantir que marcações, posições, traduções e modo escolhido permaneçam após fechar e abrir o aplicativo e após mudar zoom/orientação.
- Exportar uma **cópia** do PDF com destaques e traduções visíveis, sem sobrescrever o original. Priorizar preservação de texto selecionável; documentar diferenças entre anotações nativas, conteúdo achatado e overlay interno.
- Operar sem internet após a instalação dos modelos. Exibir gestão de modelos: tamanho, estado (não baixado/baixando/disponível/erro), baixar somente com consentimento e opção de remover.
- Poder clicar em um seletor `Básico | Contextual | Comparar`, executar as opções e acessar uma aba de **Laboratório A/B**.

## 2. PLATAFORMAS E ORDEM PRÁTICA DE IMPLEMENTAÇÃO

**Tecnologia de interface:** Flutter + Dart, com código-fonte compartilhado.

- **Principal para implementar e validar primeiro:** Android, porque ML Kit está disponível e é possível testar o produto offline numa plataforma mobile real.
- **Segundo alvo:** Windows desktop com tradução 100% local por um motor nativo próprio para desktop. Não fingir que `google_mlkit_translation` funciona no Windows — não funciona.
- **Preparar arquitetura e projeto para iOS/macOS/Linux**, ajustando integrações conforme a plataforma. Compilação iOS/macOS exige macOS/Xcode; se o ambiente atual não permitir, entregar o código/plataforma preparada, testes possíveis e um roteiro verificável de compilação, sem alegar teste não realizado.
- Web é opcional e não deve sacrificar desktop/mobile/offline. Se Web não tiver inferência disponível, apresentar suporte limitado de forma transparente.

### Bibliotecas iniciais candidatas — verificar APIs atuais antes de codificar

- PDF: `pdfrx` sobre PDFium, com seleção, extração e `pageOverlaysBuilder`, coordenadas canônicas e interações que não bloqueiem zoom/rolagem.
- Estado: Riverpod, com separação clara de domínio/infraestrutura/UI; evitar sobrearquitetura desnecessária.
- Persistência: Drift + SQLite (livros, anotações, modelo usado, cache, experimentos, medições e progresso).
- Android/iOS: `google_mlkit_translation` + SDKs nativos Google ML Kit Translation. Compatibilidade e requisitos de iOS/Android devem ser conferidos antes da integração.
- MiniLM: ONNX Runtime com plugin/FFI multiplataforma mantido, por exemplo `flutter_onnxruntime` ou wrapper atual cuja versão e suporte estejam verificados, mais tokenizador WordPiece/BERT real e offsets.
- Exportação: validar `pdf_document` ou outra biblioteca Dart/native que realmente consiga escrever highlights e FreeText ou conteúdo visível; não assumir que apenas abrir PDF com `pdfrx` resolve exportar anotações.
- Desktop translation: avaliar Bergamot/Marian, CTranslate2 quantizado, Argos Translate empacotado localmente ou outra implementação **realmente offline e distribuível**. Priorizar uma solução pequena e licenciável, sem exigir que o usuário instale manualmente um servidor, Python global ou um terminal ativo. Se usar sidecar, empacotar e inicializar automaticamente como parte do aplicativo, comunicar o tamanho e medir desempenho. Nunca encaminhar requisições a um serviço público escondido.
- Use versões estáveis atuais verificadas; registre versões exatas no `pubspec.lock` e em `docs/DECISOES_TECNICAS.md`. Não inventar APIs ou dependências.

Documentações de referência:
- https://pub.dev/packages/pdfrx
- https://pub.dev/packages/google_mlkit_translation
- https://developers.google.com/ml-kit/language/translation
- https://pub.dev/packages/flutter_onnxruntime
- https://onnxruntime.ai/docs/tutorials/mobile/
- https://pub.dev/packages/pdf_document
- https://www.sbert.net/docs/sentence_transformer/usage/usage.html

## 3. ARQUITETURA DO REPOSITÓRIO

Implemente módulos testáveis e interfaces, com estrutura equivalente a:

```text
contextual-pdf-reader/
├── app/                          # Aplicação Flutter
│   ├── lib/
│   │   ├── app/                  # Tema, roteamento, inicialização, providers
│   │   ├── features/
│   │   │   ├── library/           # Biblioteca de PDFs locais
│   │   │   ├── reader/            # PDF, navegação, seleção e sobreposições
│   │   │   ├── annotations/       # Marcação, edição, exportação
│   │   │   ├── translation/       # Casos de uso e interfaces
│   │   │   ├── experiment/        # Modo A, B, Comparar e métricas
│   │   │   └── settings/          # Modelos e preferências
│   │   ├── core/
│   │   │   ├── pdf_coordinates/
│   │   │   ├── nlp/               # Segmentação e alinhamento
│   │   │   ├── inference/         # Motor ONNX e controle de recursos
│   │   │   └── persistence/
│   │   └── main.dart
│   ├── test/
│   ├── integration_test/
│   └── assets/
├── packages/                     # Se separar bibliotecas facilitar os testes
│   ├── translation_core/
│   └── annotation_core/
├── ml/
│   ├── scripts/                  # Preparação, conversão/quantização e avaliação
│   ├── manifests/                # Metadados, hashes, licença, versão
│   ├── datasets/                 # Exemplos rotulados e licença
│   └── README.md
├── docs/
│   ├── ARQUITETURA.md
│   ├── DECISOES_TECNICAS.md
│   ├── MODELOS_OFFLINE.md
│   ├── EXPERIMENTO_AB.md
│   ├── EXPORTACAO_PDF.md
│   ├── LIMITACOES.md
│   └── TESTES_E_RESULTADOS.md
├── scripts/
├── README.md
├── AGENTS.md                      # Regras para agentes que continuem o projeto
└── .gitignore
```

Modifique a organização se houver razão técnica forte, mas mantenha clara separação de domínio, infraestrutura, apresentação e testes. Configurações de experimentação não podem contaminar a lógica de anotação.

## 4. LEITOR PDF E LOCALIZAÇÃO EXATA DO TEXTO

1. Integrar `pdfrx` com seleção por mouse/toque, toolbar flutuante, múltiplas páginas, cache limitado de páginas e rendering preguiçoso/virtualizado. Deve escalar a um livro extenso sem renderizar todas as páginas de uma vez.
2. Extrair texto, posição da seleção e faixas de caracteres de forma vinculada ao PDF, não apenas coordenadas em pixels de tela. Usar informações da API de seleção de `pdfrx`, `PdfTextSelectionRange`, fragmentos, offsets/quad points e conversores de coordenadas disponíveis na versão escolhida.
3. Preservar internamente: ID/hash do PDF, número de página, início/fim do span, `selectedText`, frase, contexto, posição canônica (quadriláteros para cada linha), texto/expressão reconhecida, versão da extração.
4. Suportar seleções que ocupam múltiplas linhas; definir tratamento seguro para seleção entre páginas (ou mostrar limitação clara inicialmente). Atenção a hifenização de fim de linha, ligaduras (`fi`, `fl`), quebras de coluna, caracteres Unicode, documentos rotacionados, escala e `CropBox`/`MediaBox`.
5. Expor um `PdfSelectionContext` com offsets e área do original, e realizar extração por frase em código isolado da UI. Não confundir posição da palavra e posição da tradução.
6. Desenhar destaques com uma camada sobre a página e traduções vermelhas em sobreposição acima da expressão. Corrigir transformações de zoom/rotação; overlays não podem bloquear seleção, rolagem nem links do PDF. Verificar `PdfOverlayInteractionRegion` ou mecanismo equivalente atual.
7. Detectar espaços disponíveis entre linhas. Prevenir colisão entre traduções vizinhas. Caso não caiba, usar abreviação, nota discreta ou posição na margem, sem cobrir de forma ilegível o texto original.
8. Salvar posições nas coordenadas nativas do documento e recalcular visualização sempre que alterar viewport; usar testes de ida e volta das transformações e screenshots em múltiplas escalas.
9. PDFs escaneados sem camada de texto: detectar e mostrar `Esta página não possui texto selecionável; OCR poderá ser adicionado futuramente`. Não fazer OCR remoto silencioso.

## 5. PIPELINE OFFLINE DE TRADUÇÃO — COMPONENTES COMUNS AOS MODOS A E B

Fluxo desejado:

```text
Seleção no PDF
  -> trecho e offsets corretos
  -> segmentação da frase/trecho
  -> reconhecimento da unidade semântica (palavra ou phrasal verb)
  -> tradução completa da frase no tradutor local
  -> geração de candidatos e alinhamento entre original e tradução
  -> [Modo A: escolha heurística] OU [Modo B: WSD contextual com MiniLM]
  -> decisão/confiança/status de revisão
  -> renderizar, permitir editar, persistir e exportar
```

### 5.1 Extração de contexto

- Receber `selectedText`, palavra/token alvo, faixa do PDF, frase completa, parágrafo anterior/próximo quando relevante, idioma origem/destino.
- Segmentar frases de forma razoável mesmo com abreviações, títulos e pontuação; manter mapeamento para posições do documento. Para experiências com inglês, considerar caso `Mr.`, `e.g.`, `i.e.` e abreviações técnicas.
- Limitar contexto para evitar alto tempo de inferência, mas preferir preservar a frase completa (e opcionalmente contexto adjacente curto).
- Reconhecer multiword expressions / phrasal verbs: `give up`, `give in`, `look up`, `look after`, `run into`, `set up`, inclusive tokens não contíguos quando fizer sentido. Utilizar léxico com origem/licença documentadas + padrões seguros, com confirmação visual quando expandir seleção.
- Não assumir que `give` sozinho em `give up` deve ser traduzido como `dar`.

### 5.2 Tradução local (mesma entrada para A e B)

- Contrato `OfflineTranslationEngine`: `isSupported`, `isModelReady`, `listInstalledModels`, `downloadModelsWithConsent`, `translateSentence`, `dispose` e diagnóstico.
- Implementação mobile com ML Kit inglês -> português brasileiro, gerenciamento explícito de download e política Wi-Fi/consentimento. Uma vez instalado, tradução sem rede.
- Desktop: implementação independente, com motor offline de tradução de frases. Nunca chamar API pública. Pesquisar compatibilidade e selecionar um motor com modelos distribuíveis (por exemplo CTranslate2/Marian/Bergamot), documentando licença, peso e caminho de instalação. O mesmo contrato é usado por todos os sistemas.
- A e B usam **a mesma tradução de frase** em uma comparação controlada. Não traduzir frases distintas nem dar ao modo B informação que o modo A não teve, exceto o encoder contextual que queremos testar.
- Armazenar cache por idioma, texto normalizado + contexto e versão do tradutor; cache de inferência do MiniLM identificado separadamente.

### 5.3 Candidatos de tradução e alinhamento

- Traduzir a frase inteira não informa automaticamente qual palavra corresponde a qual termo em português. Implementar esse passo de maneira explícita.
- Gerar candidatos a partir de uma pequena base lexical/expressões (com licença verificável), da tradução isolada da expressão, de variantes morfológicas e de n-gramas plausíveis da frase traduzida.
- Identificar trechos candidatos na tradução completa, permitindo uma palavra em inglês -> múltiplas palavras em português, ou várias palavras em inglês -> uma em português.
- Usar normalização de acentos/case/lematização quando útil, mas NÃO tomar igualdade textual como prova de alinhamento semântico.
- Distinguir **desambiguação de sentido** (qual significado?) de **alinhamento** (qual trecho em português o realiza?). Essas tarefas não são intercambiáveis.
- Se não houver candidato/âncora confiável, retornar resultado inconclusivo com frase traduzida e opções para o usuário; não inventar uma tradução exata.
- Registro de tradução deve conter `originalSpan`, `detectedExpression`, `sentenceOriginal`, `sentenceTranslated`, `shortTranslation?`, `senseId?`, `candidateTranslations`, `engineId`, `modelVersion?`, `alignmentEvidence`, `confidence?`, `status` e `latencyMs`.

## 6. MODO A — BÁSICO (SEM MINILM)

- Sempre funcionar com somente o modelo tradutor local instalado.
- Reutilizar o reconhecimento de expressões e geração de candidatos da etapa comum.
- Aplicar heurísticas documentadas: correspondência lexical e morfológica; preferência por tradução localizada dentro da frase traduzida; coincidência de expressões; fallback para tradução isolada claramente rotulada; abstenção em casos ambíguos.
- Nunca solicitar inicialização/carregamento de ONNX ou MiniLM. Teste automatizado deve provar que zero chamadas foram feitas ao encoder no modo A.
- Mostrar no painel de explicação por que escolheu ou se absteve (ex.: `Tradução localizada na frase`, `Correspondência incerta`, `Seleção expandida para expressão`).

## 7. MODO B — CONTEXTUAL COM MINILM / ONNX

Este é o experimento central. **Não implementar um `cosine(sentence, "desistir")` genérico e anunciar WSD resolvido.**

### 7.1 Preparação do modelo

- Avaliar variante MiniLM real e licenciável adequada ao domínio inglês -> português como codificador contextual de **tokens ou spans**, não apenas embedding global de frase. A família MiniLM é preferida por seu tamanho, mas escolher checkpoint com base no teste.
- Se optar por `sentence-transformers/all-MiniLM-L6-v2`, deixar claro que o modelo padrão é treinado para similaridade de sentenças e que qualquer WSD será experimental. Para WSD, extrair hidden states dos tokens correspondentes ao span selecionado, com offset mapping real do tokenizador; criar exemplos/protótipos contextuais por sentido e comparar spans dentro de exemplos contextualizados, usando o MESMO procedimento de extração. Não comparar cegamente representação de token com embedding de frase/definição se não partilham representação treinada adequadamente.
- Preferência por modelo especializado/fine-tuned para WSD de tamanho comparável, se existir com pesos, licença e inferência ONNX verificáveis. Se não existir, construir o baseline contextual descrito acima e pipeline reproduzível de ajuste/treinamento opcional com dataset permitido.
- Considerar sense prototypes: para `give up` criar exemplos correspondentes a `stop trying`, para `give` como `hand over`; representar a mesma unidade alvo nos exemplos e medir similaridade com a unidade no texto. Usar um conjunto de sentidos/expressões que possa ser ampliado.
- Criar manifest: ID, fonte, revision/commit, licença, tamanho, SHA-256, vocabulário, quantização, idioma, número de parâmetros, procedimento de exportação e validação de saída Python versus ONNX.
- Converter/exportar ONNX com scripts reproduzíveis; quantizar INT8 quando viável; usar CPU (sem GPU obrigatória), controlar threads e executar fora da UI thread.
- Respeitar offsets do tokenizador, subwords e seleção com mais de uma palavra. Lidar com truncamento de contexto e termos fora do vocabulário.

### 7.2 Decisão do modo B

- Receber **exatamente a mesma sentença, expressão detectada, tradução e conjunto de candidatos** do modo A.
- Calcular evidências semânticas adicionais para ordenar sentidos/candidatos, preferencialmente usando similaridade contextual do span alvo com exemplos/protótipos de sentido.
- Converter sentido escolhido em possível tradução PT-BR e reconciliar com a tradução da frase. Se o sentido estiver claro mas não houver localização segura do trecho em português, retornar `meaningResolved=true` e `alignmentResolved=false`; não falsificar alinhamento.
- Exibir candidato escolhido, demais alternativas, pontuações e um indicador de confiança. Pontuação cosseno **não é probabilidade**: não mostrar `91% de certeza` sem calibração em conjunto rotulado. Se não calibrado, chamar `score semântico`, não `confiança`.
- Permitir limiar/abstenção calibrado apenas com dados de validação, nunca ajustar limiar inspecionando respostas do conjunto de testes final.
- Carregar o modelo **somente na primeira solicitação do modo B** ou ao selecionar `Baixar modelo contextual`; descarregar o modelo após inatividade ou sob pressão de memória quando possível. Ao desativar MiniLM, não mantê-lo carregado sem necessidade.
- Se modelo não estiver disponível (não baixado, dispositivo incompatível, arquivo corrompido), informar o motivo e permitir modo A normalmente; não rotular resultado A como B.

### 7.3 Gestão de peso/desempenho

Metas iniciais (metas, NÃO fatos medidos):

- Arquivos de modelos opcionais com foco em no máximo ~120 MB somados, sempre publicar os tamanhos reais.
- RAM adicional de inferência preferencialmente até ~250 MB num celular intermediário, medir e reportar.
- Tempo de uma seleção até ~1 segundo em smartphone intermediário como meta, sabendo que pode não ser atingida.
- Trabalhar com 1–2 threads CPU, batch pequeno, cancelamento de tarefas obsoletas, modelos lazy-loaded.
- Exibir na UI tamanho real do download do MiniLM, custo de memória observável quando possível, e permitir instalar/remover o modelo contextual separadamente.
- Não reduzir precisão a ponto de tornar o modo B inútil sem medir o tradeoff; documentar as decisões de quantização.

## 8. CONTROLE A/B E LABORATÓRIO EXPERIMENTAL — FUNCIONALIDADE OBRIGATÓRIA

Criar uma interface simples e muito clara:

```text
[ Básico ] [ Contextual ] [ Comparar ]       (controle segmentado na toolbar)

Texto selecionado: give up
Frase: I decided to give up programming.

MODO A — tradutor local       MODO B — tradutor + MiniLM
Tradução: ________          Tradução: ________
Sentido: _________          Sentido: _________
Tempo: ___ ms               Tempo: ___ ms
Estado: _________          Estado: _________
[Usar esta]                 [Usar esta]

[Ver frase completa] [Editar resultado] [Mostrar evidências]
```

### Regras do A/B

1. Botões de modo A, B e Comparar visíveis e persistentes em preferências. Prover atalhos rápidos conforme plataformas.
2. Modo Comparar executa os dois pipelines sobre a **mesma** seleção e frase, com tradutor compartilhado (uma tradução da frase) e custo de inferência separado; apresentar tempo de tradução e tempo adicional de decisão por modo, e tempo total. Registrar cache hit/miss e aquecimento de modelo.
3. Quando cache estiver ativo, medir separadamente cold start, warm start e cache hit para não alegar falsamente que o modelo B é mais rápido apenas porque executou em segundo lugar.
4. Em `Comparar`, salvar preferência do usuário por A/B/empate/ambos ruins. Possibilitar edição manual de resposta correta; usar como rótulo de avaliação apenas com consentimento e indicação de proveniência, **sem enviar dados para servidor**.
5. A alternância não pode criar duas marcações permanentes por engano. Primeiro comparar, depois o usuário escolhe qual tradução salvar, ou altera o texto.
6. Quando os resultados coincidirem, mostrar `Resultados iguais` e ainda registrar custos/latências separados.
7. Criar uma página `Laboratório` com lista de amostras, filtros de acerto, seleção de modelo, comparação por categoria, botões `Executar lote de testes`, `Exportar CSV`, `Exportar JSON` e `Limpar medições locais`.
8. Não permitir comparar como se MiniLM tivesse sido usado caso o modelo não esteja carregado. Estado `Modelo indisponível` precisa ser explícito.

## 9. BANCO LOCAL, PRIVACIDADE E CACHE

Implementar banco Drift/SQLite, com migrações, índices e operações transacionais. Entidades mínimas:

- `Document`: id, caminho/referência de arquivo, hash SHA-256, título, número de páginas, datas, progresso, dimensões/versões.
- `Annotation`: id, documentId, pageNumber, charRange, quadPointsPdf, selectedText, detectedExpression, type, color, shortTranslation, expandedExplanation, originalSentence, translatedSentence, mode, engine/model version, manualOverride, timestamps.
- `TranslationCache`: key/hash normalizado, source/target, text/context hash, backend/version, resultado e carimbo de data.
- `ModelInstallation`: id, fonte, versão, sha256, bytes, origem/download, status, erro.
- `ExperimentRun`: id, datasetId, build/model versions, device info anonimizada, start time, warm/cold, mode, metrics summary.
- `ExperimentSample`: runId, fixtureId, input, candidates, outputs A/B, labels, per-step latency, result/user verdict.
- `Preferences`: idioma, modo padrão, estilo/cores, modelo, política de download, cache.

Usar hash do conteúdo do PDF para reabrir a mesma obra mesmo que o arquivo tenha mudado de nome; detectar se o arquivo foi realmente modificado. Não persistir dados sensíveis além do necessário. Nenhuma sincronização/telemetria por padrão. Usar cache para tradução da frase, sem comprometer a validade da comparação A/B.

## 10. EXPORTAÇÃO PDF E REPRODUÇÃO FIEL DAS ANOTAÇÕES

- Exportar **cópia** de PDF com destaques e traduções visíveis, inclusive após reabrir em outro leitor.
- Testar um mecanismo de destaques nativos (`Highlight`, com quad points) e textos (`FreeText`, com fonte e cor) ou desenho fixo na página, conforme biblioteca estável e licenças.
- A fonte deve exibir acentos, cedilha e caracteres portugueses corretamente, sem usar fontes proprietárias redistribuídas irregularmente.
- Não achatar páginas inteiras em imagens por padrão, pois isso destruiria busca/seleção; se precisar de fallback, rotular separadamente `Exportar versão achatada`, explicar perda de editabilidade e preservar original.
- Não sobrescrever PDF original; usar seletor de destino e nomes amigáveis.
- Traduções que colidem devem ser adaptadas (redução de tamanho, nota na margem, chamada compacta) tanto na tela quanto na exportação.
- Teste automatizado deve exportar, reabrir e verificar conteúdo/anotações; teste manual deve conferir resultado em leitor externo como Edge ou Acrobat. Se o recurso nativo não puder ser validado, documentar limitações e entregar alternativa funcional sem declarar editabilidade nativa inexistente.

## 11. DATASET E AVALIAÇÃO DE QUALIDADE — NÃO INVENTAR MÉTRICAS

Criar um conjunto rotulado **de pelo menos 60 exemplos manuais inicializados no repositório** com expected gold definidos explicitamente, e estrutura simples para expandir para 200–500 seleções reais.

Categorias necessárias, com exemplos variados:

1. Palavra polissêmica: `light` (leve/luz), `bank` (banco financeiro/margem de rio), `charge`, `run`.
2. Phrasal verbs: `give up`, `give in`, `give away`, `look up`, `look after`, `turn down`, `set up`, `carry on`, `run into`.
3. Contexto técnico: `thread`, `framework`, `race condition`, `lock`, `deploy`, `build`, `branch`, `release`, `state`.
4. Expressões idiomáticas: `on the fly`, `out of the box`, `at stake`, `by and large`, `laissez-faire`.
5. Inflação/flexão verbal, plurais, negações, palavras fora de ordem, expressões que traduzem para uma ou várias palavras.
6. Frases com pontuação, abreviações, aspas, quebras de linha e seleção parcial.
7. Casos em que **abster-se** é a saída correta por falta de evidência.

Exemplos obrigatórios no conjunto, com resposta correta:

```json
[
  {
    "id": "phrasal-give-up-001",
    "sentence": "I decided to give up programming.",
    "selectedText": "give",
    "expectedExpression": "give up",
    "expectedSense": "stop doing something",
    "acceptableTranslationsPtBr": ["desistir", "abandonar"],
    "category": "phrasal_verb"
  },
  {
    "id": "polysemy-light-001",
    "sentence": "Turn on the light.",
    "selectedText": "light",
    "expectedExpression": "light",
    "expectedSense": "illumination",
    "acceptableTranslationsPtBr": ["luz"],
    "category": "polysemy"
  },
  {
    "id": "polysemy-light-002",
    "sentence": "This framework is light and fast.",
    "selectedText": "light",
    "expectedExpression": "light",
    "expectedSense": "not heavy / lightweight",
    "acceptableTranslationsPtBr": ["leve", "leve em recursos"],
    "category": "technical"
  }
]
```

Não preencher o dataset com centenas de duplicações automáticas dizendo que são rótulos independentes. Se usar exemplos gerados, separá-los dos rótulos humanos e identificar fonte. Manter dados de treino/validação/teste separados quando treinar/calibrar.

### Métricas mínimas

- Acurácia da tradução curta para os rótulos humanos, aceitando equivalências permitidas por exemplo.
- Acurácia do reconhecimento da expressão/limites da expressão (exact match e sobreposição de spans).
- Acurácia da desambiguação (sense ID quando definido).
- Acurácia do alinhamento (tradução localizada versus gold), separada da qualidade semântica.
- Taxa de abstenção e taxa de erros de alta confiança.
- Diferença pareada A versus B nos **mesmos** exemplos, taxa de ganhos/perdas por categoria e análise de erros.
- Latências p50/p95, inicialização de modelo, cold/warm, cache hit, tempos tradução + MiniLM + alinhamento.
- Consumo observado de RAM e tamanho real de modelos quando a plataforma permitir instrumentação; não inventar valor quando indisponível.
- Gráficos ou tabelas exportáveis com total de amostras e versão do modelo. Evitar afirmar melhoria sem base estatística suficiente.

## 12. TESTES AUTOMÁTICOS E MANUAIS

### Unit tests

- Segmentação de frase, seleção expandida, `give` -> `give up`, lematização/variações, contexto, coordenadas de PDF, colisão visual, cache e persistência.
- Modo A nunca invoca MiniLM; modo B invoca o encoder quando está instalado; modo Comparar usa a mesma frase e mesmo resultado base do tradutor.
- Falha/degradação quando não há modelos, não há texto extraível, PDF é protegido, modelo falha ou dispositivo está sem rede.
- Validação dos hashes dos modelos e do parser de resultados; versionamento de caches; modos A/B não compartilham respostas derivadas indevidamente.
- Cancelamento de inferência ao selecionar outra palavra; descarte de recursos e lifecycle.

### Widget/integration tests

- Biblioteca -> abrir PDF -> selecionar -> marcar -> traduzir -> exibir texto vermelho -> editar -> fechar -> reabrir -> exportar -> verificar.
- Zoom/rotação/layout responsivo mantendo posição do destaque e da tradução; touch e mouse com menus que não bloqueiam gestos.
- Comparar A/B em mesma seleção, alternar modos, salvar modo em preferências e mostrar resultados corretamente.
- Gestão de download e remoção do modelo MiniLM e dos pacotes de tradução.
- No modo avião, depois dos modelos pré-baixados: tradução continua funcionando e não existe tentativa de rede. Criar teste manual reproduzível, além de instrumentação onde possível.

### Testes de performance

- Abrir livro grande; limitar renderização em cache; rolar rapidamente; comparar consumo de RAM com 0 e 50 anotações.
- Em Android físico com 4 GB, quando houver aparelho conectado, capturar logs reais, latência e memória.
- Se não houver aparelho físico/SDK disponível, rodar testes de domínio e desenvolvimento de desktop; marcar teste mobile como **PENDENTE: exige dispositivo** com comandos e resultado esperado. Não inventar que foi executado.

## 13. EXPERIÊNCIA DE USUÁRIO / DESIGN

- Interface limpa, focada no texto, com tema claro e escuro; opções para esconder barras e maximizar área de leitura.
- Toolbar de anotação compacta, similar a um leitor de PDF: cinco cores, ação `Traduzir`, `Comparar`, opção apagar.
- Destaques semi-transparentes, preservando legibilidade do livro.
- Tradução curta **vermelha** acima da expressão no tamanho proporcional; popover com contexto, resultados completos e editar. Em telas estreitas, usar bottom sheet que não oculte persistentemente o texto.
- Biblioteca inicial com arrastar-e-soltar no desktop e seletor de arquivos nos dispositivos móveis.
- Configurações `Tradução`: modelo, modo padrão, idioma, `Baixar modelos offline`, gerenciar espaço, informações e privacidade.
- Laboratório A/B acessível nas configurações e por `Comparar` no menu contextual.
- Avisos claros: `Resultado experimental`, `Correspondência incerta`, `Modelo não instalado`, `Não há texto selecionável`.
- Nunca mostrar uma “confiança de 98%” fabricada com similaridade de cosseno não calibrada.
- Suporte a acessibilidade, contraste, alvos de toque e navegação por teclado.

## 14. CRITÉRIOS DE ACEITE E DEFINIÇÃO DE PRONTO

A tarefa está concluída somente se:

- [ ] Há um projeto Flutter real e versionável no repositório, com instruções para executar.
- [ ] Um PDF de texto pode ser aberto, pesquisado, navegado, com zoom e seleção.
- [ ] O usuário marca texto em cores e as posições persistem após zoom/reabertura.
- [ ] A tradução básica é realmente offline no Android com ML Kit após download autorizado.
- [ ] O modo B executa um modelo MiniLM/encoder contextual ONNX verdadeiro, com modelo e tokenizador reais, e evidências auditáveis de inferência; não apenas heurística renomeada.
- [ ] O botão `Básico | Contextual | Comparar` funciona e altera efetivamente o pipeline.
- [ ] `Comparar` exibe A e B lado a lado com frase comum, tempos separados e escolha do usuário.
- [ ] Tradução vermelha acima do trecho selecionado funciona, sem sobreposição inadequada; em caso de colisão há fallback legível.
- [ ] É possível editar e salvar tradução, fechar e reabrir sem perder dados.
- [ ] Exportação cria PDF anotado legível em outro leitor ou deixa documentada uma limitação específica com fallback honesto funcional.
- [ ] Testes automatizados de domínio e interface passam no ambiente disponível; documentação distingue testes reais de testes pendentes por plataforma.
- [ ] Há no mínimo 60 fixtures manuais claramente rotulados e execução automática de avaliação A/B nos dispositivos que suportam os motores.
- [ ] `docs/TESTES_E_RESULTADOS.md` registra evidências e números **somente quando realmente medidos**, incluindo comparação A/B e casos em que B ficou pior.
- [ ] Não existem chamadas a IA na nuvem ocultas, chave de API ou backend obrigatório.
- [ ] O código possui tratamento explícito para falhas de download, incompatibilidade de plataforma, ausência de modelo e PDFs sem camada de texto.
- [ ] Existe documentação do peso dos modelos, instalação offline, licenças e limitações.

Não considerar o projeto pronto apenas porque a interface funciona com strings de exemplo.

## 15. ORDEM DE EXECUÇÃO — NÃO PARAR NO SCAFFOLD

**Fase 0 — Inspeção e planejamento verificável**

1. Investigue ambiente atual (`flutter doctor`, Dart, SDK Android, CMake, Gradle, toolchains, permissões de arquivos) e repositório. Pesquise APIs/versões atuais das bibliotecas diretamente nas fontes oficiais antes de implementar.
2. Crie `IMPLEMENTATION_PLAN.md` com fases, checklist, comandos e estado. Registre em `docs/DECISOES_TECNICAS.md` por que escolheu cada motor e os limites reais de plataformas.
3. Caso o projeto esteja vazio, execute `flutter create` e inicialize Git. Não sobrescreva trabalho já existente sem inspecionar. Não efetue push para repositório remoto ou crie repo GitHub sem autorização/credenciais disponíveis.

**Fase 1 — Leitor e marcações**

4. Implementar abrir PDF, reader, seleção, coordenadas canônicas, cinco cores, overlays, zoom, persistência, edição, biblioteca.
5. Criar um PDF de teste sintético com texto selecionável e expressões (`give up`, `light`, etc.) e testes de coordenadas.

**Fase 2 — Tradutor local e modo A**

6. Integrar ML Kit Android/iOS, gestão de modelos e offline. Integrar um motor offline desktop de verdade, começando pelo sistema de desenvolvimento disponível; documentar pré-requisitos de cada OS.
7. Implementar extração do contexto, reconhecimento de expressões, tradução da frase, geração de candidatos, alinhamento, abstenção e modo A.
8. Criar testes de domínio e instrumentação real de tradução no dispositivo quando disponível.

**Fase 3 — Modo B e modelos**

9. Selecionar modelo contextual MiniLM adequado, criar exportação/reprodução ONNX, tokenizador e offsets; implementar model manager com checksums, lazy load, descarregamento e inferência no isolate/native worker.
10. Criar protótipos de sentidos e desambiguação baseada em span alvo; comparar com baseline. Se o checkpoint genérico não melhorar, não maquiar: registrar falhas e avaliar modelo especializado/fine-tuning ainda compacto.
11. Integrar modelo B no mesmo `TranslationOrchestrator` e testes que provem a diferença real de execução.

**Fase 4 — Comparador e benchmark**

12. Criar seletor A/B/Comparar, painel de comparação e laboratório de avaliação.
13. Adicionar dataset rotulado, métricas, exportação de relatórios e coleta de decisão manual do usuário.
14. Executar todos os testes possíveis; registrar resultados reais de qualidade e desempenho, sem inventar.

**Fase 5 — PDF anotado exportável e acabamento**

15. Exportar destaque e tradução em cópia PDF com acentos/fontes corretos; testes de abertura e visualização externa, legibilidade e ausência de colisão.
16. Testar cenários de falha/offline, acessibilidade, leitura de livros grandes, limpeza de cache e ciclo de vida dos modelos.
17. Executar `dart format`, `flutter analyze`, `flutter test`, testes de integração e builds disponíveis (Android/Windows etc.). Capturar erro e corrigir; documentar apenas limitações externas reais.

**Fase 6 — Entrega**

18. Atualizar `README.md`, `AGENTS.md` e toda documentação, com comandos de setup, download dos modelos, teste em modo avião, captura de resultados e screenshot dos modos.
19. Entregar resumo com arquivos criados, módulos implementados, comandos de execução, status por plataforma, comparação A/B, dados de peso/latência medidos e pendências genuínas.
20. Não interromper depois de criar arquivos vazios ou estrutura. Continue iterando até completar o máximo possível das fases neste ambiente. Se houver impedimento externo concreto, implemente todos os módulos independentes restantes e deixe instrução reproduzível para resolver o bloqueio.

## 16. PRIORIDADES QUANDO HOUVER TRADEOFFS

1. Aplicativo offline real, confiável e utilizável em Android.
2. Posicionamento correto das anotações sobre o PDF e persistência.
3. Comparação A/B tecnicamente verdadeira entre motor básico e MiniLM contextual.
4. Qualidade linguística validada sem alucinar correspondências.
5. Desempenho/RAM/tamanho sob controle e exportação fiel.
6. Suporte desktop com tradução nativa distribuível, sem servidor remoto.
7. Demais alvos multiplataforma e funcionalidades complementares.

Se um limite de tamanho/performance impedir determinado modelo, **não mude o produto para online**. Explore quantização, modelo especializado menor, download opcional e abstenção; registre um comparativo quantitativo antes de decidir.

## 17. RELATÓRIO FINAL DO AGENTE

Ao fim da implementação, mostrar de maneira objetiva:

- O que funciona no ambiente atual e o que foi realmente executado.
- Como abrir/rodar o aplicativo com comandos exatos.
- Como baixar modelos offline e testar com modo avião.
- Como usar os três modos A/B/Comparar e exportar CSV/JSON de benchmark.
- Quais modelos foram usados, seus links/licenças/hashes/tamanhos reais.
- Resultados reais dos testes e limitações, sem números inventados.
- O que ainda depende de um aparelho Android/iOS, de um Mac ou de hardware que não esteja presente.

**Comece agora com a inspeção do ambiente e avance para a implementação real; não responda apenas com um plano ou protótipo visual.**
