import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:contextual_pdf_reader/app/services.dart';
import 'package:contextual_pdf_reader/core/inference/model_store.dart';
import 'package:contextual_pdf_reader/core/nlp/pipeline.dart';
import 'package:contextual_pdf_reader/core/persistence/database.dart';
import 'package:contextual_pdf_reader/features/library/document_files.dart';
import 'package:contextual_pdf_reader/features/library/library_screen.dart';
import 'package:contextual_pdf_reader/features/reader/reader_screen.dart';
import 'package:contextual_pdf_reader/main.dart';

import 'support/unused_engine.dart';

Future<void> _until(WidgetTester tester, bool Function() ready) async {
  for (var i = 0; i < 400; i++) {
    if (ready()) return;
    await tester.pump(const Duration(milliseconds: 100));
  }
  throw StateError('Timeout aguardando renderização');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Windows: nitidez estável durante marcações, zoom e salvamentos', (
    tester,
  ) async {
    pdfrxFlutterInitialize();
    final root = Directory(const String.fromEnvironment('TEST_PROJECT_ROOT'));
    final reports = Directory(const String.fromEnvironment('TEST_REPORT_DIR'));
    const stage = String.fromEnvironment(
      'SHARPNESS_STAGE',
      defaultValue: 'after',
    );
    final temp = await Directory.systemTemp.createTemp('reader-sharpness-');
    final original = await File(
      '${root.path}/reports/rendering-reader-fixture.pdf',
    ).copy('${temp.path}/livro.pdf');
    final db = ReaderDatabase.memory();
    final engine = UnusedEngine();
    final appDir = Directory('${temp.path}/app');
    final services = AppServices(
      appDir,
      db,
      ModelStore(Directory('${temp.path}/models'), {}),
      engine,
      engine,
      TranslationOrchestrator(engine, engine, {}),
    );
    final files = DocumentFiles(appDir, db);
    final book = await files.open(original.path);
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
      await db.close();
      await temp.delete(recursive: true);
    });
    final boundaryKey = GlobalKey();
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundaryKey,
        child: ProviderScope(
          overrides: [servicesProvider.overrideWithValue(services)],
          child: const ReaderApp(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    unawaited(
      Navigator.of(tester.element(find.byType(LibraryScreen))).push(
        MaterialPageRoute<void>(
          builder: (_) => ReaderScreen(
            documentId: book['id'],
            path: book['path'],
            title: book['title'],
          ),
        ),
      ),
    );
    await _until(tester, () => find.byType(ReaderScreen).evaluate().isNotEmpty);
    final state = tester.state<ReaderScreenState>(find.byType(ReaderScreen));
    await _until(
      tester,
      () => state.controller.isReady && state.document != null,
    );
    final page = state.document!.pages.first;
    final text = await page.loadStructuredText();
    final start = text.fullText.indexOf('architecture');
    final range = PdfPageTextRange(
      pageText: text,
      start: start,
      end: start + 12,
    );
    await state.saveSelection(
      manual: 'arquitetura',
      range: range,
      notify: false,
    );
    await tester.pumpAndSettle();
    final matrix = state.controller.value.clone();
    final zoom = state.controller.currentZoom;
    final baseBytes = await File(book['path']).readAsBytes();
    final unmarked =
        PdfPageTextRange(
              pageText: text,
              start: text.fullText.indexOf(
                'stays sharp',
                text.fullText.indexOf('Line 02:'),
              ),
              end: text.fullText.indexOf('Line 03:') - 1,
            )
            .enumerateFragmentBoundingRects()
            .map(
              (f) => f.bounds.toRectInDocument(
                page: page,
                pageRect: state.controller.layout.pageLayouts.first,
              ),
            )
            .reduce((a, b) => a.expandToInclude(b));
    final roi = Rect.fromPoints(
      state.controller.documentToGlobal(unmarked.topLeft)!,
      state.controller.documentToGlobal(unmarked.bottomRight)!,
    ).inflate(2);
    Future<ui.Image> capture(String name) async {
      // Esperar também o trabalho nativo: pumpAndSettle não aguarda o PDFium.
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      final image =
          await (boundaryKey.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary)
              .toImage(pixelRatio: 1);
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      await File('${reports.path}/windows-sharpness-$stage-$name.png')
          .writeAsBytes(png!.buffer.asUint8List());
      return image;
    }

    final first = await capture('initial');
    for (var i = 0; i < 24; i++) {
      // Doze notas distintas, com edição e gravação repetidas.
      final wordStart = text.fullText.indexOf(
        'architecture',
        text.fullText.indexOf('Line ${(i % 12).toString().padLeft(2, '0')}:'),
      );
      await state.saveSelection(
        manual: 'arquitetura $i',
        range: PdfPageTextRange(
          pageText: text,
          start: wordStart,
          end: wordStart + 12,
        ),
        notify: false,
      );
      await tester.pump();
      await files.save(book['id'], state.annotations);
      if (i % 4 == 0) {
        await state.controller.setZoom(
          state.controller.centerPosition,
          zoom * 2.5,
          duration: Duration.zero,
        );
        await tester.pump(const Duration(milliseconds: 100));
        await state.controller.goToPage(pageNumber: 5, duration: Duration.zero);
        await tester.pump(const Duration(milliseconds: 100));
        await state.controller.goTo(matrix.clone(), duration: Duration.zero);
      }
    }
    await state.controller.goTo(matrix.clone(), duration: Duration.zero);
    await tester.pumpAndSettle();
    expect(state.controller.currentZoom, closeTo(zoom, 0.000001));
    final last = await capture('repeated');
    final a = (await first.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    final b = (await last.toByteData(format: ui.ImageByteFormat.rawRgba))!;
    var pixels = 0, changed = 0, delta = 0, darkBefore = 0, darkAfter = 0;
    for (var y = roi.top.ceil(); y < roi.bottom.floor(); y++) {
      for (var x = roi.left.ceil(); x < roi.right.floor(); x++) {
        final index = (y * first.width + x) * 4;
        final before = a.getUint8(index), after = b.getUint8(index);
        pixels++;
        delta += (before - after).abs();
        if (before != after) changed++;
        if (before < 64) darkBefore++;
        if (after < 64) darkAfter++;
      }
    }
    expect(darkBefore, greaterThan(20));
    expect(
      delta / pixels,
      lessThan(1),
      reason: 'O texto intacto não pode borrar',
    );
    expect(darkAfter / darkBefore, greaterThan(0.98));
    expect(
      sha256.convert(await File(book['path']).readAsBytes()),
      sha256.convert(baseBytes),
    );
    // A página salva deve renderizar o texto intacto de forma idêntica à base.
    final saved = await PdfDocument.openFile(original.path);
    final beforeRender = await page.render(
      fullWidth: 1224,
      fullHeight: 1584,
      annotationRenderingMode: PdfAnnotationRenderingMode.none,
    );
    final afterRender = await saved.pages.first.render(
      fullWidth: 1224,
      fullHeight: 1584,
      annotationRenderingMode: PdfAnnotationRenderingMode.none,
    );
    final beforeHash = sha256.convert(beforeRender!.pixels).toString();
    final afterHash = sha256.convert(afterRender!.pixels).toString();
    expect(
      afterHash,
      beforeHash,
      reason: 'Salvar não pode rasterizar ou alterar o texto',
    );
    expect(
      (await saved.pages.first.loadStructuredText()).fullText,
      text.fullText,
    );
    await saved.dispose();
    beforeRender.dispose();
    afterRender.dispose();
    await File('${reports.path}/windows-sharpness-$stage.json').writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'stage': stage,
        'annotationAndSaveCycles': 24,
        'zoomAndNavigationCycles': 6,
        'zoom': zoom,
        'annotations': state.annotations.length,
        'roi': [roi.left, roi.top, roi.right, roi.bottom],
        'comparedPixels': pixels,
        'changedPixels': changed,
        'meanAbsoluteDifference': delta / pixels,
        'darkPixelsBefore': darkBefore,
        'darkPixelsAfter': darkAfter,
        'pdfBaseRenderSha256': beforeHash,
        'pdfSavedRenderSha256': afterHash,
        'originalTextPreserved': true,
        'workingPdfUnchanged': true,
        'personalDocumentsUsed': false,
      }),
    );
    first.dispose();
    last.dispose();
  });
}
