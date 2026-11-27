import 'dart:math' as math;
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../../../models/investment_models.dart';
import '../../../models/openmoney_models.dart';
import '../../../services/investment_engine.dart';
import '../../theme/liquid_glass.dart';
import 'chart_widgets.dart';

String _invCompact(int cents) {
  final v = cents / 100;
  final a = v.abs();
  if (a >= 1e6) return '${(v / 1e6).toStringAsFixed(1)}M';
  if (a >= 1e3) return '${(v / 1e3).toStringAsFixed(a >= 1e4 ? 0 : 1)}k';
  return v.toStringAsFixed(0);
}

String _invMonthShort(String ym) {
  const m = [
    'jan',
    'fev',
    'mar',
    'abr',
    'mai',
    'jun',
    'jul',
    'ago',
    'set',
    'out',
    'nov',
    'dez'
  ];
  final idx = int.tryParse(ym.substring(5, 7)) ?? 1;
  return m[(idx - 1).clamp(0, 11)];
}

typedef DividendMonthPoint = ({
  String ym,
  int dividendCents,
  int jcpCents,
  int fiiYieldCents,
});

/// Gráfico de barras empilhadas de proventos mensais (Dividendos, JCP e FIIs).
class InvestmentDividendsBarChart extends StatelessWidget {
  final List<DividendMonthPoint> months;
  final String currency;
  final int avgMonthlyExpenseCents;
  final OpenMoneyColors colors;

  const InvestmentDividendsBarChart({
    super.key,
    required this.months,
    required this.currency,
    required this.avgMonthlyExpenseCents,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    final total = months.fold<int>(
      0,
      (s, m) => s + m.dividendCents + m.jcpCents + m.fiiYieldCents,
    );
    if (months.isEmpty || total <= 0) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 28),
        child: Center(
          child: Text(
            'Sem proventos registrados no período selecionado.',
            style: TextStyle(color: colors.textMuted, fontSize: 12),
          ),
        ),
      );
    }

    final avgDiv = months.isEmpty ? 0 : (total / months.length).round();
    final expenseCoveragePct = avgMonthlyExpenseCents > 0
        ? (avgDiv / avgMonthlyExpenseCents) * 100.0
        : null;

    double maxY = 100;
    for (final m in months) {
      final sum = (m.dividendCents + m.jcpCents + m.fiiYieldCents) / 100.0;
      if (sum > maxY) maxY = sum;
    }
    maxY *= 1.18;

    const jcpColor = Color(0xFF0EA5E9);
    const fiiColor = Color(0xFF6366F1);
    final divColor = colors.income;
    final step = months.length > 8 ? 2 : 1;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 12,
          runSpacing: 6,
          children: [
            _MiniMetric(
              label: 'Total no período',
              value: formatCurrency(total, currency),
              color: colors.income,
              colors: colors,
            ),
            _MiniMetric(
              label: 'Média mensal',
              value: formatCurrency(avgDiv, currency),
              color: colors.accent,
              colors: colors,
            ),
            if (expenseCoveragePct != null)
              _MiniMetric(
                label: 'Cobertura das despesas',
                value: '${expenseCoveragePct.toStringAsFixed(1)}%',
                color: expenseCoveragePct >= 100
                    ? colors.income
                    : (expenseCoveragePct >= 25
                        ? colors.warning
                        : colors.textSecondary),
                colors: colors,
              ),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 185,
          child: BarChart(
            BarChartData(
              maxY: maxY,
              minY: 0,
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                getDrawingHorizontalLine: (_) => FlLine(
                  color: colors.borderGlass.withValues(alpha: 0.4),
                  strokeWidth: 0.7,
                ),
              ),
              borderData: FlBorderData(show: false),
              titlesData: FlTitlesData(
                topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false)),
                rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false)),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 44,
                    getTitlesWidget: (v, _) => Text(
                      _invCompact((v * 100).round()),
                      style: TextStyle(fontSize: 10, color: colors.textMuted),
                    ),
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 22,
                    getTitlesWidget: (v, _) {
                      final idx = v.round();
                      if (idx < 0 || idx >= months.length || idx % step != 0) {
                        return const SizedBox.shrink();
                      }
                      return Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          _invMonthShort(months[idx].ym),
                          style:
                              TextStyle(fontSize: 10, color: colors.textMuted),
                        ),
                      );
                    },
                  ),
                ),
              ),
              barTouchData: BarTouchData(
                touchTooltipData: BarTouchTooltipData(
                  getTooltipColor: (_) => colors.surfaceCard,
                  getTooltipItem: (group, groupIndex, rod, rodIndex) {
                    final m = months[group.x];
                    final sum =
                        m.dividendCents + m.jcpCents + m.fiiYieldCents;
                    return BarTooltipItem(
                      '${fmtMonth(m.ym)}\n'
                      'Total: ${formatCurrency(sum, currency)}\n'
                      'Div: ${formatCurrency(m.dividendCents, currency)} · '
                      'JCP: ${formatCurrency(m.jcpCents, currency)} · '
                      'FII: ${formatCurrency(m.fiiYieldCents, currency)}',
                      TextStyle(
                        color: colors.textPrimary,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    );
                  },
                ),
              ),
              barGroups: [
                for (int i = 0; i < months.length; i++)
                  _buildDividendRod(i, months[i], divColor, jcpColor, fiiColor),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 14,
          runSpacing: 4,
          children: [
            _LegendDot(color: divColor, label: 'Dividendos', colors: colors),
            _LegendDot(color: jcpColor, label: 'JCP', colors: colors),
            _LegendDot(
                color: fiiColor, label: 'Rendimentos FII', colors: colors),
          ],
        ),
      ],
    );
  }

  BarChartGroupData _buildDividendRod(
    int index,
    DividendMonthPoint m,
    Color divColor,
    Color jcpColor,
    Color fiiColor,
  ) {
    final d = m.dividendCents / 100.0;
    final j = m.jcpCents / 100.0;
    final f = m.fiiYieldCents / 100.0;
    final total = d + j + f;
    return BarChartGroupData(
      x: index,
      barRods: [
        BarChartRodData(
          toY: total,
          width: months.length > 10 ? 12 : 18,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(4)),
          rodStackItems: [
            if (d > 0) BarChartRodStackItem(0, d, divColor),
            if (j > 0) BarChartRodStackItem(d, d + j, jcpColor),
            if (f > 0) BarChartRodStackItem(d + j, total, fiiColor),
          ],
        ),
      ],
    );
  }
}

