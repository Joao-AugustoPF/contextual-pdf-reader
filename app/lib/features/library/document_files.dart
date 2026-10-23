import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

import '../../core/persistence/database.dart';
import '../annotations/exporter.dart';
import 'original_pdf_access.dart';

/// O leitor abre uma base interna; Salvar substitui o original, nunca essa base.
/// Assim o PDFium não bloqueia o destino e os destaques não aparecem em dobro.
class DocumentFiles {
  DocumentFiles(this.directory, this.db, {OriginalPdfAccess? originalAccess})
    : originalAccess =
          originalAccess ??
          (Platform.isIOS ? const IosOriginalPdfAccess() : null);
  final Directory directory;
  final ReaderDatabase db;
  final OriginalPdfAccess? originalAccess;

  Future<OriginalPdfSnapshot> _read(String source) async {
    if (isIosOriginalPdf(source)) {
      if (originalAccess == null) {
        throw StateError(
          'Este original precisa ser aberto no iPhone/iPad que o autorizou.',
        );
      }
      return originalAccess!.read(source);
    }
    return OriginalPdfSnapshot(
      p.basename(source),
      await File(source).readAsBytes(),
    );
  }

  Future<String> _resolve(String path) async =>
      isIosOriginalPdf(path) ? path : File(path).resolveSymbolicLinks();

  String _key(String path) {
    if (isIosOriginalPdf(path)) return path;
    final normalized = p.normalize(p.absolute(path));
    return Platform.isWindows ? normalized.toLowerCase() : normalized;
  }

  Future<Map<String, dynamic>> open(String path) async {
    var source = await _resolve(path);
    final rows = await db.documents();
    var existing = rows
        .where(
          (row) =>
              _key(row['path']) == _key(source) ||
              row['source_path'] != null &&
                  _key(row['source_path']) == _key(source),
        )
        .firstOrNull;
    if (existing?['source_path'] != null) {
      source = existing!['source_path'];
    }
    final snapshot = await _read(source);
    final bytes = snapshot.bytes;
    final hash = sha256.convert(bytes).toString();
    // Recupera as anotações das importações antigas ao reabrir o original.
    existing ??= rows
        .where((r) => r['id'] == hash && r['source_path'] == null)
        .firstOrNull;
    final id =
        existing?['id'] as String? ??
        (rows.any((r) => r['id'] == hash)
            ? '$hash-${DateTime.now().microsecondsSinceEpoch}'
            : hash);
    final cacheRoot = p.join(directory.path, 'documents');
    final legacyCopy =
        !isIosOriginalPdf(source) && p.isWithin(_key(cacheRoot), _key(source));
    final name = legacyCopy
        ? (existing?['title'] as String? ?? snapshot.name)
        : snapshot.name;
    final working = File(p.join(cacheRoot, id, '$hash.pdf'));
    if (!await working.exists()) {
      await working.parent.create(recursive: true);
      await working.writeAsBytes(
        withoutManagedAnnotations(bytes, id),
        flush: true,
      );
    }
    await db.putDocument(id, working.path, name, existing?['pages'] ?? 0);
    if (!legacyCopy) await db.linkSource(id, source, hash);
    return (await db.document(id))!;
  }

  /// Migração de importações que não armazenavam o caminho do arquivo original.
  Future<void> linkOriginal(String id, String path) async {
    final row = (await db.document(id))!;
    final source = await _resolve(path);
    if (!isIosOriginalPdf(source) &&
        p.isWithin(_key(p.join(directory.path, 'documents')), _key(source))) {
      throw StateError(
        'Escolha o PDF original fora da cópia interna do leitor.',
      );
    }
    final hash = sha256.convert((await _read(source)).bytes).toString();
    final workingHash = sha256
        .convert(await File(row['path']).readAsBytes())
        .toString();
    if (hash != id && hash != workingHash) {
      throw StateError(
        'Esse arquivo não corresponde ao PDF aberto. Abra o original pela biblioteca.',
      );
    }
    await db.linkSource(id, source, hash);
  }

  Future<String> save(
    String id,
    List<Map<String, dynamic>> annotations, {
    Uint8List? attributionImage,
  }) async {
    final row = (await db.document(id))!;
    final path = row['source_path'] as String?;
    if (path == null) throw StateError('Vincule o PDF original primeiro.');
    final original = (await _read(path)).bytes;
    if (sha256.convert(original).toString() != row['source_hash']) {
      throw StateError(
        'O PDF mudou fora do aplicativo. Reabra-o pela biblioteca antes de salvar.',
      );
    }
    final signature = sha256
        .convert(utf8.encode(jsonEncode(annotations)))
        .toString();
    final last = await db.getPreference('pdf-save/$id');
    if (last is Map &&
        last['sourceHash'] == row['source_hash'] &&
        last['annotationsHash'] == signature) {
      return path;
    }
    final updated = exportAnnotated(
      original,
      annotations,
      ownerId: id,
      attributionImage: attributionImage,
    );
    if (isIosOriginalPdf(path)) {
      // O hash é conferido novamente no iOS sob NSFileCoordinator, na mesma
      // operação que substitui o arquivo do provedor. A cópia interna não muda.
      await originalAccess!.write(path, updated, row['source_hash']);
      await _recordSave(id, path, updated, signature);
      return path;
    }
    final source = File(path);
    // Arquivo temporário na mesma pasta: a troca final é uma única renomeação.
    // Uma falha de escrita/arquivo bloqueado deixa o original intacto.
    final temporary = File(
      p.join(
        source.parent.path,
        '.${p.basename(path)}.entrelinhas-${DateTime.now().microsecondsSinceEpoch}.tmp',
      ),
    );
    try {
      await temporary.writeAsBytes(updated, flush: true);
      // Não sobrescrever uma alteração externa ocorrida durante a preparação.
      if (sha256.convert(await source.readAsBytes()).toString() !=
          row['source_hash']) {
        throw StateError(
          'O PDF mudou durante a gravação. Reabra-o e tente novamente.',
        );
      }
      await temporary.rename(source.path);
      await _recordSave(id, source.path, updated, signature);
    } finally {
      if (await temporary.exists()) await temporary.delete();
    }
    return source.path;
  }

  Future<void> _recordSave(
    String id,
    String source,
    Uint8List bytes,
    String signature,
  ) => db.transaction(() async {
    final hash = sha256.convert(bytes).toString();
    await db.linkSource(id, source, hash);
    await db.preference('pdf-save/$id', {
      'sourceHash': hash,
      'annotationsHash': signature,
    });
  });
}
