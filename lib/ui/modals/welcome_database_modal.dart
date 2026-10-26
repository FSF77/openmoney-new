import 'package:flutter/material.dart';
import '../../services/native_file_picker.dart';
import '../../store/money_store.dart';
import '../theme/liquid_glass.dart';

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
      final selectedPath = await NativeFilePicker.pickFile(
        title: 'Selecione sua base de dados OpenMoney (.json)',
        allowedExtensions: ['json'],
      );

      if (selectedPath != null && selectedPath.isNotEmpty) {
        final success = widget.store.openDatabaseFromPath(selectedPath);
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
      final savePath = await NativeFilePicker.saveFile(
        title: 'Escolha onde salvar sua nova base de dados',
        defaultName: 'openmoney.json',
      );

      if (savePath != null && savePath.isNotEmpty) {
        widget.store.createNewDatabaseAtPath(savePath);
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

  @override
  Widget build(BuildContext context) {
    final colors = OpenMoneyColors(widget.store.isDarkMode);

    return Scaffold(
      backgroundColor: colors.bgPrimary,
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 580),
            child: GlassCard(
              padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 36),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [colors.accent, colors.accentIndigo],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: colors.accent.withValues(alpha: 0.35),
                          blurRadius: 18,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.account_balance,
                      color: Colors.white,
                      size: 40,
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'Bem-vindo ao OpenMoney',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                      color: colors.textPrimary,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Controle financeiro rigoroso com total privacidade.\nSeus dados permanecem sempre sob o seu controle em um arquivo .json próprio.',
                    style: TextStyle(
                      fontSize: 14,
                      color: colors.textSecondary,
                      height: 1.45,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 32),
                  if (_isLoading) ...[
                    const CircularProgressIndicator(),
                    const SizedBox(height: 16),
                    Text(
                      'Aguardando seleção de arquivo...',
                      style: TextStyle(color: colors.textSecondary),
                    ),
                  ] else ...[
                    // Opção 1: Abrir base existente via gerenciador nativo
                    InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: _handleOpenExistingFile,
                      child: Container(
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: colors.surfaceCard,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: colors.accent.withValues(alpha: 0.4),
                            width: 1.5,
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: colors.accent.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(
                                Icons.folder_open_rounded,
                                color: colors.accent,
                                size: 28,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Já tenho uma base de dados',
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                      color: colors.textPrimary,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Procurar meu arquivo openmoney.json no Finder (iCloud Drive, OneDrive, etc.)',
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      color: colors.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Icon(
                              Icons.arrow_forward_ios,
                              size: 16,
                              color: colors.textMuted,
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Opção 2: Criar nova base escolhendo onde salvar via gerenciador nativo
                    InkWell(
                      borderRadius: BorderRadius.circular(14),
                      onTap: _handleCreateNewFile,
                      child: Container(
                        padding: const EdgeInsets.all(18),
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
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: colors.income.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Icon(
                                Icons.add_circle_outline_rounded,
                                color: colors.income,
                                size: 28,
                              ),
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Criar uma nova base em branco',
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w700,
                                      color: colors.textPrimary,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Escolher a pasta no Finder para salvar o novo arquivo openmoney.json',
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      color: colors.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Icon(
                              Icons.arrow_forward_ios,
                              size: 16,
                              color: colors.textMuted,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                  if (_errorMessage != null) ...[
                    const SizedBox(height: 20),
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
                  const SizedBox(height: 24),
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
          ),
        ),
      ),
    );
  }
}
