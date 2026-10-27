import 'package:flutter/material.dart';
import '../../models/openmoney_models.dart';
import '../../store/money_store.dart';
import '../theme/liquid_glass.dart';

/// Componente de filtro multiconta com seleção por checkbox e atalhos por Negócio (PF, PJ, etc.)
class AccountMultiSelectFilter extends StatelessWidget {
  final MoneyStore store;
  final Set<String> selectedAccountIds;
  final ValueChanged<Set<String>> onSelectionChanged;
  final bool isDense;

  const AccountMultiSelectFilter({
    super.key,
    required this.store,
    required this.selectedAccountIds,
    required this.onSelectionChanged,
    this.isDense = true,
  });

  List<Account> get _activeAccounts => store.activeAccounts;

  bool get _isFiltered {
    if (selectedAccountIds.isEmpty) return false;
    final activeIds = _activeAccounts.map((a) => a.id).toSet();
    return selectedAccountIds.length < activeIds.length;
  }

  String? get _currentBusinessMatch {
    for (final biz in store.allBusinesses) {
      final bizAccIds =
          store.accountsForBusiness(biz).map((a) => a.id).toSet();
      if (bizAccIds.isNotEmpty &&
          selectedAccountIds.length == bizAccIds.length &&
          selectedAccountIds.containsAll(bizAccIds)) {
        return biz;
      }
    }
    return null;
  }

  String get _buttonLabel {
    if (selectedAccountIds.isEmpty) {
      return 'Todas as Contas';
    }
    final activeIds = _activeAccounts.map((a) => a.id).toSet();
    if (selectedAccountIds.length == activeIds.length &&
        selectedAccountIds.containsAll(activeIds)) {
      return 'Todas as Contas';
    }
    final biz = _currentBusinessMatch;
    if (biz != null) {
      return 'Negócio: $biz';
    }
    if (selectedAccountIds.length == 1) {
      final firstId = selectedAccountIds.first;
      final acc = store.accById(firstId);
      return acc?.name ?? '1 Conta Selecionada';
    }
    return '${selectedAccountIds.length} contas selecionadas';
  }

  void _openFilterDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => _AccountMultiSelectDialog(
        store: store,
        initialSelected: selectedAccountIds,
        onApply: onSelectionChanged,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colors = OpenMoneyColors(isDark);
    final isFiltered = _isFiltered;
    final bizMatch = _currentBusinessMatch;

    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => _openFilterDialog(context),
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: isDense ? 10 : 12,
          vertical: isDense ? 6 : 8,
        ),
        decoration: BoxDecoration(
          color: isFiltered
              ? colors.accent.withValues(alpha: 0.12)
              : colors.bgSecondary.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isFiltered
                ? colors.accent.withValues(alpha: 0.6)
                : colors.borderGlass,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isFiltered
                  ? (bizMatch != null
                      ? Icons.business_rounded
                      : Icons.check_circle_rounded)
                  : Icons.account_balance_wallet_outlined,
              size: 16,
              color: isFiltered ? colors.accent : colors.textSecondary,
            ),
            const SizedBox(width: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 220),
              child: Text(
                _buttonLabel,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight:
                      isFiltered ? FontWeight.w700 : FontWeight.w500,
                  color: isFiltered ? colors.accent : colors.textPrimary,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 6),
            Icon(
              Icons.arrow_drop_down,
              size: 18,
              color: isFiltered ? colors.accent : colors.textSecondary,
            ),
          ],
        ),
      ),
    );
  }
}

class _AccountMultiSelectDialog extends StatefulWidget {
  final MoneyStore store;
  final Set<String> initialSelected;
  final ValueChanged<Set<String>> onApply;

  const _AccountMultiSelectDialog({
    required this.store,
    required this.initialSelected,
    required this.onApply,
  });

  @override
  State<_AccountMultiSelectDialog> createState() =>
      _AccountMultiSelectDialogState();
}

