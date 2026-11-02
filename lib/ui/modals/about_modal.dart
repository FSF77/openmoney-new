import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../services/update_service.dart';
import '../theme/liquid_glass.dart';

/// Exibe o modal "Sobre o OpenMoney" com informações de versão, build,
/// plataforma e atalho para verificação de atualizações.
Future<void> showAboutOpenMoneyModal(
  BuildContext context,
  OpenMoneyColors colors,
) async {
  await OpenMoneyVersion.init();
  if (!context.mounted) return;

  await showDialog(
    context: context,
    builder: (ctx) => _AboutOpenMoneyDialog(colors: colors),
  );
}

class _AboutOpenMoneyDialog extends StatelessWidget {
  final OpenMoneyColors colors;

  const _AboutOpenMoneyDialog({required this.colors});

  void _openUrl(String url) {
    if (kIsWeb) return;
    try {
      if (Platform.isMacOS) {
        Process.run('open', [url]);
      } else if (Platform.isWindows) {
        Process.run('cmd', ['/c', 'start', '', url]);
      } else if (Platform.isLinux) {
        Process.run('xdg-open', [url]);
      }
    } catch (_) {}
  }

  String _platformName() {
    if (kIsWeb) return 'Web';
    if (Platform.isWindows) return 'Windows';
    if (Platform.isMacOS) return 'macOS';
    if (Platform.isLinux) return 'Linux';
    if (Platform.isAndroid) return 'Android';
    if (Platform.isIOS) return 'iOS';
    return Platform.operatingSystem;
  }

  @override
  Widget build(BuildContext context) {
    final platform = _platformName();
    final isWin = !kIsWeb && Platform.isWindows;

    return Dialog(
      backgroundColor: colors.bgSecondary,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colors.borderGlass),
      ),
      child: SizedBox(
        width: 440,
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Ícone com gradiente
              Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF10B981), Color(0xFF047857)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: const Color(0xFF10B981).withValues(alpha: 0.35),
                      blurRadius: 16,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.account_balance_wallet_rounded,
                  color: Colors.white,
                  size: 34,
                ),
              ),
              const SizedBox(height: 16),

              // Nome do App
              Text(
                'OpenMoney',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  color: colors.textPrimary,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(height: 4),

              // Versão e Build
              Text(
                'Versão ${OpenMoneyVersion.version} (Build ${OpenMoneyVersion.build})',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: colors.textSecondary,
                ),
              ),
              const SizedBox(height: 4),

              Text(
                'Controle Financeiro Pessoal e Empresarial',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  color: colors.textSecondary.withValues(alpha: 0.8),
                ),
              ),
              const SizedBox(height: 18),

              // Card com detalhes da plataforma e base
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: colors.surfaceGlass,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: colors.borderGlass),
                ),
                child: Column(
                  children: [
                    _buildInfoRow(
                      label: 'Plataforma',
                      value: isWin ? 'Windows (x64)' : platform,
                      colors: colors,
                    ),
                    const Divider(height: 14),
                    _buildInfoRow(
                      label: 'Base de Dados',
                      value: 'Schema v7 • Centavos Inteiros',
                      colors: colors,
                    ),
                    const Divider(height: 14),
                    _buildInfoRow(
                      label: 'Licença & Código',
                      value: 'Open Source (GitHub)',
                      colors: colors,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),

              Text(
                '© 2026 OpenMoney • FSF Consultoria',
                style: TextStyle(
                  fontSize: 11,
                  color: colors.textSecondary.withValues(alpha: 0.65),
                ),
              ),
              const SizedBox(height: 20),

              // Ações inferiores
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton.icon(
                    icon: const Icon(Icons.open_in_browser, size: 16),
                    label: const Text('GitHub'),
                    onPressed: () => _openUrl(OpenMoneyVersion.releasesRepoUrl),
                  ),
                  Row(
                    children: [
                      OutlinedButton.icon(
                        icon: const Icon(Icons.system_update_alt, size: 15),
                        label: const Text('Atualizações'),
                        onPressed: () {
                          Navigator.pop(context);
                          UpdateService.showUpdateDialog(context, manual: true);
                        },
                      ),
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('OK'),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoRow({
    required String label,
    required String value,
    required OpenMoneyColors colors,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: colors.textSecondary,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: colors.textPrimary,
          ),
        ),
      ],
    );
  }
}
