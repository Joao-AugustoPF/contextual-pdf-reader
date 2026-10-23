import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/services.dart';
import '../../core/inference/mobile.dart';
import '../../core/nlp/pipeline.dart';
import '../translation/attribution.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});
  @override
  ConsumerState<SettingsScreen> createState() => _SettingsState();
}

class _SettingsState extends ConsumerState<SettingsScreen> {
  final status = <String, String>{};
  TranslationMode mode = TranslationMode.basic;
  bool busy = false, wifi = true;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final s = ref.read(servicesProvider);
    final saved = await s.db.getPreference('mode');
    for (final id in ['minilm', 'translator']) {
      final ready = id == 'translator' && (Platform.isAndroid || Platform.isIOS)
          ? await s.translator.isModelReady()
          : await s.models.ready(id);
      status[id] = ready ? 'Disponível' : 'Não instalado';
    }
    if (mounted) {
      setState(() {
        mode = TranslationMode.values.firstWhere(
          (m) => m.name == saved,
          orElse: () => TranslationMode.basic,
        );
      });
    }
  }

  Future<void> _install(String id) async {
    final s = ref.read(servicesProvider);
    final consent = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Baixar modelo offline?'),
        content: Text(
          id == 'minilm'
              ? 'MiniLM: ${(s.models.bytes(id) / 1048576).toStringAsFixed(1)} MiB. Download de Hugging Face. Texto dos PDFs não é enviado.'
              : 'Tradução local: ${Platform.isAndroid || Platform.isIOS ? 'pacotes gerenciados pelo Google ML Kit; tamanho exato não exposto pela API' : 'pacote Argos de aproximadamente 64 MiB'}. Após a instalação funciona offline.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Baixar'),
          ),
        ],
      ),
    );
    if (consent != true) return;
    setState(() {
      busy = true;
      status[id] = 'Baixando…';
    });
    try {
      if (id == 'translator' && (Platform.isAndroid || Platform.isIOS)) {
        await s.translator.downloadModelsWithConsent(
          consent: true,
          wifiOnly: wifi,
        );
      } else {
        await s.models.install(
          id,
          consent: true,
          onProgress: (got, total) {
            if (mounted) {
              setState(
                () => status[id] =
                    'Baixando ${(got / 1048576).toStringAsFixed(1)} MiB…',
              );
            }
          },
        );
      }
      status[id] = 'Disponível';
    } catch (e) {
      status[id] = 'Erro: $e';
    } finally {
      await s.db.model(id, {
        'status': status[id],
        'updated': DateTime.now().toIso8601String(),
      });
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _remove(String id) async {
    final s = ref.read(servicesProvider);
    setState(() => busy = true);
    try {
      if (id == 'minilm') {
        await s.pipeline.disableContextual();
        await s.models.remove(id);
      } else if (s.translator is MlKitEngine) {
        await (s.translator as MlKitEngine).removeModels();
      } else {
        await s.translator.dispose();
        await s.models.remove(id);
      }
      status[id] = 'Não instalado';
    } catch (e) {
      status[id] = 'Erro: $e';
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = ref.watch(servicesProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Preferências')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const Text(
            'Tradução',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 16),
          DropdownButtonFormField<TranslationMode>(
            initialValue: mode,
            decoration: const InputDecoration(labelText: 'Modo padrão'),
            items: const [
              DropdownMenuItem(
                value: TranslationMode.basic,
                child: Text('Básico'),
              ),
              DropdownMenuItem(
                value: TranslationMode.contextual,
                child: Text('Contextual'),
              ),
              DropdownMenuItem(
                value: TranslationMode.compare,
                child: Text('Comparar'),
              ),
            ],
            onChanged: (v) async {
              if (v != null) {
                setState(() => mode = v);
                await s.db.preference('mode', v.name);
                if (v == TranslationMode.basic) {
                  await s.pipeline.disableContextual();
                }
              }
            },
          ),
          SwitchListTile(
            title: const Text('Somente Wi-Fi para pacotes ML Kit'),
            value: wifi,
            onChanged: (v) => setState(() => wifi = v),
          ),
          for (final id in ['translator', 'minilm'])
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      id == 'minilm'
                          ? 'MiniLM L6 • contextual opcional'
                          : Platform.isAndroid || Platform.isIOS
                          ? 'Google ML Kit • inglês / português'
                          : 'CTranslate2 / Argos • inglês → português brasileiro',
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      '${status[id] ?? 'Verificando…'}${id == 'minilm' || !(Platform.isAndroid || Platform.isIOS) ? ' • ${(s.models.bytes(id) / 1048576).toStringAsFixed(1)} MiB instalados' : ''}',
                    ),
                    Wrap(
                      spacing: 8,
                      children: [
                        TextButton.icon(
                          onPressed: busy ? null : () => _install(id),
                          icon: const Icon(Icons.download),
                          label: const Text('Baixar com consentimento'),
                        ),
                        TextButton(
                          onPressed: busy ? null : () => _remove(id),
                          child: const Text('Remover'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 16),
          const Text('Privacidade e limites', style: TextStyle(fontSize: 20)),
          const Text(
            'Os PDFs e os registros ficam neste dispositivo. Sem telemetria própria. O transporte de diagnósticos ML Kit está desativado no Android; iOS ainda exige auditoria. O MiniLM é experimental. Score semântico não é confiança calibrada. ML Kit oferece português, sem opção de variante regional. Sem OCR nesta versão.',
          ),
          const SizedBox(height: 16),
          const Text(
            'Traduções no Android/iOS: atribuição Google Translate. Avalie traduções importantes; a qualidade pode variar.',
          ),
          const TranslationAttribution(),
          const Text(
            'Este aplicativo pode conter traduções automáticas fornecidas pelo Google. O Google não oferece garantias sobre exatidão, confiabilidade, comercialização ou adequação a uma finalidade específica dessas traduções.',
          ),
          const SelectableText('https://cloud.google.com/translate'),
          const SizedBox(height: 12),
          const Text(
            'Licenças: app MIT; MiniLM Apache-2.0; Argos/OPUS-MT CC-BY-4.0 (Jörg Tiedemann e Santhosh Thottingal, 2020); CTranslate2 MIT; ONNX Runtime MIT; PDFium BSD; léxico e exemplos CC0. Veja docs/LICENCAS.md.',
          ),
          const SizedBox(height: 16),
          SelectableText('Armazenamento: ${s.directory.path}'),
        ],
      ),
    );
  }
}
