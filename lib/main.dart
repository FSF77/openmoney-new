import 'package:flutter/material.dart';
import 'store/money_store.dart';
import 'ui/app_shell.dart';
import 'ui/theme/liquid_glass.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final store = MoneyStore(autoBoot: false);

  runApp(OpenMoneyApp(store: store));

  // Inicializa a base logo após o primeiro frame estar desenhado na tela
  WidgetsBinding.instance.addPostFrameCallback((_) {
    store.boot();
  });
}

class OpenMoneyApp extends StatelessWidget {
  final MoneyStore store;

  const OpenMoneyApp({super.key, required this.store});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: store,
      builder: (context, _) {
        final colors = OpenMoneyColors(store.isDarkMode);

        return MaterialApp(
          title: 'OpenMoney',
          debugShowCheckedModeBanner: false,
          themeMode: store.isDarkMode ? ThemeMode.dark : ThemeMode.light,
          theme: ThemeData(
            useMaterial3: true,
            brightness: Brightness.light,
            scaffoldBackgroundColor: const Color(0xFFF3F6FC),
            fontFamily: '-apple-system',
          ),
          darkTheme: ThemeData(
            useMaterial3: true,
            brightness: Brightness.dark,
            scaffoldBackgroundColor: const Color(0xFF0A0E17),
            fontFamily: '-apple-system',
          ),
          home: Scaffold(
            backgroundColor: colors.bgPrimary,
            body: OpenMoneyAppShell(store: store),
          ),
        );
      },
    );
  }
}
