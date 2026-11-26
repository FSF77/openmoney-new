import 'package:flutter/material.dart';
import '../../models/openmoney_models.dart';
import '../../services/analytics_engine.dart';
import '../../services/cash_flow_engine.dart';
import '../../store/money_store.dart';
import '../modals/account_multi_select_filter.dart';
import '../theme/liquid_glass.dart';
import 'charts/chart_widgets.dart';

enum _Period {
  m1('Mês'),
  m3('3M'),
  m6('6M'),
  m12('12M'),
  ytd('Ano atual'),
  lastYear('Ano anterior'),
  all('Todo período');

  final String label;
  const _Period(this.label);
}

/// Dashboard interativo de gráficos e KPIs financeiros (somente leitura).
class ChartsDashboardView extends StatefulWidget {
  final MoneyStore store;
  const ChartsDashboardView({super.key, required this.store});

  @override
  State<ChartsDashboardView> createState() => _ChartsDashboardViewState();
}

class _ChartsDashboardViewState extends State<ChartsDashboardView> {
  _Period _period = _Period.m6;
  Set<String> _accountIds = {};
  CashFlowStatusFilter _statusFilter = CashFlowStatusFilter.all;
  double _savingsGoal = 0.20;
  double _reserveMonths = 6;
  String? _categoryTop;
  String? _selectedMonth;

  AnalyticsSnapshot? _snap;
  AnalyticsSnapshot? _trend;

  @override
  void initState() {
    super.initState();
    _loadPrefs();
    _selectedMonth = widget.store.month;
    widget.store.addListener(_onStore);
  }

  @override
  void dispose() {
    widget.store.removeListener(_onStore);
    super.dispose();
  }

  void _onStore() {
    if (!mounted) return;
    setState(() {
      _snap = null;
      _trend = null;
    });
  }

  void _loadPrefs() {
    final p = widget.store.chartsPrefs;
    final name = p['period'];
    _period = _Period.values.firstWhere((e) => e.name == name,
        orElse: () => _Period.m6);
    if (p['accounts'] is List) {
      _accountIds = (p['accounts'] as List).map((e) => e.toString()).toSet();
    }
    final statusName = p['statusFilter'];
    _statusFilter = CashFlowStatusFilter.values.firstWhere(
      (e) => e.name == statusName,
      orElse: () => CashFlowStatusFilter.all,
    );
    if (p['savingsGoal'] is num) _savingsGoal = (p['savingsGoal'] as num).toDouble();
    if (p['reserveMonths'] is num) _reserveMonths = (p['reserveMonths'] as num).toDouble();
  }

  void _savePrefs() {
    widget.store.chartsPrefs = {
      'period': _period.name,
      'accounts': _accountIds.toList(),
      'statusFilter': _statusFilter.name,
      'savingsGoal': _savingsGoal,
      'reserveMonths': _reserveMonths,
    };
    // Persistência silenciosa (não dispara reconstrução do snapshot).
    widget.store.removeListener(_onStore);
    widget.store.setChartsPrefs(widget.store.chartsPrefs);
    widget.store.addListener(_onStore);
  }

  void _update(VoidCallback fn) {
    setState(() {
      fn();
      _snap = null;
      _trend = null;
    });
    _savePrefs();
  }

  String get _refYM => _selectedMonth ?? widget.store.month;

