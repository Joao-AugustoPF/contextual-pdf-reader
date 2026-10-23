import 'dart:io';

import 'package:flutter/material.dart';

class TranslationAttribution extends StatelessWidget {
  const TranslationAttribution({super.key});
  @override
  Widget build(BuildContext context) => Platform.isAndroid || Platform.isIOS
      ? Container(
          color: Colors.white,
          padding: const EdgeInsets.all(6),
          child: Image.asset(
            'assets/google-translate.png',
            height: 20,
            fit: BoxFit.contain,
            semanticLabel: 'Powered by Google Translate',
          ),
        )
      : const Text(
          'Tradução local • OPUS-MT / CTranslate2',
          style: TextStyle(fontSize: 11),
        );
}
