import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/services.dart';
import 'evaluation.dart';

class LabScreen extends ConsumerStatefulWidget {
  const LabScreen({super.key});
  @override
  ConsumerState<LabScreen> createState() => _LabState();
}

class _LabState extends ConsumerState<LabScreen> {
  List<Map<String, dynamic>> rows = [];
  String filter = 'Todos',
      message = '64 amostras autorais; revisão humana pendente.';
  bool busy = false;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final data = await ref.read(servicesProvider).db.samples();
    if (mounted) setState(() => rows = data);
  }

  Future<void> _run() async {
    setState(() => busy = true);
    final s = ref.read(servicesProvider),
        id = DateTime.now().microsecondsSinceEpoch.toString();
    try {
      final fixtures = List<Map<String, dynamic>>.from(
        jsonDecode(await rootBundle.loadString('assets/evaluation.json')),
      );
      final results = await evaluate(
        s.pipeline,
        fixtures,
        progress: (i, n) {
          if (mounted) {
            setState(
              () => message =
                  '$i / $n • tradutor compartilhado; sem cache de frases',
            );
          }
        },
      );
      await s.db.saveRun(id, {
        'summary': summarize(results),
        'engine': s.translator.id,
        'date': DateTime.now().toIso8601String(),
      });
      for (final r in results) {
        await s.db.saveSample(id, r['id'], r);
      }
      if (mounted) setState(() => rows = results);
    } catch (e) {
      if (mounted) setState(() => message = 'Erro: $e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _export(bool csv) async {
    final text = csv
        ? measurementsCsv(rows)
        : const JsonEncoder.withIndent('  ')
              .convert({'summary': summarize(rows), 'samples': rows});
    final bytes = utf8.encode(text);
    await FilePicker.saveFile(
      fileName: 'experimento-ab.${csv ? 'csv' : 'json'}',
      bytes: bytes,
    );
  }

  @override
  Widget build(BuildContext context) {
    final summary = rows.isEmpty
        ? null
        : summarize(rows.where((r) => r['correctA'] != null).toList());
    final visible = rows
        .where(
          (r) =>
              filter == 'Todos' ||
              filter == 'Ganhos B' &&
                  r['correctB'] == true &&
                  r['correctA'] != true ||
              filter == 'Erros B' && r['correctB'] == false,
        )
        .toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Laboratório A/B')),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'MiniLM L6 INT8 • CPU • inglês → português',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
            ),
            Text(message),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton.icon(
                  onPressed: busy ? null : _run,
                  icon: const Icon(Icons.play_arrow),
                  label: const Text('Executar lote de testes'),
                ),
                OutlinedButton(
                  onPressed: rows.isEmpty ? null : () => _export(true),
                  child: const Text('Exportar CSV'),
                ),
                OutlinedButton(
                  onPressed: rows.isEmpty ? null : () => _export(false),
                  child: const Text('Exportar JSON'),
                ),
                TextButton(
                  onPressed: busy
                      ? null
                      : () async {
                          await ref
                              .read(servicesProvider)
                              .db
                              .clearMeasurements();
                          if (mounted) setState(() => rows = []);
                        },
                  child: const Text('Limpar medições locais'),
                ),
              ],
            ),
            if (busy) const LinearProgressIndicator(),
            if (summary != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Text(
                  'A: ${summary['A']['correct']} / ${summary['n']} • B: ${summary['B']['correct']} / ${summary['n']} • Ganhos B: ${summary['gainsB']} • Perdas B: ${summary['lossesB']}',
                ),
              ),
            DropdownButton<String>(
              value: filter,
              items: [
                for (final s in ['Todos', 'Ganhos B', 'Erros B'])
                  DropdownMenuItem(value: s, child: Text(s)),
              ],
              onChanged: (v) => setState(() => filter = v!),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: visible.length,
                itemBuilder: (_, i) {
                  final r = visible[i];
                  return ExpansionTile(
                    title: Text(
                      r['sentenceOriginal'] ?? r['sentence'] ?? 'Seleção local',
                    ),
                    subtitle: Text(
                      'A: ${r['A']?['shortTranslation'] ?? 'abstenção'} • B: ${r['B']?['shortTranslation'] ?? 'abstenção'}',
                    ),
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: SelectableText(
                          const JsonEncoder.withIndent('  ').convert(r),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