  AnalyticsFilter _filter({bool trend = false}) {
    final ref = _refYM;
    String from = ref;
    String to = ref;
    bool isAll = false;

    switch (_period) {
      case _Period.m1:
        from = ref;
        to = ref;
        break;
      case _Period.m3:
        from = AnalyticsEngine.addMonths(ref, -2);
        to = ref;
        break;
      case _Period.m6:
        from = AnalyticsEngine.addMonths(ref, -5);
        to = ref;
        break;
      case _Period.m12:
        from = AnalyticsEngine.addMonths(ref, -11);
        to = ref;
        break;
      case _Period.ytd:
        from = '${ref.substring(0, 4)}-01';
        to = ref;
        break;
      case _Period.lastYear:
        final y = int.parse(ref.substring(0, 4)) - 1;
        from = '$y-01';
        to = '$y-12';
        break;
      case _Period.all:
        isAll = true;
        String minM = ref;
        String maxM = ref;
        for (final t in widget.store.db.txs) {
          if (t.date.length >= 7) {
            final ym = t.date.substring(0, 7);
            if (ym.compareTo(minM) < 0) minM = ym;
            if (ym.compareTo(maxM) > 0) maxM = ym;
          }
        }
        from = minM;
        to = maxM;
        break;
    }

    if (trend) {
      if (_period == _Period.all) {
        from = from;
        to = to;
      } else {
        from = AnalyticsEngine.addMonths(to, -11);
      }
    }

    return AnalyticsFilter(
      fromYM: from,
      toYM: to,
      accountIds: _accountIds,
      statusFilter: _statusFilter,
      categoryTop: trend ? null : _categoryTop,
      savingsGoal: _savingsGoal,
      reserveGoalMonths: _reserveMonths,
      isAllTime: isAll,
    );
  }

  double? _delta(int cur, int prev) =>
      prev == 0 ? null : (cur - prev) * 100 / prev.abs();

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colors = OpenMoneyColors(isDark);
    _snap ??= AnalyticsEngine.compute(widget.store, _filter());
    _trend ??= AnalyticsEngine.compute(widget.store, _filter(trend: true));
    final s = _snap!;
    final t = _trend!;
    final cur = s.currency;
    final f = _filter();

