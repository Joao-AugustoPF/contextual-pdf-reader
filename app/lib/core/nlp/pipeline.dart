import 'dart:async';
import 'dart:math' as math;

enum TranslationMode { basic, contextual, compare }

abstract interface class OfflineTranslationEngine {
  String get id;
  bool get isSupported;
  Future<bool> isModelReady();
  Future<List<String>> listInstalledModels();
  Future<void> downloadModelsWithConsent({
    required bool consent,
    bool wifiOnly = true,
  });
  Future<String> translateSentence(String text);
  Future<void> dispose();
}

abstract interface class SpanEncoder {
  Future<bool> isReady();
  Future<List<double>> encode(String sentence, int start, int end);
  Future<void> unload();
}

class SelectionContext {
  const SelectionContext(this.sentence, this.start, this.end);
  final String sentence;
  final int start, end;
  String get selectedText => sentence.substring(start, end);
  static SelectionContext fromPage(String page, int start, int end) {
    if (start < 0 || end <= start || end > page.length) {
      throw ArgumentError('Seleção inválida');
    }
    var left = 0, right = page.length;
    final boundaries = RegExp(r'[.!?]+[\s"”]+');
    for (final m in boundaries.allMatches(page)) {
      final before = page
          .substring(math.max(0, m.start - 4), m.start + 1)
          .toLowerCase();
      if (RegExp(r'(mr\.|mrs\.|dr\.|e\.g\.|i\.e\.)$').hasMatch(before)) {
        continue;
      }
      if (m.end <= start) left = m.end;
      if (m.start >= end) {
        right = m.start + 1;
        break;
      }
    }
    // Não corta o alvo; contexto excessivo exige ajuste explícito.
    return SelectionContext(
      page.substring(left, right),
      start - left,
      end - left,
    );
  }
}

class Expression {
  const Expression(this.lemma, this.start, this.end, this.tokenSpans);
  final String lemma;
  final int start, end;
  // Phrasal verbs separáveis preservam apenas tokens da unidade, sem o objeto.
  final List<(int, int)> tokenSpans;
}

String lemmaOf(String word) {
  final w = word.toLowerCase();
  const irregular = {
    'gave': 'give',
    'given': 'give',
    'ran': 'run',
    'running': 'run',
    'built': 'build',
    'giving': 'give',
    'setting': 'set',
  };
  if (irregular.containsKey(w)) return irregular[w]!;
  if (w.endsWith('ed')) return w.substring(0, w.length - 2);
  if (w.endsWith('s') && w.length > 3) return w.substring(0, w.length - 1);
  return w;
}

Expression recognize(SelectionContext c, Map<String, dynamic> lexicon) {
  final tokens = RegExp(r"[A-Za-z]+(?:-[A-Za-z]+)*")
      .allMatches(c.sentence)
      .toList();
  final selected = tokens
      .where((t) => t.start < c.end && t.end > c.start)
      .toList();
  if (selected.isEmpty) {
    return Expression(c.selectedText.toLowerCase(), c.start, c.end, [
      (c.start, c.end),
    ]);
  }
  final candidates = <Expression>[];
  for (final phrase in lexicon.keys) {
    final parts = phrase.split(' ');
    for (var i = 0; i < tokens.length; i++) {
      if (lemmaOf(tokens[i].group(0)!) != parts.first.toLowerCase()) continue;
      final indices = <int>[i];
      for (var j = 1; j < parts.length; j++) {
        final prev = indices.last;
        var found = -1;
        final gap =
            (parts.length == 2 &&
                ['give', 'look', 'set', 'turn'].contains(parts.first))
            ? 4
            : 1;
        for (
          var k = prev + 1;
          k < math.min(tokens.length, prev + gap + 1);
          k++
        ) {
          if (lemmaOf(tokens[k].group(0)!) == parts[j]) {
            found = k;
            break;
          }
        }
        if (found < 0) break;
        indices.add(found);
      }
      if (indices.length != parts.length) continue;
      final first = tokens[indices.first], last = tokens[indices.last];
      if (first.start > c.start || last.end < c.end) continue;
      // Seleção só pode tocar um token da unidade, não apenas seu objeto.
      if (!indices.any(
        (i) => tokens[i].start < c.end && tokens[i].end > c.start,
      )) {
        continue;
      }
      candidates.add(
        Expression(phrase, first.start, last.end, [
          for (final i in indices) (tokens[i].start, tokens[i].end),
        ]),
      );
    }
  }
  candidates.sort((a, b) => b.tokenSpans.length.compareTo(a.tokenSpans.length));
  return candidates.isEmpty
      ? Expression(c.selectedText.toLowerCase(), c.start, c.end, [
          (c.start, c.end),
        ])
      : candidates.first;
}

