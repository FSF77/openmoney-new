import 'package:flutter/material.dart';
import '../../models/investment_models.dart';
import '../../models/openmoney_models.dart';
import '../../services/analytics_engine.dart';
import '../../services/cash_flow_engine.dart';
import '../../services/investment_engine.dart';
import '../../services/investment_insights_engine.dart';
import '../../store/money_store.dart';
import '../modals/account_multi_select_filter.dart';
import '../theme/liquid_glass.dart';
import 'charts/chart_widgets.dart';
import 'charts/investment_chart_widgets.dart';

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

enum _ChartViewMode {
  all('Tudo'),
  finance('Finanças'),
  investments('Investimentos');

  final String label;
  const _ChartViewMode(this.label);
}

class _ChartsDashboardViewState extends State<ChartsDashboardView> {
  _Period _period = _Period.m6;
  _ChartViewMode _viewMode = _ChartViewMode.all;
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

      final singleAcc = _accountIds.length == 1 ? _accountIds.first : null;
      final invSummary = widget.store.portfolioSummary(
        accountId: singleAcc,
        targetCurrency: cur,
      );
      final invCash = widget.store.investmentCashBalance(accountId: singleAcc);
      final invReport = InvestmentInsightsEngine.analyze(
        summary: invSummary,
        cashBalanceCents: invCash,
        baseCurrency: cur,
      );
      final divMonths = _buildDividendsSeries(f.fromYM, f.toYM);
      final divTotal = divMonths.fold<int>(
        0,
        (acc, m) => acc + m.dividendCents + m.jcpCents + m.fiiYieldCents,
      );
      final hasInvestments =
          invSummary.positions.any((p) => p.hasOpenPosition) ||
              invCash > 0 ||
              divTotal > 0;

      final showFinance = _viewMode != _ChartViewMode.investments;
      final showInvestments = _viewMode == _ChartViewMode.investments ||
          (_viewMode == _ChartViewMode.all && hasInvestments);

