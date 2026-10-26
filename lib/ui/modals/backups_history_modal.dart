import 'package:flutter/material.dart';
import '../../services/backup_manager.dart';
import '../../store/money_store.dart';
import '../theme/liquid_glass.dart';

Future<void> showBackupsHistoryModal(
  BuildContext context,
  MoneyStore store,
) async {
  await showDialog(
    context: context,
    builder: (ctx) => _BackupsHistoryDialog(store: store),
  );
}

class _BackupsHistoryDialog extends StatefulWidget {
  final MoneyStore store;
  const _BackupsHistoryDialog({required this.store});

  @override
  State<_BackupsHistoryDialog> createState() => _BackupsHistoryDialogState();
}

class _BackupsHistoryDialogState extends State<_BackupsHistoryDialog> {
  List<BackupFileInfo> _backups = [];
  bool _isLoading = false;
  String? _statusMessage;
  bool _isSuccess = true;

  @override
  void initState() {
    super.initState();
    _refreshList();
  }

  void _refreshList() {
    setState(() {
      _backups = widget.store.availableBackups();
    });
  }

  Future<void> _createBackupNow() async {
    setState(() => _isLoading = true);
    final path = await widget.store.createManualZipBackup();
    setState(() => _isLoading = false);
    if (path != null) {
      _statusMessage = '✓ Backup compactado criado com sucesso!';
      _isSuccess = true;
      _refreshList();
    } else {
      _statusMessage = 'Erro ao criar backup manual.';
      _isSuccess = false;
    }
  }

  void _confirmRestore(BackupFileInfo item) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Restaurar Base de Dados?'),
        content: Text(
          'Deseja substituir a base de dados atual pelo backup "${item.filename}"?\n\n'
          'Os lançamentos atuais serão substituídos pelo conteúdo desse snapshot.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () async {
              Navigator.pop(ctx);
              setState(() => _isLoading = true);
              final ok = await widget.store.restoreDatabaseFromZip(item.path);
              setState(() => _isLoading = false);
              if (mounted) {
                if (ok) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('✓ Base restaurada com sucesso a partir do backup!'),
                      backgroundColor: Colors.teal,
                    ),
                  );
                  Navigator.pop(context);
                } else {
                  setState(() {
                    _statusMessage = 'Falha ao restaurar o backup selecionado.';
                    _isSuccess = false;
                  });
                }
              }
            },
            child: const Text('Restaurar e Recarregar'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colors = OpenMoneyColors(isDark);

    return Dialog(
      backgroundColor: colors.bgSecondary,
      surfaceTintColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colors.borderGlass, width: 1),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: 640,
          maxHeight: 520,
          minWidth: 480,
          minHeight: 380,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header estilo LiquidGlass / OpenMoney
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF162032) : const Color(0xFFF1F5F9),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                border: Border(
                  bottom: BorderSide(color: colors.borderGlass, width: 1),
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.blueAccent.withValues(alpha: 0.15),
                    ),
                    child: const Icon(
                      Icons.archive_outlined,
                      color: Colors.blueAccent,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Histórico de Backups Automáticos',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: colors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Cópias diárias compactadas (.zip) com retenção de segurança de 7 dias.',
                          style: TextStyle(
                            fontSize: 12,
                            color: colors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.tonalIcon(
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('Criar Backup Agora'),
                    onPressed: _isLoading ? null : _createBackupNow,
                  ),
                ],
              ),
            ),

            // Content
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    if (_statusMessage != null) ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(10),
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: (_isSuccess ? colors.income : colors.expense)
                              .withValues(alpha: 0.14),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: (_isSuccess ? colors.income : colors.expense)
                                .withValues(alpha: 0.3),
                          ),
                        ),
                        child: Text(
                          _statusMessage!,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: _isSuccess ? colors.income : colors.expense,
                          ),
                        ),
                      ),
                    ],
                    if (_isLoading)
                      const Expanded(
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else if (_backups.isEmpty)
                      Expanded(
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.access_time,
                                size: 48,
                                color: colors.textSecondary.withValues(alpha: 0.5),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'Nenhum backup em .zip encontrado ainda.',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: colors.textPrimary,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                'Os backups diários são gerados automaticamente na primeira gravação do dia.',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: colors.textSecondary,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                      )
                    else
                      Expanded(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Container(
                            decoration: BoxDecoration(
                              color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
                              border: Border.all(color: colors.borderGlass, width: 1),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: ListView.separated(
                              itemCount: _backups.length,
                              separatorBuilder: (_, _) => Divider(
                                height: 1,
                                color: colors.borderGlass,
                              ),
                              itemBuilder: (context, idx) {
                                final item = _backups[idx];
                                return ListTile(
                                  dense: true,
                                  leading: const Icon(
                                    Icons.folder_zip_outlined,
                                    color: Colors.blueAccent,
                                    size: 26,
                                  ),
                                  title: Text(
                                    item.filename,
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                      color: colors.textPrimary,
                                    ),
                                  ),
                                  subtitle: Text(
                                    '${item.formattedDate} • ${item.formattedSize}',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: colors.textSecondary,
                                    ),
                                  ),
                                  trailing: FilledButton.tonalIcon(
                                    icon: const Icon(Icons.restore, size: 16),
                                    label: const Text('Restaurar'),
                                    onPressed: () => _confirmRestore(item),
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),

            // Footer
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF162032) : const Color(0xFFF1F5F9),
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
                border: Border(
                  top: BorderSide(color: colors.borderGlass, width: 1),
                ),
              ),
              child: Row(
                children: [
                  TextButton.icon(
                    icon: const Icon(Icons.folder_open, size: 16),
                    label: const Text('Revelar Pasta no Finder / Explorer'),
                    onPressed: () => widget.store.revealBackupsInFinder(),
                  ),
                  const Spacer(),
                  FilledButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Fechar'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
