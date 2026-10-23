import 'dart:math' as math;

import '../../core/nlp/pipeline.dart';

bool decisionCorrect(Map<String, dynamic> fixture, Decision? d) {
  if (d == null ||
      d.status == 'Modelo indisponível' ||
      d.status == 'Erro no encoder') {
    return false;
  }
  if (fixture['expectedAbstention'] == true) return d.shortTranslation == null;
  return d.shortTranslation != null &&
      (fixture['acceptableTranslationsPtBr'] as List).any(
        (s) => normalize(s) == normalize(d.shortTranslation!),
      );
}

Future<List<Map<String, dynamic>>> evaluate(
  TranslationOrchestrator pipeline,
  List<Map<String, dynamic>> fixtures, {
  void Function(int, int)? progress,
}) async {
  final rows = <Map<String, dynamic>>[];
  for (final (i, f) in fixtures.indexed) {
    final c = SelectionContext(f['sentence'], f['start'], f['end']);
    final result = await pipeline.run(
      c,
      TranslationMode.compare,
      useCache: false,
    );
    rows.add({
      ...f,
      ...result.toJson(),
      'correctA': decisionCorrect(f, result.a),
      'correctB': decisionCorrect(f, result.b),
      'expressionCorrect':
          normalize(result.expression.lemma) ==
          normalize(f['expectedExpression']),
    });
    progress?.call(i + 1, fixtures.length);
  }
  return rows;
}

double percentile(List<double> values, double p) {
  if (values.isEmpty) return 0;
  final sorted = [...values]..sort();
  return sorted[(p * (sorted.length - 1)).round()];
}

Map<String, dynamic> summarize(List<Map<String, dynamic>> rows) {
  final n = rows.length;
  Map<String, dynamic> mode(String mode) {
    final available = rows
        .where(
          (r) =>
              r[mode] != null &&
              ![
                'Modelo indisponível',
                'Erro no encoder',
              ].contains(r[mode]['status']),
        )
        .toList();
    final times = available
        .map((r) => (r[mode]['decisionMs'] as num).toDouble())
        .toList();
    final labeled = available.where((r) => r['expectedSense'] != null).toList();
    return {
      'available': available.length,
      'correct': rows.where((r) => r['correct$mode'] == true).length,
      'accuracy': n == 0
          ? null
          : rows.where((r) => r['correct$mode'] == true).length / n,
      'abstentions': available
          .where((r) => r[mode]['shortTranslation'] == null)
          .length,
      'senseCorrect': labeled
          .where((r) => r[mode]['senseId'] == r['expectedSense'])
          .length,
      'senseLabeled': labeled.length,
      'decisionP50Ms': percentile(times, 0.5),
      'decisionP95Ms': percentile(times, 0.95),
      'calibratedConfidence': false,
      'highConfidenceErrors': null,
    };
  }

  final gains = rows
      .where((r) => r['correctB'] == true && r['correctA'] != true)
      .length;
  final losses = rows
      .where((r) => r['correctA'] == true && r['correctB'] != true)
      .length;
  final categories = rows.map((r) => r['category'] as String).toSet();
  return {
    'n': n,
    'A': mode('A'),
    'B': mode('B'),
    'gainsB': gains,
    'lossesB': losses,
    'expressionCorrect': rows
        .where((r) => r['expressionCorrect'] == true)
        .length,
    'alignmentAccuracy': null,
    'alignmentReason': 'Sem rótulos humanos independentes de alinhamento de spans PT; presença lexical não prova alinhamento',
    'translationP50Ms': percentile(
      rows.map((r) => (r['translationMs'] as num).toDouble()).toList(),
      0.5,
    ),
    'translationP95Ms': percentile(
      rows.map((r) => (r['translationMs'] as num).toDouble()).toList(),
      0.95,
    ),
    'pairedNetAccuracyDifference': n == 0 ? null : (gains - losses) / n,
    'pairedStandardError': n < 2
        ? null
        : math.sqrt(
            ((gains + losses) / n - math.pow((gains - losses) / n, 2)) /
                (n - 1),
          ),
    'categories': {
      for (final cat in categories)
        cat: {
          'n': rows.where((r) => r['category'] == cat).length,
          'A': rows
              .where((r) => r['category'] == cat && r['correctA'] == true)
              .length,
          'B': rows
              .where((r) => r['category'] == cat && r['correctB'] == true)
              .length,
        },
    },
    'provenance': 'Fixtures autorais do agente; revisão humana pendente; sem calibração/tuning nos rótulos de teste',
  };
}

String measurementsCsv(List<Map<String, dynamic>> rows) {
  String quote(Object? v) => '"${(v ?? '').toString().replaceAll('"', '""')}"';
  const fields = [
    'id',
    'category',
    'sentenceOriginal',
    'detectedExpression',
    'correctA',
    'correctB',
    'translationMs',
  ];
  return '${[...fields, 'translationA', 'translationB', 'decisionA_ms', 'decisionB_ms'].join(',')}\n${rows.map((r) => [...fields.map((f) => quote(r[f])), quote(r['A']?['shortTranslation']), quote(r['B']?['shortTranslation']), quote(r['A']?['decisionMs']), quote(r['B']?['decisionMs'])].join(',')).join('\n')}\n';
}
