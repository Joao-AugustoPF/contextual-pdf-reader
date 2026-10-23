# Licenças e atribuição

Aplicação: MIT (LICENSE). Exemplos de avaliação, léxico e protótipos foram redigidos explicitamente pelo agente para este projeto, disponibilizados CC0; não foram copiados de dicionário proprietário. Não são rótulos humanos independentes. O PDF sintético usa apenas textos autorais e fontes base-14, sem arquivos de fontes redistribuídos.

| Componente | Licença / origem |
|---|---|
| Flutter / Dart | BSD-3-Clause |
| pdfrx | MIT, Takashi Kawasaki |
| PDFium | BSD e avisos de terceiros do projeto PDFium |
| pdf_document / pdf_cos | Apache-2.0 |
| flutter_onnxruntime | MIT, MASIC AI |
| ONNX Runtime | MIT, Microsoft |
| all-MiniLM-L6-v2 e WordPiece vocab | Apache-2.0, sentence-transformers, revisão no manifest |
| CTranslate2 | MIT, OpenNMT |
| SentencePiece | Apache-2.0, Google |
| tokenizers | Apache-2.0, Hugging Face |
| Argos en_pb 1.9 / OPUS-MT | CC-BY-4.0 conforme README do pacote |
| Riverpod / Drift | MIT |
| SQLite | domínio público; wrapper sqlite3 MIT |
| FilePicker / desktop_drop / archive | MIT |
| Python | PSF-2.0; runtime incluído no sidecar |
| PyInstaller | GPL-2.0 com exceção para executáveis empacotados |
| ML Kit | SDK/modelos sob termos Google; wrapper Flutter MIT |

OPUS-MT: Jörg Tiedemann e Santhosh Thottingal (2020), “OPUS-MT — Building open translation services for the World”, EAMT, Lisboa. [Publicação](https://aclanthology.org/2020.eamt-1.61/). A distribuição do modelo deve incluir o README atribuído; o instalador o preserva.

ML Kit requer atribuição de tradução conforme [guidelines oficiais](https://developers.google.com/ml-kit/language/translation/translation-terms). A interface identifica Google Translate no mobile. Antes de publicar em lojas, validar uso do logotipo/branding vigente e condições de distribuição do SDK; esta build de desenvolvimento não é aprovação comercial.

Licenças completas das dependências Dart são acessíveis pelo registro padrão Flutter e devem acompanhar builds distribuídas. PyInstaller recolhe metadados/licenças onde fornecidos pelos pacotes; o script de distribuição inclui `docs/LICENCAS.md` e exige revisão de notices transitivos antes de publicação.

O badge oficial Google Translate em `app/assets/google-translate.png` foi extraído sem modificação do [pacote de atribuição oficial](https://docs.cloud.google.com/static/translate/images/google-translate-attribution.zip). Seu uso segue as regras de marca, não a licença MIT do app. O vocabulário WordPiece de teste acompanha o texto Apache-2.0 em `docs/licenses/Apache-2.0.txt`.
