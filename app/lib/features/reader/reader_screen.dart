import 'dart:async';
import 'dart:io';
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdfrx/pdfrx.dart';

import '../../app/services.dart';
import '../../core/nlp/pipeline.dart';
import '../../core/nlp/isolated_suggestion.dart';
import '../../core/nlp/contextual_suggestion.dart';
import '../../core/nlp/selection_text.dart';
import '../../core/pdf_coordinates/geometry.dart';
import '../annotations/exporter.dart';
import '../annotations/highlight_style.dart';
import '../annotations/selection.dart';
import '../library/document_files.dart';
import '../library/original_pdf_access.dart';
import '../translation/attribution.dart';
import '../translation/isolated_suggestion_card.dart';
import 'render_quality.dart';

class ReaderScreen extends ConsumerStatefulWidget {
  const ReaderScreen({
    required this.documentId,
    required this.path,
    required this.title,
    this.initialPage = 1,
    super.key,
  });
  final String documentId, path, title;
  final int initialPage;
  @override
  ConsumerState<ReaderScreen> createState() => ReaderScreenState();
}

class ReaderScreenState extends ConsumerState<ReaderScreen>
    with WidgetsBindingObserver {
  final controller = PdfViewerController();
  PdfTextSearcher? searcher;
  PdfDocument? document;
  PdfPageTextRange? selection;
  List<Map<String, dynamic>> annotations = [];
  TranslationMode mode = TranslationMode.basic;
  int color = 0xffffd54f, page = 1, _selectionVersion = 0;
  bool busy = false, showSearch = false, focusReading = false;
  final _relayoutPages = <int>{};
  String? warning;
  late AppServices _services;
  static const colors = [
    0xffffd54f,
    0xff81c784,
    0xff64b5f6,
    0xfff48fb1,
    0xffef9a9a,
  ];
  @override
  void initState() {
    super.initState();
    _services = ref.read(servicesProvider);
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  Future<void> _load() async {
    final db = ref.read(servicesProvider).db;
    final saved = await db.getPreference('mode'),
        data = await db.annotations(widget.documentId);
    if (mounted) {
      setState(() {
        annotations = data;
        mode = TranslationMode.values.firstWhere(
          (m) => m.name == saved,
          orElse: () => TranslationMode.basic,
        );
      });
      unawaited(_refreshLegacyLabels(page));
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _services.pipeline.cancel();
    searcher?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      unawaited(ref.read(servicesProvider).pipeline.disableContextual());
    }
  }

  void _message(String text) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
    }
  }

  Future<void> _selectionChanged(PdfTextSelection s) async {
    final version = ++_selectionVersion;
    ref.read(servicesProvider).pipeline.cancel();
    if (!s.isCopyAllowed) {
      if (mounted) {
        setState(() {
          selection = null;
          warning = 'O documento restringe a cópia de texto.';
        });
      }
      return;
    }
    final ranges = await s.getSelectedTextRanges();
    if (!mounted || version != _selectionVersion) return;
    PdfPageTextRange? normalized;
    if (ranges.length == 1) {
      final r = ranges.single;
      final span = wordSelectionSpan(r.pageText.fullText, r.start, r.end);
      if (span != null) {
        normalized = PdfPageTextRange(
          pageText: r.pageText,
          start: span.start,
          end: span.end,
        );
      }
    }
    setState(() {
      selection = normalized;
      warning = ranges.length > 1
          ? 'Selecione uma página por vez para anotar.'
          : null;
    });
  }

  Future<void> _pageChanged(int? p) async {
    if (p == null || document == null) return;
    setState(() => page = p);
    unawaited(_refreshLegacyLabels(p));
    await ref.read(servicesProvider).db.progress(widget.documentId, p);
    final text = await document!.pages[p - 1].loadText();
    if (mounted && page == p) {
      setState(
        () => warning = text == null || text.fullText.trim().isEmpty
            ? 'Esta página não possui texto selecionável; OCR poderá ser adicionado futuramente.'
            : null,
      );
    }
  }

  Future<void> _refreshLegacyLabels(int pageNumber) async {
    final doc = document;
    if (doc == null || _relayoutPages.contains(pageNumber)) return;
    final oldLabels = annotations
        .where(
          (a) =>
              a['pageNumber'] == pageNumber &&
              a['labelLayoutVersion'] != labelLayoutVersion &&
              (a['shortTranslation'] as String? ?? '').trim().isNotEmpty,
        )
        .toList();
    if (oldLabels.isEmpty) return;
    setState(() => _relayoutPages.add(pageNumber));
    try {
      final p = doc.pages[pageNumber - 1];
      final raw = await p.loadStructuredText();
      final lines = [
        for (final f in raw.fragments)
          Box(f.bounds.left, f.bounds.bottom, f.bounds.right, f.bounds.top),
      ];
      for (final old in oldLabels) {
        if (!mounted || document != doc || !annotations.contains(old)) continue;
        final placement = placeLabel(
          Box.fromJson((old['quadPointsPdf'] as List).first),
          old['shortTranslation'],
          p.width,
          p.height,
          [
            for (final other in annotations.where(
              (a) =>
                  a['id'] != old['id'] &&
                  a['pageNumber'] == pageNumber &&
                  a['shortTranslation'] != null,
            ))
              Box.fromJson(other['labelBox']),
          ],
          textLines: lines,
        );
        final updated = {
          ...old,
          'labelBox': placement.box.toJson(),
          'labelFontSize': placement.fontSize,
          'marginNote': placement.margin,
          'labelLayoutVersion': labelLayoutVersion,
        };
        await _services.db.saveAnnotation(updated);
        if (!mounted) return;
        setState(() {
          final index = annotations.indexOf(old);
          if (index >= 0) annotations[index] = updated;
        });
      }
      if (mounted) controller.invalidate();
      if (mounted && page == pageNumber) {
        final refreshed = annotations
            .where((a) => a['id'] == oldLabels.first['id'])
            .firstOrNull;
        if (refreshed != null) await _revealMeaning(refreshed);
      }
    } catch (e) {
      _message('Não foi possível reposicionar o significado: $e');
    } finally {
      if (mounted) setState(() => _relayoutPages.remove(pageNumber));
    }
  }

  Future<void> _setMode(TranslationMode value) async {
    ++_selectionVersion;
    ref.read(servicesProvider).pipeline.cancel();
    setState(() => mode = value);
    await ref.read(servicesProvider).db.preference('mode', value.name);
    if (value == TranslationMode.basic) {
      await ref.read(servicesProvider).pipeline.disableContextual();
    }
  }

  List<Box> _boxes(PdfPageTextRange r) => [
    for (final f in r.enumerateFragmentBoundingRects())
      Box(f.bounds.left, f.bounds.bottom, f.bounds.right, f.bounds.top),
  ];
  Future<bool> saveSelection({
    Decision? decision,
    Comparison? result,
    String? manual,
    String? automatic,
    String? automaticMode,
    SelectionContext? originalContext,
    bool notify = true,
    IsolatedSuggestion? suggestion,
    PdfPageTextRange? range,
  }) async {
    final r = range ?? selection;
    if (r == null || document == null) return false;
    if ((manual != null && manual.trim().isEmpty) ||
        (automatic != null && automatic.trim().isEmpty)) {
      _message('Digite um significado para colocar acima do trecho.');
      return false;
    }
    manual = manual?.trim();
    automatic = automatic?.trim();
    final existing = annotations
        .where(
          (a) =>
              a['pageNumber'] == r.pageNumber &&
              wordSelectionSpan(
                    r.pageText.fullText,
                    a['charRange'][0],
                    a['charRange'][1],
                  ) ==
                  wordSelectionSpan(r.pageText.fullText, r.start, r.end),
        )
        .firstOrNull;
    if (existing?['manualOverride'] == true &&
        manual == null &&
        (decision != null || automatic != null)) {
      _message(
        'Tradução editada preservada. Use Editar anotação para alterá-la.',
      );
      return false;
    }
    final boxes = _boxes(r);
    if (boxes.isEmpty) return false;
    final p = document!.pages[r.pageNumber - 1];
    final text =
        manual ??
        automatic ??
        decision?.shortTranslation ??
        existing?['shortTranslation'] as String?;
    final lines = [
      for (final f in r.pageText.fragments)
        Box(f.bounds.left, f.bounds.bottom, f.bounds.right, f.bounds.top),
    ];
    final occupied = [
      for (final a in annotations.where(
        (a) =>
            a['pageNumber'] == r.pageNumber &&
            a['shortTranslation'] != null &&
            a['id'] != existing?['id'],
      ))
        Box.fromJson(a['labelBox']),
    ];
    final label = placeLabel(
      boxes.first,
      text ?? '',
      p.width,
      p.height,
      occupied,
      textLines: lines,
    );
    final now = DateTime.now().toIso8601String();
    final suggestionInfo = suggestion?.toJson();
    if (suggestionInfo != null) {
      suggestionInfo['userReviewed'] = manual != null;
      suggestionInfo['requiresReview'] = false;
    }
    final annotation = <String, dynamic>{
      'id': existing?['id'] ?? DateTime.now().microsecondsSinceEpoch.toString(),
      'documentId': widget.documentId,
      'pageNumber': r.pageNumber,
      'charRange': [r.start, r.end],
      'quadPointsPdf': [for (final b in boxes) b.toJson()],
      'selectedText': r.text,
      'detectedExpression': result?.expression.lemma ?? r.text,
      'shortTranslation': text,
      'originalSentence':
          result?.context.sentence ??
          originalContext?.sentence ??
          existing?['originalSentence'],
      'translatedSentence':
          result?.translated ?? existing?['translatedSentence'],
      'type': text == null ? 'highlight' : 'translation',
      'color': color,
      'mode': decision?.mode ?? automaticMode ?? existing?['mode'],
      'engineId': ref.read(servicesProvider).translator.id,
      'modelVersion': decision?.mode == 'B'
          ? 'all-MiniLM-L6-v2@1110a243'
          : null,
      'manualOverride': manual != null || existing?['manualOverride'] == true,
      'source': manual != null || existing?['manualOverride'] == true
          ? 'editada'
          : 'automática',
      'labelBox': label.box.toJson(),
      'labelFontSize': label.fontSize,
      'labelLayoutVersion': labelLayoutVersion,
      'marginNote': label.margin,
      'extractionVersion': 'pdfrx-2.10.0',
      'createdAt': existing?['createdAt'] ?? now,
      'updatedAt': now,
      'decision': decision?.toJson() ?? existing?['decision'],
      'reviewedSuggestion': manual != null
          ? (suggestionInfo ?? existing?['reviewedSuggestion'])
          : (existing?['reviewedSuggestion']),
      'automaticSuggestion': automatic == null
          ? (existing?['automaticSuggestion'])
          : suggestionInfo,
    };
    await ref.read(servicesProvider).db.saveAnnotation(annotation);
    if (mounted) {
      setState(() {
        annotations.removeWhere((a) => a['id'] == annotation['id']);
        annotations.add(annotation);
      });
      controller.invalidate();
      if (text != null && text.isNotEmpty) await _revealMeaning(annotation);
      if (notify) {
        _message(
          text == null ? 'Marcação aplicada' : 'Significado aplicado ao trecho. Use Salvar para gravar no PDF.',
        );
      }
    }
    return true;
  }

  Future<void> _revealMeaning(Map<String, dynamic> annotation) async {
    if (!mounted || !controller.isReady || document == null) return;
    final pageNumber = annotation['pageNumber'] as int;
    final p = document!.pages[pageNumber - 1];
    final target = Box.fromJson((annotation['quadPointsPdf'] as List).first);
    final box = target.merge(Box.fromJson(annotation['labelBox']));
    final rect = PdfRect(box.l, box.t, box.r, box.b).toRectInDocument(
      page: p,
      pageRect: controller.layout.pageLayouts[pageNumber - 1],
    );
    // O resultado da gravação não depende de um ticker que pode ser cancelado
    // pela seleção ou pelo fechamento do diálogo.
    await controller.ensureVisible(rect, margin: 16, duration: Duration.zero);
  }

  Future<void> _writeMeaning() async {
    final range = selection;
    if (range == null || busy) return;
    final existing = _selectedAnnotations
        .where((a) => a['shortTranslation'] != null)
        .firstOrNull;
    final text = await _editText(
      existing?['shortTranslation'] ?? '',
      title: 'Escrever significado',
    );
    if (text == null || !mounted) return;
    if (await saveSelection(manual: text, range: range)) {
      await controller.textSelectionDelegate.clearTextSelection();
      if (mounted) {
        ++_selectionVersion;
        setState(() => selection = null);
      }
    }
  }

  Future<void> translateSelection({bool showDetails = false}) async {
    final original = selection;
    if (original == null || busy) return;
    final version = _selectionVersion;
    final requestedMode = mode;
    final s = ref.read(servicesProvider);
    final contextSelection = SelectionContext.fromPage(
      original.pageText.fullText,
      original.start,
      original.end,
    );
    var accepted = original;
    final expression = recognize(contextSelection, s.pipeline.lexicon);
    if (expression.start != contextSelection.start ||
        expression.end != contextSelection.end) {
      final choice = await showDialog<String>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Unidade semântica encontrada'),
          content: Text(
            '“${original.text}” faz parte de “${expression.lemma}”. Confirmar a faixa ampliada?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c, 'cancel'),
              child: const Text('Ajustar seleção'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c, 'expand'),
              child: Text('Usar ${expression.lemma}'),
            ),
          ],
        ),
      );
      if (choice != 'expand') return;
      final offset = original.start - contextSelection.start;
      accepted = PdfPageTextRange(
        pageText: original.pageText,
        start: offset + expression.start,
        end: offset + expression.end,
      );
    }
    if (!mounted || version != _selectionVersion) return;
    setState(() => busy = true);
    try {
      // Palavras sem entrada lexical não precisam traduzir a frase inteira.
      if (!showDetails &&
          requestedMode == TranslationMode.basic &&
          !s.pipeline.lexicon.containsKey(expression.lemma)) {
        final suggestion = await translateIsolatedText(
          s.translator,
          accepted.text,
        );
        if (!mounted || version != _selectionVersion) return;
        await saveSelection(
          automatic: suggestion.translation,
          automaticMode: 'A',
          originalContext: contextSelection,
          suggestion: suggestion,
          range: accepted,
          notify: false,
        );
        return;
      }
      final result = await s.pipeline.run(contextSelection, requestedMode);
      await s.flushCache();
      if (!mounted || version != _selectionVersion) return;
      if (showDetails || requestedMode == TranslationMode.compare) {
        setState(() => busy = false);
        await _showComparison(result, accepted);
      } else {
        final decision = requestedMode == TranslationMode.basic
            ? result.a
            : result.b;
        final suggestion = decision?.shortTranslation == null
            ? await suggestSelectionInContext(s.translator, result)
            : null;
        if (!mounted || version != _selectionVersion) return;
        await saveSelection(
          automatic: shortTranslationLabel(
            decision?.shortTranslation ?? suggestion!.translation,
          ),
          decision: decision,
          result: result,
          suggestion: suggestion,
          range: accepted,
          notify: false,
        );
      }
    } catch (e) {
      _message('Não foi possível traduzir: $e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _showComparison(
    Comparison result,
    PdfPageTextRange range,
  ) async {
    IsolatedSuggestion? loadedSuggestion;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheet) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Seleção: ${result.expression.lemma}',
                style: const TextStyle(
                  fontSize: 21,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(result.context.sentence),
              const SizedBox(height: 8),
              Text('Frase traduzida: ${result.translated}'),
              const TranslationAttribution(),
              Text(
                'Tradução comum: ${result.translationMs.toStringAsFixed(1)} ms • ${result.cacheHit ? 'cache hit' : 'cache miss'}',
              ),
              if (result.a != null &&
                  result.b != null &&
                  result.a!.shortTranslation != null &&
                  result.a!.shortTranslation == result.b!.shortTranslation)
                const Text('Resultados iguais'),
              const SizedBox(height: 12),
              if (result.a?.shortTranslation == null &&
                  result.b?.shortTranslation == null)
                IsolatedSuggestionCard(
                  load: () async {
                    final suggestion = await suggestSelectionInContext(
                      _services.translator,
                      result,
                    );
                    loadedSuggestion = suggestion;
                    return suggestion;
                  },
                  onUse: (suggestion) async {
                    final saved = await saveSelection(
                      result: result,
                      manual: suggestion.translation,
                      suggestion: suggestion,
                      range: range,
                    );
                    if (saved && sheet.mounted) Navigator.pop(sheet);
                  },
                  onReview: (suggestion) async {
                    final text = await _editText(suggestion.translation);
                    if (text == null || !mounted || !sheet.mounted) return;
                    final saved = await saveSelection(
                      result: result,
                      manual: text,
                      suggestion: suggestion,
                      range: range,
                    );
                    if (saved && sheet.mounted) Navigator.pop(sheet);
                  },
                ),
              LayoutBuilder(
                builder: (_, constraints) {
                  final cards = [
                    for (final d in [result.a, result.b].whereType<Decision>())
                      _decisionCard(d, result, range, sheet),
                  ];
                  return constraints.maxWidth > 600
                      ? Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            for (final card in cards) Expanded(child: card),
                          ],
                        )
                      : Column(children: cards);
                },
              ),
              TextButton.icon(
                onPressed: () async {
                  final text = await _editText(
                    loadedSuggestion?.translation ??
                        result.a?.shortTranslation ??
                        result.b?.shortTranslation ??
                        '',
                  );
                  if (text != null) {
                    final saved = await saveSelection(
                      result: result,
                      manual: text,
                      range: range,
                    );
                    if (saved && sheet.mounted) Navigator.pop(sheet);
                  }
                },
                icon: const Icon(Icons.edit_outlined),
                label: const Text('Escrever outro significado'),
              ),
              if (result.a != null && result.b != null)
                Wrap(
                  spacing: 8,
                  children: [
                    for (final verdict in ['A', 'B', 'Empate', 'Ambos ruins'])
                      TextButton(
                        onPressed: () async {
                          final db = ref.read(servicesProvider).db;
                          await db.saveSample(
                            'local',
                            DateTime.now().microsecondsSinceEpoch.toString(),
                            {
                              ...result.toJson(),
                              'userVerdict': verdict,
                              'provenance': 'user-preference-not-gold',
                              'labelConsent': false,
                            },
                          );
                          _message(
                            'Preferência salva localmente; não usada como rótulo de avaliação',
                          );
                        },
                        child: Text(verdict),
                      ),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _decisionCard(
    Decision d,
    Comparison result,
    PdfPageTextRange range,
    BuildContext sheet,
  ) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            d.mode == 'A' ? 'A • Básico' : 'B • Contextual',
            style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
          ),
          Text(
            d.shortTranslation ?? 'Sem correspondência curta confirmada',
            style: TextStyle(
              color: d.shortTranslation == null
                  ? Theme.of(context).colorScheme.onSurfaceVariant
                  : const Color(0xffc62828),
              fontSize: 21,
            ),
          ),
          Text(
            '${d.status}\nSentido: ${d.senseId ?? 'não resolvido'}\nDecisão adicional: ${d.decisionMs.toStringAsFixed(1)} ms',
          ),
          if (d.score != null)
            Text(
              'Score semântico: ${d.score!.toStringAsFixed(3)} (não calibrado)',
            ),
          ExpansionTile(
            title: const Text('Mostrar evidências'),
            children: [
              SelectableText(
                '${d.evidence.join('\n')}\n${jsonEncode(d.ranking)}',
              ),
            ],
          ),
          FilledButton(
            onPressed: d.shortTranslation == null
                ? null
                : () async {
                    await saveSelection(
                      decision: d,
                      result: result,
                      range: range,
                    );
                    if (sheet.mounted) Navigator.pop(sheet);
                  },
            child: const Text('Usar esta'),
          ),
        ],
      ),
    ),
  );
  Future<String?> _editText(
    String value, {
    String title = 'Editar tradução',
  }) async {
    final input = TextEditingController(text: value);
    final form = GlobalKey<FormState>();
    final result = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(title),
        content: Form(
          key: form,
          child: TextFormField(
            controller: input,
            autofocus: true,
            maxLength: 100,
            validator: (text) => (text ?? '').trim().isEmpty
                ? 'Digite um significado antes de salvar.'
                : null,
            decoration: const InputDecoration(
              labelText: 'Tradução ou significado curto',
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              final text = input.text.trim();
              if (!form.currentState!.validate()) return;
              Navigator.pop(c, text);
            },
            child: const Text('Salvar'),
          ),
        ],
      ),
    );
    // Controller pertence à rota; descarte após sua animação de saída.
    Future<void>.delayed(const Duration(seconds: 1), input.dispose);
    return result;
  }

  Future<void> _annotationDetails(Map<String, dynamic> a) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (c) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(a['selectedText'], style: const TextStyle(fontSize: 20)),
              Text(
                a['shortTranslation'] ?? 'Destaque',
                style: const TextStyle(color: Color(0xffc62828), fontSize: 22),
              ),
              if (a['automaticSuggestion'] != null)
                const Text('Tradução direta da seleção'),
              Text(
                '${a['originalSentence'] ?? ''}\n${a['translatedSentence'] ?? ''}\nModo ${a['mode'] ?? 'marcação'} • origem ${a['source']}',
              ),
              if (a['decision'] != null)
                Text((a['decision']['alignmentEvidence'] as List).join('\n')),
              Wrap(
                spacing: 8,
                children: [
                  TextButton.icon(
                    onPressed: () async {
                      final text = await _editText(a['shortTranslation'] ?? '');
                      if (text == null) return;
                      a['shortTranslation'] = text;
                      a['manualOverride'] = true;
                      a['source'] = 'editada';
                      a['updatedAt'] = DateTime.now().toIso8601String();
                      // Recalcula espaço reservado para uma edição mais longa.
                      final p = document!.pages[(a['pageNumber'] as int) - 1];
                      final raw = await p.loadStructuredText();
                      final target = Box.fromJson(
                        (a['quadPointsPdf'] as List).first,
                      );
                      final placement = placeLabel(
                        target,
                        text,
                        p.width,
                        p.height,
                        [
                          for (final other in annotations.where(
                            (o) =>
                                o['id'] != a['id'] &&
                                o['pageNumber'] == a['pageNumber'] &&
                                o['shortTranslation'] != null,
                          ))
                            Box.fromJson(other['labelBox']),
                        ],
                        textLines: [
                          for (final f in raw.fragments)
                            Box(
                              f.bounds.left,
                              f.bounds.bottom,
                              f.bounds.right,
                              f.bounds.top,
                            ),
                        ],
                      );
                      a['labelBox'] = placement.box.toJson();
                      a['labelFontSize'] = placement.fontSize;
                      a['labelLayoutVersion'] = labelLayoutVersion;
                      await ref.read(servicesProvider).db.saveAnnotation(a);
                      if (mounted) {
                        setState(() {});
                        controller.invalidate();
                        await _revealMeaning(a);
                      }
                      if (c.mounted) Navigator.pop(c);
                    },
                    icon: const Icon(Icons.edit),
                    label: const Text('Editar anotação'),
                  ),
                  TextButton.icon(
                    onPressed: () async {
                      if (await _removeAnnotations([a]) && c.mounted) {
                        Navigator.pop(c);
                      }
                    },
                    icon: const Icon(Icons.delete_outline),
                    label: const Text('Remover'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Map<String, dynamic>> get _selectedAnnotations {
    final r = selection;
    return r == null
        ? []
        : annotationsInRange(annotations, r.pageNumber, r.start, r.end);
  }

  Future<bool> _removeAnnotations(List<Map<String, dynamic>> items) async {
    if (busy || items.isEmpty) return false;
    final ids = items.map((a) => a['id']).toSet();
    ++_selectionVersion;
    _services.pipeline.cancel();
    setState(() => busy = true);
    try {
      await _services.db.transaction(() async {
        for (final id in ids) {
          await _services.db.removeAnnotation(id);
        }
      });
      if (!mounted) return false;
      setState(() => annotations.removeWhere((a) => ids.contains(a['id'])));
      if (controller.isReady) {
        await controller.textSelectionDelegate.clearTextSelection();
      }
      if (!mounted) return false;
      controller.invalidate();
      final messenger = ScaffoldMessenger.of(context);
      messenger.clearSnackBars();
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            items.length == 1
                ? 'Marcação removida'
                : '${items.length} marcações removidas',
          ),
          action: SnackBarAction(
            label: 'Desfazer',
            onPressed: () async {
              // Restaura uma única vez, sem duplicar IDs já presentes.
              final restore = items
                  .where(
                    (a) =>
                        !annotations.any((current) => current['id'] == a['id']),
                  )
                  .toList();
              await _services.db.transaction(() async {
                for (final a in restore) {
                  await _services.db.saveAnnotation(a);
                }
              });
              if (!mounted) return;
              setState(() {
                annotations.removeWhere(
                  (a) => restore.any((old) => old['id'] == a['id']),
                );
                annotations.addAll(restore);
              });
              controller.invalidate();
            },
          ),
        ),
      );
      return true;
    } catch (e) {
      _message('Não foi possível remover a marcação: $e');
      return false;
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void _paintHighlights(Canvas canvas, Rect pageRect, PdfPage p) {
    for (final a in annotations.where((a) => a['pageNumber'] == p.pageNumber)) {
      final paint = Paint()
        ..color = Color(a['color'])
            .withValues(alpha: annotationHighlightOpacity)
        ..blendMode = BlendMode.multiply;
      for (final q in a['quadPointsPdf']) {
        final b = Box.fromJson(q);
        final rect = PdfRect(b.l, b.t, b.r, b.b)
            .toRect(page: p, scaledPageSize: pageRect.size)
            .translate(pageRect.left, pageRect.top);
        canvas.drawRect(rect, paint);
      }
    }
  }

  List<Widget> _overlays(BuildContext context, Rect pageRect, PdfPage p) {
    final widgets = <Widget>[];
    for (final a in annotations.where((a) => a['pageNumber'] == p.pageNumber)) {
      for (final q in a['quadPointsPdf']) {
        final b = Box.fromJson(q),
            r = PdfRect(
              b.l,
              b.t,
              b.r,
              b.b,
            ).toRect(page: p, scaledPageSize: pageRect.size);
        widgets.add(
          Positioned.fromRect(
            rect: r,
            child: PdfOverlayInteractionRegion(
              onTap: (_) {
                unawaited(_annotationDetails(a));
                return true;
              },
              // A cor é pintada junto da página, com Multiply. Esta região
              // transparente mantém clique simples e seleção por arraste.
              child: const SizedBox.expand(),
            ),
          ),
        );
      }
      final text = a['shortTranslation'] as String?;
      if (text != null && text.isNotEmpty) {
        final b = Box.fromJson(a['labelBox']),
            r = PdfRect(
              b.l,
              b.t,
              b.r,
              b.b,
            ).toRect(page: p, scaledPageSize: pageRect.size);
        widgets.add(
          Positioned.fromRect(
            rect: r,
            child: PdfOverlayInteractionRegion(
              onTap: (_) {
                unawaited(_annotationDetails(a));
                return true;
              },
              child: Semantics(
                label: 'Tradução: $text',
                child: Container(
                  color: Colors.white.withValues(alpha: 0.94),
                  padding: const EdgeInsets.symmetric(horizontal: 1),
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: Alignment.center,
                    child: Text(
                      text,
                      style: TextStyle(
                        height: 1,
                        color: const Color(0xffc62828),
                        fontSize:
                            (a['labelFontSize'] as num).toDouble() *
                            pageRect.width /
                            p.width,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      }
    }
    return widgets;
  }

  List<Widget> _scrollbarOverlays(BuildContext context, Size viewport) {
    if (!controller.isReady || viewport.height < 48) return [];
    final documentHeight = controller.documentSize.height;
    final visibleHeight = controller.visibleRect.height;
    if (documentHeight <= visibleHeight) return [];
    final thumbHeight = (viewport.height * visibleHeight / documentHeight)
        .clamp(40.0, viewport.height.clamp(40.0, 160.0));
    return [
      Positioned(
        top: 0,
        bottom: 0,
        right: 0,
        width: 24,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (details) {
            final progress =
                ((details.localPosition.dy - thumbHeight / 2) /
                        (viewport.height - thumbHeight))
                    .clamp(0.0, 1.0);
            final destination = controller.value.clone()
              ..y = -progress * (documentHeight - visibleHeight);
            unawaited(
              controller.goTo(
                destination,
                duration: const Duration(milliseconds: 160),
              ),
            );
          },
          child: ColoredBox(
            key: const ValueKey('pdf-scroll-track'),
            color: Theme.of(context).colorScheme.onSurface
                .withValues(alpha: 0.07),
          ),
        ),
      ),
      PdfViewerScrollThumb(
        controller: controller,
        thumbSize: Size(20, thumbHeight),
        margin: 2,
        thumbBuilder: (context, size, pageNumber, ctrl) => Semantics(
          label: 'Barra de rolagem do documento',
          value: 'Página ${pageNumber ?? 1} de ${ctrl.pages.length}',
          child: Tooltip(
            message:
                'Página ${pageNumber ?? 1} de ${ctrl.pages.length} • arraste para navegar',
            child: MouseRegion(
              cursor: SystemMouseCursors.grab,
              child: Container(
                key: const ValueKey('pdf-scroll-thumb'),
                margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary
                      .withValues(alpha: 0.8),
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
        ),
      ),
    ];
  }

  Future<void> _export() async {
    try {
      final name =
          '${widget.title.replaceAll(RegExp(r'\.pdf$', caseSensitive: false), '')}-anotado.pdf';
      if (Platform.isAndroid || Platform.isIOS) {
        final badge = (await rootBundle.load('assets/google-translate.png'))
            .buffer
            .asUint8List();
        final bytes = exportAnnotated(
          await File(widget.path).readAsBytes(),
          annotations,
          attributionImage: badge,
          ownerId: widget.documentId,
        );
        final path = await FilePicker.saveFile(
          fileName: name,
          bytes: bytes,
          type: FileType.custom,
          allowedExtensions: ['pdf'],
        );
        if (path != null) _message('Cópia PDF exportada');
      } else {
        final directory = await FilePicker.getDirectoryPath(
          dialogTitle: 'Escolha a pasta para a cópia anotada',
        );
        if (directory != null) {
          var path = '$directory/$name';
          if (await File(path).exists()) {
            path = '$directory/${DateTime.now().millisecondsSinceEpoch}-$name';
          }
          final originalPath = (await _services.db.document(
            widget.documentId,
          ))?['source_path'];
          if (originalPath != null &&
              File(path).absolute.path.toLowerCase() ==
                  File(originalPath).absolute.path.toLowerCase()) {
            throw StateError('Use Salvar para atualizar o original.');
          }
          await exportCopy(
            widget.path,
            path,
            annotations,
            ownerId: widget.documentId,
          );
          _message('Cópia PDF exportada: $path');
        }
      }
    } catch (e) {
      _message('Erro ao exportar PDF: $e');
    }
  }

  Future<void> _savePdf() async {
    if (busy || _relayoutPages.isNotEmpty || document == null) return;
    setState(() => busy = true);
    try {
      final files = DocumentFiles(_services.directory, _services.db);
      final book = await _services.db.document(widget.documentId);
      final source = book?['source_path'] as String?;
      final oldIosCopy =
          Platform.isIOS &&
          source != null &&
          !isIosOriginalPdf(source) &&
          source != '${_services.directory.path}/exemplo.pdf';
      if (source == null || oldIosCopy) {
        _message(
          'Escolha o PDF original uma única vez para autorizar a gravação neste arquivo.',
        );
        if (Platform.isIOS) {
          final selected = await const IosOriginalPdfAccess().pick();
          if (selected == null) return;
          await files.linkOriginal(widget.documentId, selected);
        } else {
          final picked = await FilePicker.pickFile(
            dialogTitle: 'Vincular PDF original para salvar neste arquivo',
            type: FileType.custom,
            allowedExtensions: ['pdf'],
          );
          if (picked?.path == null) return;
          await files.linkOriginal(widget.documentId, picked!.path!);
        }
      }
      final badge = (await rootBundle.load('assets/google-translate.png'))
          .buffer
          .asUint8List();
      await files.save(
        widget.documentId,
        List<Map<String, dynamic>>.from(jsonDecode(jsonEncode(annotations))),
        attributionImage: badge,
      );
      _message('PDF salvo no arquivo original');
    } on FileSystemException catch (e) {
      _message(
        'Não foi possível salvar o PDF. Verifique a permissão da pasta e feche o arquivo em outros leitores. ${e.message}',
      );
    } on PlatformException catch (e) {
      _message(
        e.message ?? 'Não foi possível acessar o PDF original. Selecione-o novamente em Arquivos.',
      );
    } catch (e) {
      _message('Não foi possível salvar o PDF: $e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _outline() async {
    final nodes = await document?.loadOutline() ?? [];
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (c) => nodes.isEmpty
          ? const Padding(
              padding: EdgeInsets.all(32),
              child: Text('Este PDF não possui sumário.'),
            )
          : ListView(
              children: [
                for (final n in nodes)
                  ListTile(
                    title: Text(n.title),
                    onTap: () {
                      controller.goToDest(n.dest);
                      Navigator.pop(c);
                    },
                  ),
              ],
            ),
    );
  }

  Future<void> _annotationList() async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (c) => ListView(
        children: [
          if (annotations.isEmpty)
            const ListTile(title: Text('Nenhuma marcação neste documento')),
          for (final a in annotations)
            ListTile(
              title: Text(a['shortTranslation'] ?? a['selectedText']),
              subtitle: Text('Página ${a['pageNumber']} • ${a['source']}'),
              trailing: IconButton(
                tooltip: 'Remover marcação',
                icon: const Icon(Icons.delete_outline),
                onPressed: busy
                    ? null
                    : () async {
                        if (await _removeAnnotations([a]) && c.mounted) {
                          Navigator.pop(c);
                        }
                      },
              ),
              onTap: () {
                Navigator.pop(c);
                controller.goToPage(pageNumber: a['pageNumber']);
                _annotationDetails(a);
              },
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => CallbackShortcuts(
    bindings: {
      if (!Platform.isAndroid)
        const SingleActivator(LogicalKeyboardKey.keyS, control: true): () =>
            unawaited(_savePdf()),
      if (Platform.isIOS || Platform.isMacOS)
        const SingleActivator(LogicalKeyboardKey.keyS, meta: true): () =>
            unawaited(_savePdf()),
    },
    child: Focus(
      autofocus: true,
      child: Scaffold(
        appBar: focusReading
            ? null
            : AppBar(
                title: Text(widget.title, overflow: TextOverflow.ellipsis),
                actions: [
                  if (!Platform.isAndroid)
                    TextButton.icon(
                      onPressed:
                          busy || _relayoutPages.isNotEmpty || document == null
                          ? null
                          : _savePdf,
                      icon: const Icon(Icons.save_outlined),
                      label: const Text('Salvar'),
                    ),
                  IconButton(
                    tooltip: 'Sumário',
                    icon: const Icon(Icons.format_list_bulleted),
                    onPressed: _outline,
                  ),
                  IconButton(
                    tooltip: 'Buscar texto',
                    icon: const Icon(Icons.search),
                    onPressed: () => setState(() => showSearch = !showSearch),
                  ),
                  IconButton(
                    tooltip: 'Anotações',
                    icon: const Icon(Icons.notes),
                    onPressed: _annotationList,
                  ),
                  IconButton(
                    tooltip: 'Exportar cópia PDF',
                    icon: const Icon(Icons.ios_share),
                    onPressed: busy ? null : _export,
                  ),
                ],
              ),
        body: Column(
          children: [
            if (!focusReading)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: SegmentedButton<TranslationMode>(
                  segments: const [
                    ButtonSegment(
                      value: TranslationMode.basic,
                      label: Text('Básico'),
                    ),
                    ButtonSegment(
                      value: TranslationMode.contextual,
                      label: Text('Contextual'),
                    ),
                    ButtonSegment(
                      value: TranslationMode.compare,
                      label: Text('Comparar'),
                    ),
                  ],
                  selected: {mode},
                  onSelectionChanged: (s) => _setMode(s.single),
                ),
              ),
            if (!focusReading)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Wrap(
                  alignment: WrapAlignment.center,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    for (final c in colors)
                      IconButton(
                        tooltip: switch (c) {
                          0xffffd54f => 'Amarelo',
                          0xff81c784 => 'Verde',
                          0xff64b5f6 => 'Azul',
                          0xfff48fb1 => 'Rosa',
                          _ => 'Vermelho',
                        },
                        onPressed: () => setState(() => color = c),
                        icon: Icon(
                          color == c ? Icons.check_circle : Icons.circle,
                          color: Color(c),
                        ),
                      ),
                    TextButton(
                      onPressed: selection == null
                          ? null
                          : () => saveSelection(),
                      child: const Text('Marcar'),
                    ),
                    TextButton.icon(
                      onPressed: busy || _selectedAnnotations.isEmpty
                          ? null
                          : () => _removeAnnotations(_selectedAnnotations),
                      icon: const Icon(Icons.highlight_remove_outlined),
                      label: const Text('Remover marcação'),
                    ),
                    FilledButton.tonal(
                      onPressed: selection == null || busy
                          ? null
                          : translateSelection,
                      child: Text(
                        Platform.isAndroid || Platform.isIOS
                            ? 'Traduzir com Google'
                            : 'Marcar e traduzir',
                      ),
                    ),
                    TextButton.icon(
                      onPressed: selection == null || busy
                          ? null
                          : () => translateSelection(showDetails: true),
                      icon: const Icon(Icons.info_outline),
                      label: const Text('Detalhes'),
                    ),
                    TextButton.icon(
                      onPressed: selection == null || busy
                          ? null
                          : _writeMeaning,
                      icon: const Icon(Icons.edit_note),
                      label: const Text('Escrever significado'),
                    ),
                    IconButton(
                      tooltip: 'Copiar seleção',
                      onPressed: selection == null
                          ? null
                          : () => Clipboard.setData(
                              ClipboardData(text: selection!.text),
                            ),
                      icon: const Icon(Icons.copy),
                    ),
                  ],
                ),
              ),
            if (showSearch)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        decoration: const InputDecoration(
                          hintText: 'Buscar neste PDF',
                        ),
                        onChanged: (text) => searcher?.startTextSearch(text),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Próximo resultado',
                      onPressed: () => searcher?.goToNextMatch(),
                      icon: const Icon(Icons.navigate_next),
                    ),
                  ],
                ),
              ),
            SizedBox(
              height: 4,
              child: busy || _relayoutPages.isNotEmpty
                  ? const LinearProgressIndicator()
                  : null,
            ),
            if (warning != null)
              Padding(
                padding: const EdgeInsets.all(8),
                child: Text(
                  warning!,
                  style: const TextStyle(color: Colors.deepOrange),
                ),
              ),
            Expanded(
              key: const ValueKey('reader-document-viewport'),
              child: PdfViewer.file(
                widget.path,
                controller: controller,
                initialPageNumber: widget.initialPage,
                params: PdfViewerParams(
                  backgroundColor: const Color(0xffe6e9e5),
                  maxImageBytesCachedOnMemory: 48 * 1024 * 1024,
                  limitRenderingCache: true,
                  getPageRenderingScale: (context, p, ctrl, _) =>
                      pagePreviewScale(
                        pageWidth: p.width,
                        pageHeight: p.height,
                        zoom: ctrl.currentZoom,
                        devicePixelRatio: MediaQuery.devicePixelRatioOf(
                          context,
                        ),
                      ),
                  scrollByMouseWheel: 4.0,
                  interactionDelegateProvider:
                      const PdfViewerScrollInteractionDelegateProviderPhysics(
                        panFriction: 18,
                        zoomFriction: 18,
                      ),
                  viewerOverlayBuilder: (context, size, _) =>
                      _scrollbarOverlays(context, size),
                  textSelectionParams: PdfTextSelectionParams(
                    onTextSelectionChange: _selectionChanged,
                  ),
                  onGeneralTap: (context, ctrl, details) {
                    if (details.type != PdfViewerGeneralTapType.doubleTap ||
                        details.tapOn == PdfViewerPart.background ||
                        !ctrl.textSelectionDelegate.isCopyAllowed) {
                      return false;
                    }
                    unawaited(
                      ctrl.textSelectionDelegate.selectWord(
                        details.documentPosition,
                      ),
                    );
                    return true;
                  },
                  pageOverlaysBuilder: _overlays,
                  pagePaintCallbacks: [
                    if (searcher != null) searcher!.pageTextMatchPaintCallback,
                    _paintHighlights,
                  ],
                  onViewerReady: (doc, ctrl) {
                    document = doc;
                    searcher ??= PdfTextSearcher(controller);
                    ref
                        .read(servicesProvider)
                        .db
                        .putDocument(
                          widget.documentId,
                          widget.path,
                          widget.title,
                          doc.pages.length,
                        );
                    _pageChanged(widget.initialPage);
                  },
                  onPageChanged: _pageChanged,
                  buildContextMenu: (ctx, params) =>
                      AdaptiveTextSelectionToolbar.buttonItems(
                        anchors: TextSelectionToolbarAnchors(
                          primaryAnchor: params.anchorA,
                        ),
                        buttonItems: [
                          ContextMenuButtonItem(
                            label: 'Marcar',
                            onPressed: () {
                              params.dismissContextMenu();
                              saveSelection();
                            },
                          ),
                          ContextMenuButtonItem(
                            label: 'Marcar e traduzir',
                            onPressed: () {
                              params.dismissContextMenu();
                              translateSelection();
                            },
                          ),
                          ContextMenuButtonItem(
                            label: 'Explicar tradução disponível',
                            onPressed: () {
                              params.dismissContextMenu();
                              _annotationList();
                            },
                          ),
                          ContextMenuButtonItem(
                            label: 'Copiar',
                            onPressed: () {
                              params.textSelectionDelegate.copyTextSelection();
                              params.dismissContextMenu();
                            },
                          ),
                        ],
                      ),
                ),
              ),
            ),
            if (annotations.any((a) => a['shortTranslation'] != null))
              const TranslationAttribution(),
            SafeArea(
              top: false,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    tooltip: 'Página anterior',
                    onPressed: () => controller.goToPage(
                      pageNumber: (page - 1).clamp(
                        1,
                        document?.pages.length ?? 1,
                      ),
                    ),
                    icon: const Icon(Icons.chevron_left),
                  ),
                  Text('$page / ${document?.pages.length ?? '…'}'),
                  IconButton(
                    tooltip: 'Próxima página',
                    onPressed: () => controller.goToPage(
                      pageNumber: (page + 1).clamp(
                        1,
                        document?.pages.length ?? 1,
                      ),
                    ),
                    icon: const Icon(Icons.chevron_right),
                  ),
                  IconButton(
                    tooltip: 'Diminuir zoom',
                    onPressed: () => controller.zoomDown(),
                    icon: const Icon(Icons.zoom_out),
                  ),
                  IconButton(
                    tooltip: 'Aumentar zoom',
                    onPressed: () => controller.zoomUp(),
                    icon: const Icon(Icons.zoom_in),
                  ),
                  IconButton(
                    tooltip: 'Área de leitura',
                    onPressed: () =>
                        setState(() => focusReading = !focusReading),
                    icon: Icon(
                      focusReading ? Icons.fullscreen_exit : Icons.fullscreen,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
