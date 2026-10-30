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

class _CashFlowRowItem {
  final Widget left;
  final Widget right;
  final double height;

  const _CashFlowRowItem({
    required this.left,
    required this.right,
    required this.height,
  });
}

class _CashFlowViewState extends State<CashFlowView> {
  CashFlowPeriodKind _periodKind = CashFlowPeriodKind.monthly;
  late int _year;
  late int _month;
  Set<String> _selectedAccountIds = {};
  CashFlowStatusFilter _statusFilter = CashFlowStatusFilter.all;
  CashFlowKindFilter _kindFilter = CashFlowKindFilter.all;
  CashFlowDateMode _dateMode = CashFlowDateMode.transactionDate;
  String _searchQuery = '';
  final Set<String> _collapsedGroups = {};

  late final ScrollController _headerHScrollController;
  late final ScrollController _bodyHScrollController;
  late final ScrollController _catVScrollController;
  late final ScrollController _dataVScrollController;
  bool _isSyncingHScroll = false;
  bool _isSyncingVScroll = false;

  @override
  void initState() {
    super.initState();
    final mParts = widget.store.month.split('-');
    _year = int.tryParse(mParts[0]) ?? DateTime.now().year;
    _month = mParts.length >= 2 ? (int.tryParse(mParts[1]) ?? DateTime.now().month) : DateTime.now().month;

    _headerHScrollController = ScrollController();
    _bodyHScrollController = ScrollController();
    _catVScrollController = ScrollController();
    _dataVScrollController = ScrollController();

    _headerHScrollController.addListener(() {
      if (_isSyncingHScroll) return;
      _isSyncingHScroll = true;
      if (_bodyHScrollController.hasClients &&
          _bodyHScrollController.offset != _headerHScrollController.offset) {
        _bodyHScrollController.jumpTo(_headerHScrollController.offset);
      }
      _isSyncingHScroll = false;
    });

    _bodyHScrollController.addListener(() {
      if (_isSyncingHScroll) return;
      _isSyncingHScroll = true;
      if (_headerHScrollController.hasClients &&
          _headerHScrollController.offset != _bodyHScrollController.offset) {
        _headerHScrollController.jumpTo(_bodyHScrollController.offset);
      }
      _isSyncingHScroll = false;
    });

    _catVScrollController.addListener(() {
      if (_isSyncingVScroll) return;
      _isSyncingVScroll = true;
      if (_dataVScrollController.hasClients &&
          _dataVScrollController.offset != _catVScrollController.offset) {
        _dataVScrollController.jumpTo(_catVScrollController.offset);
      }
      _isSyncingVScroll = false;
    });

    _dataVScrollController.addListener(() {
      if (_isSyncingVScroll) return;
      _isSyncingVScroll = true;
      if (_catVScrollController.hasClients &&
          _catVScrollController.offset != _dataVScrollController.offset) {
        _catVScrollController.jumpTo(_dataVScrollController.offset);
      }
      _isSyncingVScroll = false;
    });
  }

