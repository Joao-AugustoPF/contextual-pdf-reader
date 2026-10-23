/// Retorna apenas marcações da página que cruzam a faixa selecionada.
/// Os offsets são UTF-16 com fim exclusivo, como na extração do leitor.
List<Map<String, dynamic>> annotationsInRange(
  List<Map<String, dynamic>> annotations,
  int page,
  int start,
  int end,
) {
  if (start < 0 || end <= start) return [];
  return annotations.where((a) {
    final range = a['charRange'] as List?;
    return a['pageNumber'] == page &&
        range != null &&
        range.length == 2 &&
        range[0] < end &&
        range[1] > start;
  }).toList();
}
