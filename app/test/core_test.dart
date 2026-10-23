// ignore_for_file: avoid_relative_lib_imports
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:pdf_document/pdf_document.dart' as pdf;
import 'package:crypto/crypto.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:path/path.dart' as p;

import '../lib/core/nlp/pipeline.dart';
import '../lib/core/nlp/isolated_suggestion.dart';
import '../lib/core/nlp/contextual_suggestion.dart';
import '../lib/core/nlp/selection_text.dart';
import '../lib/core/nlp/wordpiece.dart';
import '../lib/core/pdf_coordinates/geometry.dart';
import '../lib/core/persistence/database.dart';
import '../lib/core/inference/model_store.dart';
import '../lib/features/annotations/exporter.dart';
import '../lib/features/annotations/selection.dart';
import '../lib/features/library/document_files.dart';
import '../lib/features/library/original_pdf_access.dart';
import '../lib/features/experiment/evaluation.dart';
import '../lib/features/reader/render_quality.dart';

class FakeTranslator implements OfflineTranslationEngine {
  int calls = 0;
  String translation = 'Decidi desistir da programação.';
  Completer<String>? block;
  @override
  String get id => 'test-translator-v1';
  @override
  bool get isSupported => true;
  @override
  Future<bool> isModelReady() async => true;
  @override
  Future<List<String>> listInstalledModels() async => ['en', 'pt'];
  @override
  Future<void> downloadModelsWithConsent({
    required bool consent,
    bool wifiOnly = true,
  }) async {
    if (!consent) throw StateError('consent');
  }

  @override
  Future<String> translateSentence(String s) async {
    calls++;
    return block?.future ?? Future.value(translation);
  }

  @override
  Future<void> dispose() async {}
}

class FakeEncoder implements SpanEncoder {
  int calls = 0, unloads = 0;
  bool ready = true, fail = false;
  @override
  Future<bool> isReady() async => ready;
  @override
  Future<List<double>> encode(String s, int a, int b) async {
    calls++;
    if (fail) throw StateError('falha controlada');
    return [1, 0, 0];
  }

  @override
  Future<void> unload() async {
    unloads++;
  }
}

String root() => Directory('assets').existsSync() ? '.' : '../../app';

class ContextTranslator extends FakeTranslator {
  ContextTranslator(this.outputs);
  final Map<String, String> outputs;
  final seen = <String>[];
  @override
  Future<String> translateSentence(String text) async {
    seen.add(text);
    if (!outputs.containsKey(text)) {
      throw StateError('Entrada artificial recusada');
    }
    return outputs[text]!;
  }
}

class MemoryOriginalAccess implements OriginalPdfAccess {
  final Map<String, Uint8List> files = {};
  int writes = 0;
  bool denyRead = false, denyWrite = false;
  void Function()? beforeWrite;
  String? lastExpectedHash;
  @override
  Future<String?> pick() async => files.keys.firstOrNull;
  @override
  Future<OriginalPdfSnapshot> read(String source) async {
    if (denyRead) throw StateError('Acesso ao original revogado');
    return OriginalPdfSnapshot('livro.pdf', Uint8List.fromList(files[source]!));
  }

