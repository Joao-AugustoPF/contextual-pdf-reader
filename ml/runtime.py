"""Processo filho offline. JSON-lines; stdout reservado ao protocolo; zero sockets."""
import argparse
import hashlib
import json
from pathlib import Path
import sys
import time

class Runtime:
    def __init__(self, root, manifest):
        self.root = Path(root)
        self.manifest = json.loads(Path(manifest).read_text(encoding='utf-8-sig'))
        self.translator = self.sp = self.encoder = self.tokenizer = None
        self.encoder_calls = 0
        self.translation_calls = 0

    def verify(self, prefix):
        entries = [e for e in self.manifest['files'] if e['file'].startswith('models/' + prefix + '/')]
        if not entries:
            raise ValueError('Modelo sem manifest')
        for entry in entries:
            path = self.root / entry['file'].removeprefix('models/')
            if not path.is_file():
                raise FileNotFoundError('Modelo não instalado: ' + str(path))
            if hashlib.file_digest(path.open('rb'), 'sha256').hexdigest() != entry['sha256']:
                raise ValueError('SHA-256 inválido: ' + path.name)

    def translate(self, text):
        cold = self.translator is None
        started = time.perf_counter()
        if cold:
            self.verify('translator')
            import ctranslate2
            import sentencepiece
            self.translator = ctranslate2.Translator(str(self.root/'translator/model'), device='cpu',
                compute_type='int8', inter_threads=1, intra_threads=2)
            self.sp = sentencepiece.SentencePieceProcessor(model_file=str(self.root/'translator/sentencepiece.model'))
        load_ms = (time.perf_counter()-started)*1000 if cold else 0
        self.translation_calls += 1
        tokens = self.sp.encode(text, out_type=str)
        result = self.translator.translate_batch([tokens], beam_size=4, max_decoding_length=256)[0]
        # O pacote usa vocabulário alvo distinto do SentencePiece de entrada.
        # Detokenização alvo Marian/Argos: concatenação das peças e separador ▁.
        return {'text': ''.join(result.hypotheses[0]).replace('▁', ' ').strip(), 'cold': cold, 'loadMs': load_ms,
                'engineId': 'ctranslate2-argos-en_pb-1.9-int8'}

    def embed(self, sentence, start, end):
        cold = self.encoder is None
        started = time.perf_counter()
        if cold:
            self.verify('minilm')
            import onnxruntime as ort
            from tokenizers import Tokenizer
            options = ort.SessionOptions()
            options.intra_op_num_threads = 2
            options.inter_op_num_threads = 1
            self.encoder = ort.InferenceSession(str(self.root/'minilm/model.onnx'), options, providers=['CPUExecutionProvider'])
            self.tokenizer = Tokenizer.from_file(str(self.root/'minilm/tokenizer.json'))
            self.tokenizer.enable_truncation(max_length=256)
        load_ms = (time.perf_counter()-started)*1000 if cold else 0
        import numpy as np
        encoded = self.tokenizer.encode(sentence)
        indices = [i for i,(a,b) in enumerate(encoded.offsets) if a < end and b > start and b > a]
        if not indices or max(b for a,b in encoded.offsets) < end:
            raise ValueError('Alvo truncado ou sem tokens; ajuste o contexto')
        inputs = {'input_ids': np.array([encoded.ids], dtype=np.int64),
                  'attention_mask': np.array([encoded.attention_mask], dtype=np.int64),
                  'token_type_ids': np.array([encoded.type_ids], dtype=np.int64)}
        self.encoder_calls += 1
        hidden = self.encoder.run(None, {k:v for k,v in inputs.items() if k in {x.name for x in self.encoder.get_inputs()}})[0]
        if hidden.ndim != 3:
            raise ValueError('Checkpoint não expõe hidden states de tokens')
        span = hidden[0, indices].mean(axis=0)
        span = span / max(float(np.linalg.norm(span)), 1e-12)
        return {'vector':span.tolist(), 'tokenIndices':indices, 'offsets':[encoded.offsets[i] for i in indices],
                'cold':cold, 'loadMs':load_ms, 'encoderCalls':self.encoder_calls}

    def handle(self, request):
        op = request['op']
        if op == 'translate': return self.translate(request['text'])
        if op == 'embed': return self.embed(request['sentence'], request['start'], request['end'])
        if op == 'unload':
            self.encoder = self.tokenizer = None
            return {'unloaded':True}
        if op == 'status':
            import psutil
            memory=psutil.Process().memory_info()
            return {'translatorReady':(self.root/'translator/model/model.bin').exists(),
                'minilmReady':(self.root/'minilm/model.onnx').exists(),
                'encoderCalls':self.encoder_calls, 'translationCalls':self.translation_calls,
                'onnxImported':'onnxruntime' in sys.modules, 'rssBytes':memory.rss,
                'peakWorkingSetBytes':getattr(memory,'peak_wset',None)}
        raise ValueError('Operação desconhecida')

def main():
    sys.stdin.reconfigure(encoding='utf-8')
    sys.stdout.reconfigure(encoding='utf-8')
    def deny_network(event, args):
        if event in ('socket.connect', 'socket.getaddrinfo'):
            raise RuntimeError('Rede proibida no processo de inferência')
    sys.addaudithook(deny_network)
    p=argparse.ArgumentParser(); p.add_argument('--models', required=True); p.add_argument('--manifest',required=True)
    args=p.parse_args(); runtime=Runtime(args.models,args.manifest)
    for line in sys.stdin:
        request={}
        try:
            request=json.loads(line); t=time.perf_counter()
            result=runtime.handle(request); result['elapsedMs']=(time.perf_counter()-t)*1000
            response={'id':request['id'],'result':result}
        except Exception as e:
            response={'id':request.get('id'),'error':str(e)}
        print(json.dumps(response,ensure_ascii=False),flush=True)

if __name__=='__main__': main()
