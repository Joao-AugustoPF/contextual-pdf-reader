# Modelos offline

Downloads são ações explícitas. Inferência nunca baixa modelos, resolve DNS ou chama IA externa. Mobile pode usar somente A sem MiniLM. Instalação direta valida SHA-256 e renomeia `.part` apenas após concluir; o tradutor desktop valida cada arquivo antes do primeiro uso. Corrompidos geram erro, sem resultado falso B.

| Artefato | Bytes medidos | SHA-256 |
|---|---:|---|
| MiniLM ONNX QUInt8 | 23.046.789 | `b941bf19f1f1283680f449fa6a7336bb5600bdcd5f84d10ddc5cd72218a0fd21` |
| tokenizer.json | 466.247 | `be50c3628f2bf5bb5e3a7f17b1f74611b2561a3a27eeab05e5aa30f411572037` |
| vocab.txt | 231.508 | `07eced375cec144d27c900241f3e339478dec958f92fddbc551f295c992038a3` |
| Argos en_pb 1.9 compactado | 66.179.201 | `1d1cd5e9540c6b38c258bed002a42d3b311b8a189acb74feaa311ef30d175c5b` |

Download total 89.923.745 bytes; modelos instalados incluindo metadados do pacote: 106.703.016 bytes (~101,76 MiB). Sidecar PyInstaller: 205.389.172 bytes antes de qualquer alteração posterior, não incluídos nesses pesos. ML Kit: tamanho e revisão interna de pacotes não expostos pelo plugin; não inventamos hashes/bytes. Usa SDK nativo gerenciado pelo Google. Modelo de tradução português pode produzir variantes regionais diferentes de pt-BR.

[MiniLM Apache-2.0](https://huggingface.co/sentence-transformers/all-MiniLM-L6-v2) na revisão `1110a243fdf4706b3f48f1d95db1a4f5529b4d41`; encoder BERT de 6 camadas, hidden size 384, ~22,7 milhões de parâmetros segundo configuração pública. Artefato upstream `onnx/model_quint8_avx2.onnx`; é grafo ONNX CPU quantizado, não um binário AVX2 obrigatório. Android/ARM deve ser medido separadamente. O manifest registra o tamanho realmente baixado e a quantização, sem alegar equivalência numérica com PyTorch não medida.

Reprodução: `python ml/scripts/download_models.py --consent` na venv. A primeira obtenção registrou hashes; instalações subsequentes os comparam ao manifest versionado. Há URLs imutáveis de revisão para MiniLM; Argos possui URL de versão e seu hash é a âncora. Copie o lock para `app/assets/models.lock.json` se atualizar conscientemente o conjunto e execute novamente todas as medições.

Remoção no app descarrega o encoder e remove seu diretório. Não há sincronização ou telemetria própria. O transporte de diagnósticos ML Kit foi desativado no Android; veja PRIVACIDADE.md para limites do SDK. Downloads consentidos consultam a origem dos pesos/configurações do provedor; nenhum texto do usuário é anexado pelo aplicativo.

O adaptador mobile lê o padding fixo 128 do tokenizer pinado e mascara tokens PAD; a conformidade dos IDs/offsets nas 64 frases foi verificada automaticamente contra o tokenizer oficial. Atualizar tokenizer exige repetir esse teste e o benchmark. Sem padding idêntico, quantização dinâmica pode produzir decisões diferentes; a execução histórica que demonstrou isso foi preservada no relatório.
