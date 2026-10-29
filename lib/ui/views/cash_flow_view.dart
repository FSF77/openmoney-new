import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/cash_flow_engine.dart';
import '../../services/native_file_picker.dart';
import '../../store/money_store.dart';
import '../modals/account_multi_select_filter.dart';
import 'cash_flow_detail_dialog.dart';
import '../theme/liquid_glass.dart';

class CashFlowView extends StatefulWidget {
  final MoneyStore store;
  const CashFlowView({super.key, required this.store});

  @override
  State<CashFlowView> createState() => _CashFlowViewState();
}

class _CashFlowViewState extends State<CashFlowView> {
  CashFlowPeriodKind _periodKind = CashFlowPeriodKind.monthly;
  late int _year;
  Set<String> _selectedAccountIds = {};
  CashFlowStatusFilter _statusFilter = CashFlowStatusFilter.all;
  CashFlowKindFilter _kindFilter = CashFlowKindFilter.all;
  CashFlowDateMode _dateMode = CashFlowDateMode.transactionDate;
  String _searchQuery = '';
  final Set<String> _collapsedGroups = {};

  @override
  void initState() {
    super.initState();
    _year = int.tryParse(widget.store.month.substring(0, 4)) ??
        DateTime.now().year;
  }

  Future<void> _exportCsv(CashFlowMatrix matrix) async {
    final csv = CashFlowEngine.generateCSV(matrix);
    if (!kIsWeb) {
      final defaultName =
          'openmoney-fluxo-caixa-${_periodKind.label.toLowerCase()}-$_year.csv';
      final savePath = await NativeFilePicker.saveFile(
        title: 'Salvar Fluxo de Caixa (CSV)',
        defaultName: defaultName,
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
                content: Text('✓ Fluxo de Caixa exportado em:\n$savePath'),
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
          content: Text(
              '✓ Fluxo de Caixa CSV copiado para a área de transferência!'),
        ),
      );
    }
  }

  void _showDetail(
    CashFlowMatrix matrix, {
    int? col,
    bool? isIncome,
    String? top,
    String? sub,
  }) {
    showCashFlowDetailDialog(
      context,
      store: widget.store,
      matrix: matrix,
      columnIndex: col,
      isIncome: isIncome,
      top: top,
      sub: sub,
      accountFilterIds:
          _selectedAccountIds.isEmpty ? null : _selectedAccountIds,
      statusFilter: _statusFilter,
      kindFilter: _kindFilter,
      dateMode: _dateMode,
      searchQuery: _searchQuery,
    );
  }

  Widget _clickable(Widget child, VoidCallback onTap) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: child,
      ),
    );
  }

  void _toggleAllGroups(CashFlowMatrix matrix) {
    final keys = <String>{
      for (final sec in [matrix.incomeSection, matrix.expenseSection])
        for (final g in sec.groups)
          if (g.hasSubcategories) '${sec.title}:${g.name}',
    };
    setState(() {
      if (_collapsedGroups.isEmpty) {
        _collapsedGroups.addAll(keys);
      } else {
        _collapsedGroups.clear();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colors = OpenMoneyColors(isDark);

    final matrix = CashFlowEngine.buildMatrix(
      transactions: widget.store.db.txs,
      accounts: widget.store.db.accounts,
      periodKind: _periodKind,
      year: _year,
      accountFilterIds:
          _selectedAccountIds.isEmpty ? null : _selectedAccountIds,
      statusFilter: _statusFilter,
      kindFilter: _kindFilter,
      dateMode: _dateMode,
      searchQuery: _searchQuery,
    );

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
          child: GlassCard(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 12,
                  runSpacing: 10,
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.grid_on_rounded,
                            color: colors.accent, size: 22),
                        const SizedBox(width: 10),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Fluxo de Caixa Matricial (${_periodKind.label})',
                              style: TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.w800,
                                color: colors.textPrimary,
                              ),
                            ),
                            Text(
                              matrix.periodSubtitle,
                              style: TextStyle(
                                fontSize: 12,
                                color: colors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    SegmentedButton<CashFlowPeriodKind>(
                      segments: CashFlowPeriodKind.values
                          .map((p) =>
                              ButtonSegment(value: p, label: Text(p.label)))
                          .toList(),
                      selected: {_periodKind},
                      onSelectionChanged: (s) =>
                          setState(() => _periodKind = s.first),
                    ),
                    if (_periodKind != CashFlowPeriodKind.yearly)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.chevron_left),
                            onPressed: () => setState(() => _year -= 1),
                          ),
                          Text(
                            '$_year',
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 15,
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.chevron_right),
                            onPressed: () => setState(() => _year += 1),
                          ),
                        ],
                      ),
                    Tooltip(
                      message: _collapsedGroups.isEmpty
                          ? 'Recolher todas as categorias'
                          : 'Expandir todas as categorias',
                      child: OutlinedButton(
                        onPressed: () => _toggleAllGroups(matrix),
                        child: Icon(
                          _collapsedGroups.isEmpty
                              ? Icons.unfold_less
                              : Icons.unfold_more,
                          size: 18,
                        ),
                      ),
                    ),
                    FilledButton.tonalIcon(
                      icon: const Icon(Icons.download, size: 16),
                      label: const Text('Exportar CSV'),
                      onPressed: () => _exportCsv(matrix),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    AccountMultiSelectFilter(
                      store: widget.store,
                      selectedAccountIds: _selectedAccountIds,
                      onSelectionChanged: (set) =>
                          setState(() => _selectedAccountIds = set),
                    ),
                    SizedBox(
                      width: 190,
                      child: DropdownButtonFormField<CashFlowStatusFilter>(
                        initialValue: _statusFilter,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Status de Conciliação',
                          isDense: true,
                          border: OutlineInputBorder(),
                        ),
                        items: CashFlowStatusFilter.values
                            .map((s) => DropdownMenuItem(
                                  value: s,
                                  child: Text(s.shortLabel),
                                ))
                            .toList(),
                        onChanged: (v) {
                          if (v != null) setState(() => _statusFilter = v);
                        },
                      ),
                    ),
                    SizedBox(
                      width: 190,
                      child: DropdownButtonFormField<CashFlowKindFilter>(
                        initialValue: _kindFilter,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Tipo',
                          isDense: true,
                          border: OutlineInputBorder(),
                        ),
                        items: CashFlowKindFilter.values
                            .map((k) => DropdownMenuItem(
                                  value: k,
                                  child: Text(k.label),
                                ))
                            .toList(),
                        onChanged: (v) {
                          if (v != null) setState(() => _kindFilter = v);
                        },
                      ),
                    ),
                    SizedBox(
                      width: 210,
                      child: DropdownButtonFormField<CashFlowDateMode>(
                        initialValue: _dateMode,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Regime Contábil',
                          isDense: true,
                          border: OutlineInputBorder(),
                        ),
                        items: CashFlowDateMode.values
                            .map((m) => DropdownMenuItem(
                                  value: m,
                                  child: Text(m.shortLabel),
                                ))
                            .toList(),
                        onChanged: (v) {
                          if (v != null) setState(() => _dateMode = v);
                        },
                      ),
                    ),
                    SizedBox(
                      width: 200,
                      child: TextField(
                        decoration: const InputDecoration(
                          labelText: 'Filtrar categoria...',
                          prefixIcon: Icon(Icons.search, size: 16),
                          isDense: true,
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (v) => setState(() => _searchQuery = v),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
            child: GlassCard(
              padding: EdgeInsets.zero,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: 210.0 + (matrix.columns.length + 1) * 104.0 + 32.0,
                  child: ListView(
                    children: [
                      // Matrix Column Header
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: colors.bgPrimary.withValues(alpha: 0.65),
                          border: Border(
                            bottom: BorderSide(color: colors.borderGlass),
                          ),
                        ),
                        child: Row(
                          children: [
                            const SizedBox(
                              width: 210,
                              child: Text(
                                'Categoria / Subcategoria',
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            ...List.generate(
                              matrix.columns.length,
                              (i) {
                                final col = matrix.columns[i];
                                return SizedBox(
                                  width: 104,
                                  child: _clickable(
                                    Text(
                                      col.shortTitle,
                                      textAlign: TextAlign.right,
                                      style: TextStyle(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 12,
                                        color: col.isCurrent
                                            ? colors.accent
                                            : colors.textPrimary,
                                      ),
                                    ),
                                    () => _showDetail(matrix, col: i),
                                  ),
                                );
                              },
                            ),
                            const SizedBox(
                              width: 104,
                              child: Text(
                                'Total',
                                textAlign: TextAlign.right,
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      ..._buildSectionRows(
                        matrix,
                        matrix.incomeSection,
                        colors.income,
                        colors,
                      ),
                      const Divider(height: 1),
                      ..._buildSectionRows(
                        matrix,
                        matrix.expenseSection,
                        colors.expense,
                        colors,
                      ),
                      const Divider(height: 2),
                      _buildSummaryRow(
                        label: 'Rendimento menos Despesas',
                        periodAmounts: matrix.netPeriodTotals,
                        grandTotal: matrix.netGrandTotal,
                        colors: colors,
                        highlight: true,
                      ),
                      _buildSummaryRow(
                        label: 'Saldo Anterior Acumulado',
                        periodAmounts: matrix.priorBalancePeriodTotals,
                        grandTotal: matrix.priorBalanceGrandTotal,
                        colors: colors,
                        highlight: false,
                      ),
                      _buildSummaryRow(
                        label: 'Saldo Final Acumulado',
                        periodAmounts: matrix.endingBalancePeriodTotals,
                        grandTotal: matrix.endingBalanceGrandTotal,
                        colors: colors,
                        highlight: true,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  List<Widget> _buildSectionRows(
    CashFlowMatrix matrix,
    CashFlowSection section,
    Color sectionColor,
    OpenMoneyColors colors,
  ) {
    final rows = <Widget>[];
    final isIncome = identical(section, matrix.incomeSection);

    rows.add(
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        color: sectionColor.withValues(alpha: 0.12),
        child: Row(
          children: [
            SizedBox(
              width: 210,
              child: Text(
                section.title.toUpperCase(),
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                  color: sectionColor,
                ),
              ),
            ),
          ],
        ),
      ),
    );

    for (final group in section.groups) {
      final groupKey = '${section.title}:${group.name}';
      final isCollapsed = _collapsedGroups.contains(groupKey);

      rows.add(
        InkWell(
          onTap: group.hasSubcategories
              ? () {
                  setState(() {
                    if (isCollapsed) {
                      _collapsedGroups.remove(groupKey);
                    } else {
                      _collapsedGroups.add(groupKey);
                    }
                  });
                }
              : null,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: colors.borderGlass.withValues(alpha: 0.4),
                ),
              ),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: 210,
                  child: Row(
                    children: [
                      if (group.hasSubcategories)
                        Icon(
                          isCollapsed
                              ? Icons.chevron_right
                              : Icons.expand_more,
                          size: 16,
                          color: colors.textSecondary,
                        )
                      else
                        const SizedBox(width: 16),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          group.name,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 12.5,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
                ...List.generate(
                  group.periodTotals.length,
                  (i) => SizedBox(
                    width: 104,
                    child: _clickable(
                      Text(
                        fmtCashFlowCents(group.periodTotals[i]),
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                          color: colors.textPrimary,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      () => _showDetail(matrix,
                          col: i, isIncome: isIncome, top: group.name),
                    ),
                  ),
                ),
                SizedBox(
                  width: 104,
                  child: _clickable(
                    Text(
                      fmtCashFlowCents(group.grandTotal, showZero: true),
                      textAlign: TextAlign.right,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                        color: sectionColor,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    () => _showDetail(matrix,
                        isIncome: isIncome, top: group.name),
                  ),
                ),
              ],
            ),
          ),
        ),
      );

      if (group.hasSubcategories && !isCollapsed) {
        for (final sub in group.subcategories) {
          final subKey = sub.name.endsWith(' - Não-atribuído')
              ? CashFlowEngine.directSubKey
              : sub.name;
          rows.add(
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
              child: Row(
                children: [
                  SizedBox(
                    width: 210,
                    child: Padding(
                      padding: const EdgeInsets.only(left: 24),
                      child: Text(
                        sub.name,
                        style: TextStyle(
                          fontSize: 12,
                          color: colors.textSecondary,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                  ...List.generate(
                    sub.periodAmounts.length,
                    (i) => SizedBox(
                      width: 104,
                      child: _clickable(
                        Text(
                          fmtCashFlowCents(sub.periodAmounts[i]),
                          textAlign: TextAlign.right,
                          style: TextStyle(
                            fontSize: 11.5,
                            color: colors.textSecondary,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                        () => _showDetail(matrix,
                            col: i,
                            isIncome: isIncome,
                            top: group.name,
                            sub: subKey),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 104,
                    child: _clickable(
                      Text(
                        fmtCashFlowCents(sub.total, showZero: true),
                        textAlign: TextAlign.right,
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 11.5,
                          color: colors.textPrimary,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                      () => _showDetail(matrix,
                          isIncome: isIncome, top: group.name, sub: subKey),
                    ),
                  ),
                ],
              ),
            ),
          );
        }
      }
    }

    rows.add(
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        color: sectionColor.withValues(alpha: 0.08),
        child: Row(
          children: [
            SizedBox(
              width: 210,
              child: Text(
                'Total ${section.title}',
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 12.5,
                  color: sectionColor,
                ),
              ),
            ),
            ...List.generate(
              section.periodTotals.length,
              (i) => SizedBox(
                width: 104,
                child: _clickable(
                  Text(
                    fmtCashFlowCents(section.periodTotals[i], showZero: true),
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                      color: sectionColor,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  () => _showDetail(matrix, col: i, isIncome: isIncome),
                ),
              ),
            ),
            SizedBox(
              width: 104,
              child: _clickable(
                Text(
                  fmtCashFlowCents(section.grandTotal, showZero: true),
                  textAlign: TextAlign.right,
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 12.5,
                    color: sectionColor,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                () => _showDetail(matrix, isIncome: isIncome),
              ),
            ),
          ],
        ),
      ),
    );

    return rows;
  }

  Widget _buildSummaryRow({
    required String label,
    required List<int> periodAmounts,
    required int grandTotal,
    required OpenMoneyColors colors,
    required bool highlight,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      color: highlight
          ? colors.accent.withValues(alpha: 0.12)
          : Colors.transparent,
      child: Row(
        children: [
          SizedBox(
            width: 210,
            child: Text(
              label,
              style: TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 12.5,
                color: colors.textPrimary,
              ),
            ),
          ),
          ...periodAmounts.map((amt) {
            final c = amt >= 0 ? colors.income : colors.expense;
            return SizedBox(
              width: 104,
              child: Text(
                fmtCashFlowCents(amt, showZero: true),
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontWeight: FontWeight.w800,
                  fontSize: 12,
                  color: c,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            );
          }),
          SizedBox(
            width: 104,
            child: Text(
              fmtCashFlowCents(grandTotal, showZero: true),
              textAlign: TextAlign.right,
              style: TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 12.5,
                color: grandTotal >= 0 ? colors.income : colors.expense,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
