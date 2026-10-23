import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/services.dart';
import 'document_files.dart';
import 'original_pdf_access.dart';
import '../reader/reader_screen.dart';
import '../settings/settings_screen.dart';
import '../experiment/lab_screen.dart';

class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});
  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  List<Map<String, dynamic>> books = [];
  bool busy = false;
  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final rows = await ref.read(servicesProvider).db.documents();
    if (mounted) setState(() => books = rows);
  }

  Future<void> openPath(String path) async {
    setState(() => busy = true);
    try {
      final s = ref.read(servicesProvider);
      final book = await DocumentFiles(s.directory, s.db).open(path);
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => ReaderScreen(
            documentId: book['id'],
            path: book['path'],
            title: book['title'],
            initialPage: book['progress'],
          ),
        ),
      );
      await _reload();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              e is PlatformException
                  ? (e.message ??
                        'Não foi possível acessar o original. Selecione-o novamente em Arquivos.')
                  : 'Não foi possível abrir o PDF: $e',
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _pick() async {
    try {
      if (Platform.isIOS) {
        final source = await const IosOriginalPdfAccess().pick();
        if (source != null && mounted) await openPath(source);
        return;
      }
      final result = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
      );
      if (result?.path != null) await openPath(result!.path!);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              e is PlatformException
                  ? (e.message ??
                        'Não foi possível selecionar o PDF em Arquivos.')
                  : 'Não foi possível selecionar o PDF: $e',
            ),
          ),
        );
      }
    }
  }

  Future<void> _example() async {
    final s = ref.read(servicesProvider);
    final f = File('${s.directory.path}/exemplo.pdf');
    if (!await f.exists()) {
      await f.writeAsBytes(
        (await rootBundle.load('assets/sample.pdf')).buffer.asUint8List(),
      );
    }
    await openPath(f.path);
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Entrelinhas'),
      actions: [
        IconButton(
          tooltip: 'Laboratório A/B',
          icon: const Icon(Icons.science_outlined),
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute<void>(builder: (_) => const LabScreen()),
          ),
        ),
        IconButton(
          tooltip: 'Preferências',
          icon: const Icon(Icons.tune),
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
          ),
        ),
      ],
    ),
    body: DropTarget(
      onDragDone: (detail) {
        if (detail.files.isNotEmpty) openPath(detail.files.first.path);
      },
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1040),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Seu próximo capítulo,\ncom mais contexto.',
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.w600,
                    height: 1.2,
                  ),
                ),
                const SizedBox(height: 12),
                const Text(
                  'PDFs, marcações e traduções no seu dispositivo. Sem conta e sem nuvem.',
                ),
                const SizedBox(height: 24),
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  children: [
                    FilledButton.icon(
                      onPressed: busy ? null : _pick,
                      icon: const Icon(Icons.add),
                      label: const Text('Abrir PDF local'),
                    ),
                    OutlinedButton.icon(
                      onPressed: busy ? null : _example,
                      icon: const Icon(Icons.menu_book),
                      label: const Text('Experimentar com um PDF'),
                    ),
                  ],
                ),
                if (busy) const LinearProgressIndicator(),
                const SizedBox(height: 32),
                const Text(
                  'Biblioteca recente',
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: books.isEmpty
                      ? const Center(
                          child: Text('Abra ou arraste um PDF para começar.'),
                        )
                      : ListView.separated(
                          itemCount: books.length,
                          separatorBuilder: (_, _) => const Divider(),
                          itemBuilder: (_, i) {
                            final b = books[i];
                            return ListTile(
                              leading: const Icon(
                                Icons.picture_as_pdf_outlined,
                              ),
                              title: Text(b['title']),
                              subtitle: Text(
                                'Página ${b['progress']} • ${b['pages']} páginas',
                              ),
                              trailing: const Icon(Icons.chevron_right),
                              onTap: busy
                                  ? null
                                  : () =>
                                        openPath(b['source_path'] ?? b['path']),
                            );
                          },
                        ),
                ),
                const Text(
                  'Inglês → português • Tradução local experimental',
                  style: TextStyle(fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
