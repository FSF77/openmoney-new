import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/openmoney_models.dart';
import '../../services/cash_flow_engine.dart';
import '../../services/native_file_picker.dart';
import '../../services/platform_io.dart';
import '../../store/money_store.dart';
import '../modals/account_multi_select_filter.dart';
import '../modals/category_drill_down_modal.dart';
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
  bool _mobileShowFilters = false;

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
    final column = col != null && col >= 0 && col < matrix.columns.length
        ? matrix.columns[col]
        : null;
    final targetMonth = column?.id;

    String? categoryPath;
    final catType = isIncome == null ? null : (isIncome ? 'Receita' : 'Despesa');
    String? title;

    if (top != null) {
      if (sub != null &&
          sub != CashFlowEngine.directSubKey &&
          !sub.endsWith(' - Não-atribuído')) {
        categoryPath = '$top$kCategorySep$sub';
        title = '$top › $sub${column != null ? ' · ${column.title}' : ' · Todos os períodos'}';
      } else {
        categoryPath = top;
        title = '$top${column != null ? ' · ${column.title}' : ' · Todos os períodos'}';
      }
    } else if (isIncome != null) {
      title = 'Total ${isIncome ? "Rendimento" : "Despesas"}${column != null ? ' · ${column.title}' : ' · Todos os períodos'}';
    } else if (column != null) {
      title = 'Fluxo de Caixa · ${column.title}';
    } else {
      title = 'Fluxo de Caixa · Todos os períodos';
    }

    showCategoryDrillDownModal(
      context,
      widget.store,
      categoryPath,
      initialCurrentMonthOnly: targetMonth != null,
      targetMonth: targetMonth,
      categoryTypeFilter: catType,
      titleOverride: title,
      accountFilterIds:
          _selectedAccountIds.isEmpty ? null : _selectedAccountIds,
      dateMode: _dateMode,
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

  static const double _scrollbarSpacer = 20.0;

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

    final isMobile = MediaQuery.sizeOf(context).width < 720;

    return Column(
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(
            isMobile ? 10 : 16,
            isMobile ? 8 : 14,
            isMobile ? 10 : 16,
            isMobile ? 4 : 8,
          ),
          child: GlassCard(
            padding: EdgeInsets.all(isMobile ? 10 : 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: isMobile ? 8 : 12,
                  runSpacing: isMobile ? 6 : 10,
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.grid_on_rounded,
                            color: colors.accent, size: isMobile ? 18 : 22),
                        const SizedBox(width: 8),
                        Flexible(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Fluxo de Caixa (${_periodKind.label})',
                                style: TextStyle(
                                  fontSize: isMobile ? 14.5 : 17,
                                  fontWeight: FontWeight.w800,
                                  color: colors.textPrimary,
                                ),
                              ),
                              Text(
                                matrix.periodSubtitle,
                                style: TextStyle(
                                  fontSize: isMobile ? 11 : 12,
                                  color: colors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    SegmentedButton<CashFlowPeriodKind>(
                      style: isMobile
                          ? SegmentedButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.symmetric(horizontal: 6),
                              textStyle: const TextStyle(fontSize: 11),
                            )
                          : null,
                      segments: CashFlowPeriodKind.values
                          .map((p) =>
                              ButtonSegment(value: p, label: Text(p.label)))
                          .toList(),
                      selected: {_periodKind},
                      onSelectionChanged: (s) =>
                          setState(() => _periodKind = s.first),
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_periodKind == CashFlowPeriodKind.daily) ...[
                          IconButton(
                            visualDensity: isMobile ? VisualDensity.compact : null,
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
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: isMobile ? 13.5 : 15,
                            ),
                          ),
                          IconButton(
                            visualDensity: isMobile ? VisualDensity.compact : null,
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
                        ] else if (_periodKind != CashFlowPeriodKind.yearly) ...[
                          IconButton(
                            visualDensity: isMobile ? VisualDensity.compact : null,
                            icon: const Icon(Icons.chevron_left),
                            tooltip: 'Ano anterior',
                            onPressed: () => setState(() => _year -= 1),
                          ),
                          Text(
                            '$_year',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: isMobile ? 13.5 : 15,
                            ),
                          ),
                          IconButton(
                            visualDensity: isMobile ? VisualDensity.compact : null,
                            icon: const Icon(Icons.chevron_right),
                            tooltip: 'Próximo ano',
                            onPressed: () => setState(() => _year += 1),
                          ),
                        ],
                        Tooltip(
                          message: _collapsedGroups.isEmpty
                              ? 'Recolher todas as categorias'
                              : 'Expandir todas as categorias',
                          child: OutlinedButton(
                            style: isMobile
                                ? OutlinedButton.styleFrom(
                                    visualDensity: VisualDensity.compact,
                                    padding: const EdgeInsets.symmetric(horizontal: 10),
                                  )
                                : null,
                            onPressed: () => _toggleAllGroups(matrix),
                            child: Icon(
                              _collapsedGroups.isEmpty
                                  ? Icons.unfold_less
                                  : Icons.unfold_more,
                              size: 18,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Tooltip(
                          message: 'Exportar CSV',
                          child: OutlinedButton(
                            style: isMobile
                                ? OutlinedButton.styleFrom(
                                    visualDensity: VisualDensity.compact,
                                    padding: const EdgeInsets.symmetric(horizontal: 10),
                                  )
                                : null,
                            onPressed: () => _exportCsv(matrix),
                            child: const Icon(Icons.download, size: 18),
                          ),
                        ),
                        if (isMobile) ...[
                          const SizedBox(width: 6),
                          FilledButton.tonalIcon(
                            style: FilledButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.symmetric(horizontal: 10),
                            ),
                            icon: Icon(
                              _mobileShowFilters
                                  ? Icons.expand_less
                                  : Icons.tune,
                              size: 16,
                            ),
                            label: Text(
                              _mobileShowFilters ? 'Ocultar' : 'Filtros',
                              style: const TextStyle(fontSize: 11.5),
                            ),
                            onPressed: () => setState(
                                () => _mobileShowFilters = !_mobileShowFilters),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
                if (!isMobile || _mobileShowFilters) ...[
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 10,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.start,
                    children: [
                      SizedBox(
                        width: 200,
                        height: 40,
                        child: AccountMultiSelectFilter(
                          store: widget.store,
                          selectedAccountIds: _selectedAccountIds,
                          asFormField: true,
                          width: 200,
                          height: 40,
                          onSelectionChanged: (set) =>
                              setState(() => _selectedAccountIds = set),
                        ),
                      ),
                      SizedBox(
                        width: 200,
                        height: 40,
                        child: DropdownButtonFormField<CashFlowStatusFilter>(
                          initialValue: _statusFilter,
                          isExpanded: true,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: colors.textPrimary,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Status de Conciliação',
                            labelStyle: TextStyle(fontSize: 13),
                            isDense: true,
                            contentPadding:
                                EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            border: OutlineInputBorder(),
                          ),
                          items: CashFlowStatusFilter.values
                              .map((s) => DropdownMenuItem(
                                    value: s,
                                    child: Text(
                                      s.shortLabel,
                                      style: const TextStyle(fontSize: 13),
                                    ),
                                  ))
                              .toList(),
                          onChanged: (v) {
                            if (v != null) setState(() => _statusFilter = v);
                          },
                        ),
                      ),
                      SizedBox(
                        width: 200,
                        height: 40,
                        child: DropdownButtonFormField<CashFlowKindFilter>(
                          initialValue: _kindFilter,
                          isExpanded: true,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: colors.textPrimary,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Tipo',
                            labelStyle: TextStyle(fontSize: 13),
                            isDense: true,
                            contentPadding:
                                EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            border: OutlineInputBorder(),
                          ),
                          items: CashFlowKindFilter.values
                              .map((k) => DropdownMenuItem(
                                    value: k,
                                    child: Text(
                                      k.label,
                                      style: const TextStyle(fontSize: 13),
                                    ),
                                  ))
                              .toList(),
                          onChanged: (v) {
                            if (v != null) setState(() => _kindFilter = v);
                          },
                        ),
                      ),
                      SizedBox(
                        width: 200,
                        height: 40,
                        child: DropdownButtonFormField<CashFlowDateMode>(
                          initialValue: _dateMode,
                          isExpanded: true,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                            color: colors.textPrimary,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Regime Contábil',
                            labelStyle: TextStyle(fontSize: 13),
                            isDense: true,
                            contentPadding:
                                EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            border: OutlineInputBorder(),
                          ),
                          items: CashFlowDateMode.values
                              .map((m) => DropdownMenuItem(
                                    value: m,
                                    child: Text(
                                      m.shortLabel,
                                      style: const TextStyle(fontSize: 13),
                                    ),
                                  ))
                              .toList(),
                          onChanged: (v) {
                            if (v != null) setState(() => _dateMode = v);
                          },
                        ),
                      ),
                      SizedBox(
                        width: 200,
                        height: 40,
                        child: TextField(
                          style: TextStyle(
                            fontSize: 13,
                            color: colors.textPrimary,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Filtrar categoria...',
                            labelStyle: TextStyle(fontSize: 13),
                            prefixIcon: Icon(Icons.search, size: 16),
                            prefixIconConstraints:
                                BoxConstraints(minWidth: 32, minHeight: 0),
                            isDense: true,
                            contentPadding:
                                EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            border: OutlineInputBorder(),
                          ),
                          onChanged: (v) => setState(() => _searchQuery = v),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Divider(height: 1),
                  const SizedBox(height: 12),
                  _buildKpiSummaryRow(matrix, colors),
                ] else ...[
                  const SizedBox(height: 6),
                  const Divider(height: 1),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 12,
                    runSpacing: 4,
                    children: [
                      Text(
                        'Rec: ${brl(matrix.incomeSection.grandTotal)}',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: colors.income,
                        ),
                      ),
                      Text(
                        'Desp: ${brl(matrix.expenseSection.grandTotal)}',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: colors.expense,
                        ),
                      ),
                      Text(
                        'Líq: ${brl(matrix.netGrandTotal)}',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w800,
                          color: matrix.netGrandTotal >= 0
                              ? colors.income
                              : colors.expense,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
        Expanded(
          child: Padding(
            padding: EdgeInsets.fromLTRB(
              isMobile ? 10 : 16,
              4,
              isMobile ? 10 : 16,
              isMobile ? 10 : 20,
            ),
            child: GlassCard(
              padding: EdgeInsets.zero,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final isCompactGrid = constraints.maxWidth < 640;
                  final scaleBonus = widget.store.fontScale > 1.0 ? (widget.store.fontScale - 1.0) : 0.0;
                  final catWidth = (isCompactGrid ? 142.0 : 230.0) + (scaleBonus * 40.0);
                  final colWidth = (((isCompactGrid
                              ? 104.0
                              : (_periodKind == CashFlowPeriodKind.daily ? 124.0 : 130.0)) *
                          widget.store.fontScale))
                      .roundToDouble();
                  final totalWidth =
                      ((isCompactGrid ? 114.0 : 145.0) * widget.store.fontScale)
                          .roundToDouble();
                  final gridWidth = (matrix.columns.length * colWidth) + totalWidth + _scrollbarSpacer;
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
                                      const SizedBox(width: _scrollbarSpacer),
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
        isEndingBalance: true,
        columns: matrix.columns,
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
                          maxLines: 1,
                          softWrap: false,
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
                        maxLines: 1,
                        softWrap: false,
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
                const SizedBox(width: _scrollbarSpacer),
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
                            maxLines: 1,
                            softWrap: false,
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
                          maxLines: 1,
                          softWrap: false,
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
                  const SizedBox(width: _scrollbarSpacer),
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
                        maxLines: 1,
                        softWrap: false,
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
                      maxLines: 1,
                      softWrap: false,
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
              const SizedBox(width: _scrollbarSpacer),
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
    bool isEndingBalance = false,
    List<CashFlowColumnDef>? columns,
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
            ...List.generate(periodAmounts.length, (i) {
              final amt = periodAmounts[i];
              final c = amt >= 0 ? colors.income : colors.expense;
              final col = (columns != null && i < columns.length) ? columns[i] : null;
              final comment = col != null ? widget.store.commentForPeriod(col.id) : null;
              final hasComment = comment != null && comment.trim().isNotEmpty;

              Widget content = Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    if (hasComment) ...[
                      Icon(
                        Icons.comment_outlined,
                        size: 11,
                        color: colors.accent,
                      ),
                      const SizedBox(width: 3),
                    ],
                    Flexible(
                      child: Text(
                        fmtCashFlowCents(amt, showZero: true),
                        textAlign: TextAlign.right,
                        maxLines: 1,
                        softWrap: false,
                        style: TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 12,
                          color: c,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ),
                  ],
                ),
              );

              if (isEndingBalance && col != null) {
                final tooltipMsg = hasComment
                    ? 'Comentário (${col.title}):\n$comment\n(Clique para editar)'
                    : 'Clique para adicionar comentário em ${col.title}';
                content = Tooltip(
                  message: tooltipMsg,
                  waitDuration: const Duration(milliseconds: 300),
                  child: InkWell(
                    onTap: () => _showPeriodCommentDialog(
                      context,
                      col.id,
                      col.title,
                      amt,
                    ),
                    borderRadius: BorderRadius.circular(4),
                    child: content,
                  ),
                );
              }

              return SizedBox(
                width: colWidth,
                child: content,
              );
            }),
            SizedBox(
              width: totalWidth,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(
                  fmtCashFlowCents(grandTotal, showZero: true),
                  textAlign: TextAlign.right,
                  maxLines: 1,
                  softWrap: false,
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 12.5,
                    color: grandTotal >= 0 ? colors.income : colors.expense,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ),
            const SizedBox(width: _scrollbarSpacer),
          ],
        ),
      ),
    );
  }

  Future<void> _showPeriodCommentDialog(
    BuildContext context,
    String periodId,
    String periodTitle,
    int balanceCents,
  ) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colors = OpenMoneyColors(isDark);
    final initialText = widget.store.commentForPeriod(periodId) ?? '';
    final controller = TextEditingController(text: initialText);

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return AlertDialog(
          backgroundColor: colors.bgSecondary,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: colors.borderGlass),
          ),
          titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
          contentPadding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
          actionsPadding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: colors.accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.comment_outlined, size: 20, color: colors.accent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Comentário do Saldo Final',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: colors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Período: $periodTitle • Saldo: ${fmtCashFlowCents(balanceCents, showZero: true)}',
                      style: TextStyle(
                        fontSize: 12,
                        color: colors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          content: SizedBox(
            width: 440,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: controller,
                  autofocus: true,
                  maxLines: 4,
                  minLines: 3,
                  style: TextStyle(
                    fontSize: 13,
                    color: colors.textPrimary,
                  ),
                  decoration: InputDecoration(
                    hintText: 'Digite anotações ou observações relevantes deste período...',
                    hintStyle: TextStyle(
                      fontSize: 13,
                      color: colors.textSecondary.withValues(alpha: 0.6),
                    ),
                    filled: true,
                    fillColor: colors.bgPrimary,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: colors.borderGlass),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: colors.borderGlass),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                      borderSide: BorderSide(color: colors.accent, width: 1.5),
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            Row(
              children: [
                if (initialText.trim().isNotEmpty)
                  TextButton(
                    onPressed: () {
                      widget.store.setCommentForPeriod(periodId, null);
                      Navigator.of(ctx).pop();
                    },
                    style: TextButton.styleFrom(
                      foregroundColor: colors.expense,
                    ),
                    child: const Text('Excluir'),
                  ),
                const Spacer(),
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child: Text(
                    'Cancelar',
                    style: TextStyle(color: colors.textSecondary),
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: () {
                    widget.store.setCommentForPeriod(periodId, controller.text);
                    Navigator.of(ctx).pop();
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: colors.accent,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: const Text('Salvar'),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _buildKpiSummaryRow(CashFlowMatrix matrix, OpenMoneyColors colors) {
    final totalIncome = matrix.incomeSection.grandTotal;
    final totalExpense = matrix.expenseSection.grandTotal;
    final net = matrix.netGrandTotal;
    final isPositive = net >= 0;
    final netColor = isPositive ? colors.income : colors.expense;

    final incomeCard = _buildKpiCard(
      title: 'TOTAL RECEITAS',
      amount: brl(totalIncome),
      color: colors.income,
      icon: Icons.north_east,
      colors: colors,
    );

    final expenseCard = _buildKpiCard(
      title: 'TOTAL DESPESAS',
      amount: brl(totalExpense),
      color: colors.expense,
      icon: Icons.south_east,
      colors: colors,
    );

    final netCard = _buildKpiCard(
      title: 'RESULTADO LÍQUIDO',
      amount: brl(net),
      color: netColor,
      icon: isPositive ? Icons.check_circle_rounded : Icons.error_rounded,
      colors: colors,
      trailingBadge: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(
          color: netColor.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          isPositive ? 'Superávit' : 'Déficit',
          style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.bold,
            color: netColor,
          ),
        ),
      ),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 640) {
          return Column(
            children: [
              incomeCard,
              const SizedBox(height: 8),
              expenseCard,
              const SizedBox(height: 8),
              netCard,
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: incomeCard),
            const SizedBox(width: 14),
            Expanded(child: expenseCard),
            const SizedBox(width: 14),
            Expanded(child: netCard),
          ],
        );
      },
    );
  }

  Widget _buildKpiCard({
    required String title,
    required String amount,
    required Color color,
    required IconData icon,
    required OpenMoneyColors colors,
    Widget? trailingBadge,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: colors.surfaceCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: color.withValues(alpha: 0.22),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: colors.isDark ? 0.2 : 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.18),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, size: 16, color: color),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 6,
                  runSpacing: 2,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: colors.textSecondary,
                      ),
                    ),
                    if (trailingBadge != null) trailingBadge,
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  amount,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: color,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