  @override
  Future<void> write(
    String source,
    Uint8List bytes,
    String expectedHash,
  ) async {
    lastExpectedHash = expectedHash;
    beforeWrite?.call();
    if (denyWrite ||
        sha256.convert(files[source]!).toString() != expectedHash) {
      throw StateError('Provedor recusou escrita ou detectou mudança externa');
    }
    files[source] = Uint8List.fromList(bytes);
    writes++;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'rótulo contextual preserva flexão e acentos da frase, com offsets exatos',
    () {
      const full = 'Porque os componentes geralmente se aninham entre si.';
      final span = alignTranslationEdge(
        sentenceTranslation: full,
        withTarget: 'Porque componentes muitas vezes aninham',
        withoutTarget: 'Porque componentes muitas vezes',
        atEnd: true,
      );
      expect(span!.text, 'aninham');
      expect(full.substring(span.start, span.end), span.text);
      expect(
        alignTranslationEdge(
          sentenceTranslation: 'Os pássaros construíram um ninho.',
          withTarget: 'Os pássaros construíram',
          withoutTarget: 'Os pássaros',
          atEnd: true,
        )!.text,
        'construíram',
      );
      expect(
        alignTranslationEdge(
          sentenceTranslation: 'Eu decidi desistir da programação.',
          withTarget: 'Eu decidi desistir da programação',
          withoutTarget: 'Eu decidi desistir',
          atEnd: true,
        )!.text,
        'programação',
      );
    },
  );
  test(
    'rótulo contextual recusa forma ausente, repetida ou reescrita extensa',
    () {
      for (final full in [
        'Os componentes se aninham entre si.',
        'Os pássaros fazem ninho e outro ninho.',
      ]) {
        expect(
          alignTranslationEdge(
            sentenceTranslation: full,
            withTarget: 'Os pássaros fazem ninho',
            withoutTarget: 'Os pássaros fazem',
            atEnd: true,
          ),
          isNull,
        );
      }
      expect(
        alignTranslationEdge(
          sentenceTranslation: 'Toda a frase mudou.',
          withTarget: 'Toda a frase mudou',
          withoutTarget: 'Outro texto diferente',
          atEnd: true,
        ),
        isNull,
      );
    },
  );
  test('omissão preserva reflexivo e ignora reformulação ausente da frase original', () {
    expect(
      alignTranslationOmission(
        'Os pássaros se aninham na árvore.',
        'Os pássaros na árvore.',
      )!.text,
      'se aninham',
    );
    expect(
      alignTranslationOmission(
        'Mas a partição de nível superior ainda gira em torno de domínios.',
        'Mas o particionamento de nível superior ainda vai em torno de domínios.',
        reference: 'Mas o particionamento de nível superior ainda gira em torno de domínios.',
      )!.text,
      'gira',
    );
    expect(
      alignTranslationOmission(
        'Os pássaros fazem um ninho na árvore.',
        'Os peixes nadam no mar.',
      ),
      isNull,
    );
  });
  test('mesma palavra como substantivo mantém ninho em vez do verbo', () {
    expect(
      alignTranslationEdge(
        sentenceTranslation: 'O pássaro construiu um ninho na árvore.',
        withTarget: 'O pássaro construiu um ninho',
        withoutTarget: 'O pássaro construiu um',
        atEnd: true,
      )!.text,
      'ninho',
    );
  });
  test('sugestão contextual usa frase, sem alterar decisão A/B ou invocar encoder no A', () async {
    const sentence = 'Because components often nest within one another.';
    const translated = 'Porque os componentes geralmente se aninham entre si.';
    final translator = ContextTranslator({
      sentence: translated,
      'Because components often': 'Porque componentes muitas vezes',
      'Because components often nest':
          'Porque componentes muitas vezes aninham',
      'nest': 'ninho',
    });
    final encoder = FakeEncoder();
    final start = sentence.indexOf('nest');
    final result = await TranslationOrchestrator(
      translator,
      encoder,
      {},
    ).run(SelectionContext(sentence, start, start + 4), TranslationMode.basic);
    final decisionBefore = result.a!.toJson();
    final suggestion = await suggestSelectionInContext(translator, result);
    expect(suggestion.translation, 'aninham');
    expect(suggestion.usesSentenceTranslation, true);
    expect(suggestion.toJson()['contextVerified'], false);
    expect(suggestion.toJson()['alignmentResolved'], true);
    expect(translator.seen, [
      sentence,
      'Because components often',
      'Because components often nest',
    ]);
    expect(result.a!.toJson(), decisionBefore);
    expect(encoder.calls, 0);
  });
  test(
    'falha nas sondagens preserva fallback isolado sem alegar alinhamento',
    () async {
      const sentence = 'The birds nest in the tree.';
      final translator = ContextTranslator({
        sentence: 'Os pássaros se aninham na árvore.',
        'nest': 'ninho',
      });
      final start = sentence.indexOf('nest');
      final result =
          await TranslationOrchestrator(translator, FakeEncoder(), {}).run(
            SelectionContext(sentence, start, start + 4),
            TranslationMode.basic,
          );
      final suggestion = await suggestSelectionInContext(translator, result);
      expect(suggestion.translation, 'ninho');
      expect(suggestion.usesSentenceTranslation, false);
      expect(suggestion.toJson()['alignmentResolved'], false);
      expect(suggestion.elapsedMs, greaterThanOrEqualTo(0));
    },
  );
  test('não atribui ao alvo reescrita distante de outra oração', () async {
    const sentence =
        'Because everything is coupled to everything else, changes tend to have hard-to-predict rippling side effects.';
    final start = sentence.indexOf('rippling');
    final translator = ContextTranslator({
      sentence: 'Porque tudo está ligado ao resto, mudanças tendem a ter efeitos colaterais difíceis de prever.',
      sentence.substring(0, start).trim(): 'Uma base estável aqui',
      sentence.substring(0, start + 8).trim(): 'Uma base estável aqui resto',
      'rippling': 'Ondulação',
    });
    final result = await TranslationOrchestrator(
      translator,
      FakeEncoder(),
      {},
    ).run(SelectionContext(sentence, start, start + 8), TranslationMode.basic);
    final suggestion = await suggestSelectionInContext(translator, result);
    expect(suggestion.translation, 'Ondulação');
    expect(suggestion.usesSentenceTranslation, false);
  });
  test(
    'iOS: original externo salva, edita, remove e reabre sem cópia exportada',
    () async {
      final temp = await Directory.systemTemp.createTemp(
        'reader-ios-original-',
      );
      final db = ReaderDatabase.memory();
      addTearDown(() async {
        await db.close();
        await temp.delete(recursive: true);
      });
      final access = MemoryOriginalAccess();
      const source = 'ios-pdf://documento-1';
      final initial = File('${root()}/assets/sample.pdf').readAsBytesSync();
      access.files[source] = initial;
      final files = DocumentFiles(temp, db, originalAccess: access);
      final book = await files.open(source);
      final working = await File(book['path']).readAsBytes();
      expect(book['source_path'], source);
      final annotation = <String, dynamic>{
        'id': 'ios-a',
        'documentId': book['id'],
        'pageNumber': 1,
        'color': 0xffffd54f,
        'quadPointsPdf': [
          [48, 700, 90, 714],
        ],
        'labelBox': [48, 715, 150, 730],
        'labelFontSize': 8,
        'shortTranslation': 'computador',
      };
      await db.saveAnnotation(annotation);
      expect(await files.save(book['id'], [annotation]), source);
      expect(access.lastExpectedHash, sha256.convert(initial).toString());
      expect(
        pdf.PdfDocument.open(access.files[source]!).page(0).annotations,
        hasLength(2),
      );
      await files.save(book['id'], [annotation]);
      expect(access.writes, 1, reason: 'Salvar sem mudanças não reescreve');
      annotation['shortTranslation'] = 'computador revisado';
      await files.save(book['id'], [annotation]);
      expect(
        pdf.PdfDocument.open(access.files[source]!)
            .page(0)
            .annotations
            .map((a) => a.contents),
        contains('computador revisado'),
      );
      final reopened = await DocumentFiles(
        temp,
        db,
        originalAccess: access,
      ).open(book['path']);
      expect(reopened['id'], book['id']);
      expect(reopened['source_path'], source);
      expect(
        pdf.PdfDocument.open(await File(reopened['path']).readAsBytes())
            .page(0)
            .annotations,
        isEmpty,
      );
      await files.save(book['id'], []);
      expect(
        pdf.PdfDocument.open(access.files[source]!).page(0).annotations,
        isEmpty,
      );
      expect(await File(book['path']).readAsBytes(), working);
      expect(access.files.keys, [source]);
      expect(await db.documents(), hasLength(1));
    },
  );