      final financeTiles = !showFinance
          ? const <Widget>[]
          : <Widget>[
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
          child: Builder(builder: (context) {
            final avgExp = _avgMonthlyExpenseCents(s);
            final liqCents = _immediateLiquidityCents();
            final liqMonths = avgExp > 0 ? liqCents / avgExp : 0.0;
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                GaugeChart(
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
                const SizedBox(height: 8),
                Container(
                  width: double.infinity,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                  decoration: BoxDecoration(
                    color: colors.surfaceCard,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: colors.borderGlass, width: 0.7),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.bolt_rounded, size: 15, color: colors.accent),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          avgExp > 0
                              ? 'Liquidez imediata: ${liqMonths.toStringAsFixed(1)} meses (${formatCurrency(liqCents, cur)})'
                              : 'Liquidez imediata: ${formatCurrency(liqCents, cur)}',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: colors.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          }),
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
      ];

      final investmentTiles = !showInvestments
          ? const <Widget>[]
          : _buildInvestmentTiles(
              tile: tile,
              colors: colors,
              cur: cur,
              snapshot: s,
              summary: invSummary,
              invCash: invCash,
              report: invReport,
              divMonths: divMonths,
              divTotal: divTotal,
            );

      final showInvInsights = _viewMode != _ChartViewMode.finance &&
          (hasInvestments || _viewMode == _ChartViewMode.investments);
      final showFinInsights = _viewMode != _ChartViewMode.investments;
      final finInsights = showFinInsights ? s.insights : const <String>[];
      final invInsights = showInvInsights
          ? invReport.insights
          : const <InvestmentInsight>[];

      final children = <Widget>[
        ...financeTiles,
        ...investmentTiles,
        tile(
          ChartCard(
            title: 'Insights automáticos',
            colors: colors,
            child: (finInsights.isEmpty && invInsights.isEmpty)
                ? Text('Tudo em ordem — sem alertas para o período.',
                    style: TextStyle(color: colors.textMuted, fontSize: 12))
                : Wrap(spacing: 8, runSpacing: 8, children: [
                    for (final i in finInsights)
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
                    for (final ins in invInsights)
                      _buildInvInsightPill(ins, colors),
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

  Widget _buildInvInsightPill(InvestmentInsight ins, OpenMoneyColors colors) {
    final Color c;
    final IconData icon;
    switch (ins.severity) {
      case InvestmentInsightSeverity.critical:
        c = colors.expense;
        icon = Icons.error_outline_rounded;
        break;
      case InvestmentInsightSeverity.warning:
        c = colors.warning;
        icon = Icons.warning_amber_rounded;
        break;
      case InvestmentInsightSeverity.positive:
        c = colors.income;
        icon = Icons.trending_up_rounded;
        break;
      case InvestmentInsightSeverity.info:
        c = colors.accent;
        icon = Icons.insights_rounded;
        break;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: c.withValues(alpha: 0.25), width: 0.7),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: c),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              '${ins.title}: ${ins.detail}',
              style: TextStyle(fontSize: 12, color: colors.textPrimary),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildInvestmentTiles({
    required Widget Function(Widget child, {int span}) tile,
    required OpenMoneyColors colors,
    required String cur,
    required AnalyticsSnapshot snapshot,
    required PortfolioSummary summary,
    required int invCash,
    required InvestmentInsightsReport report,
    required List<DividendMonthPoint> divMonths,
    required int divTotal,
  }) {
    final openPositions =
        summary.positions.where((p) => p.hasOpenPosition).toList();
    final pnlPos = summary.totalUnrealizedPnlCents >= 0;
    final totalPatrimony = summary.totalMarketValueGrossCents + invCash;
    final avgExp = _avgMonthlyExpenseCents(snapshot);
    final byBroker = _buildByBroker(openPositions, cur);
    final costVsMarket = _buildCostVsMarket(openPositions, cur);
    final maturityBuckets = _buildMaturityLadder(openPositions, cur);

    return [
      tile(KpiCard(
        label: 'Carteira investida',
        value: formatCurrency(totalPatrimony, cur),
        icon: Icons.candlestick_chart_outlined,
        color: colors.accent,
        colors: colors,
        hint:
            'Ativos ${formatCurrency(summary.totalMarketValueGrossCents, cur)} · Caixa ${formatCurrency(invCash, cur)}',
      )),
      tile(KpiCard(
        label: 'Rentabilidade acumulada',
        value: formatCurrency(summary.totalUnrealizedPnlCents, cur),
        icon: pnlPos ? Icons.trending_up_rounded : Icons.trending_down_rounded,
        color: pnlPos ? colors.income : colors.expense,
        colors: colors,
        deltaPct: summary.totalCostBasisCents > 0
            ? summary.totalUnrealizedPnlPct
            : null,
        hint: 'Aplicado ${formatCurrency(summary.totalCostBasisCents, cur)}',
      )),
      tile(KpiCard(
        label: 'Proventos no período',
        value: formatCurrency(divTotal, cur),
        icon: Icons.payments_outlined,
        color: colors.income,
        colors: colors,
        hint:
            'Total histórico ${formatCurrency(summary.totalDividendsCents, cur)}',
      )),
      tile(
        ChartCard(
          title: 'Alocação da carteira',
          subtitle:
              'Diversificação: ${report.diversificationScore}/100 (${report.scoreLabel})',
          colors: colors,
          child: InvestmentAllocationChart(
            summary: summary,
            byBroker: byBroker,
            byIndexer: report.fixedIncomeByIndexer,
            currency: cur,
            colors: colors,
          ),
        ),
      ),
      tile(
        ChartCard(
          title: 'Proventos mensais',
          subtitle: 'Dividendos, JCP e rendimentos de FIIs',
          colors: colors,
          child: InvestmentDividendsBarChart(
            months: divMonths,
            currency: cur,
            avgMonthlyExpenseCents: avgExp,
            colors: colors,
          ),
        ),
        span: 2,
      ),
      tile(
        ChartCard(
          title: 'Aplicado × Valor atual por classe',
          subtitle: 'Ganho/perda não realizada por categoria',
          colors: colors,
          child: InvestmentCostVsMarketChart(
            rows: costVsMarket,
            currency: cur,
            colors: colors,
          ),
        ),
      ),
      tile(
        ChartCard(
          title: 'Escada de vencimentos (RF & Tesouro)',
          subtitle: 'Valor bruto projetado por ano de vencimento',
          colors: colors,
          child: InvestmentMaturityLadderChart(
            buckets: maturityBuckets,
            currency: cur,
            colors: colors,
          ),
        ),
        span: 2,
      ),
    ];
  }

  int _avgMonthlyExpenseCents(AnalyticsSnapshot s) {
    if (s.monthly.isEmpty) return 0;
    final sum = s.monthly.fold<int>(0, (acc, m) => acc + m.expense);
    return (sum / s.monthly.length).round();
  }

  int _immediateLiquidityCents() {
    int total = 0;
    for (final a in widget.store.db.accounts) {
      if (a.inactive == true) continue;
      if (_accountIds.isNotEmpty && !_accountIds.contains(a.id)) continue;
      if (a.type == 'Corrente' ||
          a.type == 'Dinheiro' ||
          isSavingsOrReserveAccountType(a.type)) {
        total += widget.store.convertToBase(
          widget.store.balance(a, predicted: false),
          a.currency ?? widget.store.db.baseCurrency,
        );
      } else if (a.type == 'Investimento') {
        total += widget.store.investmentCashBalance(accountId: a.id);
      }
    }
    return total;
  }

  List<DividendMonthPoint> _buildDividendsSeries(String fromYM, String toYM) {
    final months = <String>[];
    String cur = fromYM;
    int guard = 0;
    while (cur.compareTo(toYM) <= 0 && guard < 120) {
      months.add(cur);
      cur = AnalyticsEngine.addMonths(cur, 1);
      guard++;
    }
    final byYm = <String, ({int d, int j, int f})>{
      for (final ym in months) ym: (d: 0, j: 0, f: 0),
    };
    final assetsById = {
      for (final a in widget.store.db.investAssets) a.id: a,
    };
    for (final op in widget.store.db.investOps) {
      if (op.type != InvestOpType.dividend &&
          op.type != InvestOpType.jcp &&
          op.type != InvestOpType.fiiYield) {
        continue;
      }
      if (op.date.length < 7) continue;
      final ym = op.date.substring(0, 7);
      if (!byYm.containsKey(ym)) continue;
      if (_accountIds.isNotEmpty && !_accountIds.contains(op.accountId)) {
        continue;
      }
      final asset = assetsById[op.assetId];
      final cents = widget.store.convertToBase(
        op.totalCents,
        asset?.currency ?? widget.store.db.baseCurrency,
      );
      final prev = byYm[ym]!;
      byYm[ym] = (
        d: prev.d + (op.type == InvestOpType.dividend ? cents : 0),
        j: prev.j + (op.type == InvestOpType.jcp ? cents : 0),
        f: prev.f + (op.type == InvestOpType.fiiYield ? cents : 0),
      );
    }
    return [
      for (final ym in months)
        (
          ym: ym,
          dividendCents: byYm[ym]!.d,
          jcpCents: byYm[ym]!.j,
          fiiYieldCents: byYm[ym]!.f,
        ),
    ];
  }

  Map<String, int> _buildByBroker(
    List<AssetPositionSummary> openPositions,
    String targetCur,
  ) {
    final accNames = {
      for (final a in widget.store.db.accounts) a.id: a.name,
    };
    final out = <String, int>{};
    for (final p in openPositions) {
      final name = accNames[p.asset.accountId] ?? 'Corretora';
      final val = widget.store.convertToBase(
        p.currentGrossValueCents,
        p.asset.currency,
      );
      out[name] = (out[name] ?? 0) + val;
    }
    return out;
  }

  List<CostVsMarketRow> _buildCostVsMarket(
    List<AssetPositionSummary> openPositions,
    String targetCur,
  ) {
    final costMap = <InvestAssetClass, int>{};
    final mktMap = <InvestAssetClass, int>{};
    for (final p in openPositions) {
      final cls = p.asset.assetClass;
      costMap[cls] = (costMap[cls] ?? 0) +
          widget.store.convertToBase(p.currentCostBasisCents, p.asset.currency);
      mktMap[cls] = (mktMap[cls] ?? 0) +
          widget.store.convertToBase(
              p.currentGrossValueCents, p.asset.currency);
    }
    return [
      for (final cls in costMap.keys)
        (
          assetClass: cls,
          costCents: costMap[cls] ?? 0,
          marketCents: mktMap[cls] ?? 0,
        ),
    ];
  }

  List<MaturityBucket> _buildMaturityLadder(
    List<AssetPositionSummary> openPositions,
    String targetCur,
  ) {
    final sums = <String, int>{};
    final counts = <String, int>{};
    for (final p in openPositions) {
      if (!p.asset.isFixedIncome) continue;
      final md = p.asset.maturityDate?.trim() ?? '';
      final key = md.length >= 4 ? md.substring(0, 4) : 'Sem venc.';
      final gross = widget.store.convertToBase(
        p.currentGrossValueCents,
        p.asset.currency,
      );
      sums[key] = (sums[key] ?? 0) + gross;
      counts[key] = (counts[key] ?? 0) + 1;
    }
    final keys = sums.keys.toList()
      ..sort((a, b) {
        if (a == 'Sem venc.') return 1;
        if (b == 'Sem venc.') return -1;
        return a.compareTo(b);
      });
    return [
      for (final k in keys)
        (yearLabel: k, grossCents: sums[k]!, count: counts[k]!),
    ];
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
          Container(
            padding: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              color: colors.surfaceCard,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: colors.borderGlass, width: 0.8),
            ),
            child: Wrap(
              spacing: 4,
              children: [
                for (final vm in _ChartViewMode.values)
                  ChoiceChip(
                    label: Text(vm.label, style: const TextStyle(fontSize: 12)),
                    selected: _viewMode == vm,
                    visualDensity: VisualDensity.compact,
                    onSelected: (_) => setState(() => _viewMode = vm),
                  ),
              ],
            ),
          ),
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
