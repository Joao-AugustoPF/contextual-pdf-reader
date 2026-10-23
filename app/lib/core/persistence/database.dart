import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';

/// Drift com SQL explícito: evita código gerado e mantém migrações transacionais.
class ReaderDatabase extends GeneratedDatabase {
  ReaderDatabase(File file) : super(NativeDatabase.createInBackground(file));
  ReaderDatabase.memory() : super(NativeDatabase.memory());
  @override
  int get schemaVersion => 2;
  @override
  Iterable<TableInfo<Table, Object?>> get allTables => const [];
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => const [];
  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await transaction(() async {
        for (final sql in [
          'CREATE TABLE documents (id TEXT PRIMARY KEY, path TEXT NOT NULL, title TEXT NOT NULL, pages INTEGER NOT NULL DEFAULT 0, progress INTEGER NOT NULL DEFAULT 1, updated TEXT NOT NULL, source_path TEXT, source_hash TEXT)',
          'CREATE TABLE annotations (id TEXT PRIMARY KEY, document_id TEXT NOT NULL REFERENCES documents(id) ON DELETE CASCADE, page INTEGER NOT NULL, payload TEXT NOT NULL)',
          'CREATE INDEX annotations_page ON annotations(document_id,page)',
          'CREATE TABLE translation_cache (id TEXT PRIMARY KEY, backend TEXT NOT NULL, payload TEXT NOT NULL, updated TEXT NOT NULL)',
          'CREATE TABLE models (id TEXT PRIMARY KEY, payload TEXT NOT NULL)',
          'CREATE TABLE experiment_runs (id TEXT PRIMARY KEY, payload TEXT NOT NULL)',
          'CREATE TABLE experiment_samples (id TEXT PRIMARY KEY, run_id TEXT NOT NULL, payload TEXT NOT NULL)',
          'CREATE INDEX samples_run ON experiment_samples(run_id)',
          'CREATE TABLE preferences (id TEXT PRIMARY KEY, payload TEXT NOT NULL)',
        ]) {
          await customStatement(sql);
        }
      });
    },
    onUpgrade: (m, from, to) async {
      if (from < 2) {
        await customStatement(
          'ALTER TABLE documents ADD COLUMN source_path TEXT',
        );
        await customStatement(
          'ALTER TABLE documents ADD COLUMN source_hash TEXT',
        );
      }
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys=ON');
    },
  );
  Future<void> putDocument(
    String id,
    String path,
    String title,
    int pages,
  ) async {
    await customStatement(
      'INSERT INTO documents(id,path,title,pages,updated) VALUES(?,?,?,?,?) ON CONFLICT(id) DO UPDATE SET path=excluded.path,title=excluded.title,pages=excluded.pages,updated=excluded.updated',
      [id, path, title, pages, DateTime.now().toIso8601String()],
    );
  }

  Future<List<Map<String, dynamic>>> documents() async => [
    for (final r in await customSelect(
      'SELECT * FROM documents ORDER BY updated DESC',
    ).get())
      r.data,
  ];
  Future<Map<String, dynamic>?> document(String id) async =>
      (await customSelect(
        'SELECT * FROM documents WHERE id=?',
        variables: [Variable(id)],
      ).getSingleOrNull())?.data;

  Future<void> linkSource(String id, String path, String hash) async =>
      customStatement(
        'UPDATE documents SET source_path=?,source_hash=? WHERE id=?',
        [path, hash, id],
      );
  Future<void> progress(String id, int page) async => customStatement(
    'UPDATE documents SET progress=?,updated=? WHERE id=?',
    [page, DateTime.now().toIso8601String(), id],
  );
  Future<void> saveAnnotation(Map<String, dynamic> a) async => customStatement(
    'INSERT INTO annotations VALUES(?,?,?,?) ON CONFLICT(id) DO UPDATE SET page=excluded.page,payload=excluded.payload',
    [a['id'], a['documentId'], a['pageNumber'], jsonEncode(a)],
  );
  Future<List<Map<String, dynamic>>> annotations(String doc) async => [
    for (final r in await customSelect(
      'SELECT payload FROM annotations WHERE document_id=? ORDER BY page,id',
      variables: [Variable(doc)],
    ).get())
      Map<String, dynamic>.from(jsonDecode(r.read<String>('payload'))),
  ];
  Future<void> removeAnnotation(String id) async =>
      customStatement('DELETE FROM annotations WHERE id=?', [id]);
  Future<void> preference(String id, Object value) async => customStatement(
    'INSERT INTO preferences VALUES(?,?) ON CONFLICT(id) DO UPDATE SET payload=excluded.payload',
    [id, jsonEncode(value)],
  );
  Future<dynamic> getPreference(String id) async {
    final r = await customSelect(
      'SELECT payload FROM preferences WHERE id=?',
      variables: [Variable(id)],
    ).getSingleOrNull();
    return r == null ? null : jsonDecode(r.read<String>('payload'));
  }

  Future<void> saveRun(String id, Map<String, dynamic> data) async =>
      customStatement('INSERT OR REPLACE INTO experiment_runs VALUES(?,?)', [
        id,
        jsonEncode(data),
      ]);
  Future<void> saveSample(
    String run,
    String id,
    Map<String, dynamic> data,
  ) async => customStatement(
    'INSERT OR REPLACE INTO experiment_samples VALUES(?,?,?)',
    ['$run/$id', run, jsonEncode(data)],
  );
  Future<List<Map<String, dynamic>>> samples() async => [
    for (final r in await customSelect(
      'SELECT payload FROM experiment_samples ORDER BY rowid DESC',
    ).get())
      Map<String, dynamic>.from(jsonDecode(r.read<String>('payload'))),
  ];
  Future<void> clearMeasurements() async => transaction(() async {
    await customStatement('DELETE FROM experiment_samples');
    await customStatement('DELETE FROM experiment_runs');
  });
  Future<void> cache(String key, String backend, String text) async =>
      customStatement(
        'INSERT OR REPLACE INTO translation_cache VALUES(?,?,?,?)',
        [key, backend, text, DateTime.now().toIso8601String()],
      );
  Future<Map<String, String>> loadCache(String backend) async => {
    for (final r in await customSelect(
      'SELECT id,payload FROM translation_cache WHERE backend=?',
      variables: [Variable(backend)],
    ).get())
      r.read<String>('id'): r.read<String>('payload'),
  };
  Future<void> model(String id, Map<String, dynamic> value) async =>
      customStatement('INSERT OR REPLACE INTO models VALUES(?,?)', [
        id,
        jsonEncode(value),
      ]);
}
