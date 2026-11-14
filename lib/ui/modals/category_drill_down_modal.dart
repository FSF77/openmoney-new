import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/openmoney_models.dart';
import '../../services/cash_flow_engine.dart';
import '../../services/importers_exporters.dart';
import '../../services/native_file_picker.dart';
import '../../services/platform_io.dart';
import '../../store/money_store.dart';
import '../theme/liquid_glass.dart';
import 'transaction_modal.dart';

enum CategoryDrillDownScope { all, year, month }

Future<void> showCategoryDrillDownModal(
  BuildContext context,
  MoneyStore store,
  String? categoryPath, {
  bool initialCurrentMonthOnly = false,
  String? targetMonth,
  int? targetYear,
  bool isAnnual = false,
  String? categoryTypeFilter,
  String? titleOverride,
  Set<String>? accountFilterIds,
  CashFlowDateMode? dateMode,
  CashFlowStatusFilter? statusFilter,
  String? tagFilter,
}) async {
  await showDialog(
    context: context,
    builder: (ctx) => _CategoryDrillDownDialog(
      store: store,
      categoryPath: categoryPath,
      initialCurrentMonthOnly: initialCurrentMonthOnly,
      targetMonth: targetMonth,
      targetYear: targetYear,
      isAnnual: isAnnual,
      categoryTypeFilter: categoryTypeFilter,
      titleOverride: titleOverride,
      accountFilterIds: accountFilterIds,
      dateMode: dateMode,
      statusFilter: statusFilter,
      tagFilter: tagFilter,
    ),
  );
}

class _CategoryDrillDownDialog extends StatefulWidget {
  final MoneyStore store;
  final String? categoryPath;
  final bool initialCurrentMonthOnly;
  final String? targetMonth;
  final int? targetYear;
  final bool isAnnual;
  final String? categoryTypeFilter;
  final String? titleOverride;
  final Set<String>? accountFilterIds;
  final CashFlowDateMode? dateMode;
  final CashFlowStatusFilter? statusFilter;
  final String? tagFilter;

  const _CategoryDrillDownDialog({
    required this.store,
    this.categoryPath,
    required this.initialCurrentMonthOnly,
    this.targetMonth,
    this.targetYear,
    this.isAnnual = false,
    this.categoryTypeFilter,
    this.titleOverride,
    this.accountFilterIds,
    this.dateMode,
    this.statusFilter,
    this.tagFilter,
  });

  @override
  State<_CategoryDrillDownDialog> createState() =>
      _CategoryDrillDownDialogState();
}

class _CategoryDrillDownDialogState extends State<_CategoryDrillDownDialog> {
  late CategoryDrillDownScope _scope;
  String _searchQuery = '';
  String _sortField = 'date'; // 'date', 'payee', 'amount'
  bool _sortAsc = false;

  @override
  void initState() {
    super.initState();
    if (widget.isAnnual) {
      _scope = CategoryDrillDownScope.year;
    } else if (widget.initialCurrentMonthOnly) {
      _scope = CategoryDrillDownScope.month;
    } else {
      _scope = CategoryDrillDownScope.all;
    }
  }

