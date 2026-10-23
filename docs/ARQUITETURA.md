# Arquitetura

Flutter/Riverpod concentra apresentação em `features`. `AppServices` injeta banco, modelos, tradutor e encoder. Domínio em `core/nlp/pipeline.dart` não importa Flutter, ONNX, ML Kit nem dados de avaliação. O benchmark CLI e a interface executam a mesma classe `TranslationOrchestrator`.

`SelectionContext` usa offsets da extração vinculados à página, sem buscar a primeira ocorrência do texto selecionado. Reconhecimento lexical conserva spans de tokens para phrasal verbs separáveis. Segmentação mantém abreviações comuns e rejeita seleção vazia. O contexto não é cortado silenciosamente se o alvo for truncado pelo encoder.

Uma comparação gera uma única tradução completa, chaveada por backend/versão/idiomas/frase exata. A decisão A usa âncoras lexicais e flexões fracas identificadas como heurísticas. A decisão B usa o mesmo conjunto e acrescenta vetores do alvo, confrontados com protótipos em inglês. Não usa gold nem frases de avaliação na inferência. Sem âncora PT o sentido pode estar resolvido experimentalmente e o alinhamento continuar incerto. Sem encoder disponível B não recebe o resultado A.

ML Kit é chamado por platform channel no mobile. `flutter_onnxruntime` executa inferência nativa, com fila serial em Dart, duas threads CPU, liberação de tensores e unload após dois minutos. Ao trocar para A ou colocar o app em segundo plano, descarrega o encoder. Cancelamento por geração descarta resultados obsoletos; uma inferência nativa já em andamento termina antes da liberação.

Desktop usa processo filho persistente com IDs de requisição, timeout, tratamento de encerramento, UTF-8 e bloqueio de sockets. CTranslate2 INT8 e tokenização SentencePiece reais. ONNX e tokenizer Rust são importados apenas na primeira requisição contextual. Arquivos são verificados com SHA-256 antes de carregar.

Drift/SQLite usa SQL explícito, schemaVersion 2, migração v1 preservando biblioteca/progresso/anotações, chaves estrangeiras e índices. Persistem biblioteca, progresso, anotações completas JSON, preferências, modelos, cache e medições. `DocumentFiles` registra caminho original e SHA-256 observado; a identidade é mantida pelo caminho nas reaberturas, inclusive após Salvar mudar os bytes. Cópias idênticas abertas de caminhos diferentes têm identidades próprias. Importações v1 sem origem são vinculadas ao original por hash, sem perder anotações.

O PDFium lê uma base interna sem as anotações nativas pertencentes ao documento atual (`/NM = entrelinhas/<documentId>/...`); overlays continuam editáveis sem duplicação e sem bloquear o original. Salvar lê o original, reconcilia somente as nossas anotações e substitui o arquivo por renomeação de um temporário na mesma pasta, após flush e conferência do hash. Outras anotações permanecem. Salvar sem mudanças não regrava bytes. Revisões internas são cache privado; nenhum PDF adicional é criado na pasta do usuário. Arquivo alterado externamente exige reabertura para evitar sobrescrita silenciosa.

Caixas são armazenadas em pontos PDF `[left,bottom,right,top]`. `pdfrx.PdfRect.toRect` transforma rotação/zoom para tela. Highlights não interceptam gestos; `PdfOverlayInteractionRegion` recebe toques discretos. A mesma posição do rótulo persistida é usada na exportação incremental nativa. Seleção entre páginas é explicitamente recusada; leitura e navegação entre páginas continuam livres.
