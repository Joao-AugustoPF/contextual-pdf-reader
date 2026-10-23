import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../core/inference/mobile.dart';
import '../core/inference/model_store.dart';
import '../core/inference/sidecar.dart';
import '../core/nlp/pipeline.dart';
import '../core/persistence/database.dart';

final servicesProvider = Provider<AppServices>(
  (ref) => throw StateError('Inicialize os serviços'),
);

class AppServices {
  AppServices(
    this.directory,
    this.db,
    this.models,
    this.translator,
    this.encoder,
    this.pipeline,
  );
  final Directory directory;
  final ReaderDatabase db;
  final ModelStore models;
  final OfflineTranslationEngine translator;
  final SpanEncoder encoder;
  final TranslationOrchestrator pipeline;
  static Future<AppServices> create() async {
    final dir = await getApplicationSupportDirectory();
    await dir.create(recursive: true);
    final db = ReaderDatabase(File('${dir.path}/reader.sqlite'));
    final manifest = jsonDecode(
      await rootBundle.loadString('assets/models.lock.json'),
    ) as Map<String, dynamic>;
    const devRoot = String.fromEnvironment('READER_ROOT');
    final modelRoot = Directory(
      devRoot.isNotEmpty && !Platform.isAndroid && !Platform.isIOS
          ? '$devRoot/models'
          : '${dir.path}/models',
    );
    final models = ModelStore(modelRoot, manifest);
    final lock = await models.writeManifest();
    late OfflineTranslationEngine translator;
    late SpanEncoder encoder;
    if (Platform.isAndroid || Platform.isIOS) {
      translator = MlKitEngine();
      final hash =
          models
                  .entries('minilm')
                  .firstWhere((e) => e['file'].endsWith('model.onnx'))['sha256']
              as String;
      encoder = MobileMiniLm(
        '${modelRoot.path}/minilm',
        hash,
        verifyFiles: () => models.verify('minilm'),
      );
    } else {
      final exe = devRoot.isEmpty
          ? '${File(Platform.resolvedExecutable).parent.path}/runtime/reader-runtime${Platform.isWindows ? '.exe' : ''}'
          : '$devRoot/.venv/${Platform.isWindows ? 'Scripts/python.exe' : 'bin/python'}';
      final sidecar = SidecarEngine(exe, [
        if (devRoot.isNotEmpty) '$devRoot/ml/runtime.py',
        '--models',
        modelRoot.path,
        '--manifest',
        lock.path,
      ], installModels: () => models.install('translator', consent: true));
      translator = sidecar;
      encoder = sidecar;
    }
    final lexicon = jsonDecode(
      await rootBundle.loadString('assets/lexicon.json'),
    ) as Map<String, dynamic>;
    final pipeline = TranslationOrchestrator(translator, encoder, lexicon);
    pipeline.sentenceCache.addAll(await db.loadCache(translator.id));
    return AppServices(dir, db, models, translator, encoder, pipeline);
  }

  Future<void> flushCache() async {
    await db.transaction(() async {
      for (final e in pipeline.sentenceCache.entries) {
        await db.cache(e.key, translator.id, e.value);
      }
    });
  }
}
