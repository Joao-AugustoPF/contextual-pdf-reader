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
import 'package:contextual_pdf_reader/app/services.dart';
import 'package:contextual_pdf_reader/core/inference/model_store.dart';
import 'package:contextual_pdf_reader/core/inference/sidecar.dart';
import 'package:contextual_pdf_reader/core/nlp/pipeline.dart';
import 'package:contextual_pdf_reader/core/persistence/database.dart';
import 'package:contextual_pdf_reader/features/reader/reader_screen.dart';
import 'package:contextual_pdf_reader/main.dart';

Future<void> _until(WidgetTester tester, bool Function() ready) async {
  for (var i = 0; i < 600; i++) {
    if (ready()) return;
    await tester.pump(const Duration(milliseconds: 100));
  }
  throw StateError('Timeout aguardando a tradução local');
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Windows: aplicar sugestão e escrever significado no Comparar', (
    tester,
  ) async {
    pdfrxFlutterInitialize();
    final root = Directory(
      const String.fromEnvironment('TEST_PROJECT_ROOT', defaultValue: '..'),
    ).absolute;
    final temp = await Directory.systemTemp.createTemp('reader-fallback-');
    final db = ReaderDatabase.memory();
    final manifest = jsonDecode(
      await rootBundle.loadString('assets/models.lock.json'),
    ) as Map<String, dynamic>;
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
      ModelStore(Directory('${root.path}/models'), manifest),
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
    await _until(tester, () => find.byType(ReaderScreen).evaluate().isNotEmpty);
    final state = tester.state<ReaderScreenState>(find.byType(ReaderScreen));
    await _until(
      tester,
      () => state.document != null && state.controller.isReady,
    );
    final text = await state.document!.pages.first.loadStructuredText();
    const word = 'programming';
    expect(lexicon.containsKey(word), false);
    final start = text.fullText.indexOf(word);
    expect(start, greaterThanOrEqualTo(0));
    await state.controller.textSelectionDelegate.setTextSelectionPointRange(
      PdfTextSelectionRange.fromPoints(
        PdfTextSelectionPoint(text, start),
        PdfTextSelectionPoint(text, start + word.length - 1),
      ),
    );
    await _until(tester, () => state.selection?.text == word);
    await tester.tap(find.text('Comparar').first);
    await tester.pump();
    await tester.tap(find.text('Marcar e traduzir'));
    await _until(
      tester,
      () => find.text('Editar significado').evaluate().isNotEmpty,
    );
    expect(find.textContaining('Trecho da frase traduzida'), findsOneWidget);
    expect(
      find.textContaining('fora do léxico'),
      findsNothing,
    ); // Evidências recolhidas.
    expect(state.annotations, isEmpty);
    final reportDir = Directory(
      const String.fromEnvironment(
        'TEST_REPORT_DIR',
        defaultValue: '../reports',
      ),
    );
    await reportDir.create(recursive: true);
    await tester.pump(const Duration(milliseconds: 500));
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 1);
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    await File('${reportDir.path}/windows-comparison-suggestion.png')
        .writeAsBytes(png!.buffer.asUint8List());
    image.dispose();
    await tester.ensureVisible(find.text('Editar significado'));
    await tester.tap(find.text('Editar significado'));
    await tester.pumpAndSettle();
    final input = tester.widget<TextField>(find.byType(TextField));
    final machineSuggestion = input.controller!.text;
    expect(normalize(machineSuggestion), 'programacao');
    await tester.tap(find.text('Cancelar'));
    await tester.pumpAndSettle();
    expect(state.annotations, isEmpty);
    await tester.tap(find.text('Usar esta tradução'));
    await _until(
      tester,
      () =>
          state.annotations.length == 1 &&
          find.byType(BottomSheet).evaluate().isEmpty,
    );
    expect(
      normalize(state.annotations.single['shortTranslation']),
      'programacao',
    );
    expect(find.byType(AlertDialog), findsNothing);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Detalhes'));
    await _until(
      tester,
      () => find.text('Editar significado').evaluate().isNotEmpty,
    );
    await tester.ensureVisible(find.text('Editar significado'));
    await tester.tap(find.text('Editar significado'));
    await tester.pumpAndSettle();
    const edited = 'programação revisada';
    await tester.enterText(find.byType(TextField), edited);
    await tester.tap(find.text('Salvar').last);
    await _until(
      tester,
      () => state.annotations.single['shortTranslation'] == edited,
    );
    final saved = (await db.annotations(state.widget.documentId)).single;
    expect(saved['shortTranslation'], edited);
    expect(saved['manualOverride'], true);
    expect(saved['source'], 'editada');
    expect(saved['reviewedSuggestion']['userReviewed'], true);
    expect(saved['reviewedSuggestion']['contextVerified'], false);
    expect(saved['reviewedSuggestion']['alignmentResolved'], true);
    expect(saved['decision'], isNull);
    final status = await engine.request({'op': 'status'});
    expect(status['translationCalls'], 5);
    expect(status['encoderCalls'], greaterThan(0));
    expect(status['onnxImported'], true);
    await File('${reportDir.path}/windows-comparison-suggestion.json')
        .writeAsString(
          const JsonEncoder.withIndent('  ').convert({
            'platform': Platform.operatingSystem,
            'mode': 'compare',
            'selectedWord': word,
            'machineSuggestion': machineSuggestion,
            'finalTranslation': saved['shortTranslation'],
            'savedBeforeReview': false,
            'cancelPreservedEmptyAnnotations': true,
            'directSuggestionAppliedWithoutDialog': true,
            'manualOverride': saved['manualOverride'],
            'suggestionEvidence': saved['reviewedSuggestion'],
            'runtimeStatus': status,
            'userDatabaseUsed': false,
          }),
        );
  });
}
