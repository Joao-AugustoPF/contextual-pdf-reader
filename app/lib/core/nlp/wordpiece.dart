class Piece {
  const Piece(this.id, this.start, this.end);
  final int id, start, end;
}

/// BERT uncased WordPiece. Offsets são UTF-16 do texto original, como pdfrx/Dart.
/// Contexto é inglês; acentos latinos são normalizados preservando os offsets.
class WordPieceTokenizer {
  WordPieceTokenizer(String vocab, {this.padTo = 0})
    : vocabulary = {
        for (final (i, v) in vocab.split('\n').indexed) v.trim(): i,
      };
  final Map<String, int> vocabulary;
  final int padTo;
  List<Piece> tokenize(String text, {int maxLength = 256}) {
    final out = <Piece>[Piece(vocabulary['[CLS]']!, 0, 0)];
    final basic = RegExp(r"[\p{L}\p{N}]+|[^\s\p{L}\p{N}]", unicode: true);
    for (final token in basic.allMatches(text)) {
      var word = token.group(0)!.toLowerCase();
      const accented = 'áàâãäåéèêëíìîïóòôõöúùûüçñ';
      const plain = 'aaaaaaeeeeiiiiooooouuuucn';
      for (var i = 0; i < accented.length; i++) {
        word = word.replaceAll(accented[i], plain[i]);
      }
      final pieces = <Piece>[];
      var pos = 0;
      if (word.length > 100) {
        pieces.add(Piece(vocabulary['[UNK]']!, token.start, token.end));
        pos = word.length;
      }
      while (pos < word.length) {
        var end = word.length;
        int? id;
        while (end > pos) {
          id = vocabulary['${pos > 0 ? '##' : ''}${word.substring(pos, end)}'];
          if (id != null) break;
          end--;
        }
        if (id == null) {
          pieces.clear();
          pieces.add(Piece(vocabulary['[UNK]']!, token.start, token.end));
          break;
        }
        pieces.add(Piece(id, token.start + pos, token.start + end));
        pos = end;
      }
      if (out.length + pieces.length >= maxLength) break;
      out.addAll(pieces);
    }
    out.add(Piece(vocabulary['[SEP]']!, 0, 0));
    while (out.length < padTo) {
      out.add(Piece(vocabulary['[PAD]']!, 0, 0));
    }
    return out;
  }
}
