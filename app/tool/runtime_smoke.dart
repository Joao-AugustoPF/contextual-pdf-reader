import 'dart:convert';
import 'dart:io';

import 'package:contextual_pdf_reader/core/inference/sidecar.dart';

Future<void> main(List<String> args) async {
  final root = Directory(args.isEmpty ? '..' : args.first).absolute.path;
  final engine = SidecarEngine(
    '$root/.venv/${Platform.isWindows ? 'Scripts/python.exe' : 'bin/python'}',
    [
      '$root/ml/runtime.py',
      '--models',
      '$root/models',
      '--manifest',
      '$root/ml/manifests/models.lock.json',
    ],
  );
  try {
    await engine.translateSentence('Turn on the light.');
    final basic = await engine.request({'op': 'status'});
    if (basic['encoderCalls'] != 0 || basic['onnxImported'] != false) {
      throw StateError('A carregou ONNX');
    }
    await engine.dispose();
    final restarted = await engine.request({'op': 'status'});
    if (restarted['translationCalls'] != 0) {
      throw StateError('Processo não reiniciou');
    }
    const sentence = '😀 Turn on the light.';
    final start = sentence.indexOf('light');
    final vector = await engine.encode(sentence, start, start + 5);
    if (vector.length != 384) throw StateError('Saída de tokens inválida');
    final cpStart = sentence.substring(0, start).runes.length;
    final reference = await engine.request({
      'op': 'embed',
      'sentence': sentence,
      'start': cpStart,
      'end': cpStart + 5,
    });
    if (jsonEncode(reference['offsets']) !=
        jsonEncode([
          [cpStart, cpStart + 5],
        ])) {
      throw StateError('Offsets do alvo incorretos');
    }
    final expected = List<num>.from(reference['vector']);
    for (var i = 0; i < vector.length; i++) {
      if ((vector[i] - expected[i]).abs() > 1e-7) {
        throw StateError('Conversão UTF-16 alterou o alvo');
      }
    }
    await engine.unload();
    final summary = {
      'basicEncoderCalls': basic['encoderCalls'],
      'basicOnnxImported': basic['onnxImported'],
      'restartVerified': true,
      'unicodeUtf16OffsetVerified': true,
      'hiddenDimensions': vector.length,
    };
    await File('$root/reports/runtime-smoke.json')
        .writeAsString(jsonEncode(summary));
    stdout.writeln(jsonEncode(summary));
  } finally {
    await engine.dispose();
  }
}
