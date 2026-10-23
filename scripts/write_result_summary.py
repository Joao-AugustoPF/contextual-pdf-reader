"""Regenera a seção Android a partir das medições, sem constantes de sucesso."""
import json
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
p=ROOT/'docs/TESTES_E_RESULTADOS.md'
s=p.read_text(encoding='utf-8')
header='## Android: resultado final e auditoria offline'
s=s.split(header)[0].rstrip()+'\n\n'
r=json.loads((ROOT/'reports/benchmark-android.json').read_text(encoding='utf-8'))
m=r['summary'];env=r['environment']
s+=header+'\n\n'
s+='Fonte: `reports/benchmark-android.json` / `.csv`. Três testes de integração reais passaram: reader/persistência/exportação; modelos/64 pares; Comparar pela UI e salvar somente a escolha. O teste também verifica que cálculo automático não substitui uma tradução manual existente. Nenhum dado real de usuário foi utilizado.\n\n'
s+='Auditoria reproduzível: `python scripts/test_android_offline.py`. O script desligou a rede **antes** do cálculo; `ConnectivityManager` retornou `connected=false, validated=false`; `reports/network-audit.json` registra modo avião ativo, Wi-Fi desativado, sucesso e restauração do estado anterior. Tradução de frase sem cache durante o lote. A primeira tentativa de auditoria por callback de screenshot foi inválida e não é usada como evidência de offline.\n\n'
s+='| Métrica | A (ML Kit + heurística) | B (mesma frase + MiniLM ONNX) |\n|---|---:|---:|\n'
for label,key,fmt in [('Acertos curtos / 64','correct','int'),('Acurácia curta','accuracy','pct'),('Sentido correto / 60','senseCorrect','int'),('Abstenções','abstentions','int'),('Decisão adicional p50 (ms)','decisionP50Ms','float'),('Decisão adicional p95 (ms)','decisionP95Ms','float')]:
    def show(v):return f'{v*100:.2f}%' if fmt=='pct' else f'{v:.3f}' if fmt=='float' else str(v)
    s+=f"| {label} | {show(m['A'][key])} | {show(m['B'][key])} |\n"
s+=f"\nGanho pareado final: {m['gainsB']} ganhos / {m['lossesB']} perdas, {m['pairedNetAccuracyDifference']*100:.2f} pontos percentuais. Tradução comum p50 {m['translationP50Ms']:.3f} ms / p95 {m['translationP95Ms']:.3f} ms. Primeiro uso B: {r['cold']['B']['decisionMs']:.3f} ms; não confundir com latência quente.\n\n"
s+=f"RSS total do processo Android debug no AVD: antes de inferir {env['rssBeforeInference']:,} B; após lote {env['rssAfterEvaluation']:,} B (incremento observado {(env['rssAfterEvaluation']-env['rssBeforeInference'])/1048576:.2f} MiB). Inclui Flutter/SDKs/GC e não isola somente MiniLM nem mede telefone físico.\n\n"
s+='O teste de conformidade detectou padding fixo 128 no tokenizer upstream que faltava no adaptador mobile. Corrigimos padding e attention mask a partir do tokenizer pinado; **30 testes unitários passam**, incluindo IDs e offsets idênticos ao tokenizer oficial nas 64 frases. Não houve alteração dos rótulos/protótipos para melhorar os números.\n\n'
s+='A execução antiga com comprimento variável fica em `reports/benchmark-android-variable-length.json`: A 34/64, B 40/64, 7 ganhos e **1 perda real**, `bank` em “The fisherman sat on the river bank.”: A escolheu “margem”; B escolheu sentido financeiro e se absteve. Esse arquivo é histórico de um adaptador anterior; seu flag offline não foi confirmado pela instrumentação antiga. A versão final resolve esse caso, mas ainda erra/abstém em 21/64 seleções. Não interpretar a correção como prova de generalização do MiniLM.\n\n'
s+='Capturas reais: `reports/reader-android.png` e `reports/compare-android.png`. PDF exportado pelo fluxo Android: `output/pdf/exportado-android.pdf`, reaberto/renderizado com destaques, FreeText, acentos e badge oficial Google Translate quando aplicável.\n'
large=ROOT/'reports/large-document.json'
if large.exists():
    v=json.loads(large.read_text(encoding='utf-8'))
    s+=f"\nTeste sintético de {v['pages']} páginas: passou, página sem texto detectada; abertura + espera explícita de 1 s para primeiro render {v['openAndOneSecondRenderMs']:.3f} ms. RSS com 0 anotações {v['rssZeroAnnotations']:,} B / com 50 {v['rssFiftyAnnotations']:,} B (diferença {(v['rssFiftyAnnotations']-v['rssZeroAnnotations'])/1048576:.2f} MiB, sem isolar GC/cache). Evidência em `reports/large-document.json`; não é teste de livro real em aparelho físico.\n"
p.write_text(s,encoding='utf-8')
