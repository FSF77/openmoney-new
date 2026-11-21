import 'dart:math' as math;
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import '../../../models/openmoney_models.dart';
import '../../../services/analytics_engine.dart';
import '../../theme/liquid_glass.dart';

String _cur(int cents, String cur) => formatCurrency(cents, cur);

String _compact(int cents) {
  final v = cents / 100;
  final a = v.abs();
  if (a >= 1e6) return '${(v / 1e6).toStringAsFixed(1)}M';
  if (a >= 1e3) return '${(v / 1e3).toStringAsFixed(a >= 1e4 ? 0 : 1)}k';
  return v.toStringAsFixed(0);
}

const List<Color> kChartPalette = [
  Color(0xFF6366F1),
  Color(0xFF0EA5E9),
  Color(0xFF10B981),
  Color(0xFFF59E0B),
  Color(0xFFEF4444),
  Color(0xFFEC4899),
  Color(0xFF8B5CF6),
  Color(0xFF14B8A6),
  Color(0xFF94A3B8),
];

String _mShort(String ym) {
  const m = ['jan', 'fev', 'mar', 'abr', 'mai', 'jun', 'jul', 'ago', 'set', 'out', 'nov', 'dez'];
  final i = int.parse(ym.substring(5, 7));
  return m[i - 1];
}

/// Moldura padrão de cada gráfico.
class ChartCard extends StatelessWidget {
  final String title;
  final String? subtitle;
  final Widget child;
  final Widget? trailing;
  final OpenMoneyColors colors;
  const ChartCard({
    super.key,
    required this.title,
    required this.child,
    required this.colors,
    this.subtitle,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                            color: colors.textPrimary)),
                    if (subtitle != null)
                      Text(subtitle!,
                          style: TextStyle(fontSize: 11, color: colors.textMuted)),
                  ],
                ),
              ),
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

/// Card de KPI com variação percentual opcional.
class KpiCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;
  final double? deltaPct; // null = sem comparação
  final bool higherIsBetter;
  final String? hint;
  final OpenMoneyColors colors;
  final List<double>? spark;

  const KpiCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
    required this.colors,
    this.deltaPct,
    this.higherIsBetter = true,
    this.hint,
    this.spark,
  });

  @override
  Widget build(BuildContext context) {
    Widget? delta;
    if (deltaPct != null && deltaPct!.isFinite) {
      final up = deltaPct! >= 0;
      final good = up == higherIsBetter;
      final c = good ? colors.income : colors.expense;
      delta = Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(up ? Icons.arrow_upward : Icons.arrow_downward, size: 12, color: c),
        Text('${deltaPct!.abs().toStringAsFixed(1)}%',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: c)),
      ]);
    }
    return GlassCard(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8)),
              child: Icon(icon, size: 16, color: color),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: colors.textSecondary)),
            ),
            if (delta != null) delta,
          ]),
          const SizedBox(height: 10),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value,
                style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    color: colors.textPrimary,
                    fontFeatures: const [FontFeature.tabularFigures()])),
          ),
          if (hint != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(hint!,
                  style: TextStyle(fontSize: 10.5, color: colors.textMuted)),
            ),
          if (spark != null && spark!.length > 1)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: SizedBox(
                height: 28,
                child: LineChart(LineChartData(
                  gridData: const FlGridData(show: false),
                  titlesData: const FlTitlesData(show: false),
                  borderData: FlBorderData(show: false),
                  lineTouchData: const LineTouchData(enabled: false),
                  lineBarsData: [
                    LineChartBarData(
                      spots: [
                        for (int i = 0; i < spark!.length; i++)
                          FlSpot(i.toDouble(), spark![i])
                      ],
                      isCurved: true,
                      color: color,
                      barWidth: 2,
                      dotData: const FlDotData(show: false),
                      belowBarData: BarAreaData(
                          show: true, color: color.withValues(alpha: 0.12)),
                    ),
                  ],
                )),
              ),
            ),
        ],
      ),
    );
  }
}

/// Gauge semicircular (0..1) com valor central.
class GaugeChart extends StatelessWidget {
  final double ratio; // 0..1
  final String centerText;
  final String caption;
  final Color color;
  final OpenMoneyColors colors;
  final double height;
  const GaugeChart({
    super.key,
    required this.ratio,
    required this.centerText,
    required this.caption,
    required this.color,
    required this.colors,
    this.height = 120,
  });

