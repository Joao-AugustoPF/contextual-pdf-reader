import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart' as mui;
import 'package:pdfrx/pdfrx.dart';

import 'app/services.dart';
import 'features/library/library_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  pdfrxFlutterInitialize();
  try {
    final services = await AppServices.create();
    runApp(
      ProviderScope(
        overrides: [servicesProvider.overrideWithValue(services)],
        child: const ReaderApp(),
      ),
    );
  } catch (e) {
    runApp(
      MaterialApp(
        home: Scaffold(
          body: Center(child: SelectableText('Falha na inicialização: $e')),
        ),
      ),
    );
  }
}

class ReaderApp extends StatelessWidget {
  const ReaderApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Entrelinhas',
    debugShowCheckedModeBanner: false,
    locale: const Locale('pt', 'BR'),
    supportedLocales: const [Locale('pt', 'BR')],
    localizationsDelegates: const [
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    theme: ThemeData(
      colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xff315c4c)),
      useMaterial3: true,
      scaffoldBackgroundColor: const Color(0xfff8faf7),
    ),
    darkTheme: ThemeData(
      colorScheme: ColorScheme.fromSeed(
        seedColor: const Color(0xff81b99b),
        brightness: Brightness.dark,
      ),
      useMaterial3: true,
    ),
    builder: (context, child) =>
        mui.Theme(data: mui.ThemeData(), child: child!),
    home: const LibraryScreen(),
  );
}