    return LayoutBuilder(builder: (context, c) {
      final w = c.maxWidth;
      final cols = w >= 1100 ? 3 : (w >= 700 ? 2 : 1);
      const gap = 12.0;
      final cw = (w - 24 - gap * (cols - 1)) / cols;
      Widget tile(Widget child, {int span = 1}) => SizedBox(
            width: cw * span.clamp(1, cols) + gap * (span.clamp(1, cols) - 1),
            child: child,
          );

      final netWorthSpark = t.monthly.map((e) => e.netWorth / 100).toList();
      final savingsColor = s.savingsRate >= _savingsGoal
          ? colors.income
          : (s.savingsRate >= 0 ? colors.warning : colors.expense);
      final scoreColor = s.healthScore >= 70
          ? colors.income
          : (s.healthScore >= 40 ? colors.warning : colors.expense);
      final burnPct = s.projectedMonthExpense > 0 && s.burnPerDay > 0
          ? 1.0
          : 0.0;

      final children = <Widget>[
        tile(KpiCard(
          label: 'Patrimônio líquido',
          value: formatCurrency(s.netWorth, cur),
          icon: Icons.account_balance_wallet_outlined,
          color: colors.accent,
          colors: colors,
          spark: netWorthSpark,
          hint: s.investmentsNetWorth > 0
              ? 'Contas ${formatCurrency(s.cashNetWorth, cur)} · Carteira ${formatCurrency(s.investmentsNetWorth, cur)}'
              : 'Saldo consolidado em $cur',
        )),
        tile(KpiCard(
          label: 'Receitas',
          value: formatCurrency(s.income, cur),
          icon: Icons.south_west_rounded,
          color: colors.income,
          colors: colors,
          deltaPct: f.isAllTime ? null : _delta(s.income, s.prevIncome),
          hint: f.isAllTime ? 'Total histórico' : 'vs. período anterior',
        )),
        tile(KpiCard(
          label: 'Despesas',
          value: formatCurrency(s.expense, cur),
          icon: Icons.north_east_rounded,
          color: colors.expense,
          colors: colors,
          deltaPct: f.isAllTime ? null : _delta(s.expense, s.prevExpense),
          higherIsBetter: false,
          hint: f.isAllTime ? 'Total histórico' : 'vs. período anterior',
        )),
        tile(KpiCard(
          label: 'Resultado do período',
          value: formatCurrency(s.net, cur),
          icon: Icons.balance_rounded,
          color: s.net >= 0 ? colors.income : colors.expense,
          colors: colors,
          deltaPct: f.isAllTime ? null : _delta(s.net, s.prevNet),
          hint: 'Receitas − Despesas',
        )),
        tile(KpiCard(
          label: 'Gasto médio diário (mês)',
          value: formatCurrency(s.burnPerDay, cur),
          icon: Icons.local_fire_department_outlined,
          color: colors.warning,
          colors: colors,
          hint: burnPct > 0
              ? 'Projeção do mês: ${formatCurrency(s.projectedMonthExpense, cur)}'
              : 'Sem gastos no mês final',
        )),
        tile(KpiCard(
          label: 'Comprometimento fixo',
          value: '${(s.fixedCommitment * 100).toStringAsFixed(0)}%',
          icon: Icons.lock_clock_outlined,
          color: s.fixedCommitment > 0.5 ? colors.expense : colors.accent,
          colors: colors,
          hint: 'Recorrências e parcelas / receita',
        )),
        tile(ChartCard(
          title: 'Saúde financeira',
          subtitle: 'Poupança, reserva, compromissos, orçamento e tendência',
          colors: colors,
          child: GaugeChart(
            ratio: s.healthScore / 100,
            centerText: '${s.healthScore}',
            caption: s.healthScore >= 70
                ? 'Excelente'
                : (s.healthScore >= 40 ? 'Atenção' : 'Crítico'),
            color: scoreColor,
            colors: colors,
          ),
        )),
        tile(ChartCard(
          title: 'Taxa de poupança',
          subtitle: 'Meta: ${(_savingsGoal * 100).toStringAsFixed(0)}%',
          colors: colors,
          child: GaugeChart(
            ratio: _savingsGoal > 0 ? s.savingsRate / _savingsGoal : 0,
            centerText: '${(s.savingsRate * 100).toStringAsFixed(0)}%',
            caption: 'da receita poupada',
            color: savingsColor,
            colors: colors,
          ),
        )),
        tile(ChartCard(
          title: 'Reserva de emergência',
          subtitle: 'Meta: ${_reserveMonths.toStringAsFixed(0)} meses (todo patrimônio)',
          colors: colors,
          child: GaugeChart(
            ratio: _reserveMonths > 0 ? s.runwayMonths / _reserveMonths : 0,
            centerText: s.runwayMonths.toStringAsFixed(1),
            caption: 'meses de cobertura',
            color: s.runwayMonths >= _reserveMonths
                ? colors.income
                : (s.runwayMonths >= _reserveMonths / 2
                    ? colors.warning
                    : colors.expense),
            colors: colors,
          ),
        )),
        tile(
          ChartCard(
            title: 'Fluxo de caixa mensal',
            subtitle: _period == _Period.all
                ? 'Receitas × despesas (Histórico completo · ${t.monthly.length} meses)'
                : 'Receitas × despesas (12 meses)',
            colors: colors,
            child: CashflowBarChart(
              data: t.monthly,
              currency: cur,
              colors: colors,
            ),
          ),
          span: 2,
        ),
        tile(ChartCard(
          title: 'Despesas por categoria',
          subtitle: _categoryTop == null
              ? 'Toque para filtrar todo o painel'
              : 'Filtrando: $_categoryTop',
          colors: colors,
          trailing: _categoryTop == null
              ? null
              : IconButton(
                  tooltip: 'Limpar filtro',
                  icon: const Icon(Icons.close, size: 16),
                  onPressed: () => _update(() => _categoryTop = null),
                ),
          child: CategoryDonut(
            slices: s.byCategory,
            currency: cur,
            colors: colors,
            selected: _categoryTop,
            onSelect: (n) => _update(() => _categoryTop = n),
          ),
        )),
        tile(
          ChartCard(
            title: 'Evolução do patrimônio e previsão',
            subtitle: 'Histórico mensal + projeção de 90 dias (tracejado)',
            colors: colors,
            child: TrendLineChart(
              values: t.monthly.map((e) => e.netWorth.toDouble()).toList(),
              labels: t.monthly.map((e) => _lbl(e.ym)).toList(),
              projection: _projection(s),
              color: colors.accent,
              currency: cur,
              colors: colors,
            ),
          ),
          span: 2,
        ),
        tile(ChartCard(
          title: 'Orçado × realizado',
          subtitle: fmtMonth(f.toYM),
          colors: colors,
          child: BudgetProgressList(items: s.budgets, currency: cur, colors: colors),
        )),
        tile(ChartCard(
          title: 'Top estabelecimentos',
          subtitle: 'Maiores gastos do período',
          colors: colors,
          child: PayeeRankList(items: s.topPayees, currency: cur, colors: colors),
        )),
        tile(ChartCard(
          title: 'Mapa de calor de gastos',
          subtitle: fmtMonth(f.toYM),
          colors: colors,
          child: SpendHeatmap(
              ym: f.toYM, daily: s.dailySpend, currency: cur, colors: colors),
        )),
        tile(
          ChartCard(
            title: 'Insights automáticos',
            colors: colors,
            child: s.insights.isEmpty
                ? Text('Tudo em ordem — sem alertas para o período.',
                    style: TextStyle(color: colors.textMuted, fontSize: 12))
                : Wrap(spacing: 8, runSpacing: 8, children: [
                    for (final i in s.insights)
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 7),
                        decoration: BoxDecoration(
                          color: colors.accent.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Icon(Icons.lightbulb_outline,
                              size: 14, color: colors.warning),
                          const SizedBox(width: 6),
                          Flexible(
                              child: Text(i,
                                  style: TextStyle(
                                      fontSize: 12, color: colors.textPrimary))),
                        ]),
                      ),
                  ]),
          ),
          span: 3,
        ),
      ];

      return ListView(
        padding: const EdgeInsets.all(12),
        children: [
          _filters(colors),
          const SizedBox(height: 12),
          Wrap(spacing: gap, runSpacing: gap, children: children),
          const SizedBox(height: 24),
        ],
      );
    });
  }

  String _lbl(String ym) {
    const m = ['jan', 'fev', 'mar', 'abr', 'mai', 'jun', 'jul', 'ago', 'set', 'out', 'nov', 'dez'];
    return '${m[int.parse(ym.substring(5, 7)) - 1]}/${ym.substring(2, 4)}';
  }

  /// Projeção mensal aproximada a partir do forecast diário (último saldo de cada mês futuro).
  List<double> _projection(AnalyticsSnapshot s) {
    if (s.forecast.length < 2) return const [];
    final last = <String, int>{};
    for (final p in s.forecast) {
      last[p.date.substring(0, 7)] = p.balance;
    }
    final months = last.keys.toList()..sort();
    final cur = _refYM;
    // Só projeta quando o filtro termina no mês atual/referência (série contínua).
    if (_filter(trend: true).toYM.compareTo(cur) < 0) return const [];
    return [
      for (final m in months)
        if (m.compareTo(cur) > 0) last[m]!.toDouble()
    ];
  }

  Widget _filters(OpenMoneyColors colors) {
    return GlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          for (final p in _Period.values)
            ChoiceChip(
              label: Text(p.label, style: const TextStyle(fontSize: 12)),
              selected: _period == p,
              onSelected: (_) => _update(() => _period = p),
            ),
          if (_period == _Period.m1)
            Container(
              decoration: BoxDecoration(
                color: colors.surfaceCard,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: colors.borderGlass, width: 0.8),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.chevron_left, size: 18),
                    padding: const EdgeInsets.all(4),
                    constraints:
                        const BoxConstraints(minWidth: 32, minHeight: 32),
                    tooltip: 'Mês anterior',
                    onPressed: () => _update(() {
                      _selectedMonth =
                          AnalyticsEngine.addMonths(_refYM, -1);
                    }),
                  ),
                  InkWell(
                    onTap: () => _update(() {
                      _selectedMonth = widget.store.month;
                    }),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Text(
                        fmtMonth(_refYM),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: colors.textPrimary,
                        ),
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.chevron_right, size: 18),
                    padding: const EdgeInsets.all(4),
                    constraints:
                        const BoxConstraints(minWidth: 32, minHeight: 32),
                    tooltip: 'Próximo mês',
                    onPressed: () => _update(() {
                      _selectedMonth = AnalyticsEngine.addMonths(_refYM, 1);
                    }),
                  ),
                ],
              ),
            ),
          AccountMultiSelectFilter(
            store: widget.store,
            selectedAccountIds: _accountIds,
            asFormField: true,
            width: 200,
            onSelectionChanged: (set) => _update(() => _accountIds = set),
          ),
          Container(
            height: 38,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: colors.surfaceCard,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: colors.borderGlass, width: 0.8),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<CashFlowStatusFilter>(
                value: _statusFilter,
                icon: Icon(Icons.arrow_drop_down,
                    size: 18, color: colors.textSecondary),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: colors.textPrimary,
                ),
                dropdownColor: colors.surfaceCard,
                borderRadius: BorderRadius.circular(8),
                items: CashFlowStatusFilter.values
                    .map((s) => DropdownMenuItem(
                          value: s,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                s == CashFlowStatusFilter.all
                                    ? Icons.filter_alt_outlined
                                    : (s == CashFlowStatusFilter.reconciledOnly
                                        ? Icons.check_circle_outline
                                        : Icons.pending_outlined),
                                size: 14,
                                color: s == CashFlowStatusFilter.reconciledOnly
                                    ? colors.income
                                    : (s == CashFlowStatusFilter.pendingOnly
                                        ? colors.warning
                                        : colors.textMuted),
                              ),
                              const SizedBox(width: 6),
                              Text(s.shortLabel),
                            ],
                          ),
                        ))
                    .toList(),
                onChanged: (v) {
                  if (v != null) _update(() => _statusFilter = v);
                },
              ),
            ),
          ),
          if (_categoryTop != null)
            InputChip(
              label: Text(_categoryTop!, style: const TextStyle(fontSize: 12)),
              onDeleted: () => _update(() => _categoryTop = null),
            ),
          IconButton(
            tooltip: 'Metas (poupança e reserva)',
            icon: Icon(Icons.flag_outlined, color: colors.textSecondary),
            onPressed: _editGoals,
          ),
        ],
      ),
    );
  }

  Future<void> _editGoals() async {
    double sg = _savingsGoal * 100;
    double rm = _reserveMonths;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setS) => AlertDialog(
          title: const Text('Metas financeiras'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            Align(
                alignment: Alignment.centerLeft,
                child: Text('Taxa de poupança: ${sg.toStringAsFixed(0)}%')),
            Slider(
                value: sg,
                min: 0,
                max: 60,
                divisions: 60,
                onChanged: (v) => setS(() => sg = v)),
            Align(
                alignment: Alignment.centerLeft,
                child: Text('Reserva: ${rm.toStringAsFixed(0)} meses')),
            Slider(
                value: rm.clamp(1, 60),
                min: 1,
                max: 60,
                divisions: 59,
                onChanged: (v) => setS(() => rm = v)),
          ]),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancelar')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Salvar')),
          ],
        ),
      ),
    );
    if (ok == true) {
      _update(() {
        _savingsGoal = sg / 100;
        _reserveMonths = rm;
      });
    }
  }
}