enum _AllocMode {
  byClass('Por Classe'),
  byBroker('Por Corretora'),
  byIndexer('Indexador RF');

  final String label;
  const _AllocMode(this.label);
}

/// Donut interativo de alocação da carteira por classe, corretora ou indexador RF.
class InvestmentAllocationChart extends StatefulWidget {
  final PortfolioSummary summary;
  final Map<String, int> byBroker;
  final Map<String, int> byIndexer;
  final String currency;
  final OpenMoneyColors colors;

  const InvestmentAllocationChart({
    super.key,
    required this.summary,
    required this.byBroker,
    required this.byIndexer,
    required this.currency,
    required this.colors,
  });

  @override
  State<InvestmentAllocationChart> createState() =>
      _InvestmentAllocationChartState();
}

class _InvestmentAllocationChartState extends State<InvestmentAllocationChart> {
  _AllocMode _mode = _AllocMode.byClass;
  int _touchedIndex = -1;

  List<MapEntry<String, int>> _entriesForMode() {
    Map<String, int> raw;
    switch (_mode) {
      case _AllocMode.byClass:
        raw = {
          for (final e in widget.summary.byClass.entries)
            if (e.value > 0) e.key.label: e.value,
        };
        break;
      case _AllocMode.byBroker:
        raw = {
          for (final e in widget.byBroker.entries)
            if (e.value > 0) e.key: e.value,
        };
        break;
      case _AllocMode.byIndexer:
        raw = {
          for (final e in widget.byIndexer.entries)
            if (e.value > 0) e.key: e.value,
        };
        break;
    }
    final list = raw.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return list;
  }

