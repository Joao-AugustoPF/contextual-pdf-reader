final _wordCharacter = RegExp(r'[\p{L}\p{N}\p{M}]', unicode: true);

/// Retira pontuação externa de uma palavra sem alterar apóstrofos/hífens internos.
/// Seleções com várias palavras mantêm a pontuação original para cópia e marcação.
({int start, int end})? wordSelectionSpan(String text, int start, int end) {
  if (start < 0 || end <= start || end > text.length) return null;
  final selected = text.substring(start, end);
  final characters = _wordCharacter.allMatches(selected).toList();
  if (characters.isEmpty) return null;
  final first = characters.first.start, last = characters.last.end;
  if (RegExp(r'\s').hasMatch(selected.substring(first, last))) {
    return (start: start, end: end);
  }
  return (start: start + first, end: start + last);
}

/// O rótulo é uma tradução curta, sem vírgula/ponto herdado da seleção.
String shortTranslationLabel(String text) {
  final characters = _wordCharacter.allMatches(text).toList();
  if (characters.isEmpty) return '';
  return text.substring(characters.first.start, characters.last.end).trim();
}