  List<Transaction> _buildFilteredTransactions() {
    final effectiveYear = (widget.targetYear ??
            int.tryParse(widget.targetMonth?.split('-')[0] ?? '') ??
            int.tryParse(widget.store.month.split('-')[0]) ??
            DateTime.now().year)
        .toString();
    final monthYM = widget.targetMonth ?? widget.store.month;
    final catPath = widget.categoryPath;
    final hasCat = catPath != null && catPath.isNotEmpty;
    final affected = hasCat ? widget.store.affectedCategoryPaths(catPath) : const <String>{};
    final prefix = hasCat ? '$catPath$kCategorySep' : '';

    final list = widget.store.db.txs.where((t) {
      if (t.auto == true) return false;

      if (widget.accountFilterIds != null &&
          widget.accountFilterIds!.isNotEmpty &&
          !widget.accountFilterIds!.contains(t.acc)) {
        return false;
      }

      if (widget.tagFilter != null &&
          widget.tagFilter!.isNotEmpty &&
          widget.tagFilter != 'all') {
        final txTags = t.tags ?? const <String>[];
        if (widget.tagFilter == '__untagged__') {
          if (txTags.isNotEmpty) return false;
        } else {
          final normTag = widget.tagFilter!.trim().toLowerCase();
          if (!txTags.any((tg) => tg.trim().toLowerCase() == normTag)) {
            return false;
          }
        }
      }

      if (widget.statusFilter != null) {
        switch (widget.statusFilter!) {
          case CashFlowStatusFilter.all:
            break;
          case CashFlowStatusFilter.reconciledOnly:
            if (!t.rec) return false;
            break;
          case CashFlowStatusFilter.pendingOnly:
            if (t.rec) return false;
            break;
        }
      }

      if (hasCat) {
        final matchesCat = affected.contains(t.cat) ||
            t.cat == catPath ||
            t.cat.startsWith(prefix);
        if (!matchesCat) return false;
      } else if (widget.categoryTypeFilter != null) {
        if (t.xfer != null) return false;
        final isInc = t.amt > 0;
        if (widget.categoryTypeFilter == 'Receita' && !isInc) return false;
        if (widget.categoryTypeFilter == 'Despesa' && isInc) return false;
      }

      if (_scope == CategoryDrillDownScope.year) {
        final effDate = widget.dateMode != null
            ? effectiveDateForTransaction(
                t, widget.store.db.accounts, widget.dateMode!)
            : t.date;
        if (!effDate.startsWith(effectiveYear)) {
          return false;
        }
      } else if (_scope == CategoryDrillDownScope.month) {
        final effDate = widget.dateMode != null
            ? effectiveDateForTransaction(
                t, widget.store.db.accounts, widget.dateMode!)
            : t.date;
        if (!effDate.startsWith(monthYM)) {
          return false;
        }
      }

      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        final p = t.payee.toLowerCase();
        final m = t.memo.toLowerCase();
        final c = t.cat.toLowerCase();
        final accName =
            (widget.store.accById(t.acc)?.name ?? '').toLowerCase();
        if (!p.contains(q) &&
            !m.contains(q) &&
            !c.contains(q) &&
            !accName.contains(q)) {
          return false;
        }
      }
      return true;
    }).toList();

    list.sort((a, b) {
      int comp;
      switch (_sortField) {
        case 'payee':
          comp = a.payee.toLowerCase().compareTo(b.payee.toLowerCase());
          break;
        case 'amount':
          comp = a.amt.compareTo(b.amt);
          break;
        case 'date':
        default:
          comp = a.date.compareTo(b.date);
          break;
      }
      return _sortAsc ? comp : -comp;
    });

