from pathlib import Path
from reportlab.pdfgen import canvas
from reportlab.lib.pagesizes import A4
ROOT=Path(__file__).resolve().parents[1]
p=ROOT/'app/assets/sample.pdf'
c=canvas.Canvas(str(p),pagesize=A4)
c.setTitle('Leitura contextual - documento de teste')
c.bookmarkPage('start');c.addOutlineEntry('Experimente o leitor','start',0)
c.setFont('Helvetica-Bold',22);c.drawString(48,785,'Leitura contextual')
c.setFont('Helvetica',11);c.drawString(48,760,'PDF local de teste. Selecione uma palavra e use Marcar e traduzir.')
lines=['I decided to give up programming.', 'Turn on the light.', 'This framework is light and fast.',
       'The fisherman sat on the river bank.', 'She deposited cash at the bank.',
       'Use a lock to protect the shared resource.', 'The door lock is broken.',
       'Please look the number up online.', 'Each thread has its own stack.',
       'The software works out of the box.', 'Their safety is at stake here.']
c.setFont('Helvetica',14)
for i,line in enumerate(lines):c.drawString(48,710-i*46,line)
c.showPage();c.bookmarkPage('second');c.addOutlineEntry('Segunda pagina','second',0)
c.setFont('Helvetica',14)
c.drawString(48,760,'We can set up a local database.')
c.drawString(48,720,'A bat flew out of the cave.')
c.drawString(48,680,'The baseball player swung his bat.')
c.save();print(p)
