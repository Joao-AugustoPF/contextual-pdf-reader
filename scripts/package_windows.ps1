$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path $PSScriptRoot -Parent
$flutterExe = Join-Path $projectRoot '.tools\flutter\bin\flutter.bat'
if (-not (Test-Path $flutterExe)) { $flutterExe = 'flutter' }
$dartExe = Join-Path $projectRoot '.tools\flutter\bin\cache\dart-sdk\bin\dart.exe'
if (-not (Test-Path $dartExe)) { $dartExe = 'dart' }
Push-Location $projectRoot
try {
  # pub get pode pular os links quando o lock nao mudou; testa a permissao real.
  & $dartExe scripts\check_windows_symlinks.dart
  if ($LASTEXITCODE -ne 0) { throw 'Links simbolicos indisponiveis; consulte o diagnostico acima. O motor nao foi reempacotado.' }
  Push-Location app
  try {
    & $flutterExe pub get
    if ($LASTEXITCODE -ne 0) {
      throw 'Falha ao preparar os plugins Flutter; consulte a saida acima. Para o erro de symlink, abra Start-Process ms-settings:developers e ative o Modo de Desenvolvedor antes de repetir.'
    }
  }
  finally { Pop-Location }
  & '.\.venv\Scripts\pyinstaller.exe' --noconfirm --name reader-runtime --onedir --collect-all ctranslate2 --collect-all sentencepiece --collect-all onnxruntime --collect-all tokenizers ml\runtime.py
  if ($LASTEXITCODE -ne 0) { throw 'Falha no empacotamento do motor' }
  Push-Location app
  try { & $flutterExe build windows --release; if ($LASTEXITCODE -ne 0) { throw 'Falha na compilacao Flutter Windows; consulte o erro original acima. Execute flutter doctor -v para verificar o ambiente.' } }
  finally { Pop-Location }
  $bundle = Join-Path $projectRoot 'app\build\windows\x64\runner\Release'
  $runtimeTarget = Join-Path $bundle 'runtime'
  New-Item -ItemType Directory -Force $runtimeTarget | Out-Null
  Get-ChildItem -LiteralPath (Join-Path $projectRoot 'dist\reader-runtime') | Copy-Item -Destination $runtimeTarget -Recurse -Force
  Copy-Item -LiteralPath (Join-Path $projectRoot 'docs\LICENCAS.md') -Destination $bundle
  Write-Output "Aplicativo com motor local em $bundle. Modelos são instalados pela interface com consentimento."
}
finally { Pop-Location }
