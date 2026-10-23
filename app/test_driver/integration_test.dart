import 'dart:convert';
import 'dart:io';

import 'package:integration_test/integration_test_driver_extended.dart';

Future<void> main() async {
  await Directory('../reports').create(recursive: true);
  await integrationDriver(
    writeResponseOnFailure: true,
    onScreenshot:
        (String name, List<int> bytes, [Map<String, Object?>? args]) async {
          await File('../reports/$name.png').writeAsBytes(bytes);
          return true;
        },
    responseDataCallback: (data) async {
      if (data == null) return;
      for (final entry in {
        'benchmarkAndroid': 'benchmark-android',
        'flow': 'integration-flow',
        'largeDocument': 'large-document',
        'comparisonFlow': 'comparison-flow',
      }.entries) {
        if (data[entry.key] != null) {
          await File('../reports/${entry.value}.json').writeAsString(
            const JsonEncoder.withIndent('  ').convert(data[entry.key]),
          );
        }
      }
      if (data['benchmarkAndroidCsv'] != null) {
        await File('../reports/benchmark-android.csv')
            .writeAsString(data['benchmarkAndroidCsv'] as String);
      }
      if (data['annotatedPdfBase64'] != null) {
        await File('../output/pdf/exportado-android.pdf')
            .writeAsBytes(base64Decode(data['annotatedPdfBase64'] as String));
      }
    },
  );
}