  test(
    'iOS: alterações externas antes e durante a escrita são preservadas',
    () async {
      final temp = await Directory.systemTemp.createTemp(
        'reader-ios-conflict-',
      );
      final db = ReaderDatabase.memory();
      addTearDown(() async {
        await db.close();
        await temp.delete(recursive: true);
      });
      final access = MemoryOriginalAccess();
      const source = 'ios-pdf://documento-2';
      final initial = File('${root()}/assets/sample.pdf').readAsBytesSync();
      access.files[source] = initial;
      final files = DocumentFiles(temp, db, originalAccess: access);
      final book = await files.open(source);
      final hash = book['source_hash'];
      final external = Uint8List.fromList([
        ...initial,
        ...utf8.encode('\n% externo'),
      ]);
      access.files[source] = external;
      await expectLater(files.save(book['id'], []), throwsStateError);
      expect(access.writes, 0);
      expect(access.files[source], external);
      access.files[source] = initial;
      access.beforeWrite = () => access.files[source] = external;
      await expectLater(files.save(book['id'], []), throwsStateError);
      expect(access.files[source], external);
      expect((await db.document(book['id']))!['source_hash'], hash);
      expect(await db.getPreference('pdf-save/${book['id']}'), isNull);
    },
  );

  test(
    'iOS: acesso negado não grava na cópia nem marca salvamento como sucesso',
    () async {
      final temp = await Directory.systemTemp.createTemp('reader-ios-denied-');
      final db = ReaderDatabase.memory();
      addTearDown(() async {
        await db.close();
        await temp.delete(recursive: true);
      });
      final access = MemoryOriginalAccess();
      const source = 'ios-pdf://documento-3';
      final initial = File('${root()}/assets/sample.pdf').readAsBytesSync();
      access.files[source] = initial;
      final files = DocumentFiles(temp, db, originalAccess: access);
      final book = await files.open(source);
      access.denyRead = true;
      await expectLater(files.save(book['id'], []), throwsStateError);
      access.denyRead = false;
      access.denyWrite = true;
      await expectLater(files.save(book['id'], []), throwsStateError);
      expect(access.files[source], initial);
      expect(await File(book['path']).readAsBytes(), initial);
      expect(access.writes, 0);
      expect(
        (await db.document(book['id']))!['source_hash'],
        book['source_hash'],
      );
      expect(await db.getPreference('pdf-save/${book['id']}'), isNull);
    },
  );

  test('iOS: arquivos externos iguais têm identidade própria e vínculo antigo valida conteúdo', () async {
    final temp = await Directory.systemTemp.createTemp('reader-ios-link-');
    final db = ReaderDatabase.memory();
    addTearDown(() async {
      await db.close();
      await temp.delete(recursive: true);
    });
    final access = MemoryOriginalAccess();
    final initial = File('${root()}/assets/sample.pdf').readAsBytesSync();
    access.files['ios-pdf://a'] = initial;
    access.files['ios-pdf://b'] = initial;
    access.files['ios-pdf://outro'] = File('${root()}/assets/sample-large.pdf')
        .readAsBytesSync();
    final files = DocumentFiles(temp, db, originalAccess: access);
    final first = await files.open('ios-pdf://a');
    final second = await files.open('ios-pdf://b');
    expect(second['id'], isNot(first['id']));
    final local = File('${temp.path}/antigo.pdf');
    await local.writeAsBytes(initial);
    final legacy = await files.open(local.path);
    await expectLater(
      files.linkOriginal(legacy['id'], 'ios-pdf://outro'),
      throwsStateError,
    );
    expect(
      (await db.document(legacy['id']))!['source_path'],
      await local.resolveSymbolicLinks(),
    );
    await files.linkOriginal(legacy['id'], 'ios-pdf://b');
    expect((await db.document(legacy['id']))!['source_path'], 'ios-pdf://b');
  });

  test('iOS: canal usa token persistente e hash esperado, propaga cancelamento e erro', () async {
    const access = IosOriginalPdfAccess();
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    final calls = <MethodCall>[];
    var cancel = false, denied = false;
    messenger.setMockMethodCallHandler(IosOriginalPdfAccess.channel, (
      call,
    ) async {
      calls.add(call);
      if (denied) {
        throw PlatformException(
          code: 'PDF_ACCESS_LOST',
          message: 'Selecione novamente',
        );
      }
      if (call.method == 'pickPdf') return cancel ? null : 'ios-pdf://canal';
      if (call.method == 'readPdf') {
        return {
          'name': 'livro.pdf',
          'bytes': Uint8List.fromList([1, 2]),
        };
      }
      return null;
    });
    addTearDown(
      () => messenger.setMockMethodCallHandler(
        IosOriginalPdfAccess.channel,
        null,
      ),
    );
    expect(await access.pick(), 'ios-pdf://canal');
    expect((await access.read('ios-pdf://canal')).bytes, [1, 2]);
    await access.write(
      'ios-pdf://canal',
      Uint8List.fromList([3]),
      'hash-do-original',
    );
    expect(calls.last.arguments['expectedHash'], 'hash-do-original');
    expect(calls.last.arguments['source'], 'ios-pdf://canal');
    cancel = true;
    expect(await access.pick(), isNull);
    denied = true;
    await expectLater(
      access.read('ios-pdf://canal'),
      throwsA(isA<PlatformException>()),
    );
  });

