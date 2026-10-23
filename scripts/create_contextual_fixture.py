"""Caso de regressão vetorial, sem ler ou modificar o PDF pessoal."""
from pathlib import Path
import textwrap
from reportlab.pdfgen import canvas

root = Path(__file__).resolve().parents[1]
path = root / 'reports' / 'contextual-reader-fixture.pdf'
text = ('Because components often nest within one another, each component in the '
        'domain-partitioned architecture shown in Figure 9-3 (for example, CatalogCheckout) '
        'may use a persistence library and have a separate layer for business rules, '
        'but the top-level partitioning will still revolve around domains.')
c = canvas.Canvas(str(path), pagesize=(612, 792))
c.setFont('Helvetica-Bold', 18)
c.drawString(50, 740, 'Teste contextual.')
c.setFont('Times-Roman', 12)
for index, line in enumerate(textwrap.wrap(text, 85)):
    c.drawString(50, 690 - index * 24, line)
c.drawString(50, 460, 'The bird built a nest in the tree.')
c.save()
print(path)
