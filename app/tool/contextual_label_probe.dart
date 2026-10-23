import 'dart:convert';
import 'dart:io';

import 'package:contextual_pdf_reader/core/inference/sidecar.dart';
import 'package:contextual_pdf_reader/core/nlp/contextual_suggestion.dart';
import 'package:contextual_pdf_reader/core/nlp/pipeline.dart';

Future<void> main(List<String> args) async {
  final root = Directory(args.isEmpty ? '..' : args.first).absolute.path;
  final engine = SidecarEngine(
    '$root/app/build/windows/x64/runner/Release/runtime/reader-runtime.exe',
    [
      '--models',
      '$root/models',
      '--manifest',
      '$root/ml/manifests/models.lock.json',
    ],
  );
  final lex = jsonDecode(
    await File('$root/app/assets/lexicon.json').readAsString(),
  ) as Map<String, dynamic>;
  final pipeline = TranslationOrchestrator(engine, engine, lex);
  const paragraph =
      'Because components often nest within one another, each component in the domain-partitioned architecture shown in Figure 9-3 (for example, CatalogCheckout) may use a persistence library and have a separate layer for business rules, but the top-level partitioning will still revolve around domains.';
  final cases = [
    ('software_nest', paragraph, 'nest'),
    ('software_revolve', paragraph, 'revolve'),
    ('noun_nest', 'The bird built a nest in the tree.', 'nest'),
    ('birds_nest', 'The birds nest in the tree.', 'nest'),
    ('components_nest', 'These components nest within one another.', 'nest'),
    (
      'rippling',
      'Because everything is coupled to everything else, changes tend to have hard-to-predict rippling side effects.',
      'rippling',
    ),
  ];
  final rows = <Map<String, dynamic>>[];
  try {
    for (final (id, text, word) in cases) {
      final start = text.indexOf(word);
      final comparison = await pipeline.run(
        SelectionContext(text, start, start + word.length),
        TranslationMode.contextual,
      );
      final old = await engine.translateSentence(word);
      final suggestion = await suggestSelectionInContext(engine, comparison);
      final row = {
        'id': id,
        'word': word,
        'sentence': text,
        'sentenceTranslated': comparison.translated,
        'isolatedTranslationBefore': old,
        'suggestionAfter': suggestion.toJson(),
        'B': comparison.b?.toJson(),
      };
      rows.add(row);
      stdout.writeln(jsonEncode(row));
    }
    await File('$root/reports/windows-contextual-labels.json').writeAsString(
      const JsonEncoder.withIndent('  ').convert({
        'cases': rows,
        'runtimeStatus': await engine.request({'op': 'status'}),
        'evaluationGoldUsed': false,
        'remoteInferenceUsed': false,
      }),
    );
  } finally {
    await engine.dispose();
  }
}
