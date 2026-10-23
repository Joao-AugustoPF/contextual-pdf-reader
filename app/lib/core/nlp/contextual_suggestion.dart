import 'isolated_suggestion.dart';
import 'pipeline.dart';

final _words = RegExp(
  r"[\p{L}\p{M}\p{N}]+(?:[-'’][\p{L}\p{M}\p{N}]+)*",
  unicode: true,
);
const _functionWords = {
  'a',
  'o',
  'as',
  'os',
  'um',
  'uma',
  'de',
  'do',
  'da',
  'dos',
  'das',
  'em',
  'no',
  'na',
  'nos',
  'nas',
  'e',
  'ou',
  'se',
  'que',
  'para',
  'por',
  'com',
  'ao',
  'aos',
  'pelo',
  'pela',
};
typedef TranslatedSpan = ({String text, int start, int end});

List<int>? _commonIndices(List<String> a, List<String> b) {
  if (a.length < 2 || b.length < 2 || a.length > 256 || b.length > 256) {
    return null;
  }
  final lengths = List.generate(
    a.length + 1,
    (_) => List.filled(b.length + 1, 0),
  );
  for (var i = a.length - 1; i >= 0; i--) {
    for (var j = b.length - 1; j >= 0; j--) {
      lengths[i][j] = a[i] == b[j]
          ? lengths[i + 1][j + 1] + 1
          : (lengths[i + 1][j] > lengths[i][j + 1]
                ? lengths[i + 1][j]
                : lengths[i][j + 1]);
    }
  }
  final shorter = a.length < b.length ? a.length : b.length;
  if (lengths[0][0] < 2 || lengths[0][0] / shorter < 0.65) return null;
  final matched = <int>[];
  var i = 0, j = 0;
  while (i < a.length && j < b.length) {
    if (a[i] == b[j]) {
      matched.add(i++);
      j++;
    } else if (lengths[i + 1][j] >= lengths[i][j + 1]) {
      i++;
    } else {
      j++;
    }
  }
  return matched;
}

TranslatedSpan? _literalSpan(List<String> added, String sentence) {
  if (added.isEmpty ||
      added.length > 4 ||
      added.every(_functionWords.contains)) {
    return null;
  }
  // Retirar artigos/preposições da borda, preservando pronomes reflexivos.
  while (added.length > 1 &&
      added.first != 'se' &&
      _functionWords.contains(added.first)) {
    added = added.sublist(1);
  }
  final full = _words.allMatches(sentence).toList();
  final matches = <int>[];
  for (var index = 0; index + added.length <= full.length; index++) {
    var same = true;
    for (var k = 0; k < added.length; k++) {
      if (normalize(full[index + k].group(0)!) != added[k]) {
        same = false;
        break;
      }
    }
    if (same) matches.add(index);
  }
  if (matches.length != 1) return null;
  final start = full[matches.single].start;
  final end = full[matches.single + added.length - 1].end;
  final text = sentence.substring(start, end);
  if (RegExp(r'[,;:.!?\n]').hasMatch(text)) return null;
  return (text: text, start: start, end: end);
}

/// A borda alterada tem de corresponder a um único trecho literal da frase.
TranslatedSpan? alignTranslationEdge({
  required String sentenceTranslation,
  required String withTarget,
  required String withoutTarget,
  required bool atEnd,
}) {
  final a = [
    for (final w in _words.allMatches(withTarget)) normalize(w.group(0)!),
  ];
  final b = [
    for (final w in _words.allMatches(withoutTarget)) normalize(w.group(0)!),
  ];
  final matched = _commonIndices(a, b);
  if (matched == null) return null;
  final from = atEnd ? matched.last + 1 : 0;
  final to = atEnd ? a.length : matched.first;
  if (to <= from) return null;
  return _literalSpan(a.sublist(from, to), sentenceTranslation);
}

/// Omissão do alvo só é aproveitada se sobrar uma única ilha de conteúdo,
/// com pelo menos duas palavras estáveis de cada lado na tradução completa.
TranslatedSpan? alignTranslationOmission(
  String full,
  String withoutTarget, {
  String? reference,
}) {
  final tokens = _words.allMatches(full).toList();
  final a = [for (final w in tokens) normalize(w.group(0)!)];
  final b = [
    for (final w in _words.allMatches(withoutTarget)) normalize(w.group(0)!),
  ];
  final common = _commonIndices(a, b);
  if (common == null) return null;
  final stable = common.toSet();
  final candidates = <TranslatedSpan>[];
  for (var i = 0; i < a.length;) {
    if (stable.contains(i)) {
      i++;
      continue;
    }
    final from = i;
    while (i < a.length && !stable.contains(i)) {
      i++;
    }
    final group = a.sublist(from, i);
    if (group.every(_functionWords.contains)) continue;
    final candidate = _literalSpan(group, reference ?? full);
    // Uma oração isolada pode reformular outra palavra que nem aparece na
    // tradução original. Essa reformulação não deve virar rótulo do alvo.
    if (candidate == null && reference != null && reference != full) continue;
    // Reescrita lexical fora do alvo torna a omissão ambígua.
    if (candidate == null ||
        common.where((v) => v < from).length < 2 ||
        common.where((v) => v >= i).length < 2) {
      return null;
    }
    candidates.add(candidate);
  }
  return candidates.length == 1 ? candidates.single : null;
}

