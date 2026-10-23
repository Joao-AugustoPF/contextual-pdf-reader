import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pdf_document/pdf_document.dart' as pdf;
import 'package:pdfrx/pdfrx.dart';
import 'package:contextual_pdf_reader/app/services.dart';
import 'package:contextual_pdf_reader/core/inference/model_store.dart';
import 'package:contextual_pdf_reader/core/nlp/pipeline.dart';
import 'package:contextual_pdf_reader/core/pdf_coordinates/geometry.dart';
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
  throw StateError('Timeout aguardando significado');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Windows: significado visível, migração de margem, edição sem modelo e PDF',
    (tester) async {
      pdfrxFlutterInitialize();
      final root = Directory(
        const String.fromEnvironment('TEST_PROJECT_ROOT', defaultValue: '..'),
      ).absolute;
      final reports = Directory(
        const String.fromEnvironment(
          'TEST_REPORT_DIR',
          defaultValue: '../reports',
        ),
      );
      final temp = await Directory.systemTemp.createTemp('reader-meaning-');
      final original = await File(
        '${root.path}/reports/dense-reader-fixture.pdf',
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
      final seedDoc = await PdfDocument.openFile(book['path']);
      final seedText = await seedDoc.pages.first.loadStructuredText();
      final start = seedText.fullText.indexOf('rippling');
      expect(start, greaterThanOrEqualTo(0));
      final range = PdfPageTextRange(
        pageText: seedText,
        start: start,
        end: start + 8,
      );
      final quads = [
        for (final f in range.enumerateFragmentBoundingRects())
          Box(
            f.bounds.left,
            f.bounds.bottom,
            f.bounds.right,
            f.bounds.top,
          ).toJson(),
      ];
      await db.saveAnnotation({
        'id': 'legacy-rippling',
        'documentId': book['id'],
        'pageNumber': 1,
        'charRange': [start, start + 8],
        'selectedText': 'rippling',
        'shortTranslation': 'Ondulação',
        'quadPointsPdf': quads,
        'color': 0xffffd54f,
        'labelBox': [4.0, 762.0, 55.2, 774.0],
        'labelFontSize': 8.0,
        'marginNote': true,
        'manualOverride': true,
        'source': 'editada',
      });
      await seedDoc.dispose();
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
      void open(Map<String, dynamic> data) {
        unawaited(
          Navigator.of(tester.element(find.byType(LibraryScreen))).push(
            MaterialPageRoute<void>(
              builder: (_) => ReaderScreen(
                documentId: data['id'],
                path: data['path'],
                title: data['title'],
              ),
            ),
          ),
        );
      }

      open(book);
      await _until(
        tester,
        () => find.byType(ReaderScreen).evaluate().isNotEmpty,
      );
      var state = tester.state<ReaderScreenState>(find.byType(ReaderScreen));
      await _until(
        tester,
        () =>
            state.controller.isReady &&
            state.annotations.isNotEmpty &&
            state.annotations.single['labelLayoutVersion'] ==
                labelLayoutVersion,
      );
      await tester.pumpAndSettle();
      final migrated = Map<String, dynamic>.from(state.annotations.single);
      final target = Box.fromJson(quads.first);
      final nearby = Box.fromJson(migrated['labelBox']);
      expect((nearby.b - target.t).abs(), lessThan(32));
      expect(
        (nearby.l + nearby.r) / 2,
        closeTo((target.l + target.r) / 2, 0.01),
      );
      expect(nearby.b, greaterThan(target.t));
      expect(migrated['marginNote'], false);
      expect(migrated['shortTranslation'], 'Ondulação');
      expect(find.text('Ondulação'), findsOneWidget);
      final actualText = await state.document!.pages.first.loadStructuredText();
      expect(
        actualText.fragments.any(
          (f) => nearby.overlaps(
            Box(f.bounds.left, f.bounds.bottom, f.bounds.right, f.bounds.top),
          ),
        ),
        false,
      );

      await state.controller.textSelectionDelegate.setTextSelectionPointRange(
        PdfTextSelectionRange.fromPoints(
          PdfTextSelectionPoint(actualText, start),
          PdfTextSelectionPoint(actualText, start + 7),
        ),
      );
      await _until(tester, () => state.selection?.text == 'rippling');
      await tester.tap(find.text('Escrever significado'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'Ondulação',
      );
      await tester.enterText(find.byType(TextField), '   ');
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Salvar'),
        ),
      );
      await tester.pump();
      expect(
        find.text('Digite um significado antes de salvar.'),
        findsOneWidget,
      );
      expect(state.annotations.single['shortTranslation'], 'Ondulação');
      await tester.tap(find.byType(TextField));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'em cascata');
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'em cascata',
      );
      final beforeSave =
          await (boundaryKey.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary)
              .toImage(pixelRatio: 1);
      final beforeSavePng = await beforeSave.toByteData(
        format: ui.ImageByteFormat.png,
      );
      await File('${reports.path}/windows-meaning-editor.png')
          .writeAsBytes(beforeSavePng!.buffer.asUint8List());
      beforeSave.dispose();
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Salvar'),
        ),
      );
      await tester.pump(const Duration(milliseconds: 500));
      debugPrint(
        'Significado após Salvar: ${jsonEncode({'translation': state.annotations.single['shortTranslation'], 'selection': state.selection?.text, 'dialogs': find.byType(AlertDialog).evaluate().length})}',
      );
      await _until(
        tester,
        () =>
            state.annotations.single['shortTranslation'] == 'em cascata' &&
            find.byType(AlertDialog).evaluate().isEmpty &&
            state.selection == null,
      );
      await tester.pumpAndSettle();
      expect(find.text('em cascata'), findsOneWidget);
      final edited = state.annotations.single;
      expect(edited['manualOverride'], true);
      final label = Box.fromJson(edited['labelBox']);
      expect((label.b - target.t).abs(), lessThan(32));
      expect((label.l + label.r) / 2, closeTo((target.l + target.r) / 2, 0.01));
      expect(label.b, greaterThan(target.t));
      expect(edited['marginNote'], false);
      final docRect = PdfRect(label.l, label.t, label.r, label.b)
          .toRectInDocument(
            page: state.document!.pages.first,
            pageRect: state.controller.layout.pageLayouts.first,
          );
      final topLeft = state.controller.documentToGlobal(docRect.topLeft)!;
      final bottomRight = state.controller.documentToGlobal(
        docRect.bottomRight,
      )!;
      final boundary =
          boundaryKey.currentContext!.findRenderObject()!
              as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 1);
      final rgba = (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!;
      var redPixels = 0;
      for (
        var y = topLeft.dy.floor().clamp(0, image.height - 1);
        y < bottomRight.dy.ceil().clamp(0, image.height);
        y++
      ) {
        for (
          var x = topLeft.dx.floor().clamp(0, image.width - 1);
          x < bottomRight.dx.ceil().clamp(0, image.width);
          x++
        ) {
          final i = (y * image.width + x) * 4;
          if (rgba.getUint8(i) > 120 &&
              rgba.getUint8(i + 1) < 110 &&
              rgba.getUint8(i + 2) < 110) {
            redPixels++;
          }
        }
      }
      expect(
        redPixels,
        greaterThan(10),
        reason: 'O significado vermelho precisa aparecer na tela',
      );
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      await File('${reports.path}/windows-word-meaning.png')
          .writeAsBytes(png!.buffer.asUint8List());
      image.dispose();
      await tester.tap(find.text('Salvar'));
      await _until(tester, () => !state.busy);
      final bytes = await original.readAsBytes();
      final savedPdf = pdf.PdfDocument.open(bytes);
      expect(savedPdf.page(0).annotations, hasLength(2));
      expect(
        savedPdf.page(0).annotations.map((a) => a.contents),
        contains('em cascata'),
      );
      await File('${reports.path}/windows-word-meaning.pdf')
          .writeAsBytes(bytes);
      await tester.tap(find.byTooltip('Voltar'));
      await tester.pumpAndSettle();
      await _until(tester, () => find.byType(ReaderScreen).evaluate().isEmpty);
      open(await files.open(original.path));
      await tester.pumpAndSettle();
      state = tester.state<ReaderScreenState>(find.byType(ReaderScreen));
      await _until(
        tester,
        () => state.annotations.isNotEmpty && state.controller.isReady,
      );
      expect(state.annotations.single['shortTranslation'], 'em cascata');
      expect(state.annotations.single['labelBox'], edited['labelBox']);
      await File('${reports.path}/windows-word-meaning.json').writeAsString(
        const JsonEncoder.withIndent('  ').convert({
          'legacyLabelBox': [4, 762, 55.2, 774],
          'migratedLabelBox': migrated['labelBox'],
          'targetBox': target.toJson(),
          'finalMeaning': 'em cascata',
          'finalLabelBox': label.toJson(),
          'distanceFromWordTopPoints': (label.b - target.t).abs(),
          'horizontalCenterDifferencePoints':
              ((label.l + label.r - target.l - target.r) / 2).abs(),
          'directlyAboveWord': true,
          'visibleRedPixels': redPixels,
          'emptyMeaningRejected': true,
          'originalPdfContainsMeaning': true,
          'preservedOnReopen': true,
          'modelsInstalledOrInvoked': false,
          'personalDocumentsUsedForTest': false,
        }),
      );
    },
  );
}
