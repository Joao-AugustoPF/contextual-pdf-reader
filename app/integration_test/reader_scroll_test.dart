import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart' as mui;
import 'package:pdfrx/pdfrx.dart';
import 'package:contextual_pdf_reader/app/services.dart';
import 'package:contextual_pdf_reader/core/inference/model_store.dart';
import 'package:contextual_pdf_reader/core/nlp/pipeline.dart';
import 'package:contextual_pdf_reader/core/persistence/database.dart';
import 'package:contextual_pdf_reader/features/reader/reader_screen.dart';
import 'package:contextual_pdf_reader/main.dart';

import 'support/unused_engine.dart';

Future<void> _until(WidgetTester tester, bool Function() ready) async {
  for (var i = 0; i < 300; i++) {
    if (ready()) return;
    await tester.pump(const Duration(milliseconds: 100));
  }
  throw StateError('Timeout aguardando navegação PDF');
}

Future<void> _wheel(WidgetTester tester, Offset position, double delta) =>
    tester.sendEventToBinding(
      PointerScrollEvent(
        position: position,
        scrollDelta: Offset(0, delta),
        kind: PointerDeviceKind.mouse,
      ),
    );

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Windows: rolagem suave, barra arrastável, trilha e zoom', (
    tester,
  ) async {
    pdfrxFlutterInitialize();
    final temp = await Directory.systemTemp.createTemp('reader-scroll-');
    final sample = File('${temp.path}/baseline.pdf');
    await sample.writeAsBytes(
      (await rootBundle.load('assets/sample.pdf')).buffer.asUint8List(),
    );
    final db = ReaderDatabase.memory();
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 1));
      await db.close();
      await temp.delete(recursive: true);
    });

    // Mede a configuração antiga com o mesmo PDF e um evento igual de roda.
    final baseline = PdfViewerController();
    await tester.pumpWidget(
      MaterialApp(
        home: mui.Theme(
          data: mui.ThemeData(),
          child: Scaffold(
            body: PdfViewer.file(sample.path, controller: baseline),
          ),
        ),
      ),
    );
    await _until(tester, () => baseline.isReady);
    await tester.pump(const Duration(seconds: 1));
    final baselineZoom = baseline.currentZoom;
    final baselineStart = baseline.visibleRect.top * baselineZoom;
    await _wheel(tester, tester.getCenter(find.byType(PdfViewer)), 20);
    await tester.pump(const Duration(milliseconds: 500));
    final baselinePixels =
        baseline.visibleRect.top * baselineZoom - baselineStart;
    expect(baselinePixels, greaterThan(0));

    final lexicon = jsonDecode(
      await rootBundle.loadString('assets/lexicon.json'),
    ) as Map<String, dynamic>;
    final engine = UnusedEngine();
    final services = AppServices(
      temp,
      db,
      ModelStore(Directory('${temp.path}/models'), {}),
      engine,
      engine,
      TranslationOrchestrator(engine, engine, lexicon),
    );
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
    final state = tester.state<ReaderScreenState>(find.byType(ReaderScreen));
    await _until(
      tester,
      () => state.document != null && state.controller.isReady,
    );
    await tester.pump(const Duration(seconds: 1));
    final ctrl = state.controller;
    final trackFinder = find.byKey(const ValueKey('pdf-scroll-track'));
    final thumbFinder = find.byKey(const ValueKey('pdf-scroll-thumb'));
    expect(trackFinder, findsOneWidget);
    expect(thumbFinder, findsOneWidget);
    final zoom = ctrl.currentZoom;
    final start = ctrl.visibleRect.top * zoom;
    final pointer = tester.getCenter(find.byType(PdfViewer));
    await _wheel(tester, pointer, 20);
    await tester.pump(const Duration(milliseconds: 16));
    final intermediatePixels = ctrl.visibleRect.top * zoom - start;
    await tester.pump(const Duration(milliseconds: 650));
    final smoothPixels = ctrl.visibleRect.top * zoom - start;
    expect(smoothPixels, greaterThan(baselinePixels * 3));
    expect(
      intermediatePixels,
      lessThan(smoothPixels),
      reason: 'O avanço deve ocorrer ao longo de frames',
    );
    expect(smoothPixels, closeTo(80, 2));

    // Eventos rápidos se acumulam, permitindo atravessar páginas com menos roda.
    await ctrl.goToPage(pageNumber: 1, duration: Duration.zero);
    await tester.pump(const Duration(milliseconds: 100));
    var wheelEventsToNextPage = 0;
    while (state.page < 2 && wheelEventsToNextPage < 40) {
      await _wheel(tester, pointer, 20);
      wheelEventsToNextPage++;
      await tester.pump(const Duration(milliseconds: 90));
    }
    await _until(tester, () => state.page == 2);
    await tester.pump(const Duration(milliseconds: 650));
    final track = tester.getRect(trackFinder);
    await tester.dragFrom(
      tester.getCenter(thumbFinder),
      Offset(0, -track.height),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump(const Duration(milliseconds: 650));
    expect(ctrl.visibleRect.top, closeTo(0, 2));

    // Um clique na trilha navega até a fração correspondente do livro.
    await tester.tapAt(
      Offset(track.center.dx, track.top + track.height * 0.6),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump(const Duration(milliseconds: 500));
    final progress =
        ctrl.visibleRect.top /
        (ctrl.documentSize.height - ctrl.visibleRect.height);
    expect(progress, inInclusiveRange(0.45, 0.75));

    // Após zoom a barra continua alcançando o fim, sem alterar a ampliação.
    await ctrl.zoomUp(duration: Duration.zero);
    await tester.pump(const Duration(milliseconds: 300));
    final zoomBeforeDrag = ctrl.currentZoom;
    final zoomedTrack = tester.getRect(trackFinder);
    await tester.dragFrom(
      tester.getCenter(thumbFinder),
      Offset(0, zoomedTrack.height),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump(const Duration(milliseconds: 650));
    expect(ctrl.currentZoom, closeTo(zoomBeforeDrag, 0.001));
    expect(ctrl.visibleRect.bottom, closeTo(ctrl.documentSize.height, 2));
    expect(state.page, state.document!.pages.length);
    final reportDir = Directory(
      const String.fromEnvironment(
        'TEST_REPORT_DIR',
        defaultValue: '../reports',
      ),
    );
    await reportDir.create(recursive: true);
    final boundary =
        boundaryKey.currentContext!.findRenderObject()!
            as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: 1);
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    await File('${reportDir.path}/windows-reader-scroll.png')
        .writeAsBytes(png!.buffer.asUint8List());
    image.dispose();
    await File('${reportDir.path}/windows-reader-scroll.json').writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'platform': Platform.operatingSystem,
        'wheelEventDelta': 20,
        'baselineZoom': baselineZoom,
        'baselineInstantPixels': baselinePixels,
        'readerZoom': zoom,
        'smoothIntermediatePixels': intermediatePixels,
        'smoothFinalPixels': smoothPixels,
        'wheelEventsToNextPage': wheelEventsToNextPage,
        'scrollbarDragToStart': true,
        'trackClickProgress': progress,
        'scrollbarDragToEndAfterZoom': true,
        'zoomPreservedByScrollbar': true,
        'userDatabaseUsed': false,
      }),
    );
  });
}