/// Sugestão de leitura, separada do experimento A/B. Nunca inventa uma flexão:
/// o rótulo contextual é sempre um substring da frase traduzida original.
Future<IsolatedSuggestion> suggestSelectionInContext(
  OfflineTranslationEngine translator,
  Comparison result,
) async {
  final sentence = result.context.sentence;
  final start = result.expression.start, end = result.expression.end;
  final clock = Stopwatch()..start();
  final cache = <String, String>{sentence.trim(): result.translated};
  Future<String> translate(String input) async {
    final text = input.trim();
    return cache[text] ??= await translator.translateSentence(text);
  }

  IsolatedSuggestion? make(
    TranslatedSpan span,
    String method,
    String base,
    String included,
  ) {
    // Evitar atribuir ao alvo uma reescrita em outra região da frase.
    final sourcePosition =
        _words.allMatches(sentence.substring(0, start)).length /
        _words.allMatches(sentence).length;
    final targetPosition =
        _words.allMatches(result.translated.substring(0, span.start)).length /
        _words.allMatches(result.translated).length;
    if ((sourcePosition - targetPosition).abs() > 0.25) return null;
    return IsolatedSuggestion(
      original: sentence.substring(start, end).trim(),
      translation: span.text,
      engineId: translator.id,
      elapsedMs: clock.elapsedMicroseconds / 1000,
      basis: 'contextual-$method-alignment',
      alignmentEvidence: {
        'method': method,
        'withoutTargetTranslation': base,
        'withTargetTranslation': included,
        'sentenceTranslatedSpan': [span.start, span.end],
      },
    );
  }

  Future<IsolatedSuggestion?> edge(
    bool atEnd, {
    bool closeClause = false,
  }) async {
    final without =
        (atEnd ? sentence.substring(0, start) : sentence.substring(end)).trim();
    if (_words.allMatches(without).length < 2) return null;
    final withText =
        (atEnd ? sentence.substring(0, end) : sentence.substring(start)).trim();
    final base = await translate(closeClause ? '$without.' : without);
    final included = await translate(closeClause ? '$withText.' : withText);
    final span = alignTranslationEdge(
      sentenceTranslation: result.translated,
      withTarget: included,
      withoutTarget: base,
      atEnd: atEnd,
    );
    return span == null
        ? null
        : make(
            span,
            closeClause
                ? 'prefix-clause'
                : atEnd
                ? 'prefix'
                : 'suffix',
            base,
            included,
          );
  }

  if (sentence.length <= 2000) {
    // Nenhum insucesso destas entradas artificiais invalida a frase original.
    try {
      final answer = await edge(true);
      if (answer != null) return answer;
    } catch (_) {}
    try {
      // Limitar a comparação à oração do alvo evita que sua omissão altere
      // uma palavra distante e a mudança seja atribuída à seleção.
      var left = 0, right = sentence.length;
      for (final boundary in RegExp(r'[,;:!?]').allMatches(sentence)) {
        if (boundary.end <= start) left = boundary.end;
        if (boundary.start >= end) {
          right = boundary.start;
          break;
        }
      }
      final included = await translate(sentence.substring(left, right));
      final omitted =
          '${sentence.substring(left, start)} ${sentence.substring(end, right)}'
              .replaceAll(RegExp(r'\s+'), ' ')
              .trim();
      if (_words.allMatches(omitted).length >= 2) {
        final base = await translate(omitted);
        final span = alignTranslationOmission(
          included,
          base,
          reference: result.translated,
        );
        if (span != null) {
          final answer = make(span, 'omission', base, included);
          if (answer != null) return answer;
        }
      }
    } catch (_) {}
    try {
      final answer = await edge(true, closeClause: true);
      if (answer != null) return answer;
    } catch (_) {}
    try {
      final answer = await edge(false);
      if (answer != null) return answer;
    } catch (_) {}
  }
  final isolated = await suggestIsolatedTranslation(translator, result);
  return IsolatedSuggestion(
    original: isolated.original,
    translation: isolated.translation,
    engineId: isolated.engineId,
    elapsedMs: clock.elapsedMicroseconds / 1000,
  );
}
