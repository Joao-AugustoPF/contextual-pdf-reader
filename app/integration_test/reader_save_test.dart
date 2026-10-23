import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pdf_document/pdf_document.dart' as pdf;
import 'package:pdfrx/pdfrx.dart';
import 'package:contextual_pdf_reader/app/services.dart';
import 'package:contextual_pdf_reader/core/inference/model_store.dart';
import 'package:contextual_pdf_reader/core/nlp/pipeline.dart';
import 'package:contextual_pdf_reader/core/persistence/database.dart';
import 'package:contextual_pdf_reader/features/reader/reader_screen.dart';
import 'package:contextual_pdf_reader/main.dart';

import 'support/unused_engine.dart';

Future<void> _until(WidgetTester tester, bool Function() ready) async {
  for (var i = 0; i < 400; i++) {
    if (ready()) return;
    await tester.pump(const Duration(milliseconds: 100));
  }
  throw StateError('Timeout aguardando salvar PDF');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Windows: Salvar/Ctrl+S no original, editar, reabrir e remover', (
    tester,
  ) async {
    pdfrxFlutterInitialize();
    final temp = await Directory.systemTemp.createTemp('reader-save-ui-');
    final db = ReaderDatabase.memory();
    final engine = UnusedEngine();
    final services = AppServices(
      temp,
      db,
      ModelStore(Directory('${temp.path}/models'), {}),
      engine,
      engine,
      TranslationOrchestrator(engine, engine, {}),
    );
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
    await _until(
      tester,
      () => find.text('Experimentar com um PDF').evaluate().isNotEmpty,
    );
    await tester.tap(find.text('Experimentar com um PDF'));
    await _until(tester, () => find.byType(ReaderScreen).evaluate().isNotEmpty);
    var state = tester.state<ReaderScreenState>(find.byType(ReaderScreen));
    await _until(
      tester,
      () => state.document != null && state.controller.isReady,
    );
    await tester.pump(const Duration(seconds: 1));
    final original = File('${temp.path}/exemplo.pdf');
    final initialBytes = await original.readAsBytes();
    final id = state.widget.documentId;
    expect(
      (await db.document(id))!['source_path'],
      await original.resolveSymbolicLinks(),
    );
    final text = await state.document!.pages.first.loadStructuredText();
    const word = 'programming';
    final start = text.fullText.indexOf(word);
    await state.controller.textSelectionDelegate.setTextSelectionPointRange(
      PdfTextSelectionRange.fromPoints(
        PdfTextSelectionPoint(text, start),
        PdfTextSelectionPoint(text, start + word.length - 1),
      ),
    );
    await _until(tester, () => state.selection?.text == word);
    await tester.tap(find.text('Marcar'));
    await _until(tester, () => state.annotations.length == 1);

    Future<void> openDetails() async {
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Anotações'));
      await tester.pumpAndSettle();
      await tester.tap(find.byType(ListTile).first);
      await tester.pumpAndSettle();
    }

    Future<void> edit(String label) async {
      await openDetails();
      await tester.tap(find.text('Editar anotação'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), label);
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Salvar'),
        ),
      );
      await _until(
        tester,
        () =>
            state.annotations.single['shortTranslation'] == label &&
            find.byType(BottomSheet).evaluate().isEmpty,
      );
      await tester.pumpAndSettle();
    }

    await edit('programação');
    await state.controller.textSelectionDelegate.clearTextSelection();
    await tester.pump(const Duration(milliseconds: 400));
    final zoom = state.controller.currentZoom;
    final viewerDocument = state.document;
    final timer = Stopwatch()..start();
    await tester.tap(find.text('Salvar'));
    await _until(tester, () => !state.busy);
    final saveMs = timer.elapsedMicroseconds / 1000;
    final firstBytes = await original.readAsBytes();
    expect(firstBytes, isNot(initialBytes));
    final saved = pdf.PdfDocument.open(firstBytes);
    expect(saved.page(0).annotations, hasLength(2));
    expect(
      saved.page(0).annotations.map((a) => a.contents),
      contains('programação'),
    );
    expect(state.document, same(viewerDocument));
    expect(state.controller.currentZoom, closeTo(zoom, 0.001));
    await tester.tap(find.text('Salvar'));
    await _until(tester, () => !state.busy);
    expect(await original.readAsBytes(), firstBytes);
    await edit('programação revisada');
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await _until(tester, () => !state.busy);
    final editedBytes = await original.readAsBytes();
    final edited = pdf.PdfDocument.open(editedBytes);
    expect(edited.page(0).annotations, hasLength(2));
    expect(
      edited.page(0).annotations.map((a) => a.contents),
      contains('programação revisada'),
    );
    final reports = Directory(
      const String.fromEnvironment(
        'TEST_REPORT_DIR',
        defaultValue: '../reports',
      ),
    );
    await reports.create(recursive: true);
    await File('${reports.path}/windows-save-original.pdf')
        .writeAsBytes(editedBytes);
    await tester.pump(const Duration(milliseconds: 500));
    final boundary =
        boundaryKey.currentContext!.findRenderObject()!
            as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 1);
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    await File('${reports.path}/windows-save-original.png')
        .writeAsBytes(png!.buffer.asUint8List());
    image.dispose();

    await tester.tap(find.byTooltip('Voltar'));
    await tester.pumpAndSettle();
    await _until(tester, () => find.byType(ReaderScreen).evaluate().isEmpty);
    await _until(
      tester,
      () => find.text('Biblioteca recente').evaluate().isNotEmpty,
    );
    await _until(
      tester,
      () => find.widgetWithText(ListTile, 'exemplo.pdf').evaluate().isNotEmpty,
    );
    await tester.tap(find.widgetWithText(ListTile, 'exemplo.pdf'));
    await tester.pumpAndSettle();
    await _until(tester, () => find.byType(ReaderScreen).evaluate().isNotEmpty);
    final previousState = state;
    state = tester.state<ReaderScreenState>(find.byType(ReaderScreen));
    expect(state, isNot(same(previousState)));
    await _until(
      tester,
      () =>
          state.document != null &&
          state.controller.isReady &&
          state.annotations.length == 1,
    );
    expect(state.widget.documentId, id);
    expect(await db.documents(), hasLength(1));
    expect(
      state.annotations.single['shortTranslation'],
      'programação revisada',
    );
    // Sem anotações nativas duplicadas por baixo dos overlays editáveis.
    final working = pdf.PdfDocument.open(
      await File(state.widget.path).readAsBytes(),
    );
    expect(working.page(0).annotations, isEmpty);

    Future<void> selectWord(String word, {bool partial = false}) async {
      final pageText = await state.document!.pages.first.loadStructuredText();
      final offset = pageText.fullText.indexOf(word);
      expect(offset, greaterThanOrEqualTo(0));
      await state.controller.textSelectionDelegate.setTextSelectionPointRange(
        PdfTextSelectionRange.fromPoints(
          PdfTextSelectionPoint(pageText, partial ? offset + 2 : offset),
          PdfTextSelectionPoint(
            pageText,
            partial ? offset + 4 : offset + word.length - 1,
          ),
        ),
      );
      await _until(tester, () => state.selection != null);
      await tester.pumpAndSettle();
    }

    // Selecionar só parte do trecho também permite apagar a marcação inteira.
    await selectWord(word, partial: true);
    await tester.tap(find.text('Remover marcação'));
    await _until(
      tester,
      () => state.annotations.isEmpty && !state.busy && state.selection == null,
    );
    expect(await db.annotations(id), isEmpty);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Desfazer'));
    await _until(tester, () => state.annotations.length == 1);
    expect(
      (await db.annotations(id)).single['shortTranslation'],
      'programação revisada',
    );

    // Uma segunda marcação fora da seleção deve permanecer no PDF.
    await selectWord('light');
    await tester.tap(find.text('Marcar'));
    await _until(tester, () => state.annotations.length == 2);
    await state.controller.textSelectionDelegate.clearTextSelection();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Salvar'));
    await _until(tester, () => !state.busy);
    expect(
      pdf.PdfDocument.open(await original.readAsBytes()).page(0).annotations,
      hasLength(3),
    );
    await selectWord(word);
    await tester.tap(find.text('Remover marcação'));
    await _until(tester, () => state.annotations.length == 1 && !state.busy);
    expect(state.annotations.single['selectedText'], 'light');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Salvar'));
    await _until(tester, () => !state.busy);
    expect(
      pdf.PdfDocument.open(await original.readAsBytes())
          .page(0)
          .annotations
          .single
          .subtype,
      'Highlight',
    );

    // Remoção direta pela lixeira da lista, sem precisar selecionar o texto.
    await tester.tap(find.byTooltip('Anotações'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Remover marcação'));
    await _until(
      tester,
      () =>
          state.annotations.isEmpty &&
          !state.busy &&
          find.byType(BottomSheet).evaluate().isEmpty,
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Salvar'));
    await _until(tester, () => !state.busy);
    expect(
      pdf.PdfDocument.open(await original.readAsBytes()).page(0).annotations,
      isEmpty,
    );
    expect(
      temp.listSync().whereType<File>().where((f) => f.path.endsWith('.pdf')),
      hasLength(1),
    );
    await File('${reports.path}/windows-save-original.json').writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'platform': Platform.operatingSystem,
        'firstSaveMs': saveMs,
        'initialBytes': initialBytes.length,
        'firstSaveBytes': firstBytes.length,
        'editedBytes': editedBytes.length,
        'unchangedSaveBytesIdentical': true,
        'annotationsAfterSave': 2,
        'annotationsAfterEditing': 2,
        'annotationsAfterDeletingAndSaving': 0,
        'partialSelectionRemoval': true,
        'undoRestoredTranslationAndDatabase': true,
        'unrelatedHighlightPreserved': true,
        'removedDirectlyFromAnnotationList': true,
        'ctrlSUpdatedOriginal': true,
        'viewerAndZoomPreserved': true,
        'documentIdentityPreservedOnReopen': true,
        'annotationsInWorkingBaseAfterReopen': 0,
        'pdfFilesInUserFolder': 1,
        'userDocumentsOrDatabaseUsed': false,
        'modelsInvoked': false,
      }),
    );
  });
}
