import 'dart:math' as math;

/// Dobrar a resolução em cada eixo preserva as bordas das letras pequenas.
/// Acima do teto, o pdfrx completa a região visível na resolução real.
double pagePreviewScale({
  required double pageWidth,
  required double pageHeight,
  required double zoom,
  required double devicePixelRatio,
}) => math.min(
  2 * zoom * devicePixelRatio,
  math.min(
    4096 / math.max(pageWidth, pageHeight),
    math.sqrt(12 * 1024 * 1024 / (pageWidth * pageHeight)),
  ),
);