  @override
  void dispose() {
    _headerHScrollController.dispose();
    _bodyHScrollController.dispose();
    _catVScrollController.dispose();
    _dataVScrollController.dispose();
    super.dispose();
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

  double _rowHeight(double base) {
    if (widget.store.fontScale <= 1.0) return base;
    return (base * (1.0 + (widget.store.fontScale - 1.0) * 0.75)).roundToDouble();
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
      month: _month,
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
                    if (_periodKind == CashFlowPeriodKind.daily)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.chevron_left),
                            tooltip: 'Mês anterior',
                            onPressed: () {
                              setState(() {
                                if (_month == 1) {
                                  _month = 12;
                                  _year -= 1;
                                } else {
                                  _month -= 1;
                                }
                              });
                            },
                          ),
                          Text(
                            '${_month.toString().padLeft(2, '0')}/$_year',
                            style: const TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 15,
                            ),
                          ),
                          IconButton(
                            icon: const Icon(Icons.chevron_right),
                            tooltip: 'Próximo mês',
                            onPressed: () {
                              setState(() {
                                if (_month == 12) {
                                  _month = 1;
                                  _year += 1;
                                } else {
                                  _month += 1;
                                }
                              });
                            },
                          ),
                        ],
                      )
                    else if (_periodKind != CashFlowPeriodKind.yearly)
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.chevron_left),
                            tooltip: 'Ano anterior',
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
                            tooltip: 'Próximo ano',
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
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final scaleBonus = widget.store.fontScale > 1.0 ? (widget.store.fontScale - 1.0) : 0.0;
                  final catWidth = 230.0 + (scaleBonus * 35.0);
                  final colWidth = (_periodKind == CashFlowPeriodKind.daily ? 112.0 : 104.0) + (scaleBonus * 20.0);
                  final totalWidth = 114.0 + (scaleBonus * 20.0);
                  final gridWidth = (matrix.columns.length * colWidth) + totalWidth;
                  final allRows = _buildAllRows(matrix, colors, colWidth, totalWidth);

                  return Column(
                    children: [
                      // 1. CABEÇALHO FIXO VERTICALMENTE (Sticky Header Row)
                      Container(
                        height: _rowHeight(48),
                        decoration: BoxDecoration(
                          color: colors.bgPrimary.withValues(alpha: 0.85),
                          border: Border(
                            bottom: BorderSide(color: colors.borderGlass),
                          ),
                        ),
                        child: Row(
                          children: [
                            // Canto superior esquerdo: Fixo horizontal e verticalmente
                            Container(
                              width: catWidth,
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              alignment: Alignment.centerLeft,
                              child: const Text(
                                'Categoria / Subcategoria',
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 12,
                                ),
                              ),
                            ),
                            // Colunas de Período (rolagem horizontal sincronizada com o corpo)
                            Expanded(
                              child: SingleChildScrollView(
                                controller: _headerHScrollController,
                                scrollDirection: Axis.horizontal,
                                physics: const ClampingScrollPhysics(),
                                child: SizedBox(
                                  width: gridWidth,
                                  child: Row(
                                    children: [
                                      ...List.generate(
                                        matrix.columns.length,
                                        (i) {
                                          final col = matrix.columns[i];
                                          return SizedBox(
                                            width: colWidth,
                                            child: Padding(
                                              padding: const EdgeInsets.symmetric(horizontal: 4),
                                              child: _clickable(
                                                Column(
                                                  mainAxisAlignment: MainAxisAlignment.center,
                                                  crossAxisAlignment: CrossAxisAlignment.end,
                                                  children: [
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
                                                    Text(
                                                      col.title,
                                                      textAlign: TextAlign.right,
                                                      style: TextStyle(
                                                        fontSize: 9,
                                                        color: colors.textSecondary,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                                () => _showDetail(matrix, col: i),
                                              ),
                                            ),
                                          );
                                        },
                                      ),
                                      SizedBox(
                                        width: totalWidth,
                                        child: const Padding(
                                          padding: EdgeInsets.symmetric(horizontal: 4),
                                          child: Align(
                                            alignment: Alignment.centerRight,
                                            child: Text(
                                              'Total',
                                              style: TextStyle(
                                                fontWeight: FontWeight.w800,
                                                fontSize: 12,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      // 2. CORPO DA MATRIZ (Freeze Panes com Barra de Rolagem Horizontal no Rodapé Visível)
                      Expanded(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            // Coluna inicial das Categorias (Fixa na horizontal, com rolagem vertical sincronizada)
                            Container(
                              width: catWidth,
                              decoration: BoxDecoration(
                                border: Border(
                                  right: BorderSide(
                                    color: colors.borderGlass.withValues(alpha: 0.5),
                                  ),
                                ),
                              ),
                              child: SingleChildScrollView(
                                controller: _catVScrollController,
                                scrollDirection: Axis.vertical,
                                physics: const ClampingScrollPhysics(),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.stretch,
                                  children: allRows
                                      .map((r) => SizedBox(height: r.height, child: r.left))
                                      .toList(),
                                ),
                              ),
                            ),
                            // Grid de dados (Rolagem horizontal EXTERNA com barra visível no rodapé e rolagem vertical INTERNA)
                            Expanded(
                              child: Scrollbar(
                                controller: _bodyHScrollController,
                                thumbVisibility: true,
                                trackVisibility: true,
                                child: SingleChildScrollView(
                                  controller: _bodyHScrollController,
                                  scrollDirection: Axis.horizontal,
                                  physics: const ClampingScrollPhysics(),
                                  child: SizedBox(
                                    width: gridWidth,
                                    child: Scrollbar(
                                      controller: _dataVScrollController,
                                      thumbVisibility: true,
                                      child: SingleChildScrollView(
                                        controller: _dataVScrollController,
                                        scrollDirection: Axis.vertical,
                                        physics: const ClampingScrollPhysics(),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.stretch,
                                          children: allRows
                                              .map((r) => SizedBox(height: r.height, child: r.right))
                                              .toList(),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                );
                },
              ),
            ),
          ),
        ),
      ],
    );
  }

  List<_CashFlowRowItem> _buildAllRows(
    CashFlowMatrix matrix,
    OpenMoneyColors colors,
    double colWidth,
    double totalWidth,
  ) {
    final rows = <_CashFlowRowItem>[];

    // Saldo Anterior Acumulado (Top)
    rows.add(
      _buildSummaryRow(
        label: 'Saldo Anterior Acumulado',
        periodAmounts: matrix.priorBalancePeriodTotals,
        grandTotal: matrix.priorBalanceGrandTotal,
        colors: colors,
        colWidth: colWidth,
        totalWidth: totalWidth,
        highlight: false,
      ),
    );

    // Section 1: Rendimento / Receitas
    rows.addAll(_buildSectionRowItems(
      matrix,
      matrix.incomeSection,
      colors.income,
      colors,
      colWidth,
      totalWidth,
    ));

    // Separator
    rows.add(_buildSeparator(colors));

    // Section 2: Despesas
    rows.addAll(_buildSectionRowItems(
      matrix,
      matrix.expenseSection,
      colors.expense,
      colors,
      colWidth,
      totalWidth,
    ));

    // Separator
    rows.add(_buildSeparator(colors));

    // Summary Rows: Net Result, Prior Balance, Ending Balance
    rows.add(
      _buildSummaryRow(
        label: 'Rendimento menos Despesas',
        periodAmounts: matrix.netPeriodTotals,
        grandTotal: matrix.netGrandTotal,
        colors: colors,
        colWidth: colWidth,
        totalWidth: totalWidth,
        highlight: true,
      ),
    );

    rows.add(
      _buildSummaryRow(
        label: 'Saldo Anterior Acumulado',
        periodAmounts: matrix.priorBalancePeriodTotals,
        grandTotal: matrix.priorBalanceGrandTotal,
        colors: colors,
        colWidth: colWidth,
        totalWidth: totalWidth,
        highlight: false,
      ),
    );

    rows.add(
      _buildSummaryRow(
        label: 'Saldo Final Acumulado',
        periodAmounts: matrix.endingBalancePeriodTotals,
        grandTotal: matrix.endingBalanceGrandTotal,
        colors: colors,
        colWidth: colWidth,
        totalWidth: totalWidth,
        highlight: true,
      ),
    );

    return rows;
  }

  _CashFlowRowItem _buildSeparator(OpenMoneyColors colors) {
    return _CashFlowRowItem(
      height: 8,
      left: Container(
        color: colors.bgPrimary.withValues(alpha: 0.15),
      ),
      right: Container(
        color: colors.bgPrimary.withValues(alpha: 0.15),
      ),
    );
  }

  List<_CashFlowRowItem> _buildSectionRowItems(
    CashFlowMatrix matrix,
    CashFlowSection section,
    Color sectionColor,
    OpenMoneyColors colors,
    double colWidth,
    double totalWidth,
  ) {
    final rows = <_CashFlowRowItem>[];
    final isIncome = identical(section, matrix.incomeSection);

    // Section Banner
    rows.add(
      _CashFlowRowItem(
        height: _rowHeight(32),
        left: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          alignment: Alignment.centerLeft,
          color: sectionColor.withValues(alpha: 0.14),
          child: Text(
            section.title.toUpperCase(),
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 12,
              color: sectionColor,
            ),
          ),
        ),
        right: Container(
          color: sectionColor.withValues(alpha: 0.14),
        ),
      ),
    );

    for (final group in section.groups) {
      final groupKey = '${section.title}:${group.name}';
      final isCollapsed = _collapsedGroups.contains(groupKey);

      // Category Header Row
      rows.add(
        _CashFlowRowItem(
          height: _rowHeight(36),
          left: InkWell(
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
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: colors.borderGlass.withValues(alpha: 0.35),
                  ),
                ),
              ),
              child: Row(
                children: [
                  if (group.hasSubcategories)
                    Icon(
                      isCollapsed ? Icons.chevron_right : Icons.expand_more,
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
          ),
          right: Container(
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(
                  color: colors.borderGlass.withValues(alpha: 0.35),
                ),
              ),
            ),
            child: Row(
              children: [
                ...List.generate(
                  group.periodTotals.length,
                  (i) => SizedBox(
                    width: colWidth,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
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
                        () => _showDetail(matrix, col: i, isIncome: isIncome, top: group.name),
                      ),
                    ),
                  ),
                ),
                SizedBox(
                  width: totalWidth,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
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
                      () => _showDetail(matrix, isIncome: isIncome, top: group.name),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );

      // Subcategories Rows
      if (group.hasSubcategories && !isCollapsed) {
        for (final sub in group.subcategories) {
          final subKey = sub.name.endsWith(' - Não-atribuído')
              ? CashFlowEngine.directSubKey
              : sub.name;

          rows.add(
            _CashFlowRowItem(
              height: _rowHeight(32),
              left: Container(
                padding: const EdgeInsets.only(left: 32, right: 12),
                alignment: Alignment.centerLeft,
                child: Text(
                  sub.name,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: colors.textSecondary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              right: Row(
                children: [
                  ...List.generate(
                    sub.periodAmounts.length,
                    (i) => SizedBox(
                      width: colWidth,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
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
                          () => _showDetail(
                            matrix,
                            col: i,
                            isIncome: isIncome,
                            top: group.name,
                            sub: subKey,
                          ),
                        ),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: totalWidth,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
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
                        () => _showDetail(
                          matrix,
                          isIncome: isIncome,
                          top: group.name,
                          sub: subKey,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        }
      }
    }

    // Section Total Row
    rows.add(
      _CashFlowRowItem(
        height: _rowHeight(38),
        left: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          alignment: Alignment.centerLeft,
          color: sectionColor.withValues(alpha: 0.10),
          child: Text(
            'Total ${section.title}',
            style: TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 12.5,
              color: sectionColor,
            ),
          ),
        ),
        right: Container(
          color: sectionColor.withValues(alpha: 0.10),
          child: Row(
            children: [
              ...List.generate(
                section.periodTotals.length,
                (i) => SizedBox(
                  width: colWidth,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
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
              ),
              SizedBox(
                width: totalWidth,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
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
              ),
            ],
          ),
        ),
      ),
    );

    return rows;
  }

  _CashFlowRowItem _buildSummaryRow({
    required String label,
    required List<int> periodAmounts,
    required int grandTotal,
    required OpenMoneyColors colors,
    required double colWidth,
    required double totalWidth,
    required bool highlight,
  }) {
    final bgColor = highlight
        ? colors.accent.withValues(alpha: 0.12)
        : colors.bgPrimary.withValues(alpha: 0.05);

    return _CashFlowRowItem(
      height: _rowHeight(38),
      left: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        alignment: Alignment.centerLeft,
        color: bgColor,
        child: Text(
          label,
          style: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 12.5,
            color: colors.textPrimary,
          ),
        ),
      ),
      right: Container(
        color: bgColor,
        child: Row(
          children: [
            ...periodAmounts.map((amt) {
              final c = amt >= 0 ? colors.income : colors.expense;
              return SizedBox(
                width: colWidth,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
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
                ),
              );
            }),
            SizedBox(
              width: totalWidth,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
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
            ),
          ],
        ),
      ),
    );
  }
}
