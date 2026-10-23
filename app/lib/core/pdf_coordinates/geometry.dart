import 'dart:math' as math;

/// Coordenadas PDF canônicas: x cresce à direita, y para cima; [l,b,r,t].
class Box {
  const Box(this.l, this.b, this.r, this.t);
  final double l, b, r, t;
  double get width => r - l;
  double get height => t - b;
  List<double> toJson() => [l, b, r, t];
  factory Box.fromJson(List v) => Box(
    (v[0] as num).toDouble(),
    (v[1] as num).toDouble(),
    (v[2] as num).toDouble(),
    (v[3] as num).toDouble(),
  );
  bool overlaps(Box o) => l < o.r && r > o.l && b < o.t && t > o.b;
  Box merge(Box o) => Box(
    math.min(l, o.l),
    math.min(b, o.b),
    math.max(r, o.r),
    math.max(t, o.t),
  );
  Box toScreen(
    double width,
    double height,
    double pageWidth,
    double pageHeight,
  ) => Box(
    l * width / pageWidth,
    (pageHeight - t) * height / pageHeight,
    r * width / pageWidth,
    (pageHeight - b) * height / pageHeight,
  );
  Box fromScreen(
    double width,
    double height,
    double pageWidth,
    double pageHeight,
  ) => Box(
    l * pageWidth / width,
    pageHeight - t * pageHeight / height,
    r * pageWidth / width,
    pageHeight - b * pageHeight / height,
  );
}

class LabelPlacement {
  const LabelPlacement(this.box, this.fontSize, this.margin);
  final Box box;
  final double fontSize;
  final bool margin;
}

const labelLayoutVersion = 3;

LabelPlacement placeLabel(
  Box target,
  String text,
  double pageWidth,
  double pageHeight,
  List<Box> occupied, {
  List<Box> textLines = const [],
}) {
  final obstacles = [...occupied, ...textLines];
  double width(double font) =>
      math.max(12.0, math.min(pageWidth - 4, text.length * font * 0.6 + 2));
  double height(double font) => font + 0.8;
  bool fits(Box box) =>
      box.l >= 2 &&
      box.r <= pageWidth - 2 &&
      box.b >= 2 &&
      box.t <= pageHeight - 3 &&
      !obstacles.any((r) => r.overlaps(box));
  // O rótulo pertence à palavra: permanece centrado diretamente acima dela.
  // Reduz a fonte nas entrelinhas apertadas, sem procurar outra área da página.
  Box above(double font) {
    final w = width(font);
    final left = ((target.l + target.r - w) / 2)
        .clamp(2.0, math.max(2.0, pageWidth - w - 2))
        .toDouble();
    return Box(left, target.t + 0.3, left + w, target.t + 0.3 + height(font));
  }

  for (final font in [8.0, 7.0, 6.0, 5.0, 4.0]) {
    final box = above(font);
    if (fits(box)) return LabelPlacement(box, font, false);
  }
  // Não desloca a tradução para a margem nem para o topo se o documento não
  // tiver espaço livre. O vínculo com a palavra tem prioridade nesse caso.
  return LabelPlacement(above(4), 4, false);
}
