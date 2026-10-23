import 'dart:io';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:archive/archive.dart';

class ModelStore {
  ModelStore(this.root, this.manifest);
  final Directory root;
  final Map<String, dynamic> manifest;
  List<Map<String, dynamic>> entries(String id) => [
    for (final j in manifest['files'])
      if ((j['file'] as String).startsWith('models/$id/'))
        Map<String, dynamic>.from(j),
  ];
  int bytes(String id) =>
      entries(id).fold(0, (sum, e) => sum + (e['bytes'] as int));
  File local(Map<String, dynamic> e) =>
      File('${root.path}/${(e['file'] as String).replaceFirst('models/', '')}');
  Future<bool> ready(String id) async =>
      entries(id).isNotEmpty &&
      entries(id).every(
        (e) => local(e).existsSync() && local(e).lengthSync() == e['bytes'],
      );
  Future<void> verify(String id) async {
    for (final e in entries(id)) {
      final f = local(e);
      if (!await f.exists() ||
          (await sha256.bind(f.openRead()).first).toString() != e['sha256']) {
        throw StateError('Modelo corrompido: ${f.path}');
      }
    }
  }

  Future<void> install(
    String id, {
    required bool consent,
    void Function(int, int)? onProgress,
  }) async {
    if (!consent) throw StateError('Download exige consentimento');
    final client = HttpClient();
    var received = 0;
    Future<void> download(Map<String, dynamic> e, File f) async {
      await f.parent.create(recursive: true);
      final part = File('${f.path}.part');
      try {
        final req = await client.getUrl(Uri.parse(e['url']));
        final response = await req.close();
        if (response.statusCode != 200) {
          throw HttpException('Download HTTP ${response.statusCode}');
        }
        final sink = part.openWrite();
        try {
          await for (final chunk in response) {
            sink.add(chunk);
            received += chunk.length;
            onProgress?.call(received, e['bytes']);
          }
        } finally {
          await sink.close();
        }
        if ((await sha256.bind(part.openRead()).first).toString() !=
            e['sha256']) {
          throw StateError('Download rejeitado: SHA-256');
        }
        await part.rename(f.path);
      } finally {
        if (await part.exists()) await part.delete();
      }
    }

    try {
      if (id == 'minilm') {
        for (final e in entries(id)) {
          await download(e, local(e));
        }
      } else {
        final e = Map<String, dynamic>.from(
          (manifest['files'] as List).firstWhere(
            (e) => e['file'] == 'models/translate-en_pb-1_9.argosmodel',
          ),
        );
        final archive = File('${root.path}/translator.argosmodel');
        await download(e, archive);
        final decoded = ZipDecoder().decodeBytes(await archive.readAsBytes());
        for (final item in decoded.files.where((f) => f.isFile)) {
          final parts = item.name
              .replaceAll('\\', '/')
              .split('/')
              .skip(1)
              .toList();
          if (parts.any((p) => p == '..' || p.contains(':')) || parts.isEmpty) {
            throw StateError('Pacote inválido');
          }
          final f = File('${root.path}/translator/${parts.join('/')}');
          await f.parent.create(recursive: true);
          await f.writeAsBytes(item.content as List<int>);
        }
        await archive.delete();
      }
      await verify(id);
    } finally {
      client.close(force: true);
    }
  }

  Future<void> remove(String id) async {
    if (!['minilm', 'translator'].contains(id)) throw ArgumentError(id);
    final d = Directory('${root.path}/$id');
    if (await d.exists()) await d.delete(recursive: true);
  }

  Future<File> writeManifest() async {
    await root.create(recursive: true);
    return File('${root.path}/models.lock.json')
        .writeAsString(jsonEncode(manifest));
  }
}
