# Decisões técnicas — 23/10/2026

Fontes verificadas antes da implementação: [pdfrx](https://pub.dev/packages/pdfrx), [ML Kit](https://developers.google.com/ml-kit/language/translation), [plugin ML Kit](https://pub.dev/packages/google_mlkit_translation), [ONNX Flutter](https://pub.dev/packages/flutter_onnxruntime), [pdf_document](https://pub.dev/packages/pdf_document), [CTranslate2](https://opennmt.net/CTranslate2/), [MiniLM](https://huggingface.co/sentence-transformers/all-MiniLM-L6-v2).

Versões exatas resolvidas: Flutter 3.47.7, Dart 3.13.5; pdfrx 2.10.0; pdf_document 10.0.0 (Apache-2.0); flutter_onnxruntime 1.9.0; google_mlkit_translation 0.15.1; Riverpod 3.4.3; Drift 2.35.2; sqlite3 3.5.2; FilePicker 13.1.0; material_ui 1.8.0; archive 4.5.2. Todas as transitivas estão no `app/pubspec.lock`; ambiente Python no `ml/requirements.lock.txt`.

Escolhemos pdfrx por texto estruturado, seleção por offsets, transformações de rotação e overlays que preservam gestos. A versão 2.10 exige um compilador C para o gate de PDFium; não foi substituído silenciosamente quando MSVC faltou no Windows. O harness de testes independente executa o código real de domínio/persistência/exportação sem importar o viewer; testes completos do viewer são feitos no Android.

ML Kit não funciona no Windows. CTranslate2 com pacote Argos en_pb 1.9 foi escolhido para tradução desktop por seu modelo compacto já convertido e licença identificada no README do pacote (CC-BY-4.0, derivado de OPUS-MT). Não há servidor. PyInstaller inclui runtime privado. A distribuição completa ocupa mais que os pesos e sua build Windows depende de MSVC.

MiniLM genérico não é WSD pronto. Usamos extração de hidden states do alvo, normalização L2 e comparação com spans em protótipos contextuais separados. São 43 sentidos autorais, sem treinamento e sem limiar ajustado nos exemplos de teste. Escolha por maior cosseno é experimental; abstenção da tradução curta decorre da reconciliação com a frase traduzida. Não apresentamos score como confiança calibrada.

O exportador puro Dart escreve Highlight + FreeText com appearance streams. Acentos portugueses são atendidos por Helvetica base-14/WinAnsi, sem redistribuir fontes proprietárias; texto fora de sua cobertura ainda exige fonte incorporada e validação específica. O original é preservado, sem rasterizar páginas.

FilePicker 13 tem métodos estáticos, salva bytes e retorna Uri. Na exportação desktop, PDF usa escolha de pasta + nome novo; o botão Salvar usa fluxo separado para atualizar o original. Android exporta pela criação de documento do sistema. Em iOS, FilePicker importa PDFs como cópia, por isso a abertura destinada à edição foi substituída por um canal nativo: `UIDocumentPickerViewController(asCopy:false)`, bookmark persistente, `NSFileCoordinator` e escrita atômica com hash esperado. A renderização continua em uma base interna. CSV/JSON e exportação de cópia usam `saveFile`. A implementação iOS ainda precisa de compilação e execução nativas.
