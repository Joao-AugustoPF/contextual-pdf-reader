import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:pdf_document/pdf_document.dart' as pdf;
import 'package:contextual_pdf_reader/app/services.dart';
import 'package:contextual_pdf_reader/core/inference/model_store.dart';
import 'package:contextual_pdf_reader/core/inference/sidecar.dart';
import 'package:contextual_pdf_reader/core/nlp/isolated_suggestion.dart';
import 'package:contextual_pdf_reader/core/nlp/pipeline.dart';
import 'package:contextual_pdf_reader/core/persistence/database.dart';
import 'package:contextual_pdf_reader/features/reader/reader_screen.dart';
import 'package:contextual_pdf_reader/main.dart';

Future<void> _until(WidgetTester tester, bool Function() ready) async {
  for (var i = 0; i < 600; i++) {
    if (ready()) return;
    await tester.pump(const Duration(milliseconds: 100));
  }
  throw StateError('Timeout aguardando tradução direta');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Windows: tradução direta sem painel, pontuação e edição preservada',
    (tester) async {
      pdfrxFlutterInitialize();
      final root = Directory(
        const String.fromEnvironment('TEST_PROJECT_ROOT', defaultValue: '..'),
      ).absolute;
      final temp = await Directory.systemTemp.createTemp('reader-quick-');
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
      final services = AppServices(
        temp,
        db,
        ModelStore(Directory('${root.path}/models'), {}),
        engine,
        engine,
        TranslationOrchestrator(engine, engine, lexicon),
      );
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
      await _until(
        tester,
        () => find.text('Experimentar com um PDF').evaluate().isNotEmpty,
      );
      await tester.tap(find.text('Experimentar com um PDF'));
      await _until(
        tester,
        () => find.byType(ReaderScreen).evaluate().isNotEmpty,
      );
      final state = tester.state<ReaderScreenState>(find.byType(ReaderScreen));
      await _until(
        tester,
        () => state.document != null && state.controller.isReady,
      );
      await tester.pump(const Duration(seconds: 1));
      final initialZoom = state.controller.currentZoom;
      final text = await state.document!.pages.first.loadStructuredText();
      const word = 'programming';
      final start = text.fullText.indexOf(word);
      expect(
        text.fullText.substring(start, start + word.length + 1),
        'programming.',
      );
      await state.controller.textSelectionDelegate.setTextSelectionPointRange(
        PdfTextSelectionRange.fromPoints(
          PdfTextSelectionPoint(text, start),
          PdfTextSelectionPoint(text, start + word.length),
        ),
      );
      await _until(tester, () => state.selection?.text == word);
      final timer = Stopwatch()..start();
      await tester.tap(find.text('Marcar e traduzir'));
      await _until(tester, () => state.annotations.length == 1 && !state.busy);
      final directMs = timer.elapsedMicroseconds / 1000;
      expect(find.byType(BottomSheet), findsNothing);
      expect(find.text('Revisar e salvar sugestão'), findsNothing);
      final annotation = state.annotations.single;
      expect(normalize(annotation['shortTranslation']), 'programacao');
      expect(annotation['selectedText'], word);
      expect(annotation['charRange'], [start, start + word.length]);
      expect(annotation['manualOverride'], false);
      expect(annotation['source'], 'automática');
      expect(annotation['automaticSuggestion']['userReviewed'], false);
      expect(annotation['automaticSuggestion']['contextVerified'], false);
      expect(annotation['automaticSuggestion']['requiresReview'], false);
      expect(annotation['translatedSentence'], isNull);
      expect(state.controller.currentZoom, closeTo(initialZoom, 0.001));
      final quickStatus = await engine.request({'op': 'status'});
      expect(quickStatus['translationCalls'], 1);
      expect(quickStatus['encoderCalls'], 0);
      expect(quickStatus['onnxImported'], false);
      final reportDir = Directory(
        const String.fromEnvironment(
          'TEST_REPORT_DIR',
          defaultValue: '../reports',
        ),
      );
      await reportDir.create(recursive: true);
      await state.controller.textSelectionDelegate.clearTextSelection();
      await tester.pump(const Duration(milliseconds: 500));
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 1);
      final range = PdfPageTextRange(
        pageText: text,
        start: start,
        end: start + word.length,
      );
      final wordRect = range
          .enumerateFragmentBoundingRects()
          .first
          .bounds
          .toRectInDocument(
            page: state.document!.pages.first,
            pageRect: state.controller.layout.pageLayouts.first,
          );
      final topLeft = state.controller.documentToGlobal(wordRect.topLeft)!;
      final bottomRight = state.controller.documentToGlobal(
        wordRect.bottomRight,
      )!;
      final pixels = (await image.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!;
      var darkTextPixels = 0;
      for (var y = topLeft.dy.ceil(); y < bottomRight.dy.floor(); y++) {
        for (var x = topLeft.dx.ceil(); x < bottomRight.dx.floor(); x++) {
          final index = (y * image.width + x) * 4;
          if (pixels.getUint8(index) < 64 &&
              pixels.getUint8(index + 1) < 64 &&
              pixels.getUint8(index + 2) < 64) {
            darkTextPixels++;
          }
        }
      }
      expect(
        darkTextPixels,
        greaterThan(20),
        reason: 'O texto PDF deve continuar renderizado ao salvar',
      );
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      await File('${reportDir.path}/windows-quick-translation.png')
          .writeAsBytes(png!.buffer.asUint8List());
      image.dispose();

      // A tradução real aplicada no overlay também precisa ir para o original.
      await tester.tap(find.text('Salvar'));
      await _until(tester, () => !state.busy);
      final originalPath =
          (await db.document(state.widget.documentId))!['source_path']
              as String;
      final savedPdf = pdf.PdfDocument.open(
        await File(originalPath).readAsBytes(),
      );
      expect(savedPdf.page(0).annotations, hasLength(2));
      expect(
        savedPdf.page(0).annotations.map((a) => a.contents),
        contains(annotation['shortTranslation']),
      );

      // Caso exato do usuário pelo mesmo motor real, sem enviar a vírgula ao modelo.
      final computer = await translateIsolatedText(engine, 'computer,');
      expect(computer.original, 'computer');
      expect(normalize(computer.translation), 'computador');
      expect(computer.translation, isNot(endsWith(',')));

      // Anotação antiga/editada com pontuação continua tendo prioridade.
      annotation['charRange'] = [start, start + word.length + 1];
      annotation['selectedText'] = 'programming.';
      annotation['shortTranslation'] = 'programação manual';
      annotation['manualOverride'] = true;
      annotation['source'] = 'editada';
      await db.saveAnnotation(annotation);
      await state.controller.textSelectionDelegate.setTextSelectionPointRange(
        PdfTextSelectionRange.fromPoints(
          PdfTextSelectionPoint(text, start),
          PdfTextSelectionPoint(text, start + word.length),
        ),
      );
      await _until(tester, () => state.selection?.text == word);
      await tester.tap(find.text('Marcar e traduzir'));
      await _until(tester, () => !state.busy);
      expect(state.annotations.length, 1);
      expect(
        state.annotations.single['shortTranslation'],
        'programação manual',
      );
      expect(
        (await db.annotations(state.widget.documentId))
            .single['manualOverride'],
        true,
      );

      // O painel permanece disponível mediante pedido explícito.
      await tester.tap(find.text('Detalhes'));
      await _until(tester, () => find.text('A • Básico').evaluate().isNotEmpty);
      expect(state.annotations.length, 1);
      final status = await engine.request({'op': 'status'});
      expect(status['encoderCalls'], 0);
      expect(status['onnxImported'], false);
      await File('${reportDir.path}/windows-quick-translation.json')
          .writeAsString(
            const JsonEncoder.withIndent('  ').convert({
              'platform': Platform.operatingSystem,
              'selectedWithPunctuation': 'programming.',
              'savedSelection': word,
              'automaticTranslation':
                  annotation['automaticSuggestion']['translation'],
              'quickFlowElapsedMs': directMs,
              'zoomPreserved': true,
              'darkTextPixelsAfterSaving': darkTextPixels,
              'quickRuntimeStatus': quickStatus,
              'computerCase': computer.toJson(),
              'popupOpenedAutomatically': false,
              'actualTranslationSavedInOriginalPdf': true,
              'legacyManualAnnotationPreserved': true,
              'explicitDetailsOpened': true,
              'userDatabaseUsed': false,
            }),
          );
    },
  );
}
