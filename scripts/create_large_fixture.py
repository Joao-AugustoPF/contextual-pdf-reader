"""PDF sintético de 1.001 páginas; textos autorais e fonte base-14."""
from pathlib import Path
from reportlab.pdfgen import canvas
ROOT=Path(__file__).resolve().parents[1]
p=ROOT/'app/assets/sample-large.pdf'
c=canvas.Canvas(str(p),pagesize=(600,800),pageCompression=1)
for i in range(1001):
    if i<1000:
        c.setFont('Helvetica',14)
        c.drawString(48,720,f'Page {i+1}: I decided to give up programming.')
        c.drawString(48,680,'This framework is light and fast.')
        if i==0:
            for line in range(10):c.drawString(48,640-line*24,'word word word word word word')
    c.showPage()
c.save();print(p.stat().st_size)
