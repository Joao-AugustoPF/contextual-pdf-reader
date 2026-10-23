import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:contextual_pdf_reader/main.dart' as app;
import 'package:contextual_pdf_reader/app/services.dart';
import 'package:contextual_pdf_reader/features/reader/reader_screen.dart';
import 'package:contextual_pdf_reader/features/annotations/exporter.dart';
import 'package:contextual_pdf_reader/features/experiment/evaluation.dart';
import 'package:contextual_pdf_reader/core/nlp/pipeline.dart';
import 'package:flutter/services.dart';

Future<void> until(
  WidgetTester t,
  bool Function() check, {
  int seconds = 60,
}) async {
  for (var i = 0; i < seconds * 4; i++) {
    if (check()) return;
    await t.pump(const Duration(milliseconds: 250));
  }
  throw StateError('Timeout aguardando interface');
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'PDF real: selecionar, salvar, editar, zoom, reabrir e exportar',
    (tester) async {
      await app.main();
      await until(
        tester,
        () => find.text('Experimentar com um PDF').evaluate().isNotEmpty,
      );
      await tester.tap(find.text('Experimentar com um PDF'));
      await until(
        tester,
        () => find.byType(ReaderScreen).evaluate().isNotEmpty,
      );
      final state = tester.state<ReaderScreenState>(find.byType(ReaderScreen));
      await until(tester, () => state.document != null);
      final doc = state.document!;
      final text = await doc.pages.first.loadStructuredText();
      final start = text.fullText.indexOf('give up');
      expect(start, greaterThanOrEqualTo(0));
      await state.controller.textSelectionDelegate.setTextSelectionPointRange(
        PdfTextSelectionRange.fromPoints(
          PdfTextSelectionPoint(text, start),
          PdfTextSelectionPoint(text, start + 6),
        ),
      );
      await until(tester, () => state.selection != null);
      final initialCount = state.annotations.length;
      await tester.tap(find.text('Marcar'));
      await until(tester, () => state.annotations.length == initialCount + 1);
      final before = state.annotations.length;
      await tester.tap(find.byTooltip('Anotações'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('give up').last);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Editar anotação'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'ação: desistir');
      await tester.tap(find.text('Salvar').last);
      await tester.pumpAndSettle();
      expect(state.annotations.length, before);
      final annotation = state.annotations.last;
      expect(annotation['manualOverride'], true);
      expect(annotation['shortTranslation'], 'ação: desistir');
      await state.saveSelection(
        range: PdfPageTextRange(pageText: text, start: start, end: start + 7),
        decision: Decision(
          mode: 'A',
          status: 'teste de preservação',
          shortTranslation: 'substituição automática',
          evidence: [],
          decisionMs: 0,
        ),
      );
      expect(state.annotations.length, before);
      expect(state.annotations.last['shortTranslation'], 'ação: desistir');
      final quads = jsonEncode(annotation['quadPointsPdf']);
      await state.controller.zoomUp(duration: Duration.zero);
      await tester.pumpAndSettle();
      expect(jsonEncode(state.annotations.last['quadPointsPdf']), quads);
      final scope = ProviderScope.containerOf(
        tester.element(find.byType(ReaderScreen)),
        listen: false,
      );
      final services = scope.read(servicesProvider);
      addTearDown(() async {
        await services.encoder.unload();
        await services.translator.dispose();
        await services.db.close();
      });
      final saved = await services.db.annotations(state.widget.documentId);
      expect(saved.last['shortTranslation'], 'ação: desistir');
      final output = '${services.directory.path}/exportado-integracao.pdf';
      await exportCopy(state.widget.path, output, saved);
      final reopened = await PdfDocument.openFile(output);
      expect(reopened.pages.length, doc.pages.length);
      expect(
        (await reopened.pages.first.loadStructuredText()).fullText,
        contains('give up programming'),
      );
      await reopened.dispose();
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      await tester.tap(find.text('exemplo.pdf').first);
      await until(
        tester,
        () => find.byType(ReaderScreen).evaluate().isNotEmpty,
      );
      final again = tester.state<ReaderScreenState>(find.byType(ReaderScreen));
      await until(
        tester,
        () => again.document != null && again.annotations.isNotEmpty,
      );
      expect(again.annotations.last['shortTranslation'], 'ação: desistir');
      await binding.convertFlutterSurfaceToImage();
      await tester.pump();
      await binding.takeScreenshot('reader-android');
      binding.reportData ??= {};
      binding.reportData!['flow'] = {
        'success': true,
        'annotations': saved.length,
        'pages': doc.pages.length,
      };
      await File('${services.directory.path}/integration-flow.json')
          .writeAsString(
            jsonEncode({
              'success': true,
              'annotations': saved.length,
              'exported': output,
              'pages': doc.pages.length,
            }),
          );
    },
  );

  testWidgets(
    'ML Kit + MiniLM reais: instalar explicitamente e avaliar 64 seleções',
    (tester) async {
      await app.main();
      await until(
        tester,
        () => find.text('Experimentar com um PDF').evaluate().isNotEmpty,
      );
      final scope = ProviderScope.containerOf(
        tester.element(find.byType(app.ReaderApp)),
        listen: false,
      );
      final s = scope.read(servicesProvider);
      addTearDown(() async {
        await s.encoder.unload();
        await s.translator.dispose();
        await s.db.close();
      });
      await tester.runAsync(() async {
        if (!await s.translator.isModelReady()) {
          await s.translator
              .downloadModelsWithConsent(consent: true, wifiOnly: false)
              .timeout(const Duration(minutes: 3));
        }
        if (!await s.models.ready('minilm')) {
          await s.models
              .install('minilm', consent: true)
              .timeout(const Duration(minutes: 3));
        }
        final memoryBefore = ProcessInfo.currentRss;
        Map<dynamic, dynamic>? networkStatus;
        if (const bool.fromEnvironment('OFFLINE_AUDIT')) {
          debugPrint('MODELS_READY_OFFLINE');
          for (var i = 0; i < 120; i++) {
            networkStatus = await const MethodChannel(
              'br.com.estudos.reader/diagnostics',
            ).invokeMapMethod('networkStatus');
            if (networkStatus?['connected'] == false) break;
            await Future<void>.delayed(const Duration(milliseconds: 250));
          }
          expect(
            networkStatus?['connected'],
            false,
            reason: 'O host deve desativar a rede antes da inferência',
          );
        }
        final fixtures = List<Map<String, dynamic>>.from(
          jsonDecode(await rootBundle.loadString('assets/evaluation.json')),
        );
        final cold = await s.pipeline.run(
          SelectionContext(
            fixtures.first['sentence'],
            fixtures.first['start'],
            fixtures.first['end'],
          ),
          TranslationMode.compare,
          useCache: false,
        );
        expect(cold.b!.status, isNot('Erro no encoder'));
        expect(cold.b!.status, isNot('Modelo indisponível'));
        expect(cold.b!.score, isNotNull);
        final rows = await evaluate(s.pipeline, fixtures);
        final result = {
          'environment': {
            'platform': Platform.operatingSystem,
            'device': 'emulator Android x86_64; não aparelho físico',
            'airplaneModeDuringEvaluation': const bool.fromEnvironment(
              'OFFLINE_AUDIT',
            ),
            'nativeNetworkStatusBeforeInference': networkStatus,
            'rssBeforeInference': memoryBefore,
            'rssAfterEvaluation': ProcessInfo.currentRss,
          },
          'summary': summarize(rows),
          'cold': cold.toJson(),
          'samples': rows,
        };
        binding.reportData ??= {};
        binding.reportData!['benchmarkAndroid'] = result;
        binding.reportData!['benchmarkAndroidCsv'] = measurementsCsv(rows);
        await File('${s.directory.path}/benchmark-android.json')
            .writeAsString(const JsonEncoder.withIndent('  ').convert(result));
        await File('${s.directory.path}/benchmark-android.csv')
            .writeAsString(measurementsCsv(rows));
        expect(rows.length, 64);
      });
    },
    timeout: const Timeout(Duration(minutes: 10)),
  );
  testWidgets('Comparar na seleção real salva apenas uma anotação', (
    tester,
  ) async {
    await app.main();
    await until(
      tester,
      () => find.text('Experimentar com um PDF').evaluate().isNotEmpty,
    );
    await tester.tap(find.text('Experimentar com um PDF'));
    await until(tester, () => find.byType(ReaderScreen).evaluate().isNotEmpty);
    final state = tester.state<ReaderScreenState>(find.byType(ReaderScreen));
    await until(tester, () => state.document != null);
    final scope = ProviderScope.containerOf(
      tester.element(find.byType(ReaderScreen)),
      listen: false,
    );
    final s = scope.read(servicesProvider);
    addTearDown(() async {
      await s.encoder.unload();
      await s.translator.dispose();
      await s.db.close();
    });
    final text = await state.document!.pages.first.loadStructuredText();
    final start = text.fullText.indexOf('light');
    await state.controller.textSelectionDelegate.setTextSelectionPointRange(
      PdfTextSelectionRange.fromPoints(
        PdfTextSelectionPoint(text, start),
        PdfTextSelectionPoint(text, start + 4),
      ),
    );
    await until(tester, () => state.selection != null);
    await tester.tap(find.text('Comparar').first);
    await tester.pump();
    final initial = state.annotations.length;
    await tester.tap(find.text('Traduzir com Google'));
    await until(tester, () => find.text('A • Básico').evaluate().isNotEmpty);
    expect(find.text('B • Contextual'), findsOneWidget);
    expect(state.annotations.length, initial);
    expect(await s.db.getPreference('mode'), 'compare');
    await binding.convertFlutterSurfaceToImage();
    await tester.pump();
    await binding.takeScreenshot('compare-android');
    await tester.ensureVisible(find.text('Usar esta').first);
    await tester.tap(find.text('Usar esta').first);
    await until(tester, () => state.annotations.length == initial + 1);
    binding.reportData ??= {};
    binding.reportData!['comparisonFlow'] = {
      'annotations': state.annotations.length,
      'last': state.annotations.last,
      'success': true,
    };
    final bytes = exportAnnotated(
      await File(state.widget.path).readAsBytes(),
      state.annotations,
      attributionImage: (await rootBundle.load('assets/google-translate.png'))
          .buffer
          .asUint8List(),
    );
    binding.reportData!['annotatedPdfBase64'] = base64Encode(bytes);
  });
}
