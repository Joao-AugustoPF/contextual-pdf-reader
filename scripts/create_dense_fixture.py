"""PDF sintético com entrelinhas estreitas, sem usar o documento do usuário."""
from pathlib import Path
from reportlab.pdfgen import canvas

root = Path(__file__).resolve().parents[1]
path = root / 'reports' / 'dense-reader-fixture.pdf'
path.parent.mkdir(exist_ok=True)
c = canvas.Canvas(str(path), pagesize=(612, 792))
c.setTitle('Teste de significado junto da seleção')
c.setFont('Helvetica-Bold', 20)
c.drawString(55, 735, 'Significado junto da palavra')
c.setFont('Times-Roman', 12)
for y, line in [
    (184, 'Small changes can spread through a system and affect other parts.'),
    (168, 'Because everything is coupled to everything else, changes tend to'),
    (152, 'have hard-to-predict rippling side effects throughout the system.'),
    (136, 'The next line leaves little space for a translation above the word.'),
    (120, 'A nearby margin is preferable to hiding the label at the page top.'),
]:
    c.drawString(55, y, line)
c.save()
print(path)
