import 'dart:io';
import 'dart:typed_data';

import 'package:pdf_document/pdf_document.dart' as pdf;

import '../../core/pdf_coordinates/geometry.dart';
import 'highlight_style.dart';

String _ownerPrefix(String ownerId) => 'entrelinhas/$ownerId/';

bool _removeManaged(
  pdf.PdfDocument document,
  pdf.PdfEditor editor,
  String ownerId,
) {
  var changed = false;
  for (var page = 0; page < document.pageCount; page++) {
    final managed = document
        .page(page)
        .annotations
        .where((a) => a.name?.startsWith(_ownerPrefix(ownerId)) ?? false)
        .toList();
    if (managed.isNotEmpty) {
      editor.removeAnnotations(page, managed);
      changed = true;
    }
  }
  return changed;
}

/// A visualização usa uma base sem nossos overlays já gravados no original.
/// Anotações de outros leitores/documentos continuam na página.
Uint8List withoutManagedAnnotations(Uint8List bytes, String ownerId) {
  final document = pdf.PdfDocument.open(bytes);
  final editor = pdf.PdfEditor(document);
  return _removeManaged(document, editor, ownerId) ? editor.save() : bytes;
}

Uint8List exportAnnotated(
  Uint8List original,
  List<Map<String, dynamic>> annotations, {
  Uint8List? attributionImage,
  String ownerId = 'export',
}) {
  final document = pdf.PdfDocument.open(original);
  final editor = pdf.PdfEditor(document);
  _removeManaged(document, editor, ownerId);
  final prefix = _ownerPrefix(ownerId);
  for (final a in annotations) {
    final page = (a['pageNumber'] as int) - 1;
    final boxes = [for (final q in a['quadPointsPdf']) Box.fromJson(q)];
    editor.addHighlight(
      page,
      [for (final b in boxes) pdf.PdfRect(b.l, b.b, b.r, b.t)],
      color: (a['color'] as int) & 0xffffff,
      opacity: annotationHighlightOpacity,
      name: '$prefix${a['id']}',
    );
    final text = a['shortTranslation'] as String?;
    if (text == null || text.isEmpty) continue;
    final label = Box.fromJson(a['labelBox']);
    final anchored = (a['labelLayoutVersion'] as int? ?? 0) >= 3;
    // pdf_document reserva 3 pt de padding no FreeText. Compensar no retângulo
    // mantém a tinta na caixa compacta exibida sobre a palavra, sem cortá-la.
    final inset = anchored ? 3.0 : 0.0;
    editor.addFreeText(
      page,
      pdf.PdfRect(
        label.l - inset,
        label.b - inset,
        label.r + inset,
        label.t + inset,
      ),
      text,
      color: 0xc62828,
      fontSize: (a['labelFontSize'] as num?)?.toDouble() ?? 8,
      borderWidth: 0,
      align: anchored ? pdf.PdfTextAlign.center : null,
      name: '$prefix${a['id']}-translation',
    );
  }
  if (attributionImage != null) {
    final image = pdf.PdfEmbeddableImage.decode(attributionImage);
    final pages = annotations
        .where(
          (a) =>
              a['shortTranslation'] != null &&
              (a['engineId'] as String? ?? '').startsWith('google-mlkit'),
        )
        .map((a) => (a['pageNumber'] as int) - 1)
        .toSet();
    for (final page in pages) {
      final bounds = document.page(page).cropBox;
      const width = 115.0;
      final height = width * image.height / image.width;
      editor.addImageStamp(
        page,
        pdf.PdfRect(
          bounds.right - width - 8,
          bounds.bottom + 4,
          bounds.right - 8,
          bounds.bottom + 4 + height,
        ),
        image,
        name: '${prefix}google-translate-attribution-$page',
      );
    }
  }
  return editor.save();
}

Future<void> exportCopy(
  String input,
  String output,
  List<Map<String, dynamic>> annotations, {
  Uint8List? attributionImage,
  String ownerId = 'export',
}) async {
  if (File(input).absolute.path.toLowerCase() ==
      File(output).absolute.path.toLowerCase()) {
    throw ArgumentError('Escolha uma cópia; o original é preservado');
  }
  final bytes = exportAnnotated(
    await File(input).readAsBytes(),
    annotations,
    attributionImage: attributionImage,
    ownerId: ownerId,
  );
  await File(output).writeAsBytes(bytes, flush: true);
}
