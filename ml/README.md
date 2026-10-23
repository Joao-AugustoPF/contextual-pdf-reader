# Inferência e avaliação local

`runtime.py` é o sidecar empacotável, sem sockets; modelos reais são lazy-loaded. `scripts/download_models.py --consent` instala os artefatos registrados em `manifests/models.lock.json`. `requirements.lock.txt` fixa o ambiente medido. O tokenizer WordPiece mobile segue BERT uncased para inglês e conserva offsets UTF-16; o sidecar converte offsets Dart para codepoints Python antes de chamar o tokenizer oficial.

Léxico/protótipos em `app/assets/lexicon.json` e avaliação em `datasets/evaluation.json`. `scripts/seed_data.py` contém cada exemplo explicitamente; não gera variações duplicadas para inflar N. Os 64 exemplos são rotulados pelo agente, não passaram por anotador humano. Não treinar/calibrar nos exemplos de teste. Não incluir gold na inferência.

O modelo ONNX é exportação/quantização upstream validada por inferência real com saída `[1, sequence, 384]`, norma e offsets testados. Não alegamos que foi reexportado pelo projeto nem medimos paridade Python PyTorch vs ONNX. Uma reprodução independente de exportação está descrita em `scripts/export_minilm.py`, exige dependências adicionais e deve produzir novo manifest/hash, não substituir o artefato medido silenciosamente.
