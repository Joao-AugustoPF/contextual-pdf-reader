"""PDF vetorial sintético para verificar nitidez, sem documentos pessoais."""
from pathlib import Path
from reportlab.pdfgen import canvas

root = Path(__file__).resolve().parents[1]
path = root / 'reports' / 'rendering-reader-fixture.pdf'
path.parent.mkdir(exist_ok=True)
c = canvas.Canvas(str(path), pagesize=(612, 792))
c.setTitle('Nitidez durante uso repetido')
for page in range(1, 7):
    c.setFont('Helvetica-Bold', 18)
    c.drawString(55, 735, f'Nitidez do leitor - pagina {page}')
    c.setFont('Times-Italic', 12)
    for i in range(12):
        c.drawString(55, 690 - i * 22,
                     f'Line {i:02d}: italic architecture stays sharp during repeated reading.')
    c.setFont('Times-Roman', 12)
    for i in range(7):
        c.drawString(55, 390 - i * 22,
                     f'Body {i:02d}: original text remains selectable after saving annotations.')
    c.showPage()
c.save()
print(path)
