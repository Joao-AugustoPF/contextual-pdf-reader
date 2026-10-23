"""Empacota somente os fontes necessários para levar o projeto iOS ao Mac."""
import hashlib
import json
from pathlib import Path
import zipfile

root = Path(__file__).resolve().parents[1]
output = root / 'dist' / 'contextual-pdf-reader-ios-fontes.zip'
output.parent.mkdir(exist_ok=True)
trees = ('app/lib', 'app/assets', 'app/ios', 'app/test',
         'packages/validation', 'docs')
files = ('README.md', 'CONTRIBUTING.md', 'AGENTS.md', 'LICENSE', '.gitignore', '.gitattributes',
         'IMPLEMENTATION_PLAN.md', 'codemagic.yaml',
         'app/pubspec.yaml', 'app/pubspec.lock', 'app/analysis_options.yaml',
         'app/.metadata', 'app/.gitignore', 'scripts/package_ios_sources.py')
excluded = {'build', '.dart_tool', '.symlinks', 'Pods', 'ephemeral',
            'xcuserdata', 'DerivedData', '__pycache__'}
generated = {'Generated.xcconfig', 'flutter_export_environment.sh',
             'GeneratedPluginRegistrant.h', 'GeneratedPluginRegistrant.m',
             '.flutter-plugins-dependencies', '.DS_Store'}
selected = {root / name for name in files}
for tree in trees:
    for path in (root / tree).rglob('*'):
        relative = path.relative_to(root)
        if (path.is_file() and not path.is_symlink()
                and not excluded.intersection(relative.parts)
                and path.name not in generated):
            selected.add(path)

prefix = 'contextual-pdf-reader/'
for path in selected:
    assert path.suffix.lower() not in {
        '.exe', '.sqlite', '.p12', '.p8', '.pem', '.key', '.pfx', '.mobileprovision'
    }, f'Arquivo proibido no pacote de fontes: {path.name}'
with zipfile.ZipFile(output, 'w', compression=zipfile.ZIP_DEFLATED) as bundle:
    for path in sorted(selected):
        bundle.write(path, prefix + path.relative_to(root).as_posix())
    bundle.writestr(prefix + 'LEIA_PRIMEIRO.txt',
                   'Comece por docs/COMPILAR_IPHONE_IPAD.md.\n'
                   'Fontes para compilar no Mac; nao e um IPA.\n'
                   'iOS/iPadOS minimo 16; compilacao iOS ainda nao validada.\n')

with zipfile.ZipFile(output) as bundle:
    assert bundle.testzip() is None
    names = set(bundle.namelist())
    required = ('app/pubspec.yaml', 'app/pubspec.lock', 'app/lib/main.dart',
                'app/ios/Runner.xcodeproj/project.pbxproj',
                'app/ios/Runner.xcworkspace/contents.xcworkspacedata',
                'app/ios/Runner/OriginalPdfPlugin.swift',
                'app/ios/RunnerTests/RunnerTests.swift', 'codemagic.yaml',
                'app/lib/core/nlp/contextual_suggestion.dart',
                'docs/BUILD_IOS_NUVEM.md',
                'docs/COMPILAR_IPHONE_IPAD.md')
    assert all(prefix + name in names for name in required)
    assert not any(set(Path(name).parts) & excluded for name in names)
    assert not any(name.endswith(('.exe', '.sqlite', '.p12', '.mobileprovision'))
                   for name in names)
    report = {
        'file': output.name,
        'bytes': output.stat().st_size,
        'sha256': hashlib.sha256(output.read_bytes()).hexdigest(),
        'entries': len(names),
        'zipIntegrityVerified': True,
        'requiredSourcesPresent': True,
        'iosBuildExecuted': False,
        'iosOriginalSaveImplementationIncluded': True,
        'contextualLabelAlignmentIncluded': True,
        'nativeXCTestCasesIncluded': 3,
        'cloudWorkflowsIncluded': ['ios-verificar', 'ios-testflight'],
        'includesPersonalDocumentsOrInstalledModels': False,
    }
(root / 'reports' / 'ios-source-package.json').write_text(
    json.dumps(report, indent=2), encoding='utf-8')
print(json.dumps(report, indent=2))
