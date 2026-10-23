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
import 'package:pdfrx/pdfrx.dart';
import 'package:contextual_pdf_reader/app/services.dart';
import 'package:contextual_pdf_reader/core/inference/model_store.dart';
import 'package:contextual_pdf_reader/core/nlp/pipeline.dart';
import 'package:contextual_pdf_reader/core/persistence/database.dart';
import 'package:contextual_pdf_reader/features/reader/reader_screen.dart';
import 'package:contextual_pdf_reader/main.dart';

import 'support/unused_engine.dart';

Future<void> _until(WidgetTester tester, bool Function() ready) async {
  for (var i = 0; i < 240; i++) {
    if (ready()) return;
    await tester.pump(const Duration(milliseconds: 100));
  }
  throw StateError('Timeout aguardando o leitor');
}

Future<void> _doubleClick(WidgetTester tester, Offset position) async {
  await tester.tapAt(position, kind: PointerDeviceKind.mouse);
  await tester.pump(const Duration(milliseconds: 70));
  await tester.tapAt(position, kind: PointerDeviceKind.mouse);
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Windows: duplo clique, contraste, anotação e zoom', (
    tester,
  ) async {
    pdfrxFlutterInitialize();
    final temp = await Directory.systemTemp.createTemp('reader-interaction-');
    final db = ReaderDatabase.memory();
    final engine = UnusedEngine();
    final lexicon = jsonDecode(
      await rootBundle.loadString('assets/lexicon.json'),
    ) as Map<String, dynamic>;
    final services = AppServices(
      temp,
      db,
      ModelStore(Directory('${temp.path}/models'), {}),
      engine,
      engine,
      TranslationOrchestrator(engine, engine, lexicon),
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
    final state = tester.state<ReaderScreenState>(find.byType(ReaderScreen));
    await _until(
      tester,
      () => state.document != null && state.controller.isReady,
    );
    final text = await state.document!.pages.first.loadStructuredText();
    final start = text.fullText.indexOf('give up');
    expect(start, greaterThanOrEqualTo(0));
    Rect wordRect(int start, int end) {
      final range = PdfPageTextRange(pageText: text, start: start, end: end);
      final rect = range
          .enumerateFragmentBoundingRects()
          .first
          .bounds
          .toRectInDocument(
            page: state.document!.pages.first,
            pageRect: state.controller.layout.pageLayouts.first,
          );
      return Rect.fromPoints(
        state.controller.documentToGlobal(rect.topLeft)!,
        state.controller.documentToGlobal(rect.bottomRight)!,
      );
    }

    final reportDir = Directory(
      const String.fromEnvironment(
        'TEST_REPORT_DIR',
        defaultValue: '../reports',
      ),
    );
    await reportDir.create(recursive: true);
    Future<ui.Image> capture(String name) async {
      await tester.pump(const Duration(seconds: 1));
      final boundary =
          boundaryKey.currentContext!.findRenderObject()!
              as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 1);
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      await File('${reportDir.path}/$name.png')
          .writeAsBytes(png!.buffer.asUint8List());
      return image;
    }

    await tester.pump(const Duration(seconds: 2));
    final original = await capture('windows-highlight-before');
    final target = wordRect(start, start + 4);
    await _doubleClick(tester, target.center);
    await _until(tester, () => state.selection != null);
    expect(state.selection!.text.trim(), 'give');
    await tester.tap(find.text('Marcar'));
    await _until(tester, () => state.annotations.length == 1);
    await state.controller.textSelectionDelegate.clearTextSelection();
    await tester.pump(const Duration(milliseconds: 500));
    final highlighted = await capture('windows-highlight-after');
    final before = (await original.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    ))!;
    final after = (await highlighted.toByteData(
      format: ui.ImageByteFormat.rawRgba,
    ))!;
    var darkBefore = 0, preservedDark = 0, strongBackground = 0;
    for (var y = target.top.ceil(); y < target.bottom.floor(); y++) {
      for (var x = target.left.ceil(); x < target.right.floor(); x++) {
        final i = (y * original.width + x) * 4;
        if (before.getUint8(i) < 64 &&
            before.getUint8(i + 1) < 64 &&
            before.getUint8(i + 2) < 64) {
          darkBefore++;
          if (after.getUint8(i) < 64 &&
              after.getUint8(i + 1) < 64 &&
              after.getUint8(i + 2) < 64) {
            preservedDark++;
          }
        }
        if (before.getUint8(i + 2) > 245 && after.getUint8(i + 2) < 140) {
          strongBackground++;
        }
      }
    }
    expect(
      darkBefore,
      greaterThan(5),
      reason: 'O PDF precisa estar renderizado',
    );
    expect(
      preservedDark / darkBefore,
      greaterThan(0.95),
      reason: 'As letras não podem ficar apagadas',
    );
    expect(
      strongBackground,
      greaterThan(10),
      reason: 'O amarelo deve ter intensidade maior',
    );
    original.dispose();
    highlighted.dispose();

    // Duplo clique em anotação não abre o painel de clique simples.
    await _doubleClick(tester, wordRect(start, start + 4).center);
    await _until(tester, () => state.selection?.text.trim() == 'give');
    expect(find.text('Editar anotação'), findsNothing);
    // Uma anotação de expressão não transforma duplo clique em seleção da frase.
    await state.saveSelection(
      range: PdfPageTextRange(pageText: text, start: start, end: start + 7),
    );
    await state.controller.textSelectionDelegate.clearTextSelection();
    await tester.pump(const Duration(milliseconds: 500));
    await _doubleClick(tester, wordRect(start + 5, start + 7).center);
    await _until(tester, () => state.selection?.text.trim() == 'up');
    expect(find.text('Editar anotação'), findsNothing);
    // Arrastar continua selecionando texto através das regiões anotadas.
    final dragStart = Offset(target.left + 1, target.center.dy);
    final dragEnd = Offset(
      wordRect(start + 5, start + 7).right - 1,
      target.center.dy,
    );
    await tester.dragFrom(
      dragStart,
      dragEnd - dragStart,
      kind: PointerDeviceKind.mouse,
    );
    await _until(
      tester,
      () => state.selection?.text.contains('give up') == true,
    );
    // A mesma palavra continua selecionável após ampliar.
    await state.controller.zoomUp(
      zoomCenter: state.controller.globalToDocument(
        wordRect(start, start + 4).center,
      ),
      duration: Duration.zero,
    );
    await tester.pump(const Duration(milliseconds: 500));
    await state.controller.textSelectionDelegate.clearTextSelection();
    await _doubleClick(tester, wordRect(start, start + 4).center);
    await _until(tester, () => state.selection?.text.trim() == 'give');
    // Clique simples continua abrindo os detalhes da anotação.
    await tester.pump(const Duration(milliseconds: 500));
    await tester.tapAt(
      wordRect(start, start + 4).center,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Editar anotação'), findsOneWidget);
    await File('${reportDir.path}/windows-reader-interaction.json')
        .writeAsString(
          const JsonEncoder.withIndent('  ').convert({
            'platform': Platform.operatingSystem,
            'doubleClickPlainWord': true,
            'doubleClickHighlightedWord': true,
            'doubleClickInsideHighlightedPhrase': true,
            'dragAcrossAnnotation': true,
            'doubleClickAfterZoom': true,
            'singleClickAnnotationDetails': true,
            'darkPixelsBefore': darkBefore,
            'darkPixelsPreserved': preservedDark,
            'strongBackgroundPixels': strongBackground,
            'userDatabaseUsed': false,
          }),
        );
  });
}