  @override
  Widget build(BuildContext context) {
    final colors = widget.colors;
    final entries = _entriesForMode();
    final total = entries.fold<int>(0, (s, e) => s + e.value);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final m in _AllocMode.values)
              ChoiceChip(
                label: Text(m.label, style: const TextStyle(fontSize: 11)),
                selected: _mode == m,
                visualDensity: VisualDensity.compact,
                onSelected: (_) => setState(() {
                  _mode = m;
                  _touchedIndex = -1;
                }),
              ),
          ],
        ),
        const SizedBox(height: 12),
        if (entries.isEmpty || total <= 0)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 28),
            child: Center(
              child: Text(
                _mode == _AllocMode.byIndexer
                    ? 'Sem posições abertas em Renda Fixa / Tesouro.'
                    : 'Sem posições abertas na carteira.',
                style: TextStyle(color: colors.textMuted, fontSize: 12),
              ),
            ),
          )
        else
          LayoutBuilder(builder: (context, constraints) {
            final sideBySide = constraints.maxWidth >= 340;
            final chart = SizedBox(
              height: 168,
              width: sideBySide ? 168 : double.infinity,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  PieChart(
                    PieChartData(
                      centerSpaceRadius: 42,
                      sectionsSpace: 2,
                      pieTouchData: PieTouchData(
                        touchCallback: (event, resp) {
                          if (!event.isInterestedForInteractions ||
                              resp == null ||
                              resp.touchedSection == null) {
                            if (_touchedIndex != -1) {
                              setState(() => _touchedIndex = -1);
                            }
                            return;
                          }
                          final idx = resp.touchedSection!.touchedSectionIndex;
                          if (idx != _touchedIndex) {
                            setState(() => _touchedIndex = idx);
                          }
                        },
                      ),
                      sections: [
                        for (int i = 0; i < entries.length; i++)
                          PieChartSectionData(
                            value: entries[i].value.toDouble(),
                            color: kChartPalette[i % kChartPalette.length],
                            radius: _touchedIndex == i ? 32 : 26,
                            showTitle: false,
                          ),
                      ],
                    ),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        _touchedIndex >= 0 && _touchedIndex < entries.length
                            ? entries[_touchedIndex].key
                            : 'Total',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 10, color: colors.textMuted),
                      ),
                      Text(
                        _invCompact(
                          _touchedIndex >= 0 && _touchedIndex < entries.length
                              ? entries[_touchedIndex].value
                              : total,
                        ),
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w800,
                          color: colors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );

            final legend = Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (int i = 0; i < entries.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Row(
                      children: [
                        Container(
                          width: 9,
                          height: 9,
                          decoration: BoxDecoration(
                            color: kChartPalette[i % kChartPalette.length],
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            entries[i].key,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              color: colors.textPrimary,
                              fontWeight: _touchedIndex == i
                                  ? FontWeight.w700
                                  : FontWeight.w500,
                            ),
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '${((entries[i].value / total) * 100).toStringAsFixed(1)}%',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: colors.textSecondary,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          formatCurrency(entries[i].value, widget.currency),
                          style: TextStyle(
                            fontSize: 11,
                            color: colors.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            );

            if (sideBySide) {
              return Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  chart,
                  const SizedBox(width: 12),
                  Expanded(child: legend),
                ],
              );
            }
            return Column(
              children: [
                chart,
                const SizedBox(height: 10),
                legend,
              ],
            );
          }),
      ],
    );
  }
}

typedef CostVsMarketRow = ({
  InvestAssetClass assetClass,
  int costCents,
  int marketCents,
});

/// Comparativo horizontal Aplicado vs. Valor Atual por classe de ativo.
class InvestmentCostVsMarketChart extends StatelessWidget {
  final List<CostVsMarketRow> rows;
  final String currency;
  final OpenMoneyColors colors;

  const InvestmentCostVsMarketChart({
    super.key,
    required this.rows,
    required this.currency,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    final activeRows =
        rows.where((r) => r.costCents > 0 || r.marketCents > 0).toList()
          ..sort((a, b) => b.marketCents.compareTo(a.marketCents));

    if (activeRows.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 28),
        child: Center(
          child: Text(
            'Nenhuma posição aberta para comparar.',
            style: TextStyle(color: colors.textMuted, fontSize: 12),
          ),
        ),
      );
    }

    int maxVal = 1;
    for (final r in activeRows) {
      maxVal = math.max(maxVal, math.max(r.costCents, r.marketCents));
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 14,
          runSpacing: 4,
          children: [
            _LegendDot(
                color: colors.textMuted, label: 'Aplicado', colors: colors),
            _LegendDot(
                color: colors.income, label: 'Valor Atual', colors: colors),
          ],
        ),
        const SizedBox(height: 12),
        for (final r in activeRows) ...[
          _buildRow(r, maxVal),
          const SizedBox(height: 10),
        ],
      ],
    );
  }

  Widget _buildRow(CostVsMarketRow r, int maxVal) {
    final pnl = r.marketCents - r.costCents;
    final pct = r.costCents > 0 ? (pnl / r.costCents) * 100.0 : 0.0;
    final isPos = pnl >= 0;
    final marketColor = isPos ? colors.income : colors.expense;
    final costRatio = (r.costCents / maxVal).clamp(0.0, 1.0);
    final mktRatio = (r.marketCents / maxVal).clamp(0.0, 1.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                r.assetClass.label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: colors.textPrimary,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: marketColor.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                '${isPos ? '+' : ''}${pct.toStringAsFixed(1)}%',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: marketColor,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        _BarLine(
          label: 'Aplicado',
          valueText: formatCurrency(r.costCents, currency),
          ratio: costRatio,
          barColor: colors.textMuted.withValues(alpha: 0.55),
          colors: colors,
        ),
        const SizedBox(height: 3),
        _BarLine(
          label: 'Atual',
          valueText: formatCurrency(r.marketCents, currency),
          ratio: mktRatio,
          barColor: marketColor,
          colors: colors,
        ),
      ],
    );
  }
}