String normalize(String text) {
  var s = text.toLowerCase();
  const accents = {
    'á': 'a',
    'à': 'a',
    'ã': 'a',
    'â': 'a',
    'é': 'e',
    'ê': 'e',
    'í': 'i',
    'ó': 'o',
    'ô': 'o',
    'õ': 'o',
    'ú': 'u',
    'ç': 'c',
  };
  accents.forEach((a, b) => s = s.replaceAll(a, b));
  return s.replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();
}

class Candidate {
  Candidate(this.senseId, this.translations, this.prototypes);
  final String senseId;
  final List<String> translations;
  final List<Map<String, dynamic>> prototypes;
  factory Candidate.fromJson(Map<String, dynamic> j) => Candidate(
    j['senseId'],
    List<String>.from(j['translations']),
    List<Map<String, dynamic>>.from(j['prototypes']),
  );
  String? align(String sentence) {
    final normalized = ' ${normalize(sentence)} ';
    for (final pt in translations) {
      if (normalized.contains(' ${normalize(pt)} ')) return pt;
    }
    // Flexões são evidência fraca: preserva a forma traduzida e registra como tal.
    for (final pt in translations.where(
      (s) => !s.contains(' ') && s.length > 5,
    )) {
      final stem = normalize(pt).substring(0, pt.length - 2);
      for (final word in normalize(sentence).split(' ')) {
        if (word.startsWith(stem) && word.length >= stem.length) return word;
      }
    }
    return null;
  }
}

class Decision {
  Decision({
    required this.mode,
    required this.status,
    this.shortTranslation,
    this.senseId,
    this.score,
    required this.evidence,
    required this.decisionMs,
    this.ranking = const [],
  });
  final String mode, status;
  final String? shortTranslation, senseId;
  final double? score;
  final List<String> evidence;
  final double decisionMs;
  final List<Map<String, dynamic>> ranking;
  Map<String, dynamic> toJson() => {
    'mode': mode,
    'status': status,
    'shortTranslation': shortTranslation,
    'senseId': senseId,
    'semanticScore': score,
    'confidence': null,
    'meaningResolved': senseId != null,
    'alignmentResolved': shortTranslation != null,
    'alignmentEvidence': evidence,
    'decisionMs': decisionMs,
    'ranking': ranking,
  };
}

class Comparison {
  Comparison(
    this.context,
    this.expression,
    this.translated,
    this.candidates,
    this.a,
    this.b,
    this.translationMs,
    this.cacheHit,
    this.totalMs,
  );
  final SelectionContext context;
  final Expression expression;
  final String translated;
  final List<Candidate> candidates;
  final Decision? a, b;
  final double translationMs, totalMs;
  final bool cacheHit;
  Map<String, dynamic> toJson() => {
    'sentenceOriginal': context.sentence,
    'sentenceTranslated': translated,
    'originalSpan': [context.start, context.end],
    'detectedExpression': expression.lemma,
    'expressionSpan': [expression.start, expression.end],
    'tokenSpans': [
      for (final s in expression.tokenSpans) [s.$1, s.$2],
    ],
    'candidateTranslations': [
      for (final c in candidates)
        {'senseId': c.senseId, 'translations': c.translations},
    ],
    'A': a?.toJson(),
    'B': b?.toJson(),
    'translationMs': translationMs,
    'totalMs': totalMs,
    'cacheHit': cacheHit,
  };
}

