import 'package:flutter/material.dart';
import 'store/money_store.dart';
import 'ui/app_shell.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  final store = MoneyStore();
  runApp(OpenMoneyApp(store: store));
}

class OpenMoneyApp extends StatelessWidget {
  final MoneyStore store;
  const OpenMoneyApp({super.key, required this.store});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: store,
      builder: (context, _) {
        return MaterialApp(
          title: store.windowTitle,
          debugShowCheckedModeBanner: false,
          themeMode: store.isDarkMode ? ThemeMode.dark : ThemeMode.light,
          theme: ThemeData(
            useMaterial3: true,
            brightness: Brightness.light,
            colorSchemeSeed: const Color(0xFF0EA5E9),
            scaffoldBackgroundColor: const Color(0xFFF3F6FC),
          ),
          darkTheme: ThemeData(
            useMaterial3: true,
            brightness: Brightness.dark,
            colorSchemeSeed: const Color(0xFF0EA5E9),
            scaffoldBackgroundColor: const Color(0xFF0A0E17),
          ),
          home: OpenMoneyAppShell(store: store),
        );
      },
    );
  }
}
