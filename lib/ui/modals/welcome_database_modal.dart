import 'package:flutter/material.dart';
import '../../services/cloud_sync_service.dart';
import '../../services/native_file_picker.dart';
import '../../services/platform_io.dart';
import '../../store/money_store.dart';
import '../theme/liquid_glass.dart';
import 'cloud_account_modal.dart';

/// Tela inicial de Boas-Vindas apresentada quando nenhuma base de dados estiver configurada ainda
class WelcomeDatabaseSelectionScreen extends StatefulWidget {
  final MoneyStore store;

  const WelcomeDatabaseSelectionScreen({super.key, required this.store});

  @override
  State<WelcomeDatabaseSelectionScreen> createState() =>
      _WelcomeDatabaseSelectionScreenState();
}

class _WelcomeDatabaseSelectionScreenState
    extends State<WelcomeDatabaseSelectionScreen> {
  bool _isLoading = false;
  String? _errorMessage;

  Future<void> _handleOpenExistingFile() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final res = await NativeFilePicker.pickFileWithMetadata(
        title: 'Selecione sua base de dados OpenMoney (.json)',
        allowedExtensions: ['json'],
      );

      if (res != null && res.path.isNotEmpty) {
        final success = widget.store.openDatabaseFromPath(
          res.path,
          bookmarkData: res.bookmark,
        );
        if (!success) {
          setState(() {
            _errorMessage =
                'Não foi possível abrir o arquivo selecionado. Verifique se é um arquivo .json válido.';
          });
        }
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Erro ao selecionar o arquivo: $e';
      });
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _handleCreateNewFile() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final res = await NativeFilePicker.saveFileWithMetadata(
        title: 'Escolha onde salvar sua nova base de dados',
        defaultName: 'openmoney.json',
      );

      if (res != null && res.path.isNotEmpty) {
        widget.store.createNewDatabaseAtPath(
          res.path,
          bookmarkData: res.bookmark,
        );
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Erro ao escolher local para salvar: $e';
      });
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _handleOpenCloudModal() async {
    await showCloudAccountModal(context, widget.store);
    if (CloudSyncService.instance.isAuthenticated) {
      await widget.store.switchToCloudMode();
      widget.store.showWelcomeScreen = false;
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = OpenMoneyColors(widget.store.isDarkMode);

    return Scaffold(
      backgroundColor: colors.bgPrimary,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 28),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                GlassCard(
                  padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(20),
                    child: Image.asset(
                      'logo/openmoney_app_icon.png',
                      width: 68,
                      height: 68,
                      filterQuality: FilterQuality.medium,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Bem-vindo ao OpenMoney',
                    style: TextStyle(
                      fontSize: 23,
                      fontWeight: FontWeight.w900,
                      color: colors.textPrimary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Controle financeiro rigoroso com total privacidade.\nEscolha como deseja iniciar e armazenar seus dados:',
                    style: TextStyle(
                      fontSize: 13.5,
                      color: colors.textSecondary,
                      height: 1.4,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 26),
                  if (_isLoading) ...[
                    const CircularProgressIndicator(),
                    const SizedBox(height: 16),
                    Text(
                      'Aguardando seleção...',
                      style: TextStyle(color: colors.textSecondary),
                    ),
                  ] else ...[
                    // ========================================================
                    // Bloco 1: Base Local (.json)
                    // ========================================================
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'USO LOCAL (ARQUIVO NO COMPUTADOR)',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.5,
                          color: colors.textMuted,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: _handleOpenExistingFile,
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: colors.surfaceCard,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: colors.accent.withValues(alpha: 0.35),
                            width: 1.5,
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: colors.accent.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(
                                Icons.folder_open_rounded,
                                color: colors.accent,
                                size: 24,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Abrir base local existente (.json)',
                                    style: TextStyle(
                                      fontSize: 14.5,
                                      fontWeight: FontWeight.w700,
                                      color: colors.textPrimary,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    'Procurar arquivo openmoney.json no seu computador, iCloud Drive ou OneDrive',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: colors.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Icon(
                              Icons.arrow_forward_ios,
                              size: 15,
                              color: colors.textMuted,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: _handleCreateNewFile,
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: colors.surfaceCard,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: colors.borderGlass,
                            width: 1.5,
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: colors.income.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(
                                Icons.add_circle_outline_rounded,
                                color: colors.income,
                                size: 24,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Criar nova base local em branco (.json)',
                                    style: TextStyle(
                                      fontSize: 14.5,
                                      fontWeight: FontWeight.w700,
                                      color: colors.textPrimary,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    'Escolher onde salvar um novo arquivo openmoney.json no computador',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: colors.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Icon(
                              Icons.arrow_forward_ios,
                              size: 15,
                              color: colors.textMuted,
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 22),

                    // ========================================================
                    // Bloco 2: OpenMoney Cloud (Sync v2 em Tempo Real)
                    // ========================================================
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        'OPENMONEY CLOUD (SINCRONIZAÇÃO EM TEMPO REAL)',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.5,
                          color: colors.accentGreen,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: _handleOpenCloudModal,
                      child: Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: colors.surfaceCard,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: colors.accentGreen.withValues(alpha: 0.35),
                            width: 1.5,
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: colors.accentGreen.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(
                                Icons.cloud_sync_rounded,
                                color: colors.accentGreen,
                                size: 24,
                              ),
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Conectar em Conta Online ou Criar Nova Conta',
                                    style: TextStyle(
                                      fontSize: 14.5,
                                      fontWeight: FontWeight.w700,
                                      color: colors.textPrimary,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    'Sincronize automaticamente seus lançamentos em tempo real entre Web, Mac, Windows e iPhone',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: colors.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Icon(
                              Icons.arrow_forward_ios,
                              size: 15,
                              color: colors.textMuted,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                  if (_errorMessage != null) ...[
                    const SizedBox(height: 18),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: colors.expense.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: colors.expense.withValues(alpha: 0.4),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.error_outline,
                              color: colors.expense, size: 20),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _errorMessage!,
                              style: TextStyle(
                                color: colors.expense,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 22),
                  TextButton.icon(
                    icon: Icon(
                      widget.store.isDarkMode
                          ? Icons.light_mode_outlined
                          : Icons.dark_mode_outlined,
                      size: 18,
                    ),
                    label: Text(
                      widget.store.isDarkMode ? 'Tema Claro' : 'Tema Escuro',
                      style: const TextStyle(fontSize: 13),
                    ),
                    onPressed: widget.store.toggleThemeMode,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            _buildFooter(colors),
          ],
        ),
      ),
    ),
  ),
);
  }

  Widget _buildFooter(OpenMoneyColors colors) {
    return Wrap(
      alignment: WrapAlignment.center,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 12,
      runSpacing: 8,
      children: [
        // Botão Apoiar o Projeto (Link na Bio)
        Tooltip(
          message: 'Apoie o desenvolvimento contínuo do OpenMoney',
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () => webOpenExternalUrl(
              'https://linknabio.gg/fabianodesouzafernandes',
            ),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                color: colors.bgSecondary.withValues(alpha: 0.88),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: const Color(0xFFF59E0B).withValues(alpha: 0.45),
                  width: 1.1,
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFF59E0B).withValues(alpha: 0.08),
                    blurRadius: 10,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.coffee_rounded,
                    size: 15,
                    color: Color(0xFFF59E0B),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'Apoiar o Projeto',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: colors.textPrimary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),

        // E-mail de Contato
        Tooltip(
          message: 'Enviar mensagem para contato@openmoney.app.br',
          child: InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () => webOpenExternalUrl('mailto:contato@openmoney.app.br'),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                color: colors.bgSecondary.withValues(alpha: 0.72),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: colors.borderGlass),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.mail_outline_rounded,
                    size: 14,
                    color: colors.textSecondary,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    'contato@openmoney.app.br',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: colors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
