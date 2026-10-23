"""Exportação independente opcional. pip install torch transformers onnx.
Não é o artefato upstream usado nas medições; requer novo manifest e benchmark.
"""
from pathlib import Path
import torch
from transformers import AutoModel, AutoTokenizer
from onnxruntime.quantization import quantize_dynamic, QuantType
ID='sentence-transformers/all-MiniLM-L6-v2'
REV='1110a243fdf4706b3f48f1d95db1a4f5529b4d41'
out=Path('models/reexport');out.mkdir(parents=True,exist_ok=True)
tokenizer=AutoTokenizer.from_pretrained(ID,revision=REV)
model=AutoModel.from_pretrained(ID,revision=REV).eval()
class Tokens(torch.nn.Module):
    def __init__(self, model):super().__init__();self.model=model
    def forward(self,input_ids,attention_mask,token_type_ids):
        return self.model(input_ids=input_ids,attention_mask=attention_mask,token_type_ids=token_type_ids).last_hidden_state
inputs=tokenizer('Turn on the light.',return_tensors='pt')
torch.onnx.export(Tokens(model),tuple(inputs[k] for k in ['input_ids','attention_mask','token_type_ids']),str(out/'float.onnx'),
    input_names=['input_ids','attention_mask','token_type_ids'],output_names=['last_hidden_state'],opset_version=17,
    dynamic_axes={k:{0:'batch',1:'sequence'} for k in ['input_ids','attention_mask','token_type_ids','last_hidden_state']},dynamo=False)
quantize_dynamic(str(out/'float.onnx'),str(out/'int8.onnx'),weight_type=QuantType.QUInt8)
tokenizer.save_pretrained(out)
print('Exportado. Validar numericamente com PyTorch e medir qualidade antes de adotar.')
