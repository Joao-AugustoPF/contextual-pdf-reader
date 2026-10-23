import 'pipeline.dart';
import 'selection_text.dart';

/// Sugestão curta com origem explícita; não altera decisões ou métricas A/B.
class IsolatedSuggestion {
  const IsolatedSuggestion({
    required this.original,
    required this.translation,
    required this.engineId,
    required this.elapsedMs,
    this.basis = 'isolated-translation',
    this.alignmentEvidence,
  });

  final String original, translation, engineId;
  final double elapsedMs;
  final String basis;
  final Map<String, dynamic>? alignmentEvidence;
  bool get usesSentenceTranslation => basis.startsWith('contextual-');

  Map<String, dynamic> toJson() => {
    'basis': basis,
    'original': original,
    'translation': translation,
    'engineId': engineId,
    'elapsedMs': elapsedMs,
    'contextVerified': false,
    'alignmentResolved': usesSentenceTranslation,
    if (alignmentEvidence != null) 'alignmentEvidence': alignmentEvidence,
    'requiresReview': true,
  };
}

Future<IsolatedSuggestion> suggestIsolatedTranslation(
  OfflineTranslationEngine translator,
  Comparison result,
) async {
  final original = result.context.sentence
      .substring(result.expression.start, result.expression.end)
      .trim();
  return translateIsolatedText(translator, original);
}

Future<IsolatedSuggestion> translateIsolatedText(
  OfflineTranslationEngine translator,
  String text,
) async {
  final original = shortTranslationLabel(text);
  if (original.isEmpty) throw ArgumentError('Seleção vazia');
  final clock = Stopwatch()..start();
  final translated = shortTranslationLabel(
    await translator.translateSentence(original),
  );
  if (translated.isEmpty) throw StateError('Tradução vazia');
  return IsolatedSuggestion(
    original: original,
    translation: translated,
    engineId: translator.id,
    elapsedMs: clock.elapsedMicroseconds / 1000,
  );
}
