import 'package:flutter/services.dart';

bool isIosOriginalPdf(String source) => source.startsWith('ios-pdf://');

class OriginalPdfSnapshot {
  const OriginalPdfSnapshot(this.name, this.bytes);
  final String name;
  final Uint8List bytes;
}

/// A autorização externa pertence ao iOS; nunca tratar seu identificador como
/// um caminho local ou salvar silenciosamente na cópia de leitura.
abstract interface class OriginalPdfAccess {
  Future<String?> pick();
  Future<OriginalPdfSnapshot> read(String source);
  Future<void> write(String source, Uint8List bytes, String expectedHash);
}

class IosOriginalPdfAccess implements OriginalPdfAccess {
  const IosOriginalPdfAccess();
  static const channel = MethodChannel('br.com.estudos.reader/original_pdf');

  @override
  Future<String?> pick() => channel.invokeMethod<String>('pickPdf');

  @override
  Future<OriginalPdfSnapshot> read(String source) async {
    final result = await channel.invokeMapMethod<String, dynamic>('readPdf', {
      'source': source,
    });
    if (result == null ||
        result['bytes'] is! Uint8List ||
        result['name'] is! String) {
      throw StateError(
        'O iOS não devolveu o PDF original. Selecione-o novamente em Arquivos.',
      );
    }
    return OriginalPdfSnapshot(result['name'], result['bytes']);
  }

  @override
  Future<void> write(String source, Uint8List bytes, String expectedHash) =>
      channel.invokeMethod<void>('writePdf', {
        'source': source,
        'bytes': bytes,
        'expectedHash': expectedHash,
      });
}