class _AccountMultiSelectDialogState extends State<_AccountMultiSelectDialog> {
  late Set<String> _selectedIds;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _selectedIds = Set.from(widget.initialSelected);
  }

  List<Account> get _activeAccounts => widget.store.activeAccounts;

  List<Account> get _filteredAccounts {
    final q = _searchQuery.trim().toLowerCase();
    if (q.isEmpty) return _activeAccounts;
    return _activeAccounts.where((a) {
      return a.name.toLowerCase().contains(q) ||
          (a.business?.toLowerCase().contains(q) == true);
    }).toList();
  }

  void _applyAndClose() {
    widget.onApply(_selectedIds);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colors = OpenMoneyColors(isDark);
    final allBusinesses = widget.store.allBusinesses;
    final accounts = _filteredAccounts;

    return AlertDialog(
      backgroundColor: colors.bgSecondary,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colors.borderGlass),
      ),
      titlePadding: const EdgeInsets.fromLTRB(20, 16, 16, 8),
      contentPadding: const EdgeInsets.symmetric(horizontal: 20),
      actionsPadding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
      title: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            children: [
              Icon(Icons.filter_list_rounded, color: colors.accent, size: 20),
              const SizedBox(width: 8),
              Text(
                'Filtrar Contas',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: colors.textPrimary,
                ),
              ),
            ],
          ),
          Row(
            children: [
              TextButton(
                style: TextButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                onPressed: () {
                  setState(() => _selectedIds.clear());
                },
                child: const Text('Todas', style: TextStyle(fontSize: 12)),
              ),
              if (_selectedIds.isNotEmpty) ...[
                const SizedBox(width: 4),
                TextButton(
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    foregroundColor: colors.textSecondary,
                  ),
                  onPressed: () {
                    setState(() => _selectedIds.clear());
                  },
                  child: const Text('Limpar', style: TextStyle(fontSize: 12)),
                ),
              ],
            ],
          ),
        ],
      ),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Atalhos rápidos por Negócio (se existirem)
            if (allBusinesses.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                'NEGÓCIOS (ATALHOS)',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5,
                  color: colors.textMuted,
                ),
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: allBusinesses.map((biz) {
                  final bizAccs = widget.store.accountsForBusiness(biz);
                  final bizIds = bizAccs.map((a) => a.id).toSet();
                  final isBizSelected = bizIds.isNotEmpty &&
                      _selectedIds.length == bizIds.length &&
                      _selectedIds.containsAll(bizIds);

                  return InkWell(
                    borderRadius: BorderRadius.circular(6),
                    onTap: () {
                      setState(() {
                        if (isBizSelected) {
                          _selectedIds.clear();
                        } else {
                          _selectedIds = Set.from(bizIds);
                        }
                      });
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: isBizSelected
                            ? colors.accent.withValues(alpha: 0.2)
                            : colors.borderGlass.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                          color: isBizSelected
                              ? colors.accent
                              : colors.borderGlass,
                          width: isBizSelected ? 1.2 : 1,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.business_rounded,
                            size: 13,
                            color: isBizSelected
                                ? colors.accent
                                : colors.textSecondary,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '$biz (${bizAccs.length})',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: isBizSelected
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                              color: isBizSelected
                                  ? colors.accent
                                  : colors.textPrimary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 10),
              Divider(height: 1, color: colors.borderGlass),
              const SizedBox(height: 8),
            ],

            // Campo de busca rápida
            if (_activeAccounts.length > 4) ...[
              TextField(
                decoration: InputDecoration(
                  hintText: 'Buscar conta...',
                  hintStyle: TextStyle(fontSize: 12, color: colors.textMuted),
                  prefixIcon: const Icon(Icons.search, size: 16),
                  isDense: true,
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
                style: const TextStyle(fontSize: 12),
                onChanged: (v) => setState(() => _searchQuery = v),
              ),
              const SizedBox(height: 8),
            ],

            // Lista de contas com checkboxes
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 260),
              child: accounts.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Center(
                        child: Text(
                          'Nenhuma conta encontrada.',
                          style: TextStyle(
                              fontSize: 12, color: colors.textMuted),
                        ),
                      ),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      itemCount: accounts.length,
                      itemBuilder: (ctx, idx) {
                        final acc = accounts[idx];
                        final isChecked = _selectedIds.contains(acc.id);
                        final isCard = acc.type == kCardType;

                        return InkWell(
                          borderRadius: BorderRadius.circular(6),
                          onTap: () {
                            setState(() {
                              if (_selectedIds.contains(acc.id)) {
                                _selectedIds.remove(acc.id);
                              } else {
                                _selectedIds.add(acc.id);
                              }
                            });
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 5),
                            child: Row(
                              children: [
                                Checkbox(
                                  value: isChecked,
                                  onChanged: (v) {
                                    setState(() {
                                      if (v == true) {
                                        _selectedIds.add(acc.id);
                                      } else {
                                        _selectedIds.remove(acc.id);
                                      }
                                    });
                                  },
                                  materialTapTargetSize:
                                      MaterialTapTargetSize.shrinkWrap,
                                  visualDensity: VisualDensity.compact,
                                ),
                                const SizedBox(width: 6),
                                Icon(
                                  isCard
                                      ? Icons.credit_card
                                      : Icons.account_balance_wallet_outlined,
                                  size: 16,
                                  color: colors.textSecondary,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    acc.name,
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: isChecked
                                          ? FontWeight.w600
                                          : FontWeight.w400,
                                      color: colors.textPrimary,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (acc.business != null &&
                                    acc.business!.isNotEmpty) ...[
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 5, vertical: 1.5),
                                    decoration: BoxDecoration(
                                      color: colors.borderGlass
                                          .withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      acc.business!,
                                      style: TextStyle(
                                        fontSize: 9.5,
                                        fontWeight: FontWeight.w600,
                                        color: colors.textMuted,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
      actions: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              _selectedIds.isEmpty
                  ? 'Todas as contas inclusas'
                  : '${_selectedIds.length} de ${_activeAccounts.length} selecionadas',
              style: TextStyle(fontSize: 11, color: colors.textMuted),
            ),
            Row(
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancelar'),
                ),
                FilledButton(
                  onPressed: _applyAndClose,
                  child: const Text('Aplicar'),
                ),
              ],
            ),
          ],
        ),
      ],
    );
  }
}
