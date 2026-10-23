import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_onnxruntime/flutter_onnxruntime.dart';
import 'package:google_mlkit_translation/google_mlkit_translation.dart';

import '../nlp/pipeline.dart';
import '../nlp/wordpiece.dart';

class MlKitEngine implements OfflineTranslationEngine {
  final manager = OnDeviceTranslatorModelManager();
  OnDeviceTranslator? _translator;
  @override
  String get id => 'google-mlkit-en-pt-sdk-0.15.1';
  @override
  bool get isSupported => Platform.isAndroid || Platform.isIOS;
  @override
  Future<bool> isModelReady() async =>
      isSupported &&
      await manager.isModelDownloaded('en') &&
      await manager.isModelDownloaded('pt');
  @override
  Future<List<String>> listInstalledModels() async => [
    for (final l in ['en', 'pt'])
      if (await manager.isModelDownloaded(l)) l,
  ];
  @override
  Future<void> downloadModelsWithConsent({
    required bool consent,
    bool wifiOnly = true,
  }) async {
    if (!consent) throw StateError('Download exige consentimento');
    for (final lang in ['en', 'pt']) {
      if (!await manager.downloadModel(lang, isWifiRequired: wifiOnly)) {
        throw StateError('Falha no download ML Kit: $lang');
      }
    }
  }

  Future<void> removeModels() async {
    await dispose();
    for (final lang in ['en', 'pt']) {
      await manager.deleteModel(lang);
    }
  }

  @override
  Future<String> translateSentence(String text) async {
    if (!await isModelReady()) {
      throw StateError('Modelo de tradução não instalado; abra Preferências');
    }
    _translator ??= OnDeviceTranslator(
      sourceLanguage: TranslateLanguage.english,
      targetLanguage: TranslateLanguage.portuguese,
    );
    return _translator!.translateText(text);
  }

  @override
  Future<void> dispose() async {
    await _translator?.close();
    _translator = null;
  }
}

class MobileMiniLm implements SpanEncoder {
  MobileMiniLm(this.directory, this.expectedHash, {this.verifyFiles});
  final String directory, expectedHash;
  final Future<void> Function()? verifyFiles;
  OrtSession? _session;
  WordPieceTokenizer? _tokenizer;
  Timer? _idle;
  // Serializa inferência e descarregamento; plugin executa em worker nativo.
  Future<void> _queue = Future.value();
  @override
  Future<bool> isReady() async =>
      File('$directory/model.onnx').existsSync() &&
      File('$directory/vocab.txt').existsSync();
  @override
  Future<List<double>> encode(String sentence, int start, int end) {
    final c = Completer<List<double>>();
    _queue = _queue.then((_) async {
      try {
        c.complete(await _encode(sentence, start, end));
      } catch (e, s) {
        c.completeError(e, s);
      }
    });
    return c.future;
  }

  Future<List<double>> _encode(String sentence, int start, int end) async {
    _idle?.cancel();
    if (_session == null) {
      await verifyFiles?.call();
      final file = File('$directory/model.onnx');
      final digest = await sha256.bind(file.openRead()).first;
      if (digest.toString() != expectedHash) {
        throw StateError('MiniLM corrompido: SHA-256 inválido');
      }
      _tokenizer = WordPieceTokenizer(
        await File('$directory/vocab.txt').readAsString(),
        padTo:
            (jsonDecode(
                  await File('$directory/tokenizer.json').readAsString(),
                )['padding']?['strategy']?['Fixed']
                as int?) ??
            0,
      );
      _session = await OnnxRuntime().createSession(
        file.path,
        options: OrtSessionOptions(intraOpNumThreads: 2, interOpNumThreads: 1),
      );
    }
    final tokens = _tokenizer!.tokenize(sentence);
    final indices = [
      for (var i = 0; i < tokens.length; i++)
        if (tokens[i].start < end && tokens[i].end > start) i,
    ];
    if (indices.isEmpty || tokens.map((t) => t.end).reduce(math.max) < end) {
      throw StateError('Alvo truncado ou sem tokens');
    }
    final inputs = <String, OrtValue>{};
    final outputs = <String, OrtValue>{};
    try {
      for (final name in _session!.inputNames) {
        final data = name == 'input_ids'
            ? tokens.map((t) => t.id).toList()
            : tokens
                  .map((t) => name == 'attention_mask' && t.id != 0 ? 1 : 0)
                  .toList();
        inputs[name] = await OrtValue.fromList(Int64List.fromList(data), [
          1,
          tokens.length,
        ]);
      }
      outputs.addAll(await _session!.run(inputs));
      final hidden = await outputs.values.first.asList();
      final rows = hidden[0] as List;
      final first = rows[indices.first] as List;
      final vector = List.generate(
        first.length,
        (i) =>
            indices
                .map((j) => (rows[j][i] as num).toDouble())
                .reduce((a, b) => a + b) /
            indices.length,
      );
      final norm = math.sqrt(vector.fold(0.0, (a, b) => a + b * b));
      return vector.map((x) => x / math.max(norm, 1e-12)).toList();
    } finally {
      for (final v in inputs.values) {
        await v.dispose();
      }
      for (final v in outputs.values) {
        await v.dispose();
      }
      _idle = Timer(const Duration(minutes: 2), () {
        unawaited(unload());
      });
    }
  }

  @override
  Future<void> unload() {
    _idle?.cancel();
    _queue = _queue.then((_) async {
      await _session?.close();
      _session = null;
      _tokenizer = null;
    });
    return _queue;
  }
}
