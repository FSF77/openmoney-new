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

        final themeColorScheme = ColorScheme.fromSeed(
          seedColor: colors.accent,
          brightness: Brightness.light,
          primary: colors.accent,
          onPrimary: Colors.white,
          primaryContainer: colors.accent.withValues(alpha: 0.16),
          onPrimaryContainer: colors.accent,
          secondary: colors.accent,
          secondaryContainer: colors.accent.withValues(alpha: 0.16),
          onSecondaryContainer: colors.accent,
          tertiary: colors.accent,
          tertiaryContainer: colors.accent.withValues(alpha: 0.16),
          onTertiaryContainer: colors.accent,
        );

        final darkThemeColorScheme = ColorScheme.fromSeed(
          seedColor: colors.accent,
          brightness: Brightness.dark,
          primary: colors.accent,
          onPrimary: Colors.white,
          primaryContainer: colors.accent.withValues(alpha: 0.20),
          onPrimaryContainer: colors.accent,
          secondary: colors.accent,
          secondaryContainer: colors.accent.withValues(alpha: 0.20),
          onSecondaryContainer: colors.accent,
          tertiary: colors.accent,
          tertiaryContainer: colors.accent.withValues(alpha: 0.20),
          onTertiaryContainer: colors.accent,
        );

        return MaterialApp(
          title: 'OpenMoney',
          debugShowCheckedModeBanner: false,
          themeMode: store.isDarkMode ? ThemeMode.dark : ThemeMode.light,
          theme: ThemeData(
            useMaterial3: true,
            colorScheme: themeColorScheme,
            scaffoldBackgroundColor: const Color(0xFFF3F6FC),
            fontFamily: '-apple-system',
            outlinedButtonTheme: OutlinedButtonThemeData(
              style: OutlinedButton.styleFrom(
                foregroundColor: colors.accent,
                side: BorderSide(color: colors.accent.withValues(alpha: 0.35)),
              ),
            ),
            filledButtonTheme: FilledButtonThemeData(
              style: FilledButton.styleFrom(
                backgroundColor: colors.accent,
                foregroundColor: Colors.white,
              ),
            ),
            segmentedButtonTheme: SegmentedButtonThemeData(
              style: SegmentedButton.styleFrom(
                selectedBackgroundColor: colors.accent.withValues(alpha: 0.18),
                selectedForegroundColor: colors.accent,
                foregroundColor: const Color(0xFF475569),
                visualDensity: VisualDensity.compact,
              ),
            ),
            chipTheme: ChipThemeData(
              selectedColor: colors.accent.withValues(alpha: 0.16),
              checkmarkColor: colors.accent,
            ),
          ),
          darkTheme: ThemeData(
            useMaterial3: true,
            colorScheme: darkThemeColorScheme,
            scaffoldBackgroundColor: const Color(0xFF0A0E17),
            fontFamily: '-apple-system',
            outlinedButtonTheme: OutlinedButtonThemeData(
              style: OutlinedButton.styleFrom(
                foregroundColor: colors.accent,
                side: BorderSide(color: colors.accent.withValues(alpha: 0.35)),
              ),
            ),
            filledButtonTheme: FilledButtonThemeData(
              style: FilledButton.styleFrom(
                backgroundColor: colors.accent,
                foregroundColor: Colors.white,
              ),
            ),
            segmentedButtonTheme: SegmentedButtonThemeData(
              style: SegmentedButton.styleFrom(
                selectedBackgroundColor: colors.accent.withValues(alpha: 0.20),
                selectedForegroundColor: colors.accent,
                foregroundColor: const Color(0xFF94A3B8),
                visualDensity: VisualDensity.compact,
              ),
            ),
            chipTheme: ChipThemeData(
              selectedColor: colors.accent.withValues(alpha: 0.18),
              checkmarkColor: colors.accent,
            ),
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