  @override
  Widget build(BuildContext context) {
    final r = ratio.clamp(0.0, 1.0);
    return SizedBox(
      height: height,
      child: Stack(alignment: Alignment.bottomCenter, children: [
        CustomPaint(
          size: Size.infinite,
          painter: _GaugePainter(r, color, colors.borderGlass),
        ),
        Column(mainAxisSize: MainAxisSize.min, children: [
          Text(centerText,
              style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  color: colors.textPrimary)),
          Text(caption, style: TextStyle(fontSize: 11, color: colors.textMuted)),
        ]),
      ]),
    );
  }
}

class _GaugePainter extends CustomPainter {
  final double r;
  final Color color;
  final Color track;
  _GaugePainter(this.r, this.color, this.track);

  @override
  void paint(Canvas canvas, Size size) {
    final radius = math.min(size.width / 2, size.height) - 8;
    final center = Offset(size.width / 2, size.height - 4);
    final rect = Rect.fromCircle(center: center, radius: radius);
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 12
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, math.pi, math.pi, false, p..color = track);
    canvas.drawArc(rect, math.pi, math.pi * r, false, p..color = color);
  }

  @override
  bool shouldRepaint(covariant _GaugePainter o) =>
      o.r != r || o.color != color || o.track != track;
}

/// Barras agrupadas receita × despesa + linha de resultado.
class CashflowBarChart extends StatelessWidget {
  final List<MonthPoint> data;
  final String currency;
  final OpenMoneyColors colors;
  final void Function(String ym)? onMonthTap;
  const CashflowBarChart({
    super.key,
    required this.data,
    required this.currency,
    required this.colors,
    this.onMonthTap,
  });

  @override
  Widget build(BuildContext context) {
    if (data.isEmpty) return const SizedBox(height: 220);
    final maxV = data
        .map((e) => math.max(e.income, e.expense))
        .fold<int>(1, math.max)
        .toDouble();

    return SizedBox(
      height: 240,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isScrollable = data.length > 14;
          final totalWidth = isScrollable
              ? math.max(constraints.maxWidth, data.length * 36.0)
              : constraints.maxWidth;

          Widget chart = SizedBox(
            width: totalWidth,
            child: BarChart(BarChartData(
              maxY: maxV * 1.15,
              alignment: BarChartAlignment.spaceAround,
              gridData: FlGridData(
                drawVerticalLine: false,
                getDrawingHorizontalLine: (_) =>
                    FlLine(color: colors.borderGlass, strokeWidth: 0.6),
              ),
              borderData: FlBorderData(show: false),
              titlesData: FlTitlesData(
                topTitles: const AxisTitles(),
                rightTitles: const AxisTitles(),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 40,
                    getTitlesWidget: (v, m) => v == m.max
                        ? const SizedBox()
                        : Text(_compact(v.toInt()),
                            style: TextStyle(fontSize: 9.5, color: colors.textMuted)),
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    getTitlesWidget: (v, m) {
                      final i = v.toInt();
                      if (i < 0 || i >= data.length) return const SizedBox();
                      final ym = data[i].ym;
                      final label = isScrollable
                          ? '${_mShort(ym)}\n${ym.substring(2, 4)}'
                          : _mShort(ym);
                      return Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(label,
                            textAlign: TextAlign.center,
                            style: TextStyle(fontSize: 9.5, color: colors.textMuted)),
                      );
                    },
                  ),
                ),
              ),
              barTouchData: BarTouchData(
                touchCallback: (e, r) {
                  if (e is FlTapUpEvent && r?.spot != null && onMonthTap != null) {
                    onMonthTap!(data[r!.spot!.touchedBarGroupIndex].ym);
                  }
                },
                touchTooltipData: BarTouchTooltipData(
                  getTooltipColor: (_) => colors.surfaceCard.withValues(alpha: 0.97),
                  getTooltipItem: (g, gi, rod, ri) {
                    final d = data[gi];
                    return BarTooltipItem(
                      '${fmtMonth(d.ym)}\n',
                      TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 11,
                          color: colors.textPrimary),
                      children: [
                        TextSpan(
                            text: 'Receita ${_cur(d.income, currency)}\n',
                            style: TextStyle(color: colors.income, fontSize: 11)),
                        TextSpan(
                            text: 'Despesa ${_cur(d.expense, currency)}\n',
                            style: TextStyle(color: colors.expense, fontSize: 11)),
                        TextSpan(
                            text: 'Resultado ${_cur(d.net, currency)}',
                            style: TextStyle(color: colors.textSecondary, fontSize: 11)),
                      ],
                    );
                  },
                ),
              ),
              barGroups: [
                for (int i = 0; i < data.length; i++)
                  BarChartGroupData(x: i, barsSpace: 3, barRods: [
                    BarChartRodData(
                        toY: data[i].income.toDouble(),
                        color: colors.income,
                        width: isScrollable ? 8 : (data.length > 8 ? 7 : 12),
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(3))),
                    BarChartRodData(
                        toY: data[i].expense.toDouble(),
                        color: colors.expense,
                        width: isScrollable ? 8 : (data.length > 8 ? 7 : 12),
                        borderRadius: const BorderRadius.vertical(top: Radius.circular(3))),
                  ]),
              ],
            )),
          );

          if (isScrollable) {
            return SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: chart,
            );
          }
          return chart;
        },
      ),
    );
  }
}

