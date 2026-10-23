import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../nlp/pipeline.dart';

class SidecarEngine implements OfflineTranslationEngine, SpanEncoder {
  SidecarEngine(this.executable, this.arguments, {this.installModels});
  final String executable;
  final List<String> arguments;
  final Future<void> Function()? installModels;
  Timer? _idle;
  Process? _process;
  Future<void>? _starting;
  final _pending = <int, Completer<Map<String, dynamic>>>{};
  int _sequence = 0;
  @override
  String get id => 'ctranslate2-argos-en_pb-1.9-int8';
  @override
  bool get isSupported =>
      Platform.isWindows || Platform.isLinux || Platform.isMacOS;
  Future<void> _start() async {
    if (_process != null) return;
    if (_starting != null) return _starting;
    _starting = _launch();
    try {
      await _starting;
    } finally {
      _starting = null;
    }
  }

  Future<void> _launch() async {
    final p = await Process.start(executable, arguments, runInShell: false);
    _process = p;
    p.stdout.transform(utf8.decoder).transform(const LineSplitter()).listen((
      line,
    ) {
      try {
        final j = jsonDecode(line) as Map<String, dynamic>;
        final c = _pending.remove(j['id']);
        if (c == null) return;
        if (j['error'] != null) {
          c.completeError(StateError(j['error']));
        } else {
          c.complete(Map<String, dynamic>.from(j['result']));
        }
      } catch (_) {
        /* Linhas inválidas nunca viram respostas válidas. */
      }
    });
    // Não encaminha texto privado do stderr para telemetria.
    p.stderr.drain<void>();
    unawaited(
      p.exitCode.then((code) {
        if (!identical(_process, p)) return;
        _process = null;
        for (final c in _pending.values) {
          if (!c.isCompleted) {
            c.completeError(StateError('Motor local encerrou ($code)'));
          }
        }
        _pending.clear();
      }),
    );
  }

  Future<Map<String, dynamic>> request(Map<String, dynamic> command) async {
    await _start();
    final id = ++_sequence, c = Completer<Map<String, dynamic>>();
    _pending[id] = c;
    _process!.stdin.writeln(jsonEncode({...command, 'id': id}));
    try {
      return await c.future.timeout(const Duration(minutes: 2));
    } finally {
      _pending.remove(id);
    }
  }

  @override
  Future<bool> isModelReady() async =>
      (await request({'op': 'status'}))['translatorReady'] == true;
  @override
  Future<bool> isReady() async =>
      (await request({'op': 'status'}))['minilmReady'] == true;
  @override
  Future<List<String>> listInstalledModels() async => [
    if (await isModelReady()) id,
  ];
  @override
  Future<void> downloadModelsWithConsent({
    required bool consent,
    bool wifiOnly = true,
  }) async {
    if (!consent) throw StateError('Download exige consentimento');
    if (installModels == null) {
      throw UnsupportedError('Instalador não configurado neste processo CLI');
    }
    await installModels!();
  }

  @override
  Future<String> translateSentence(String text) async =>
      (await request({'op': 'translate', 'text': text}))['text'] as String;
  @override
  Future<List<double>> encode(String sentence, int start, int end) async {
    _idle?.cancel();
    final response = await request({
      'op': 'embed',
      'sentence': sentence,
      'start': sentence.substring(0, start).runes.length,
      'end': sentence.substring(0, end).runes.length,
    });
    _idle = Timer(const Duration(minutes: 2), () {
      unawaited(unload());
    });
    return List<num>.from(response['vector']).map((n) => n.toDouble()).toList();
  }

  @override
  Future<void> unload() async {
    _idle?.cancel();
    if (_process != null) await request({'op': 'unload'});
  }

  @override
  Future<void> dispose() async {
    _idle?.cancel();
    final p = _process;
    _process = null;
    for (final c in _pending.values) {
      if (!c.isCompleted) c.completeError(StateError('Motor local descartado'));
    }
    _pending.clear();
    await p?.stdin.close();
    p?.kill();
  }
}