    return list;
  }

  Future<void> _exportCsv(List<Transaction> txs) async {
    final csv = CSVExporter.generateCSV(
      transactions: txs,
      accounts: widget.store.db.accounts,
      baseCurrency: widget.store.baseCurrency,
      rates: widget.store.db.rates,
      allTransactionsForPairs: widget.store.db.txs,
    );

    if (!kIsWeb) {
      final rawCat = widget.categoryPath ??
          widget.categoryTypeFilter ??
          'lancamentos';
      final safeCat = rawCat
          .replaceAll(':', '-')
          .replaceAll('/', '-')
          .replaceAll(' ', '_');
      final savePath = await NativeFilePicker.saveFile(
        title: 'Exportar Lançamentos (CSV)',
        defaultName: 'Categoria-$safeCat.csv',
        allowedExtensions: ['csv'],
      );
      if (savePath != null && savePath.isNotEmpty) {
        try {
          final f = File(savePath);
          f.parent.createSync(recursive: true);
          f.writeAsStringSync(csv, flush: true);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('✓ CSV exportado com sucesso em:\n$savePath'),
              ),
            );
          }
          return;
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Erro ao salvar CSV: $e'),
                backgroundColor: Colors.redAccent,
              ),
            );
          }
          return;
        }
      }
      return;
    }

    Clipboard.setData(ClipboardData(text: csv));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✓ Lançamentos copiados em formato CSV!'),
        ),
      );
    }
  }

  Widget _buildScopeButton({
    required String label,
    required CategoryDrillDownScope scope,
    required OpenMoneyColors colors,
    bool isFirst = false,
    bool isLast = false,
  }) {
    final isSelected = (_scope == scope);
    return InkWell(
      borderRadius: BorderRadius.horizontal(
        left: isFirst ? const Radius.circular(7) : Radius.zero,
        right: isLast ? const Radius.circular(7) : Radius.zero,
      ),
      onTap: () => setState(() => _scope = scope),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? colors.accent.withValues(alpha: 0.2)
              : Colors.transparent,
          borderRadius: BorderRadius.horizontal(
            left: isFirst ? const Radius.circular(7) : Radius.zero,
            right: isLast ? const Radius.circular(7) : Radius.zero,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.w800 : FontWeight.w500,
            color: isSelected ? colors.accent : colors.textSecondary,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colors = OpenMoneyColors(isDark);
    final effectiveYear = (widget.targetYear ??
            int.tryParse(widget.targetMonth?.split('-')[0] ?? '') ??
            int.tryParse(widget.store.month.split('-')[0]) ??
            DateTime.now().year)
        .toString();
    final monthYM = widget.targetMonth ?? widget.store.month;
    final txs = _buildFilteredTransactions();
    final targetCur = widget.store.targetCurrencyForAccounts(
        widget.accountFilterIds);
    final totalCents = txs.fold<int>(
      0,
      (s, t) => s + widget.store.convertTxToCurrency(t, targetCur),
    );
    final hasCat = widget.categoryPath != null && widget.categoryPath!.isNotEmpty;
    final hasTag = widget.tagFilter != null && widget.tagFilter!.isNotEmpty;
    final displayTitle = widget.titleOverride ??
        (hasTag && !hasCat
            ? (widget.tagFilter == '__untagged__'
                ? 'Auditoria de Lançamentos: Sem tag'
                : 'Auditoria de Lançamentos: #${widget.tagFilter}')
            : (hasCat
                ? 'Auditoria de Lançamentos: ${widget.categoryPath}'
                : (widget.categoryTypeFilter != null
                    ? 'Auditoria: ${widget.categoryTypeFilter}'
                    : 'Auditoria de Lançamentos')));

    final screenSize = MediaQuery.sizeOf(context);
    final isMobile = screenSize.width < 720;
    final dialogWidth =
        isMobile ? (screenSize.width - 20).clamp(320.0, 780.0) : 780.0;
    final dialogHeight =
        isMobile ? (screenSize.height - 24).clamp(440.0, 720.0) : 560.0;

    return Dialog(
      backgroundColor: colors.bgSecondary,
      insetPadding: EdgeInsets.symmetric(
        horizontal: isMobile ? 8 : 24,
        vertical: isMobile ? 10 : 24,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colors.borderGlass),
      ),
      child: SizedBox(
        width: dialogWidth,
        height: dialogHeight,
        child: Padding(
          padding: EdgeInsets.all(isMobile ? 12 : 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              if (isMobile) ...[
                Row(
                  children: [
                    Icon(Icons.manage_search, color: colors.accent, size: 22),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            displayTitle,
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 14,
                              color: colors.textPrimary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            'Clique no lançamento para editar',
                            style: TextStyle(
                              fontSize: 10.5,
                              color: colors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      tooltip: 'Exportar CSV',
                      icon: const Icon(Icons.download, size: 18),
                      onPressed: () => _exportCsv(txs),
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      tooltip: 'Fechar',
                      icon: const Icon(Icons.close, size: 20),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: colors.borderGlass),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _buildScopeButton(
                          label: 'Histórico',
                          scope: CategoryDrillDownScope.all,
                          colors: colors,
                          isFirst: true,
                          isLast: false,
                        ),
                        _buildScopeButton(
                          label: effectiveYear,
                          scope: CategoryDrillDownScope.year,
                          colors: colors,
                          isFirst: false,
                          isLast: widget.isAnnual,
                        ),
                        if (!widget.isAnnual)
                          _buildScopeButton(
                            label: fmtMonth(monthYM),
                            scope: CategoryDrillDownScope.month,
                            colors: colors,
                            isFirst: false,
                            isLast: true,
                          ),
                      ],
                    ),
                  ),
                ),
              ] else ...[
                Row(
                  children: [
                    Icon(Icons.manage_search, color: colors.accent, size: 24),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            displayTitle,
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 16,
                              color: colors.textPrimary,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            'Clique em qualquer lançamento abaixo para abrir ou editar',
                            style: TextStyle(
                              fontSize: 11.5,
                              color: colors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton.tonalIcon(
                      icon: const Icon(Icons.download, size: 16),
                      label: const Text('Exportar CSV'),
                      onPressed: () => _exportCsv(txs),
                    ),
                    const SizedBox(width: 8),
                    // Botões de escopo temporal
                    Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: colors.borderGlass),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _buildScopeButton(
                            label: 'Todo o Histórico',
                            scope: CategoryDrillDownScope.all,
                            colors: colors,
                            isFirst: true,
                            isLast: false,
                          ),
                          _buildScopeButton(
                            label: 'Ano $effectiveYear',
                            scope: CategoryDrillDownScope.year,
                            colors: colors,
                            isFirst: false,
                            isLast: widget.isAnnual,
                          ),
                          if (!widget.isAnnual)
                            _buildScopeButton(
                              label: fmtMonth(monthYM),
                              scope: CategoryDrillDownScope.month,
                              colors: colors,
                              isFirst: false,
                              isLast: true,
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
              SizedBox(height: isMobile ? 8 : 14),
              // Barra de Pesquisa e Ordenação
              if (isMobile) ...[
                Row(
                  children: [
                    Expanded(
                      child: SizedBox(
                        height: 36,
                        child: TextField(
                          decoration: InputDecoration(
                            hintText: 'Pesquisar...',
                            hintStyle: const TextStyle(fontSize: 12),
                            prefixIcon: const Icon(Icons.search, size: 16),
                            isDense: true,
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 6,
                            ),
                          ),
                          onChanged: (v) =>
                              setState(() => _searchQuery = v.trim()),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    DropdownButton<String>(
                      value: _sortField,
                      underline: const SizedBox(),
                      style: TextStyle(
                        fontSize: 12,
                        color: colors.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                      items: const [
                        DropdownMenuItem(value: 'date', child: Text('Data')),
                        DropdownMenuItem(value: 'payee', child: Text('Nome')),
                        DropdownMenuItem(value: 'amount', child: Text('Valor')),
                      ],
                      onChanged: (v) {
                        if (v != null) setState(() => _sortField = v);
                      },
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      tooltip:
                          _sortAsc ? 'Ordem Crescente' : 'Ordem Decrescente',
                      icon: Icon(
                        _sortAsc ? Icons.arrow_upward : Icons.arrow_downward,
                        size: 16,
                      ),
                      onPressed: () => setState(() => _sortAsc = !_sortAsc),
                    ),
                  ],
                ),
              ] else ...[
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        decoration: InputDecoration(
                          hintText:
                              'Pesquisar nos resultados (favorecido, nota, conta)...',
                          prefixIcon: const Icon(Icons.search, size: 18),
                          isDense: true,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 9,
                          ),
                        ),
                        onChanged: (v) =>
                            setState(() => _searchQuery = v.trim()),
                      ),
                    ),
                    const SizedBox(width: 12),
                    const Text(
                      'Ordenar:',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(width: 6),
                    DropdownButton<String>(
                      value: _sortField,
                      underline: const SizedBox(),
                      items: const [
                        DropdownMenuItem(value: 'date', child: Text('Data')),
                        DropdownMenuItem(value: 'payee', child: Text('Nome')),
                        DropdownMenuItem(value: 'amount', child: Text('Valor')),
                      ],
                      onChanged: (v) {
                        if (v != null) setState(() => _sortField = v);
                      },
                    ),
                    IconButton(
                      tooltip:
                          _sortAsc ? 'Ordem Crescente' : 'Ordem Decrescente',
                      icon: Icon(
                        _sortAsc ? Icons.arrow_upward : Icons.arrow_downward,
                        size: 18,
                      ),
                      onPressed: () => setState(() => _sortAsc = !_sortAsc),
                    ),
                  ],
                ),
              ],
              SizedBox(height: isMobile ? 6 : 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${txs.length} lançamento(s)',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: isMobile ? 11.5 : 12.5,
                      color: colors.textSecondary,
                    ),
                  ),
                  Text(
                    'Total: ${formatCurrency(totalCents, targetCur)}',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: isMobile ? 12 : 13.5,
                      color: totalCents >= 0 ? colors.income : colors.expense,
                    ),
                  ),
                ],
              ),
              const Divider(height: 16),
              // Lista de Lançamentos
              Expanded(
                child: txs.isEmpty
                    ? Center(
                        child: Text(
                          'Nenhum lançamento encontrado para este filtro.',
                          style: TextStyle(color: colors.textSecondary),
                        ),
                      )
                    : ListView.separated(
                        itemCount: txs.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (context, i) {
                          final t = txs[i];
                          final txAcc = widget.store.accById(t.acc);
                          final accName = txAcc?.name ?? 'Conta';
                          final txCur = txAcc?.effectiveCurrency ??
                              widget.store.baseCurrency;
                          return ListTile(
                            dense: true,
                            contentPadding:
                                const EdgeInsets.symmetric(horizontal: 6),
                            leading: Icon(
                              t.rec
                                  ? Icons.check_circle
                                  : Icons.radio_button_unchecked,
                              size: 16,
                              color:
                                  t.rec ? colors.income : colors.textMuted,
                            ),
                            title: Text(
                              t.payee,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                              ),
                            ),
                            subtitle: Text(
                              '${fmtDate(t.date)} • $accName • ${t.cat}${t.memo.isNotEmpty ? " • ${t.memo}" : ""}',
                              style: const TextStyle(fontSize: 11.5),
                            ),
                            trailing: Text(
                              formatCurrency(t.amt, txCur),
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 13,
                                color: t.amt >= 0
                                    ? colors.income
                                    : colors.expense,
                              ),
                            ),
                            onTap: () {
                              Navigator.pop(context);
                              showTransactionEditModal(
                                context,
                                widget.store,
                                t,
                              );
                            },
                          );
                        },
                      ),
              ),
              const Divider(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  FilledButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Fechar'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