class TranslationOrchestrator {
  TranslationOrchestrator(this.translator, this.encoder, this.lexicon);
  final OfflineTranslationEngine translator;
  final SpanEncoder encoder;
  final Map<String, dynamic> lexicon;
  final Map<String, String> sentenceCache = {};
  final Map<String, List<double>> prototypeCache = {};
  int _generation = 0;
  void cancel() => _generation++;
  Future<Comparison> run(
    SelectionContext context,
    TranslationMode mode, {
    bool useCache = true,
  }) async {
    final generation = ++_generation;
    final total = Stopwatch()..start();
    final expression = recognize(context, lexicon);
    final candidates = [
      for (final j in (lexicon[expression.lemma] as List? ?? []))
        Candidate.fromJson(Map<String, dynamic>.from(j)),
    ];
    final key = '${translator.id}|en|pt-BR|${context.sentence}';
    final hit = useCache && sentenceCache.containsKey(key);
    final tw = Stopwatch()..start();
    final translated = hit
        ? sentenceCache[key]!
        : await translator.translateSentence(context.sentence);
    if (useCache) sentenceCache[key] = translated;
    final translationMs = tw.elapsedMicroseconds / 1000;
    if (generation != _generation) {
      throw StateError('Seleção substituída; operação cancelada');
    }
    Decision? a, b;
    if (mode != TranslationMode.contextual) a = _basic(candidates, translated);
    if (mode != TranslationMode.basic) {
      final bw = Stopwatch()..start();
      if (!await encoder.isReady()) {
        b = Decision(
          mode: 'B',
          status: 'Modelo indisponível',
          evidence: [
            'Instale o MiniLM; nenhuma inferência contextual executada',
          ],
          decisionMs: bw.elapsedMicroseconds / 1000,
        );
      } else {
        try {
          // Encoder é executado mesmo se o léxico não cobrir o alvo: não simula B.
          final parts = <List<double>>[];
          for (final span in expression.tokenSpans) {
            parts.add(await encoder.encode(context.sentence, span.$1, span.$2));
          }
          final target = _mean(parts);
          final ranked = <({Candidate c, double score})>[];
          for (final c in candidates) {
            final scores = <double>[];
            for (final p in c.prototypes) {
              final pk = '${p['sentence']}|${p['start']}|${p['end']}';
              final vector = prototypeCache[pk] ??= await encoder.encode(
                p['sentence'],
                p['start'],
                p['end'],
              );
              scores.add(_cosine(target, vector));
            }
            ranked.add((c: c, score: scores.reduce(math.max)));
          }
          ranked.sort((a, b) => b.score.compareTo(a.score));
          final best = ranked.isEmpty ? null : ranked.first;
          final aligned = best?.c.align(translated);
          b = Decision(
            mode: 'B',
            status: best == null
                ? 'Inconclusivo'
                : aligned == null
                ? 'Sentido experimental; alinhamento incerto'
                : 'Resultado experimental',
            shortTranslation: aligned,
            senseId: best?.c.senseId,
            score: best?.score,
            evidence: [
              'Pooling do span alvo; protótipos contextualizados',
              'Score semântico não calibrado; não é probabilidade',
              if (candidates.isEmpty)
                'A seleção está fora do léxico de sentidos desta versão',
              if (aligned != null)
                'Candidato localizado na frase traduzida'
              else
                'Sem âncora segura na tradução',
            ],
            decisionMs: bw.elapsedMicroseconds / 1000,
            ranking: [
              for (final r in ranked)
                {'senseId': r.c.senseId, 'score': r.score},
            ],
          );
        } catch (e) {
          b = Decision(
            mode: 'B',
            status: 'Erro no encoder',
            evidence: [e.toString()],
            decisionMs: bw.elapsedMicroseconds / 1000,
          );
        }
      }
    }
    if (generation != _generation) {
      throw StateError('Seleção substituída; operação cancelada');
    }
    return Comparison(
      context,
      expression,
      translated,
      candidates,
      a,
      b,
      translationMs,
      hit,
      total.elapsedMicroseconds / 1000,
    );
  }

  Decision _basic(List<Candidate> candidates, String translated) {
    final w = Stopwatch()..start();
    final anchored = candidates
        .where((c) => c.align(translated) != null)
        .toList();
    final c = anchored.length == 1 ? anchored.single : null;
    return Decision(
      mode: 'A',
      status: c == null ? 'Inconclusivo' : 'Correspondência lexical',
      shortTranslation: c?.align(translated),
      senseId: c?.senseId,
      evidence: [
        if (candidates.isEmpty)
          'A seleção está fora do léxico de sentidos desta versão'
        else if (c != null)
          'Tradução localizada na frase; evidência lexical, não alinhamento garantido'
        else
          'Nenhuma âncora única; revisão necessária',
      ],
      decisionMs: w.elapsedMicroseconds / 1000,
    );
  }

  Future<void> disableContextual() async {
    prototypeCache.clear();
    await encoder.unload();
  }
}

List<double> _mean(List<List<double>> vectors) => List.generate(
  vectors.first.length,
  (i) => vectors.map((v) => v[i]).reduce((a, b) => a + b) / vectors.length,
);
double _cosine(List<double> a, List<double> b) {
  var dot = 0.0, aa = 0.0, bb = 0.0;
  for (var i = 0; i < a.length; i++) {
    dot += a[i] * b[i];
    aa += a[i] * a[i];
    bb += b[i] * b[i];
  }
  return dot / math.max(math.sqrt(aa * bb), 1e-12);
}
