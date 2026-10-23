import 'dart:convert';
import 'dart:io';

import 'package:contextual_pdf_reader/core/inference/sidecar.dart';
import 'package:contextual_pdf_reader/core/nlp/pipeline.dart';
import 'package:contextual_pdf_reader/features/experiment/evaluation.dart';

Future<void> main(List<String> args) async {
  final root = Directory(args.isEmpty ? '..' : args.first).absolute.path;
  final sidecar = SidecarEngine(
    '$root/.venv/${Platform.isWindows ? 'Scripts/python.exe' : 'bin/python'}',
    [
      '$root/ml/runtime.py',
      '--models',
      '$root/models',
      '--manifest',
      '$root/ml/manifests/models.lock.json',
    ],
  );
  final lex = jsonDecode(
    await File('$root/app/assets/lexicon.json').readAsString(),
  ) as Map<String, dynamic>;
  final fixtures = List<Map<String, dynamic>>.from(
    jsonDecode(await File('$root/ml/datasets/evaluation.json').readAsString()),
  );
  final pipeline = TranslationOrchestrator(sidecar, sidecar, lex);
  try {
    final initial = await sidecar.request({'op': 'status'});
    final f = fixtures.first,
        c = SelectionContext(f['sentence'], f['start'], f['end']);
    final basic = await pipeline.run(c, TranslationMode.basic, useCache: false);
    final afterA = await sidecar.request({'op': 'status'});
    if (afterA['encoderCalls'] != 0 || afterA['onnxImported'] != false) {
      throw StateError('Modo A violou isolamento');
    }
    final cold = await pipeline.run(
      c,
      TranslationMode.compare,
      useCache: false,
    );
    final afterCold = await sidecar.request({'op': 'status'});
    final rows = await evaluate(
      pipeline,
      fixtures,
      progress: (i, n) {
        if (i % 8 == 0) stdout.writeln('$i/$n');
      },
    );
    final warm = await pipeline.run(
      c,
      TranslationMode.compare,
      useCache: false,
    );
    final miss = await pipeline.run(c, TranslationMode.compare);
    final hit = await pipeline.run(c, TranslationMode.compare);
    final report = {
      'environment': {
        'os': Platform.operatingSystemVersion,
        'dart': Platform.version,
        'device': 'host CPU; não Android',
        'network':
            'socket.connect e getaddrinfo proibidos por audit hook no sidecar',
        'date': DateTime.now().toUtc().toIso8601String(),
      },
      'summary': summarize(rows),
      'initial': initial,
      'afterA': afterA,
      'afterCold': afterCold,
      'final': await sidecar.request({'op': 'status'}),
      'basicFirst': basic.toJson(),
      'coldEncoder': cold.toJson(),
      'warm': warm.toJson(),
      'cacheMiss': miss.toJson(),
      'cacheHit': hit.toJson(),
      'modelManifest': jsonDecode(
        await File('$root/ml/manifests/models.lock.json').readAsString(),
      ),
      'samples': rows,
    };
    final out = Directory('$root/reports');
    await out.create(recursive: true);
    await File('${out.path}/benchmark.json')
        .writeAsString(const JsonEncoder.withIndent('  ').convert(report));
    await File('${out.path}/benchmark.csv')
        .writeAsString(measurementsCsv(rows));
    stdout.writeln(
      const JsonEncoder.withIndent('  ').convert(report['summary']),
    );
  } finally {
    await sidecar.dispose();
  }
}