/// Donut interativo de despesas por categoria.
class CategoryDonut extends StatefulWidget {
  final List<CategorySlice> slices;
  final String currency;
  final OpenMoneyColors colors;
  final String? selected;
  final void Function(String? top) onSelect;
  const CategoryDonut({
    super.key,
    required this.slices,
    required this.currency,
    required this.colors,
    required this.onSelect,
    this.selected,
  });

  @override
  State<CategoryDonut> createState() => _CategoryDonutState();
}

class _CategoryDonutState extends State<CategoryDonut> {
  int _touched = -1;

  List<CategorySlice> get _display {
    final s = widget.slices;
    if (s.length <= 8) return s;
    final top = s.take(7).toList();
    final rest = s.skip(7).fold<int>(0, (a, b) => a + b.cents);
    return [...top, CategorySlice('Outras', rest, const {})];
  }

  @override
  Widget build(BuildContext context) {
    final colors = widget.colors;
    final data = _display;
    final total = data.fold<int>(0, (a, b) => a + b.cents);
    if (total == 0) {
      return SizedBox(
          height: 200,
          child: Center(
              child: Text('Sem despesas no período',
                  style: TextStyle(color: colors.textMuted))));
    }
    return LayoutBuilder(builder: (context, c) {
      final wide = c.maxWidth > 420;
      final donut = SizedBox(
        height: 200,
        width: wide ? 200 : double.infinity,
        child: PieChart(PieChartData(
          centerSpaceRadius: 56,
          sectionsSpace: 2,
          pieTouchData: PieTouchData(touchCallback: (e, r) {
            final i = r?.touchedSection?.touchedSectionIndex ?? -1;
            if (e is FlTapUpEvent && i >= 0 && i < data.length) {
              final n = data[i].name;
              widget.onSelect(widget.selected == n || n == 'Outras' ? null : n);
            }
            if (_touched != i) setState(() => _touched = i);
          }),
          sections: [
            for (int i = 0; i < data.length; i++)
              PieChartSectionData(
                value: data[i].cents.toDouble(),
                color: kChartPalette[i % kChartPalette.length].withValues(
                    alpha: widget.selected == null || widget.selected == data[i].name
                        ? 1
                        : 0.3),
                radius: _touched == i ? 34 : 28,
                showTitle: false,
              ),
          ],
        )),
      );
      final legend = Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (int i = 0; i < data.length; i++)
            InkWell(
              onTap: () => widget.onSelect(
                  widget.selected == data[i].name || data[i].name == 'Outras'
                      ? null
                      : data[i].name),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Row(children: [
                  Container(
                      width: 9,
                      height: 9,
                      decoration: BoxDecoration(
                          color: kChartPalette[i % kChartPalette.length],
                          shape: BoxShape.circle)),
                  const SizedBox(width: 8),
                  Expanded(
                      child: Text(data[i].name,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 12,
                              fontWeight: widget.selected == data[i].name
                                  ? FontWeight.w800
                                  : FontWeight.w500,
                              color: colors.textPrimary))),
                  Text('${(data[i].cents * 100 / total).toStringAsFixed(0)}%',
                      style: TextStyle(fontSize: 11, color: colors.textMuted)),
                  const SizedBox(width: 8),
                  Text(_cur(data[i].cents, widget.currency),
                      style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: colors.textSecondary)),
                ]),
              ),
            ),
        ],
      );
      final centered = Stack(alignment: Alignment.center, children: [
        donut,
        IgnorePointer(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(
                _touched >= 0 && _touched < data.length
                    ? data[_touched].name
                    : 'Total',
                style: TextStyle(fontSize: 10.5, color: colors.textMuted)),
            Text(
                _compact(_touched >= 0 && _touched < data.length
                    ? data[_touched].cents
                    : total),
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: colors.textPrimary)),
          ]),
        ),
      ]);
      return wide
          ? Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
              SizedBox(width: 200, child: centered),
              const SizedBox(width: 16),
              Expanded(child: legend),
            ])
          : Column(children: [centered, const SizedBox(height: 8), legend]);
    });
  }
}

