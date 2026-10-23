import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart' as mui;
import 'package:pdfrx/pdfrx.dart';
import 'package:contextual_pdf_reader/app/services.dart';
import 'package:contextual_pdf_reader/features/reader/reader_screen.dart';

import 'reader_flow_test.dart' show until;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    '1.001 páginas: leitura preguiçosa, 50 marcações e página sem texto',
    (tester) async {
      pdfrxFlutterInitialize();
      final s = await AppServices.create();
      addTearDown(() async {
        await s.encoder.unload();
        await s.translator.dispose();
        await s.db.close();
      });
      final file = File('${s.directory.path}/large-fixture.pdf');
      await file.writeAsBytes(
        (await rootBundle.load('assets/sample-large.pdf')).buffer.asUint8List(),
      );
      await s.db.putDocument(
        'synthetic-large-1001',
        file.path,
        'Livro sintético',
        1001,
      );
      for (final a in await s.db.annotations('synthetic-large-1001')) {
        await s.db.removeAnnotation(a['id']);
      }
      final before = ProcessInfo.currentRss;
      final timer = Stopwatch()..start();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [servicesProvider.overrideWithValue(s)],
          child: MaterialApp(
            home: mui.Theme(
              data: mui.ThemeData(),
              child: ReaderScreen(
                documentId: 'synthetic-large-1001',
                path: file.path,
                title: 'Livro sintético',
              ),
            ),
          ),
        ),
      );
      final state = tester.state<ReaderScreenState>(find.byType(ReaderScreen));
      await until(tester, () => state.document != null);
      await tester.pump(const Duration(seconds: 1));
      final openMs = timer.elapsedMicroseconds / 1000,
          zero = ProcessInfo.currentRss;
      expect(state.document!.pages.length, 1001);
      final text = await state.document!.pages.first.loadStructuredText();
      final words = RegExp(r'\bword\b')
          .allMatches(text.fullText)
          .take(50)
          .toList();
      expect(words.length, 50);
      for (var i = 0; i < 50; i++) {
        await state.saveSelection(
          range: PdfPageTextRange(
            pageText: text,
            start: words[i].start,
            end: words[i].end,
          ),
        );
      }
      await tester.pump();
      expect(state.annotations.length, 50);
      final fifty = ProcessInfo.currentRss;
      await state.controller.goToPage(
        pageNumber: 1001,
        duration: Duration.zero,
      );
      await until(
        tester,
        () => state.warning?.contains('não possui texto selecionável') == true,
      );
      binding.reportData ??= {};
      binding.reportData!['largeDocument'] = {
        'pages': 1001,
        'annotations': 50,
        'openAndOneSecondRenderMs': openMs,
        'rssBefore': before,
        'rssZeroAnnotations': zero,
        'rssFiftyAnnotations': fifty,
        'textlessPageDetected': true,
        'device': 'Android emulator x86_64 debug; não físico; não teste de livro real',
      };
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