class _BarLine extends StatelessWidget {
  final String label;
  final String valueText;
  final double ratio;
  final Color barColor;
  final OpenMoneyColors colors;

  const _BarLine({
    required this.label,
    required this.valueText,
    required this.ratio,
    required this.barColor,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 52,
          child: Text(
            label,
            style: TextStyle(fontSize: 10, color: colors.textMuted),
          ),
        ),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: ratio,
              minHeight: 7,
              backgroundColor: colors.borderGlass.withValues(alpha: 0.25),
              valueColor: AlwaysStoppedAnimation(barColor),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          valueText,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w600,
            color: colors.textSecondary,
          ),
        ),
      ],
    );
  }
}

typedef MaturityBucket = ({
  String yearLabel,
  int grossCents,
  int count,
});

/// Escada de vencimentos de Renda Fixa e Tesouro Direto por ano.
class InvestmentMaturityLadderChart extends StatelessWidget {
  final List<MaturityBucket> buckets;
  final String currency;
  final OpenMoneyColors colors;

  const InvestmentMaturityLadderChart({
    super.key,
    required this.buckets,
    required this.currency,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    if (buckets.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 28),
        child: Center(
          child: Text(
            'Nenhum título de Renda Fixa ou Tesouro com posição aberta.',
            style: TextStyle(color: colors.textMuted, fontSize: 12),
          ),
        ),
      );
    }

    double maxY = 100;
    for (final b in buckets) {
      final v = b.grossCents / 100.0;
      if (v > maxY) maxY = v;
    }
    maxY *= 1.18;

    return SizedBox(
      height: 190,
      child: BarChart(
        BarChartData(
          maxY: maxY,
          minY: 0,
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            getDrawingHorizontalLine: (_) => FlLine(
              color: colors.borderGlass.withValues(alpha: 0.4),
              strokeWidth: 0.7,
            ),
          ),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            topTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles:
                const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 44,
                getTitlesWidget: (v, _) => Text(
                  _invCompact((v * 100).round()),
                  style: TextStyle(fontSize: 10, color: colors.textMuted),
                ),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 22,
                getTitlesWidget: (v, _) {
                  final idx = v.round();
                  if (idx < 0 || idx >= buckets.length) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      buckets[idx].yearLabel,
                      style: TextStyle(fontSize: 10, color: colors.textMuted),
                    ),
                  );
                },
              ),
            ),
          ),
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              getTooltipColor: (_) => colors.surfaceCard,
              getTooltipItem: (group, groupIndex, rod, rodIndex) {
                final b = buckets[group.x];
                final suf = b.count == 1 ? 'título' : 'títulos';
                return BarTooltipItem(
                  '${b.yearLabel}\n'
                  '${formatCurrency(b.grossCents, currency)}\n'
                  '${b.count} $suf',
                  TextStyle(
                    color: colors.textPrimary,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                );
              },
            ),
          ),
          barGroups: [
            for (int i = 0; i < buckets.length; i++)
              BarChartGroupData(
                x: i,
                barRods: [
                  BarChartRodData(
                    toY: buckets[i].grossCents / 100.0,
                    width: buckets.length > 8 ? 14 : 22,
                    color: kChartPalette[i % kChartPalette.length],
                    borderRadius:
                        const BorderRadius.vertical(top: Radius.circular(5)),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _MiniMetric extends StatelessWidget {
  final String label;
  final String value;
  final Color color;
  final OpenMoneyColors colors;

  const _MiniMetric({
    required this.label,
    required this.value,
    required this.color,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: colors.surfaceCard,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.borderGlass, width: 0.7),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: TextStyle(fontSize: 10, color: colors.textMuted)),
          Text(
            value,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _LegendDot extends StatelessWidget {
  final Color color;
  final String label;
  final OpenMoneyColors colors;

  const _LegendDot({
    required this.color,
    required this.label,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(label, style: TextStyle(fontSize: 11, color: colors.textSecondary)),
      ],
    );
  }
}
