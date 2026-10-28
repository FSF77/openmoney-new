import 'package:flutter/material.dart';
import '../../services/audit_log_manager.dart';
import '../../store/money_store.dart';
import '../theme/liquid_glass.dart';

Future<void> showAuditLogsModal(
  BuildContext context,
  MoneyStore store,
) async {
  await showDialog(
    context: context,
    builder: (ctx) => _AuditLogsDialog(store: store),
  );
}

class _AuditLogsDialog extends StatefulWidget {
  final MoneyStore store;
  const _AuditLogsDialog({required this.store});

  @override
  State<_AuditLogsDialog> createState() => _AuditLogsDialogState();
}

class _AuditLogsDialogState extends State<_AuditLogsDialog> {
  List<AuditLogEntry> _allEntries = [];
  bool _isLoading = true;
  String _searchQuery = '';
  String _selectedFilter = 'all'; // 'all', 'transaction', 'account', 'category', 'delete'
  final TextEditingController _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadLogs();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadLogs() async {
    setState(() => _isLoading = true);
    final list = await widget.store.readRecentAuditLogs(limit: 500);
    if (mounted) {
      setState(() {
        _allEntries = list;
        _isLoading = false;
      });
    }
  }

  List<AuditLogEntry> get _filteredEntries {
    return _allEntries.where((entry) {
      // Filtro de Categoria/Tipo
      if (_selectedFilter == 'transaction' && entry.entity != AuditEntity.transaction) return false;
      if (_selectedFilter == 'account' && entry.entity != AuditEntity.account) return false;
      if (_selectedFilter == 'category' && entry.entity != AuditEntity.category) return false;
      if (_selectedFilter == 'delete' &&
          entry.action != AuditAction.delete &&
          entry.action != AuditAction.batchDelete) {
        return false;
      }

      // Filtro de Texto
      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        final matchSummary = entry.summary.toLowerCase().contains(q);
        final matchAction = entry.actionLabel.toLowerCase().contains(q);
        final matchEntity = entry.entityLabel.toLowerCase().contains(q);
        return matchSummary || matchAction || matchEntity;
      }
      return true;
    }).toList();
  }

  Color _badgeColorForAction(AuditAction action) {
    switch (action) {
      case AuditAction.create:
        return const Color(0xFF10B981); // Emerald Green
      case AuditAction.update:
        return const Color(0xFF3B82F6); // Blue
      case AuditAction.delete:
        return const Color(0xFFEF4444); // Red
      case AuditAction.batchDelete:
        return const Color(0xFFF97316); // Orange
      case AuditAction.importBatch:
        return const Color(0xFF8B5CF6); // Purple
    }
  }

  IconData _iconForAction(AuditAction action) {
    switch (action) {
      case AuditAction.create:
        return Icons.add_circle_outline;
      case AuditAction.update:
        return Icons.edit_note_outlined;
      case AuditAction.delete:
        return Icons.delete_outline;
      case AuditAction.batchDelete:
        return Icons.cleaning_services_outlined;
      case AuditAction.importBatch:
        return Icons.file_download_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colors = OpenMoneyColors(isDark);
    final filtered = _filteredEntries;

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
          maxWidth: 780,
          maxHeight: 640,
          minWidth: 540,
          minHeight: 440,
        ),
        child: Column(
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
                      color: Colors.amber.withValues(alpha: 0.15),
                    ),
                    child: const Icon(
                      Icons.history_edu_outlined,
                      color: Colors.amber,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Logs de Auditoria e Alterações',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: colors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Histórico detalhado mantido pelos últimos 30 dias (${widget.store.logFilePath.split(RegExp(r"[/\\]")).last})',
                          style: TextStyle(
                            fontSize: 12,
                            color: colors.textSecondary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Recarregar logs',
                    icon: const Icon(Icons.refresh, size: 20),
                    onPressed: _loadLogs,
                  ),
                ],
              ),
            ),

            // Barra de Filtros e Busca
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    flex: 5,
                    child: SizedBox(
                      height: 36,
                      child: TextField(
                        controller: _searchCtrl,
                        decoration: InputDecoration(
                          hintText: 'Filtrar por texto, descrição ou valor...',
                          hintStyle: TextStyle(fontSize: 12, color: colors.textMuted),
                          prefixIcon: Icon(Icons.search, size: 16, color: colors.textMuted),
                          suffixIcon: _searchQuery.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear, size: 14),
                                  onPressed: () {
                                    _searchCtrl.clear();
                                    setState(() => _searchQuery = '');
                                  },
                                )
                              : null,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(color: colors.borderGlass),
                          ),
                          filled: true,
                          fillColor: isDark ? const Color(0xFF0F172A) : const Color(0xFFFFFFFF),
                        ),
                        style: const TextStyle(fontSize: 13),
                        onChanged: (val) => setState(() => _searchQuery = val.trim()),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Segmented filters
                  Wrap(
                    spacing: 6,
                    children: [
                      _buildFilterChip('all', 'Todos', colors),
                      _buildFilterChip('transaction', 'Lançamentos', colors),
                      _buildFilterChip('account', 'Contas', colors),
                      _buildFilterChip('category', 'Categorias', colors),
                      _buildFilterChip('delete', 'Exclusões', colors),
                    ],
                  ),
                ],
              ),
            ),

            const Divider(height: 1),

            // Conteúdo dos Logs
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : filtered.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.find_in_page_outlined,
                                size: 48,
                                color: colors.textMuted.withValues(alpha: 0.6),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                _allEntries.isEmpty
                                    ? 'Nenhum registro de log encontrado ainda.'
                                    : 'Nenhum log corresponde aos filtros informados.',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: colors.textPrimary,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                _allEntries.isEmpty
                                    ? 'Qualquer nova inclusão, alteração ou exclusão será gravada aqui.'
                                    : 'Tente alterar os termos da busca ou os filtros selecionados.',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: colors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          itemCount: filtered.length,
                          separatorBuilder: (_, _) => Divider(height: 1, color: colors.borderGlass),
                          itemBuilder: (context, idx) {
                            final entry = filtered[idx];
                            final badgeColor = _badgeColorForAction(entry.action);
                            final icon = _iconForAction(entry.action);

                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Badge de Ação
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: badgeColor.withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(
                                        color: badgeColor.withValues(alpha: 0.4),
                                        width: 1,
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(icon, size: 13, color: badgeColor),
                                        const SizedBox(width: 4),
                                        Text(
                                          entry.actionLabel,
                                          style: TextStyle(
                                            fontSize: 11,
                                            fontWeight: FontWeight.w700,
                                            color: badgeColor,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  // Resumo e Detalhes
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          entry.summary,
                                          style: TextStyle(
                                            fontSize: 13,
                                            fontWeight: FontWeight.w500,
                                            color: colors.textPrimary,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Row(
                                          children: [
                                            Text(
                                              entry.formattedDate,
                                              style: TextStyle(
                                                fontSize: 11,
                                                color: colors.textMuted,
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Text(
                                              '•  ${entry.entityLabel}',
                                              style: TextStyle(
                                                fontSize: 11,
                                                color: colors.textSecondary,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
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
                    icon: const Icon(Icons.file_open_outlined, size: 16),
                    label: const Text('Abrir Arquivo .log'),
                    onPressed: () => widget.store.openLogFileInEditor(),
                  ),
                  const SizedBox(width: 8),
                  TextButton.icon(
                    icon: const Icon(Icons.folder_open, size: 16),
                    label: const Text('Revelar no Finder / Explorer'),
                    onPressed: () => widget.store.revealLogFileInFinder(),
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

  Widget _buildFilterChip(String key, String label, OpenMoneyColors colors) {
    final isSelected = _selectedFilter == key;
    return ChoiceChip(
      label: Text(label),
      labelStyle: TextStyle(
        fontSize: 11,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        color: isSelected ? Colors.white : colors.textPrimary,
      ),
      selected: isSelected,
      selectedColor: Colors.blueAccent,
      showCheckmark: false,
      visualDensity: VisualDensity.compact,
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
      onSelected: (_) => setState(() => _selectedFilter = key),
    );
  }
}