  test(
    'renderização acompanha zoom e monitor com teto para páginas grandes',
    () {
      double scale(double zoom, double dpr, {double w = 612, double h = 792}) =>
          pagePreviewScale(
            pageWidth: w,
            pageHeight: h,
            zoom: zoom,
            devicePixelRatio: dpr,
          );
      expect(scale(1.5, 1), 3);
      expect(scale(0.75, 2), 3);
      expect(scale(0.75, 1.25), 1.875);
      final large = scale(10, 2);
      expect(612 * 792 * large * large, closeTo(12 * 1024 * 1024, 0.01));
      expect(792 * large, lessThanOrEqualTo(4096));
      final square = scale(10, 2, w: 1000, h: 1000);
      expect(1000 * 1000 * square * square, closeTo(12 * 1024 * 1024, 0.01));
      expect(scale(1, 2, w: 10000, h: 20000), closeTo(4096 / 20000, 0.000001));
    },
  );

  test('seleção de palavra remove pontuação e preserva offsets Unicode', () {
    for (final (source, expected) in [
      ('computer,', 'computer'),
      ('“computer,”', 'computer'),
      ("don't,", "don't"),
      ('hard-to-predict.', 'hard-to-predict'),
      ('cafe\u0301,', 'cafe\u0301'),
    ]) {
      final span = wordSelectionSpan(source, 0, source.length)!;
      expect(source.substring(span.start, span.end), expected);
    }
    const source = '🙂 computer,';
    final span = wordSelectionSpan(source, 3, source.length)!;
    expect(source.substring(span.start, span.end), 'computer');
    expect(span.start, 3);
    expect(wordSelectionSpan('...', 0, 3), isNull);
    expect(wordSelectionSpan('A sentence.', 0, 11), (start: 0, end: 11));
    expect(shortTranslationLabel(' computador, '), 'computador');
  });
  test(
    'tradução direta usa somente a palavra limpa e limpa o rótulo',
    () async {
      final translator = FakeTranslator()..translation = 'computador,';
      final suggestion = await translateIsolatedText(translator, 'computer,');
      expect(suggestion.original, 'computer');
      expect(suggestion.translation, 'computador');
      expect(translator.calls, 1);
      expect(suggestion.toJson()['contextVerified'], false);
    },
  );
  test('WordPiece mobile coincide com tokenizer oficial nas 64 frases', () {
    final tok = WordPieceTokenizer(
      File('${root()}/test/wordpiece_vocab.txt').readAsStringSync(),
      padTo: 128,
    );
    final refs = jsonDecode(
      File('${root()}/test/tokenizer_reference.json').readAsStringSync(),
    ) as List;
    for (final r in refs) {
      final pieces = tok.tokenize(r['text']);
      expect(pieces.map((p) => p.id).toList(), r['ids'], reason: r['text']);
      expect(
        pieces.map((p) => [p.start, p.end]).toList(),
        r['offsets'],
        reason: r['text'],
      );
    }
  });
  late Map<String, dynamic> lex;
  setUpAll(() {
    lex = jsonDecode(File('${root()}/assets/lexicon.json').readAsStringSync());
  });
  test('give -> give up com offsets exatos', () {
    const c = SelectionContext('I decided to give up programming.', 13, 17);
    final e = recognize(c, lex);
    expect(e.lemma, 'give up');
    expect(c.sentence.substring(e.start, e.end), 'give up');
  });
  test('phrasal separável não inclui objeto no pooling', () {
    const s = 'Please look the number up online.';
    final e = recognize(const SelectionContext(s, 7, 11), lex);
    expect(e.lemma, 'look up');
    expect(e.tokenSpans.map((t) => s.substring(t.$1, t.$2)), ['look', 'up']);
  });
  test('flexão deu -> give', () {
    expect(lemmaOf('gave'), 'give');
    expect(lemmaOf('looks'), 'look');
  });
  test('abreviações preservam a frase', () {
    const s = 'Mr. Smith said give up. Then leave.';
    final c = SelectionContext.fromPage(
      s,
      s.indexOf('give'),
      s.indexOf('give') + 4,
    );
    expect(c.sentence, 'Mr. Smith said give up.');
  });
  test('seleção inválida e sem caracteres falha', () {
    expect(() => SelectionContext.fromPage('abc', 0, 0), throwsArgumentError);
    expect(() => SelectionContext.fromPage('abc', -1, 2), throwsArgumentError);
  });
  test('unicode e acentos normalizados', () {
    expect(normalize('CONDIÇÃO de Corrida!'), 'condicao de corrida');
  });
  test('A não consulta nem executa MiniLM', () async {
    final t = FakeTranslator(), e = FakeEncoder()..ready = false;
    final p = TranslationOrchestrator(t, e, lex);
    final r = await p.run(
      const SelectionContext('I decided to give up programming.', 13, 17),
      TranslationMode.basic,
    );
    expect(e.calls, 0);
    expect(r.a!.shortTranslation, 'desistir');
    expect(r.b, isNull);
  });
  test('Comparar compartilha uma tradução e B executa encoder', () async {
    final t = FakeTranslator(), e = FakeEncoder();
    final p = TranslationOrchestrator(t, e, lex);
    final r = await p.run(
      const SelectionContext('I decided to give up programming.', 13, 17),
      TranslationMode.compare,
    );
    expect(t.calls, 1);
    expect(e.calls, greaterThan(0));
    expect(r.a!.shortTranslation, r.b!.shortTranslation);
    expect(r.b!.score, isNotNull);
    expect(r.b!.toJson()['confidence'], isNull);
  });
  test('B indisponível nunca é rotulado como A', () async {
    final p = TranslationOrchestrator(
      FakeTranslator(),
      FakeEncoder()..ready = false,
      lex,
    );
    final r = await p.run(
      const SelectionContext('light', 0, 5),
      TranslationMode.compare,
    );
    expect(r.b!.mode, 'B');
    expect(r.b!.status, 'Modelo indisponível');
    expect(r.b!.shortTranslation, isNull);
  });
  test('falha encoder é explícita', () async {
    final p = TranslationOrchestrator(
      FakeTranslator(),
      FakeEncoder()..fail = true,
      lex,
    );
    final r = await p.run(
      const SelectionContext('light', 0, 5),
      TranslationMode.contextual,
    );
    expect(r.b!.status, 'Erro no encoder');
  });
  test('sugestão isolada exige revisão e não muda a decisão A/B', () async {
    final t = FakeTranslator()..translation = 'O telescópio observa nebulosas.';
    final e = FakeEncoder();
    final pipeline = TranslationOrchestrator(t, e, lex);
    const sentence = 'The telescope observes nebulae.';
    final start = sentence.indexOf('nebulae');
    final result = await pipeline.run(
      SelectionContext(sentence, start, start + 'nebulae'.length),
      TranslationMode.basic,
    );
    expect(result.a!.shortTranslation, isNull);
    expect(result.a!.evidence.single, contains('fora do léxico'));
    final originalDecision = result.a!.toJson();
    t.translation = 'nebulosas';
    final suggestion = await suggestIsolatedTranslation(t, result);
    expect(suggestion.original, 'nebulae');
    expect(suggestion.translation, 'nebulosas');
    expect(suggestion.toJson()['requiresReview'], true);
    expect(suggestion.toJson()['contextVerified'], false);
    expect(suggestion.toJson()['alignmentResolved'], false);
    expect(result.a!.toJson(), originalDecision);
    expect(t.calls, 2);
    expect(e.calls, 0);
    expect(result.b, isNull);
  });
  test('falha da sugestão não transforma abstenção em resultado', () async {
    final t = FakeTranslator();
    final pipeline = TranslationOrchestrator(t, FakeEncoder(), lex);
    final result = await pipeline.run(
      const SelectionContext('A nebula.', 2, 8),
      TranslationMode.basic,
    );
    t.block = Completer<String>();
    final future = suggestIsolatedTranslation(t, result);
    t.block!.completeError(StateError('falha controlada'));
    await expectLater(future, throwsStateError);
    expect(result.a!.shortTranslation, isNull);
  });
  test('cache tem backend e não compartilha decisões A/B', () async {
    final t = FakeTranslator(), e = FakeEncoder();
    final p = TranslationOrchestrator(t, e, lex);
    const c = SelectionContext('light', 0, 5);
    await p.run(c, TranslationMode.basic);
    final b = await p.run(c, TranslationMode.contextual);
    expect(t.calls, 1);
    expect(b.cacheHit, true);
    expect(e.calls, greaterThan(0));
    expect(p.sentenceCache.keys.single, startsWith(t.id));
  });
  test('cancelamento descarta seleção obsoleta', () async {
    final t = FakeTranslator()..block = Completer<String>();
    final p = TranslationOrchestrator(t, FakeEncoder(), lex);
    final future = p.run(
      const SelectionContext('light', 0, 5),
      TranslationMode.basic,
    );
    p.cancel();
    t.block!.complete('luz');
    await expectLater(future, throwsStateError);
  });
  test('desativação descarrega e limpa protótipos', () async {
    final e = FakeEncoder(),
        p = TranslationOrchestrator(FakeTranslator(), FakeEncoder(), lex);
    final p2 = TranslationOrchestrator(FakeTranslator(), e, lex);
    p.prototypeCache['a'] = [1];
    await p2.disableContextual();
    expect(e.unloads, 1);
    expect(p2.prototypeCache, isEmpty);
  });
  for (final scale in [0.5, 1.0, 2.5, 4.0]) {
    test('coordenadas ida/volta zoom $scale', () {
      const b = Box(40, 300, 100, 315);
      final screen = b.toScreen(600 * scale, 800 * scale, 600, 800);
      final restored = screen.fromScreen(600 * scale, 800 * scale, 600, 800);
      expect(restored.toJson(), b.toJson());
    });
  }
  test('Mesmo sem espaço livre a tradução continua ancorada acima', () {
    const target = Box(50, 700, 100, 714);
    final a = placeLabel(target, 'luz', 600, 800, []);
    final b = placeLabel(target, 'leve', 600, 800, [a.box]);
    expect(a.margin, false);
    expect(b.margin, false);
    expect(b.fontSize, 4);
    expect((b.box.l + b.box.r) / 2, 75);
    expect(b.box.b, greaterThan(714));
  });
  test('Linha ocupada não envia a tradução para outra área da página', () {
    const target = Box(50, 700, 100, 714);
    final a = placeLabel(
      target,
      'luz',
      600,
      800,
      [],
      textLines: [const Box(40, 715, 300, 730)],
    );
    expect(a.margin, false);
    expect((a.box.l + a.box.r) / 2, 75);
    expect(a.box.b, greaterThan(target.t));
  });
  test('Entrelinha estreita usa rótulo compacto acima sem cobrir texto', () {
    const target = Box(80, 700, 130, 714);
    const previousLine = Box(55, 721.6, 550, 735.6);
    final label = placeLabel(
      target,
      'luz',
      612,
      792,
      [],
      textLines: [previousLine],
    );
    expect(label.margin, false);
    expect(label.fontSize, 6);
    expect(label.box.b, greaterThan(target.t));
    expect(label.box.overlaps(previousLine), false);
  });
  test('Texto denso mantém significado diretamente acima da palavra', () {
    const target = Box(203, 132, 250, 146);
    final lines = [
      for (var y = 72.0; y < 200; y += 20) Box(55, y, 500, y + 14),
    ];
    final label = placeLabel(
      target,
      'em cascata',
      612,
      792,
      [],
      textLines: lines,
    );
    expect(label.margin, false);
    expect(label.fontSize, greaterThanOrEqualTo(4));
    expect((label.box.b - target.t).abs(), lessThan(20));
    expect(lines.any((line) => line.overlaps(label.box)), false);
    expect(label.box.overlaps(target), false);
    expect(
      (label.box.l + label.box.r) / 2,
      (target.l + target.r) / 2,
      reason: 'O centro do significado acompanha o centro da palavra',
    );
  });
  test('Drift persiste anotação editada, preferências e progresso', () async {
    final d = await Directory.systemTemp.createTemp('reader-db-'),
        file = File('${d.path}/reader.sqlite');
    var db = ReaderDatabase(file);
    await db.putDocument('hash', '/book.pdf', 'Livro', 2);
    await db.progress('hash', 2);
    await db.saveAnnotation({
      'id': 'a',
      'documentId': 'hash',
      'pageNumber': 1,
      'manualOverride': true,
      'shortTranslation': 'ação',
    });
    await db.preference('mode', 'compare');
    await db.close();
    db = ReaderDatabase(file);
    expect((await db.annotations('hash')).single['shortTranslation'], 'ação');
    expect((await db.documents()).single['progress'], 2);
    expect(await db.getPreference('mode'), 'compare');
    await db.close();
    await d.delete(recursive: true);
  });
  test('cache e medições transacionais', () async {
    final db = ReaderDatabase.memory();
    await db.cache('k', 'v1', 'texto');
    expect(await db.loadCache('v1'), {'k': 'texto'});
    expect(await db.loadCache('v2'), isEmpty);
    await db.saveSample('run', '1', {'id': '1'});
    expect(await db.samples(), hasLength(1));
    await db.clearMeasurements();
    expect(await db.samples(), isEmpty);
    await db.close();
  });
  test(
    'download recusado sem consentimento e hash corrompido rejeitado',
    () async {
      final d = await Directory.systemTemp.createTemp('reader-model-');
      final f = File('${d.path}/minilm/model.onnx');
      await f.parent.create();
      await f.writeAsString('corrompido');
      final store = ModelStore(d, {
        'files': [
          {'file': 'models/minilm/model.onnx', 'sha256': 'bad', 'bytes': 1},
        ],
      });
      await expectLater(
        store.install('minilm', consent: false),
        throwsStateError,
      );
      await expectLater(store.verify('minilm'), throwsStateError);
      await d.delete(recursive: true);
    },
  );
  test('WordPiece preserva subwords e offsets', () {
    final tok = WordPieceTokenizer(
      '[PAD]\n[UNK]\n[CLS]\n[SEP]\nlight\nprogram\n##ming\n.',
    );
    final p = tok.tokenize('LIGHT programming.');
    expect(p.map((t) => t.id), [2, 4, 5, 6, 7, 3]);
    expect(
      p.where((t) => t.start < 17 && t.end > 6).map((t) => (t.start, t.end)),
      [(6, 13), (13, 17)],
    );
  });
  test('WordPiece truncamento mantém SEP e detectável pelo consumidor', () {
    final tok = WordPieceTokenizer('[PAD]\n[UNK]\n[CLS]\n[SEP]\nlight');
    expect(tok.tokenize('light light light', maxLength: 4).length, 4);
  });
  test('64 fixtures explícitas, únicas e gold separado de protótipos', () {
    final f = List<Map<String, dynamic>>.from(
      jsonDecode(File('${root()}/assets/evaluation.json').readAsStringSync()),
    );
    expect(f.length, greaterThanOrEqualTo(60));
    expect(f.map((f) => f['sentence']).toSet().length, f.length);
    for (final row in f) {
      expect(
        (row['sentence'] as String).substring(row['start'], row['end']),
        row['selectedText'],
      );
      expect(row['provenance'], 'agent-authored-explicit-unvalidated');
    }
  });
  test(
    'Salvar atualiza o original, sem duplicar; edita, remove e reabre',
    () async {
      final temp = await Directory.systemTemp.createTemp('reader-save-');
      final db = ReaderDatabase.memory();
      addTearDown(() async {
        await db.close();
        await temp.delete(recursive: true);
      });
      final folder = await Directory('${temp.path}/Meus PDFs').create();
      final original = File('${folder.path}/livro ação.pdf');
      final base = File('${root()}/assets/sample.pdf').readAsBytesSync();
      final foreignEditor = pdf.PdfEditor(pdf.PdfDocument.open(base));
      foreignEditor.addFreeText(
        0,
        const pdf.PdfRect(48, 40, 180, 60),
        'Nota de outro leitor',
        name: 'external-note',
      );
      await original.writeAsBytes(foreignEditor.save());
      final files = DocumentFiles(Directory('${temp.path}/app'), db);
      final book = await files.open(original.path);
      final id = book['id'] as String;
      final annotation = <String, dynamic>{
        'id': 'a',
        'documentId': id,
        'pageNumber': 1,
        'color': 0xffffd54f,
        'quadPointsPdf': [
          [48, 700, 90, 714],
        ],
        'labelBox': [48, 715, 150, 730],
        'labelFontSize': 8,
        'shortTranslation': 'ação: desistir',
      };
      await db.saveAnnotation(annotation);
      await db.progress(id, 2);
      await files.save(id, [annotation]);
      final first = await original.readAsBytes();
      expect(pdf.PdfDocument.open(first).page(0).annotations, hasLength(3));
      await files.save(id, [annotation]);
      expect(
        await original.readAsBytes(),
        first,
        reason: 'Salvar sem mudanças não cresce o arquivo',
      );
      annotation['shortTranslation'] = 'ação revisada';
      await db.saveAnnotation(annotation);
      await files.save(id, [annotation]);
      final edited = pdf.PdfDocument.open(await original.readAsBytes());
      expect(edited.pageCount, 2);
      expect(edited.page(0).annotations, hasLength(3));
      expect(
        edited.page(0).annotations.map((a) => a.contents),
        contains('ação revisada'),
      );
      final reopened = await files.open(original.path);
      expect(reopened['id'], id);
      expect(reopened['progress'], 2);
      expect(await db.documents(), hasLength(1));
      expect(
        (await db.annotations(id)).single['shortTranslation'],
        'ação revisada',
      );
      expect(
        pdf.PdfDocument.open(await File(reopened['path']).readAsBytes())
            .page(0)
            .annotations
            .single
            .name,
        'external-note',
        reason: 'Base interna sem as marcações que o overlay já desenha',
      );
      await db.removeAnnotation('a');
      await files.save(id, []);
      final removed = pdf.PdfDocument.open(await original.readAsBytes());
      expect(removed.page(0).annotations.single.name, 'external-note');
      expect(folder.listSync().map((f) => p.normalize(f.path)), [
        p.normalize(original.path),
      ]);
    },
  );
  test('PDFs iguais em caminhos diferentes têm identidade própria', () async {
    final temp = await Directory.systemTemp.createTemp('reader-identity-');
    final db = ReaderDatabase.memory();
    addTearDown(() async {
      await db.close();
      await temp.delete(recursive: true);
    });
    final bytes = File('${root()}/assets/sample.pdf').readAsBytesSync();
    final first = await File('${temp.path}/primeiro.pdf').writeAsBytes(bytes);
    final second = await File('${temp.path}/segundo.pdf').writeAsBytes(bytes);
    final files = DocumentFiles(Directory('${temp.path}/app'), db);
    final a = await files.open(first.path), b = await files.open(second.path);
    expect(a['id'], isNot(b['id']));
    expect(
      (await files.open(a['path']))['source_path'],
      p.normalize(first.path),
    );
    expect((await files.open(second.path))['id'], b['id']);
  });
  test(
    'Importação antiga vincula original uma vez e mantém as anotações',
    () async {
      final temp = await Directory.systemTemp.createTemp('reader-legacy-');
      final db = ReaderDatabase.memory();
      addTearDown(() async {
        await db.close();
        await temp.delete(recursive: true);
      });
      final bytes = File('${root()}/assets/sample.pdf').readAsBytesSync();
      final id = sha256.convert(bytes).toString();
      final cache = Directory('${temp.path}/app/documents');
      await cache.create(recursive: true);
      final oldCopy = await File('${cache.path}/$id.pdf').writeAsBytes(bytes);
      final original = await File('${temp.path}/original.pdf')
          .writeAsBytes(bytes);
      final wrong = await File('${temp.path}/outro.pdf').writeAsString('outro');
      await db.putDocument(id, oldCopy.path, 'Antigo', 2);
      await db.saveAnnotation({
        'id': 'legacy',
        'documentId': id,
        'pageNumber': 1,
      });
      final files = DocumentFiles(Directory('${temp.path}/app'), db);
      expect((await files.open(oldCopy.path))['source_path'], isNull);
      await expectLater(files.linkOriginal(id, wrong.path), throwsStateError);
      await expectLater(files.linkOriginal(id, oldCopy.path), throwsStateError);
      await files.linkOriginal(id, original.path);
      expect(
        (await db.document(id))!['source_path'],
        p.normalize(original.path),
      );
      expect((await files.open(original.path))['id'], id);
      expect((await db.annotations(id)).single['id'], 'legacy');
      expect(await db.documents(), hasLength(1));
    },
  );
  test('Migração v1 mantém biblioteca, progresso e anotações', () async {
    final temp = await Directory.systemTemp.createTemp('reader-migration-');
    final file = File('${temp.path}/reader.sqlite');
    var db = ReaderDatabase(file);
    await db.putDocument('old', 'cached.pdf', 'Livro antigo', 2);
    await db.progress('old', 2);
    await db.saveAnnotation({'id': 'a', 'documentId': 'old', 'pageNumber': 1});
    await db.close();
    final raw = sqlite.sqlite3.open(file.path);
    raw.execute('ALTER TABLE documents DROP COLUMN source_path');
    raw.execute('ALTER TABLE documents DROP COLUMN source_hash');
    raw.execute('PRAGMA user_version=1');
    raw.close();
    db = ReaderDatabase(file);
    addTearDown(() async {
      await db.close();
      await temp.delete(recursive: true);
    });
    expect((await db.documents()).single['progress'], 2);
    expect((await db.document('old'))!['source_path'], isNull);
    expect(await db.annotations('old'), hasLength(1));
    await db.linkSource('old', 'original.pdf', 'hash');
    expect((await db.document('old'))!['source_hash'], 'hash');
  });
  test(
    'Mudança externa é preservada e pede reabertura antes de salvar',
    () async {
      final temp = await Directory.systemTemp.createTemp('reader-conflict-');
      final db = ReaderDatabase.memory();
      addTearDown(() async {
        await db.close();
        await temp.delete(recursive: true);
      });
      final original = await File('${temp.path}/original.pdf')
          .writeAsBytes(File('${root()}/assets/sample.pdf').readAsBytesSync());
      final files = DocumentFiles(Directory('${temp.path}/app'), db);
      final book = await files.open(original.path);
      final editor = pdf.PdfEditor(
        pdf.PdfDocument.open(await original.readAsBytes()),
      );
      editor.addFreeText(
        0,
        const pdf.PdfRect(40, 40, 160, 60),
        'Edição externa',
      );
      final external = editor.save();
      await original.writeAsBytes(external);
      await expectLater(files.save(book['id'], []), throwsStateError);
      expect(await original.readAsBytes(), external);
      expect(
        temp.listSync().whereType<File>().map((f) => p.normalize(f.path)),
        [p.normalize(original.path)],
      );
      await files.open(original.path);
      await files.save(book['id'], []);
      expect(
        pdf.PdfDocument.open(await original.readAsBytes()).page(0).annotations,
        hasLength(1),
      );
    },
  );
  if (Platform.isWindows) {
    test('Arquivo bloqueado: falha atômica preserva original e limpa temporário', () async {
      final temp = await Directory.systemTemp.createTemp('reader-locked-');
      final db = ReaderDatabase.memory();
      addTearDown(() async {
        await db.close();
        await temp.delete(recursive: true);
      });
      final bytes = File('${root()}/assets/sample.pdf').readAsBytesSync();
      final original = await File('${temp.path}/original.pdf')
          .writeAsBytes(bytes);
      final files = DocumentFiles(Directory('${temp.path}/app'), db);
      final book = await files.open(original.path);
      final quoted = original.path.replaceAll("'", "''");
      final ready = File('${temp.path}/app/lock-ready');
      final release = File('${temp.path}/app/lock-release');
      final readyPath = ready.path.replaceAll("'", "''");
      final releasePath = release.path.replaceAll("'", "''");
      final holder = await Process.start('powershell', [
        '-NoProfile',
        '-NonInteractive',
        '-WindowStyle',
        'Hidden',
        '-Command',
        "\$handle = [IO.File]::Open('$quoted', [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read); try { [IO.File]::WriteAllText('$readyPath', 'ready'); while (-not [IO.File]::Exists('$releasePath')) { Start-Sleep -Milliseconds 50 } } finally { \$handle.Dispose() }",
      ]);
      final stdoutDone = holder.stdout.drain<void>();
      final stderrDone = holder.stderr.drain<void>();
      try {
        final timer = Stopwatch()..start();
        while (!await ready.exists() && timer.elapsed.inSeconds < 10) {
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
        expect(await ready.exists(), true);
        await expectLater(
          files.save(book['id'], []),
          throwsA(isA<FileSystemException>()),
        );
        expect(await original.readAsBytes(), bytes);
        expect(
          temp.listSync().whereType<File>().map((f) => p.normalize(f.path)),
          [p.normalize(original.path)],
        );
      } finally {
        await release.writeAsString('release');
        await holder.exitCode.timeout(
          const Duration(seconds: 5),
          onTimeout: () {
            holder.kill();
            return -1;
          },
        );
        await Future.wait([stdoutDone, stderrDone]);
      }
    });
  }
  test('Retirar marcação afeta apenas faixas sobrepostas da mesma página', () {
    final items = <Map<String, dynamic>>[
      {
        'id': 'left',
        'pageNumber': 1,
        'charRange': [0, 5],
      },
      {
        'id': 'target',
        'pageNumber': 1,
        'charRange': [5, 15],
      },
      {
        'id': 'right',
        'pageNumber': 1,
        'charRange': [15, 20],
      },
      {
        'id': 'other-page',
        'pageNumber': 2,
        'charRange': [5, 15],
      },
      {'id': 'no-range', 'pageNumber': 1},
    ];
    expect(annotationsInRange(items, 1, 5, 15).map((a) => a['id']), ['target']);
    expect(annotationsInRange(items, 1, 8, 9).map((a) => a['id']), ['target']);
    expect(annotationsInRange(items, 1, 4, 16).map((a) => a['id']), [
      'left',
      'target',
      'right',
    ]);
    expect(annotationsInRange(items, 1, 3, 3), isEmpty);
    expect(annotationsInRange(items, 1, -1, 3), isEmpty);
  });
  test('exportar reabre com Highlight/FreeText sem rasterizar texto', () async {
    final source = File('${root()}/assets/sample.pdf').readAsBytesSync();
    final output = exportAnnotated(source, [
      {
        'id': 'a',
        'pageNumber': 1,
        'color': 0xffffd54f,
        'quadPointsPdf': [
          [48, 700, 90, 714],
        ],
        'labelBox': [48, 715, 150, 730],
        'labelFontSize': 8,
        'shortTranslation': 'ação: desistir',
      },
    ]);
    final doc = pdf.PdfDocument.open(output);
    expect(doc.pageCount, 2);
    final highlight = doc
        .page(0)
        .annotations
        .firstWhere((annotation) => annotation.subtype == 'Highlight');
    expect(highlight.appearanceOpacity, closeTo(0.85, 0.001));
    expect(output.length, greaterThan(source.length));
    final raw = latin1.decode(output);
    expect(raw, contains('/Highlight'));
    expect(raw, contains('/FreeText'));
    expect(raw, contains('/Multiply'));
    expect(output.take(source.length).toList(), source);
    final dir = Directory(
      root() == ' .'
          ? '../output/pdf'
          : root() == '.'
          ? '../output/pdf'
          : '../../output/pdf',
    );
    await dir.create(recursive: true);
    await File('${dir.path}/exportado-teste.pdf').writeAsBytes(output);
  });
  test('exportação impede sobrescrever original', () async {
    await expectLater(
      exportCopy('same.pdf', 'same.pdf', []),
      throwsArgumentError,
    );
  });
  test('CSV escapa aspas e quebras de linha', () {
    final csv = measurementsCsv([
      {'sentenceOriginal': 'He said "hello".\nNext.'},
    ]);
    expect(csv, contains('""hello""'));
  });
  test('indisponibilidade não conta como abstenção correta', () {
    expect(
      decisionCorrect(
        {'expectedAbstention': true},
        Decision(
          mode: 'B',
          status: 'Modelo indisponível',
          evidence: [],
          decisionMs: 0,
        ),
      ),
      false,
    );
  });
}
