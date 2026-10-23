"""Comparação local das capturas sintéticas, no mesmo zoom e trecho intacto.

Energia de bordas é uma medida de contraste local, não uma nota universal de
legibilidade nem evidência de reprodução do defeito relatado pelo usuário.
"""
import json
import math
from pathlib import Path
from PIL import Image

reports = Path(__file__).resolve().parents[1] / 'reports'
run = json.loads((reports / 'windows-sharpness-after.json').read_text())
left, top, right, bottom = run['roi']
box = (math.ceil(left), math.ceil(top), math.floor(right), math.floor(bottom))
metrics = {}
for stage in ('before', 'after'):
    image = Image.open(reports / f'windows-sharpness-{stage}-repeated.png')
    gray = image.convert('L').crop(box)
    values = list(gray.get_flattened_data())
    width, height = gray.size
    energy = sum(
        (values[y * width + x] - values[y * width + x - 1]) ** 2
        + (values[y * width + x] - values[(y - 1) * width + x]) ** 2
        for y in range(1, height) for x in range(1, width)
    ) / ((width - 1) * (height - 1))
    metrics[stage] = {
        'edgeEnergy': energy,
        'darkPixels': sum(v < 64 for v in values),
        'midGrayPixels': sum(64 <= v < 192 for v in values),
    }

result = {
    'roi': box,
    'zoom': run['zoom'],
    'metrics': metrics,
    'edgeEnergyIncreasePercent': 100 * (
        metrics['after']['edgeEnergy'] / metrics['before']['edgeEnergy'] - 1),
    'progressiveBlurReproducedBeforeFix': False,
    'scope': 'Um trecho sintético em Times-Italic, Windows, mesmo zoom/viewport; '
             'não substitui inspeção do livro/monitor do usuário.',
}
path = reports / 'windows-sharpness-comparison.json'
path.write_text(json.dumps(result, indent=2, ensure_ascii=False), encoding='utf-8')
print(path)
print(json.dumps(result, indent=2, ensure_ascii=False))
