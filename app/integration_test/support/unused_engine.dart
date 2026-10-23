import 'package:contextual_pdf_reader/core/nlp/pipeline.dart';

/// Ensaios de desenho/gestos não devem instalar nem invocar modelos.
class UnusedEngine implements OfflineTranslationEngine, SpanEncoder {
  @override
  String get id => 'interaction-test';
  @override
  bool get isSupported => true;
  @override
  Future<bool> isModelReady() async => false;
  @override
  Future<bool> isReady() async => false;
  @override
  Future<List<String>> listInstalledModels() async => [];
  @override
  Future<void> downloadModelsWithConsent({
    required bool consent,
    bool wifiOnly = true,
  }) async => throw UnsupportedError('Não há download neste teste');
  @override
  Future<String> translateSentence(String text) async =>
      throw UnsupportedError('Não há tradução neste teste');
  @override
  Future<List<double>> encode(String sentence, int start, int end) async =>
      throw UnsupportedError('Não há encoder neste teste');
  @override
  Future<void> unload() async {}
  @override
  Future<void> dispose() async {}
}