/// Linha/área: patrimônio mensal (+ projeção opcional).
class TrendLineChart extends StatelessWidget {
  final List<double> values;
  final List<String> labels;
  final List<double>? projection; // continua após values
  final Color color;
  final String currency;
  final OpenMoneyColors colors;
  final double height;
  const TrendLineChart({
    super.key,
    required this.values,
    required this.labels,
    required this.color,
    required this.currency,
    required this.colors,
    this.projection,
    this.height = 220,
  });

  @override
  Widget build(BuildContext context) {
    if (values.length < 2) {
      return SizedBox(
          height: height,
          child: Center(
              child: Text('Dados insuficientes',
                  style: TextStyle(color: colors.textMuted))));
    }
    final proj = projection ?? const <double>[];
    final all = [...values, ...proj];
    final minV = all.reduce(math.min);
    final maxV = all.reduce(math.max);
    final pad = (maxV - minV).abs() * 0.1 + 1;
    final step = math.max(1, (labels.length / 6).ceil());
    return SizedBox(
      height: height,
      child: LineChart(LineChartData(
        minY: minV - pad,
        maxY: maxV + pad,
        gridData: FlGridData(
          drawVerticalLine: false,
          getDrawingHorizontalLine: (_) =>
              FlLine(color: colors.borderGlass, strokeWidth: 0.6),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(),
          rightTitles: const AxisTitles(),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 44,
              getTitlesWidget: (v, m) => (v == m.max || v == m.min)
                  ? const SizedBox()
                  : Text(_compact(v.toInt()),
                      style: TextStyle(fontSize: 9.5, color: colors.textMuted)),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: step.toDouble(),
              getTitlesWidget: (v, m) {
                final i = v.toInt();
                if (i < 0 || i >= labels.length || v != i.toDouble()) {
                  return const SizedBox();
                }
                return Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(labels[i],
                      style: TextStyle(fontSize: 9.5, color: colors.textMuted)),
                );
              },
            ),
          ),
        ),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipColor: (_) => colors.surfaceCard.withValues(alpha: 0.97),
            getTooltipItems: (spots) => [
              for (final s in spots)
                LineTooltipItem(
                  '${s.x.toInt() < labels.length ? labels[s.x.toInt()] : ''}\n${_cur(s.y.toInt(), currency)}',
                  TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      color: colors.textPrimary),
                ),
            ],
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: [
              for (int i = 0; i < values.length; i++) FlSpot(i.toDouble(), values[i])
            ],
            isCurved: true,
            curveSmoothness: 0.2,
            color: color,
            barWidth: 2.5,
            dotData: FlDotData(show: values.length <= 14),
            belowBarData:
                BarAreaData(show: true, color: color.withValues(alpha: 0.12)),
          ),
          if (proj.isNotEmpty)
            LineChartBarData(
              spots: [
                FlSpot((values.length - 1).toDouble(), values.last),
                for (int i = 0; i < proj.length; i++)
                  FlSpot((values.length + i).toDouble(), proj[i]),
              ],
              isCurved: true,
              curveSmoothness: 0.2,
              color: colors.warning,
              barWidth: 2,
              dashArray: [6, 4],
              dotData: const FlDotData(show: false),
            ),
        ],
      )),
    );
  }
}

