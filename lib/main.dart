import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'services/cloud_sync_service.dart';
import 'services/shortcut_url_service.dart';
import 'services/update_service.dart';
import 'store/money_store.dart';
import 'ui/app_shell.dart';
import 'ui/theme/liquid_glass.dart';
import 'ui/views/auth_view.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  ShortcutUrlService.instance.captureFromCurrentUrl();
  await OpenMoneyVersion.init();

  final store = MoneyStore(autoBoot: false);
  if (kIsWeb) {
    store.boot();
  }

  runApp(OpenMoneyApp(store: store));

  if (!kIsWeb) {
    // Inicializa a base local logo após o primeiro frame estar desenhado na tela
    WidgetsBinding.instance.addPostFrameCallback((_) {
      store.boot();
    });
  }
}

class OpenMoneyApp extends StatelessWidget {
  final MoneyStore store;

  const OpenMoneyApp({super.key, required this.store});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([store, CloudSyncService.instance]),
      builder: (context, _) {
        final colors = OpenMoneyColors(store.isDarkMode);
        final cloud = CloudSyncService.instance;
        final needsWebAuth = kIsWeb &&
            (!cloud.isAuthenticated || cloud.isWebAuthFlowInProgress) &&
            !cloud.isWebOfflineGuestMode;

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
          builder: (context, child) {
            if (child == null) return const SizedBox.shrink();
            return MediaQuery(
              data: MediaQuery.of(context).copyWith(
                textScaler: TextScaler.linear(store.fontScale),
              ),
              child: child,
            );
          },
          home: needsWebAuth
              ? AuthView(store: store)
              : Scaffold(
                  backgroundColor: colors.bgPrimary,
                  body: OpenMoneyAppShell(store: store),
                ),
        );
      },
    );
  }
}
