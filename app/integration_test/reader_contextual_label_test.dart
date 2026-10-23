import 'dart:async';
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
import 'package:contextual_pdf_reader/core/inference/sidecar.dart';
import 'package:contextual_pdf_reader/core/nlp/pipeline.dart';
import 'package:contextual_pdf_reader/core/persistence/database.dart';
import 'package:contextual_pdf_reader/features/library/document_files.dart';
import 'package:contextual_pdf_reader/features/library/library_screen.dart';
import 'package:contextual_pdf_reader/features/reader/reader_screen.dart';
import 'package:contextual_pdf_reader/main.dart';

Future<void> _until(WidgetTester tester, bool Function() ready) async {
  for (var i = 0; i < 800; i++) {
    if (ready()) return;
    await tester.pump(const Duration(milliseconds: 100));
  }
  throw StateError('Timeout aguardando rótulo contextual');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Windows: nest verbo e substantivo, rótulo contextual e PDF original',
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
      final temp = await Directory.systemTemp.createTemp(
        'reader-contextual-label-',
      );
      final original = await File(
        '${root.path}/reports/contextual-reader-fixture.pdf',
      ).copy('${temp.path}/livro.pdf');
      final db = ReaderDatabase.memory();
      final engine = SidecarEngine(
        '${root.path}/app/build/windows/x64/runner/Release/runtime/reader-runtime.exe',
        [
          '--models',
          '${root.path}/models',
          '--manifest',
          '${root.path}/ml/manifests/models.lock.json',
        ],
      );
      final lexicon = jsonDecode(
        await rootBundle.loadString('assets/lexicon.json'),
      ) as Map<String, dynamic>;
      final appDir = Directory('${temp.path}/app');
      final services = AppServices(
        appDir,
        db,
        ModelStore(Directory('${root.path}/models'), {}),
        engine,
        engine,
        TranslationOrchestrator(engine, engine, lexicon),
      );
      final files = DocumentFiles(appDir, db);
      final book = await files.open(original.path);
      addTearDown(() async {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump(const Duration(seconds: 1));
        await engine.dispose();
        await db.close();
        await temp.delete(recursive: true);
      });
      final key = GlobalKey();
      await tester.pumpWidget(
        RepaintBoundary(
          key: key,
          child: ProviderScope(
            overrides: [servicesProvider.overrideWithValue(services)],
            child: const ReaderApp(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      void open(Map<String, dynamic> data) => unawaited(
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
      open(book);
      await _until(
        tester,
        () => find.byType(ReaderScreen).evaluate().isNotEmpty,
      );
      var state = tester.state<ReaderScreenState>(find.byType(ReaderScreen));
      await _until(
        tester,
        () => state.controller.isReady && state.document != null,
      );
      await tester.tap(find.text('Contextual').first);
      await tester.pumpAndSettle();
      final text = await state.document!.pages.first.loadStructuredText();
      final verbStart = text.fullText.indexOf('nest');
      final verbRange = PdfPageTextRange(
        pageText: text,
        start: verbStart,
        end: verbStart + 4,
      );
      // Reproduzir o rótulo errado já gravado automaticamente na versão anterior.
      await state.saveSelection(
        automatic: 'ninho',
        automaticMode: 'B',
        range: verbRange,
        notify: false,
      );
      final annotationId = state.annotations.single['id'];
      Future<void> translateAt(int start) async {
        await state.controller.textSelectionDelegate.setTextSelectionPointRange(
          PdfTextSelectionRange.fromPoints(
            PdfTextSelectionPoint(text, start),
            PdfTextSelectionPoint(text, start + 3),
          ),
        );
        await _until(tester, () => state.selection?.start == start);
        await tester.tap(find.text('Marcar e traduzir'));
        await _until(tester, () => !state.busy);
        await tester.pumpAndSettle();
      }

      final clock = Stopwatch()..start();
      await translateAt(verbStart);
      final verbMs = clock.elapsedMicroseconds / 1000;
      final verb = Map<String, dynamic>.from(state.annotations.single);
      expect(verb['id'], annotationId);
      expect(verb['shortTranslation'], 'aninham');
      expect(verb['translatedSentence'], contains('aninham'));
      expect(
        verb['automaticSuggestion']['basis'],
        'contextual-prefix-alignment',
      );
      expect(verb['manualOverride'], false);
      expect(verb['automaticSuggestion']['contextVerified'], false);
      expect(find.byType(BottomSheet), findsNothing);
      expect(find.text('aninham'), findsOneWidget);
      final nounStart = text.fullText.lastIndexOf('nest');
      expect(nounStart, greaterThan(verbStart));
      await translateAt(nounStart);
      expect(state.annotations, hasLength(2));
      final noun = state.annotations.singleWhere(
        (a) => a['charRange'][0] == nounStart,
      );
      expect(noun['shortTranslation'], 'ninho');
      await state.controller.textSelectionDelegate.clearTextSelection();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Salvar'));
      await _until(tester, () => !state.busy);
      final bytes = await original.readAsBytes();
      final saved = pdf.PdfDocument.open(bytes);
      expect(saved.page(0).annotations, hasLength(4));
      expect(
        saved.page(0).annotations.map((a) => a.contents),
        containsAll(['aninham', 'ninho']),
      );
      final image =
          await (key.currentContext!.findRenderObject()!
                  as RenderRepaintBoundary)
              .toImage(pixelRatio: 1);
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      await File('${reports.path}/windows-contextual-label-ui.png')
          .writeAsBytes(png!.buffer.asUint8List());
      image.dispose();
      await File('${reports.path}/windows-contextual-label-ui.pdf')
          .writeAsBytes(bytes);
      await tester.tap(find.byTooltip('Voltar'));
      await tester.pumpAndSettle();
      await _until(tester, () => find.byType(ReaderScreen).evaluate().isEmpty);
      open(await files.open(original.path));
      await tester.pumpAndSettle();
      state = tester.state<ReaderScreenState>(find.byType(ReaderScreen));
      await _until(
        tester,
        () => state.annotations.length == 2 && state.controller.isReady,
      );
      expect(
        state.annotations.map((a) => a['shortTranslation']),
        containsAll(['aninham', 'ninho']),
      );
      final status = await engine.request({'op': 'status'});
      expect(status['encoderCalls'], greaterThanOrEqualTo(2));
      await File('${reports.path}/windows-contextual-label-ui.json')
          .writeAsString(
            const JsonEncoder.withIndent('  ').convert({
              'verb': verb,
              'noun': noun,
              'verbColdUiMs': verbMs,
              'runtimeStatus': status,
              'automaticAnnotationReplacedWithoutDuplicate': true,
              'savedInOriginalAndPreservedOnReopen': true,
              'panelOpened': false,
              'personalDocumentsUsed': false,
            }),
          );
    },
  );
}
