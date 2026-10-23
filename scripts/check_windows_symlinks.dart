import 'dart:io';

void main() {
  if (!Platform.isWindows) return;
  // Mesmo filesystem do projeto e mesma API usada pelo Flutter.
  final probe = Directory.current.createTempSync('.windows-symlink-check-');
  final target = Directory('${probe.path}/target')..createSync();
  final link = Link('${probe.path}/link');
  try {
    link.createSync(target.absolute.path);
  } on FileSystemException catch (error) {
    stderr.writeln('Nao foi possivel criar links simbolicos neste projeto.');
    stderr.writeln(error);
    if (error.osError?.errorCode == 1314) {
      stderr.writeln(
        'Abra Start-Process ms-settings:developers no PowerShell, '
        'ative o Modo de Desenvolvedor e repita o empacotamento.',
      );
    }
    exitCode = 1;
  } finally {
    if (link.existsSync()) link.deleteSync();
    target.deleteSync();
    probe.deleteSync();
  }
}
