import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../services/platform_io.dart';
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
    webOpenExternalUrl(url);
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
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colors.borderGlass),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Logo Oficial OpenMoney
              ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Image.asset(
                  'logo/openmoney_app_icon.png',
                  width: 68,
                  height: 68,
                  filterQuality: FilterQuality.medium,
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

              // Card com detalhes da plataforma
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
                      label: 'Licença & Código',
                      value: 'Open Source (GitHub)',
                      colors: colors,
                    ),
                    const Divider(height: 14),
                    _buildInfoRow(
                      label: 'Contato',
                      value: 'contato@openmoney.app.br',
                      colors: colors,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),

              // Botão Apoiar o Projeto (Link na Bio)
              InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () =>
                    _openUrl('https://linknabio.gg/fabianodesouzafernandes'),
                child: Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF59E0B).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: const Color(0xFFF59E0B).withValues(alpha: 0.45),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.local_cafe_rounded,
                        size: 18,
                        color: Color(0xFFF59E0B),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'Apoiar o Projeto',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: colors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),

              if (kIsWeb) ...[
                // Botões de download dos apps Desktop (macOS e Windows)
                Row(
                  children: [
                    Expanded(
                      child: Tooltip(
                        message:
                            'Baixar aplicativo nativo para macOS (v${OpenMoneyVersion.version})',
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 10,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          icon: const Icon(Icons.apple, size: 16),
                          label: const Text(
                            'App macOS',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          onPressed: () =>
                              _openUrl(OpenMoneyVersion.macosDownloadUrl),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Tooltip(
                        message:
                            'Baixar aplicativo nativo para Windows (v${OpenMoneyVersion.version})',
                        child: OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 10,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                          ),
                          icon: const Icon(
                            Icons.window_rounded,
                            size: 15,
                            color: Color(0xFF00ADEF),
                          ),
                          label: const Text(
                            'App Windows',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          onPressed: () =>
                              _openUrl(OpenMoneyVersion.windowsDownloadUrl),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
              ],

              Text(
                '© 2026 OpenMoney • FSF Consultoria',
                style: TextStyle(
                  fontSize: 11,
                  color: colors.textSecondary.withValues(alpha: 0.65),
                ),
              ),
              const SizedBox(height: 18),

              // Ações inferiores
              SizedBox(
                width: double.infinity,
                child: Wrap(
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    TextButton.icon(
                      style: TextButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                      ),
                      icon: const Icon(Icons.open_in_browser, size: 15),
                      label: const Text('GitHub', style: TextStyle(fontSize: 12.5)),
                      onPressed: () => _openUrl(OpenMoneyVersion.releasesRepoUrl),
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (!kIsWeb) ...[
                          OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            ),
                            icon: const Icon(Icons.system_update_alt, size: 15),
                            label: const Text('Atualizações', style: TextStyle(fontSize: 12.5)),
                            onPressed: () {
                              Navigator.pop(context);
                              UpdateService.showUpdateDialog(context, manual: true);
                            },
                          ),
                          const SizedBox(width: 8),
                        ],
                        FilledButton(
                          style: FilledButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          ),
                          onPressed: () => Navigator.pop(context),
                          child: const Text('OK', style: TextStyle(fontSize: 12.5)),
                        ),
                      ],
                    ),
                  ],
                ),
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
      children: [
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: colors.textSecondary,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            value,
            textAlign: TextAlign.end,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: colors.textPrimary,
            ),
          ),
        ),
      ],
    );
  }
}