/// Barras de progresso orçado × realizado.
class BudgetProgressList extends StatelessWidget {
  final List<BudgetProgress> items;
  final String currency;
  final OpenMoneyColors colors;
  const BudgetProgressList({
    super.key,
    required this.items,
    required this.currency,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Center(
            child: Text('Nenhum limite de gastos definido',
                style: TextStyle(color: colors.textMuted))),
      );
    }
    return Column(children: [
      for (final b in items.take(8))
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 5),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                  child: Text(b.category.replaceAll(kCategorySep, ' › '),
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: colors.textPrimary))),
              Text('${_cur(b.spent, currency)} / ${_cur(b.budget, currency)}',
                  style: TextStyle(fontSize: 11, color: colors.textMuted)),
            ]),
            const SizedBox(height: 4),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: b.ratio.clamp(0.0, 1.0),
                minHeight: 7,
                backgroundColor: colors.borderGlass,
                color: b.ratio > 1
                    ? colors.expense
                    : (b.ratio > 0.8 ? colors.warning : colors.income),
              ),
            ),
          ]),
        ),
    ]);
  }
}

/// Ranking horizontal de estabelecimentos.
class PayeeRankList extends StatelessWidget {
  final List<PayeeRank> items;
  final String currency;
  final OpenMoneyColors colors;
  const PayeeRankList({
    super.key,
    required this.items,
    required this.currency,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Center(
            child: Text('Sem dados', style: TextStyle(color: colors.textMuted))),
      );
    }
    final max = items.first.cents.toDouble();
    return Column(children: [
      for (final p in items)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                  child: Text(p.payee,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: colors.textPrimary))),
              Text('${p.count}x  ',
                  style: TextStyle(fontSize: 10.5, color: colors.textMuted)),
              Text(_cur(p.cents, currency),
                  style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: colors.textSecondary)),
            ]),
            const SizedBox(height: 3),
            FractionallySizedBox(
              widthFactor: (p.cents / max).clamp(0.02, 1.0),
              child: Container(
                  height: 5,
                  decoration: BoxDecoration(
                      color: colors.accent.withValues(alpha: 0.8),
                      borderRadius: BorderRadius.circular(3))),
            ),
          ]),
        ),
    ]);
  }
}

/// Mapa de calor de gastos diários do mês.
class SpendHeatmap extends StatelessWidget {
  final String ym;
  final Map<String, int> daily;
  final String currency;
  final OpenMoneyColors colors;
  const SpendHeatmap({
    super.key,
    required this.ym,
    required this.daily,
    required this.currency,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    final y = int.parse(ym.substring(0, 4));
    final m = int.parse(ym.substring(5, 7));
    final days = DateTime(y, m + 1, 0).day;
    final firstWd = DateTime(y, m, 1).weekday % 7; // domingo = 0
    final maxV = daily.values.fold<int>(0, math.max);
    const wd = ['D', 'S', 'T', 'Q', 'Q', 'S', 'S'];
    final cells = <Widget>[];
    for (int i = 0; i < firstWd; i++) {
      cells.add(const SizedBox());
    }
    for (int d = 1; d <= days; d++) {
      final key = '$ym-${d.toString().padLeft(2, '0')}';
      final v = daily[key] ?? 0;
      final t = maxV > 0 ? v / maxV : 0.0;
      cells.add(Tooltip(
        message: '$d/${m.toString().padLeft(2, '0')}: ${_cur(v, currency)}',
        child: Container(
          decoration: BoxDecoration(
            color: v == 0
                ? colors.borderGlass.withValues(alpha: 0.5)
                : Color.lerp(colors.expense.withValues(alpha: 0.25),
                    colors.expense, t),
            borderRadius: BorderRadius.circular(4),
          ),
          alignment: Alignment.center,
          child: Text('$d',
              style: TextStyle(
                  fontSize: 9.5,
                  color: t > 0.55 ? Colors.white : colors.textMuted)),
        ),
      ));
    }
    return Column(children: [
      Row(children: [
        for (final w in wd)
          Expanded(
              child: Center(
                  child: Text(w,
                      style: TextStyle(fontSize: 10, color: colors.textMuted)))),
      ]),
      const SizedBox(height: 4),
      GridView.count(
        crossAxisCount: 7,
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        mainAxisSpacing: 4,
        crossAxisSpacing: 4,
        childAspectRatio: 1.25,
        children: cells,
      ),
    ]);
  }
}
