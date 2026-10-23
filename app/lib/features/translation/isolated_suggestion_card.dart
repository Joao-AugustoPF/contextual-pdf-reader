import 'package:flutter/material.dart';

import '../../core/nlp/isolated_suggestion.dart';

class IsolatedSuggestionCard extends StatefulWidget {
  const IsolatedSuggestionCard({
    required this.load,
    required this.onReview,
    required this.onUse,
    super.key,
  });

  final Future<IsolatedSuggestion> Function() load;
  final Future<void> Function(IsolatedSuggestion suggestion) onReview;
  final Future<void> Function(IsolatedSuggestion suggestion) onUse;

  @override
  State<IsolatedSuggestionCard> createState() => _IsolatedSuggestionCardState();
}

class _IsolatedSuggestionCardState extends State<IsolatedSuggestionCard> {
  late final Future<IsolatedSuggestion> _suggestion = widget.load();
  bool _reviewing = false;

  @override
  Widget build(BuildContext context) => Card(
    child: Padding(
      padding: const EdgeInsets.all(16),
      child: FutureBuilder<IsolatedSuggestion>(
        future: _suggestion,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const Text(
              'A sugestão não está disponível. Você ainda pode '
              'usar “Escrever outro significado” abaixo.',
            );
          }
          final suggestion = snapshot.data;
          if (suggestion == null) {
            return const Row(
              children: [
                SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 12),
                Expanded(child: Text('Obtendo sugestão local para a seleção…')),
              ],
            );
          }
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Sugestão para “${suggestion.original}”',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                suggestion.translation,
                style: const TextStyle(color: Color(0xffc62828), fontSize: 21),
              ),
              const SizedBox(height: 8),
              Text(
                suggestion.usesSentenceTranslation
                    ? 'Trecho da frase traduzida, preservando a forma usada no contexto. Você pode editar o significado.'
                    : 'Sugestão isolada; o sentido na frase pode precisar de ajuste. Use esta tradução ou escreva outro significado.',
              ),
              Text(
                'Sugestão adicional: ${suggestion.elapsedMs.toStringAsFixed(1)} ms',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: _reviewing
                    ? null
                    : () => _act(() => widget.onUse(suggestion)),
                icon: const Icon(Icons.check),
                label: const Text('Usar esta tradução'),
              ),
              FilledButton.icon(
                onPressed: _reviewing
                    ? null
                    : () => _act(() => widget.onReview(suggestion)),
                icon: const Icon(Icons.edit_outlined),
                label: const Text('Editar significado'),
              ),
            ],
          );
        },
      ),
    ),
  );

  Future<void> _act(Future<void> Function() action) async {
    setState(() => _reviewing = true);
    try {
      await action();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Não foi possível aplicar o significado: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _reviewing = false);
    }
  }
}
