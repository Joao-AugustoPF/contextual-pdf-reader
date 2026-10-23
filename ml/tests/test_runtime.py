import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import pytest

ROOT=Path(__file__).resolve().parents[2]
spec=importlib.util.spec_from_file_location('runtime',ROOT/'ml/runtime.py')
runtime=importlib.util.module_from_spec(spec);spec.loader.exec_module(runtime)

@pytest.fixture
def engine():return runtime.Runtime(ROOT/'models',ROOT/'ml/manifests/models.lock.json')

def test_translation_real_and_no_encoder(engine):
    result=engine.translate('I decided to give up programming.')
    assert 'desist' in result['text'].lower()
    assert '▁' not in result['text']
    assert engine.encoder is None and engine.encoder_calls==0

def test_real_onnx_target_hidden_states(engine):
    a=engine.embed('Turn on the light.',12,17)
    b=engine.embed('This bag is light.',12,17)
    assert len(a['vector'])==384 and a['offsets']==[(12,17)]
    assert sum(x*x for x in a['vector'])==pytest.approx(1,abs=1e-5)
    assert a['vector']!=b['vector']

def test_corrupt_hash_rejected(engine,tmp_path):
    engine.root=tmp_path
    p=tmp_path/'minilm/model.onnx';p.parent.mkdir();p.write_bytes(b'corrupt')
    with pytest.raises(ValueError,match='SHA-256'):engine.verify('minilm')

def test_target_truncation_explicit(engine):
    sentence='word '*400+'light'
    with pytest.raises(ValueError,match='truncado'):engine.embed(sentence,len(sentence)-5,len(sentence))

def test_packaged_process_without_global_python():
    exe=ROOT/'dist/reader-runtime/reader-runtime.exe'
    if not exe.exists():pytest.skip('Empacotamento ainda não executado')
    data='\n'.join(json.dumps(j) for j in [{'id':1,'op':'status'},{'id':2,'op':'translate','text':'Turn on the light.'},{'id':3,'op':'embed','sentence':'Turn on the light.','start':12,'end':17}])+'\n'
    p=subprocess.run([str(exe),'--models',str(ROOT/'models'),'--manifest',str(ROOT/'ml/manifests/models.lock.json')],input=data,capture_output=True,text=True,encoding='utf-8',timeout=90)
    assert p.returncode==0,p.stderr
    rows=[json.loads(line) for line in p.stdout.splitlines()]
    assert rows[0]['result']['onnxImported'] is False
    assert 'luz' in rows[1]['result']['text'].lower()
    assert len(rows[2]['result']['vector'])==384
