"""Instalação explícita. Nunca importado pelo caminho de inferência."""
import argparse
import hashlib
import json
from pathlib import Path
import zipfile
import requests

ROOT = Path(__file__).resolve().parents[2]
REV = '1110a243fdf4706b3f48f1d95db1a4f5529b4d41'

def fetch(url, path):
    path.parent.mkdir(parents=True, exist_ok=True)
    if not path.exists():
        tmp = path.with_suffix(path.suffix + '.part')
        with requests.get(url, stream=True, timeout=180) as r:
            r.raise_for_status()
            with tmp.open('wb') as f:
                for chunk in r.iter_content(1024 * 1024):
                    f.write(chunk)
        tmp.replace(path)
    return {'file': str(path.relative_to(ROOT)).replace('\\', '/'), 'url': url,
            'bytes': path.stat().st_size, 'sha256': hashlib.sha256(path.read_bytes()).hexdigest()}

def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--consent', action='store_true', required=True)
    args = parser.parse_args()
    records = []
    for remote, local in [('onnx/model_quint8_avx2.onnx', 'model.onnx'), ('tokenizer.json', 'tokenizer.json'), ('vocab.txt', 'vocab.txt')]:
        records.append(fetch(f'https://huggingface.co/sentence-transformers/all-MiniLM-L6-v2/resolve/{REV}/{remote}', ROOT / 'models/minilm' / local))
    archive = ROOT / 'models/translate-en_pb-1_9.argosmodel'
    records.append(fetch('https://argos-net.com/v1/translate-en_pb-1_9.argosmodel', archive))
    target = ROOT / 'models/translator'
    target.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(archive) as z:
        for entry in z.infolist():
            # Remove o diretório externo do pacote, sem aceitar traversal.
            parts = Path(entry.filename).parts[1:]
            if not parts or entry.is_dir():
                continue
            dest = target.joinpath(*parts).resolve()
            if not dest.is_relative_to(target.resolve()):
                raise ValueError('Caminho inválido no pacote')
            dest.parent.mkdir(parents=True, exist_ok=True)
            dest.write_bytes(z.read(entry))
    for path in sorted(target.rglob('*')):
        if path.is_file():
            records.append({'file': str(path.relative_to(ROOT)).replace('\\', '/'), 'bytes': path.stat().st_size,
                            'sha256': hashlib.sha256(path.read_bytes()).hexdigest()})
    manifest = {'minilm': {'id': 'sentence-transformers/all-MiniLM-L6-v2', 'revision': REV,
                'license': 'Apache-2.0', 'quantization': 'dynamic QUInt8 AVX2, upstream export',
                'dimensions': 384, 'parameters': 22713216, 'pooling': 'target token hidden states; experimental WSD'},
                'translator': {'id': 'Argos translate-en_pb', 'version': '1.9', 'source': 'argosopentech/argospm-index',
                               'license': 'CC-BY-4.0', 'attribution':'Jorg Tiedemann and Santhosh Thottingal (2020), OPUS-MT'}, 'files': records}
    out = ROOT / 'ml/manifests/models.lock.json'
    out.parent.mkdir(parents=True, exist_ok=True)
    # Manifest existente é a âncora: instalação subsequente recusa divergência.
    if out.exists():
        old = json.loads(out.read_text(encoding='utf-8'))
        if old['files'] != records:
            raise ValueError('Hashes diferem do manifest versionado; instalação rejeitada')
    out.write_text(json.dumps(manifest, indent=2, ensure_ascii=False), encoding='utf-8')
    print(json.dumps({'files': len(records), 'downloadBytes': sum(x['bytes'] for x in records[:4]), 'manifest': str(out)}))

if __name__ == '__main__':
    main()
