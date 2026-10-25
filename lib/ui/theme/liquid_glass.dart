import 'dart:ui';
import 'package:flutter/material.dart';

class OpenMoneyColors {
  final bool isDark;
  const OpenMoneyColors(this.isDark);

  Color get bgPrimary =>
      isDark ? const Color(0xFF0A0E17) : const Color(0xFFF3F6FC);
  Color get bgSecondary =>
      isDark ? const Color(0xFF111827) : const Color(0xFFFFFFFF);
  Color get surfaceGlass => isDark
      ? const Color(0xFF1E293B).withValues(alpha: 0.62)
      : const Color(0xFFFFFFFF).withValues(alpha: 0.78);
  Color get surfaceCard => isDark
      ? const Color(0xFF162032).withValues(alpha: 0.85)
      : const Color(0xFFFFFFFF).withValues(alpha: 0.92);
  Color get borderGlass => isDark
      ? const Color(0xFFFFFFFF).withValues(alpha: 0.10)
      : const Color(0xFF0F172A).withValues(alpha: 0.09);
  Color get borderHighlight => isDark
      ? const Color(0xFF38BDF8).withValues(alpha: 0.45)
      : const Color(0xFF0284C7).withValues(alpha: 0.35);

  Color get textPrimary =>
      isDark ? const Color(0xFFF8FAFC) : const Color(0xFF0F172A);
  Color get textSecondary =>
      isDark ? const Color(0xFF94A3B8) : const Color(0xFF475569);
  Color get textMuted =>
      isDark ? const Color(0xFF64748B) : const Color(0xFF94A3B8);

  Color get accent => const Color(0xFF0EA5E9);
  Color get accentIndigo => const Color(0xFF6366F1);
  Color get income =>
      isDark ? const Color(0xFF34D399) : const Color(0xFF059669);
  Color get expense =>
      isDark ? const Color(0xFFFB7185) : const Color(0xFFE11D48);
  Color get warning =>
      isDark ? const Color(0xFFFBBF24) : const Color(0xFFD97706);

  TextStyle get tabularMono => TextStyle(
        fontFeatures: const [FontFeature.tabularFigures()],
        color: textPrimary,
      );
}

class GlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;
  final double borderRadius;
  final Color? borderColor;
  final Color? backgroundColor;
  final VoidCallback? onTap;

  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.margin,
    this.borderRadius = 14,
    this.borderColor,
    this.backgroundColor,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colors = OpenMoneyColors(isDark);

    Widget content = Container(
      margin: margin,
      decoration: BoxDecoration(
        color: backgroundColor ?? colors.surfaceCard,
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(
          color: borderColor ?? colors.borderGlass,
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.28 : 0.05),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
          child: Padding(
            padding: padding,
            child: child,
          ),
        ),
      ),
    );

    if (onTap != null) {
      return InkWell(
        borderRadius: BorderRadius.circular(borderRadius),
        onTap: onTap,
        child: content,
      );
    }
    return content;
  }
}

class StatusBadge extends StatelessWidget {
  final String text;
  final Color color;
  final IconData? icon;

  const StatusBadge({
    super.key,
    required this.text,
    required this.color,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.45), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 4),
          ],
          Text(
            text,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: color,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }
}

class KpiMetricCard extends StatelessWidget {
  final String label;
  final String value;
  final String? subtitle;
  final Color valueColor;
  final IconData icon;

  const KpiMetricCard({
    super.key,
    required this.label,
    required this.value,
    this.subtitle,
    required this.valueColor,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colors = OpenMoneyColors(isDark);

    return GlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: valueColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 16, color: valueColor),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: colors.textSecondary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            value,
            style: TextStyle(
              fontSize: 19,
              fontWeight: FontWeight.w800,
              color: valueColor,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          if (subtitle != null && subtitle!.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              subtitle!,
              style: TextStyle(
                fontSize: 11,
                color: colors.textMuted,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class MonthYearPickerBar extends StatelessWidget {
  final String currentMonthYM;
  final List<int> availableYears;
  final ValueChanged<String> onMonthChanged;

  const MonthYearPickerBar({
    super.key,
    required this.currentMonthYM,
    required this.availableYears,
    required this.onMonthChanged,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colors = OpenMoneyColors(isDark);

    final parts = currentMonthYM.split('-');
    final curYear =
        parts.isNotEmpty ? (int.tryParse(parts[0]) ?? 2026) : 2026;
    final curMonth =
        parts.length > 1 ? (int.tryParse(parts[1]) ?? 1) : 1;

    const shortMonths = [
      'Jan',
      'Fev',
      'Mar',
      'Abr',
      'Mai',
      'Jun',
      'Jul',
      'Ago',
      'Set',
      'Out',
      'Nov',
      'Dez',
    ];

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          tooltip: 'Mês Anterior',
          icon: const Icon(Icons.chevron_left, size: 20),
          onPressed: () {
            final prevYear = curMonth == 1 ? curYear - 1 : curYear;
            final prevMonth = curMonth == 1 ? 12 : curMonth - 1;
            onMonthChanged(
              '${prevYear.toString().padLeft(4, '0')}-${prevMonth.toString().padLeft(2, '0')}',
            );
          },
        ),
        PopupMenuButton<String>(
          tooltip: 'Selecionar Mês / Ano',
          itemBuilder: (ctx) {
            return [
              PopupMenuItem<String>(
                enabled: false,
                child: SizedBox(
                  width: 260,
                  child: StatefulBuilder(
                    builder: (context, setPopupState) {
                      int selY = curYear;
                      return Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.remove_circle_outline,
                                    size: 18),
                                onPressed: () {
                                  Navigator.pop(
                                    ctx,
                                    '${(curYear - 1).toString().padLeft(4, '0')}-${curMonth.toString().padLeft(2, '0')}',
                                  );
                                },
                              ),
                              Text(
                                '$selY',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 15,
                                  color: colors.textPrimary,
                                ),
                              ),
                              IconButton(
                                icon: const Icon(Icons.add_circle_outline,
                                    size: 18),
                                onPressed: () {
                                  Navigator.pop(
                                    ctx,
                                    '${(curYear + 1).toString().padLeft(4, '0')}-${curMonth.toString().padLeft(2, '0')}',
                                  );
                                },
                              ),
                            ],
                          ),
                          const Divider(height: 12),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: List.generate(12, (idx) {
                              final m = idx + 1;
                              final isSel = m == curMonth;
                              final ym =
                                  '${curYear.toString().padLeft(4, '0')}-${m.toString().padLeft(2, '0')}';
                              return InkWell(
                                borderRadius: BorderRadius.circular(8),
                                onTap: () => Navigator.pop(ctx, ym),
                                child: Container(
                                  width: 56,
                                  padding:
                                      const EdgeInsets.symmetric(vertical: 8),
                                  alignment: Alignment.center,
                                  decoration: BoxDecoration(
                                    color: isSel
                                        ? colors.accent
                                        : colors.surfaceGlass,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    shortMonths[idx],
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: isSel
                                          ? Colors.white
                                          : colors.textPrimary,
                                    ),
                                  ),
                                ),
                              );
                            }),
                          ),
                          const SizedBox(height: 10),
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              icon: const Icon(Icons.today, size: 15),
                              label: const Text('Mês Atual (Hoje)'),
                              onPressed: () {
                                final now = DateTime.now();
                                Navigator.pop(
                                  ctx,
                                  '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}',
                                );
                              },
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ];
          },
          onSelected: onMonthChanged,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: colors.surfaceGlass,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: colors.borderGlass),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.calendar_month, size: 16, color: colors.accent),
                const SizedBox(width: 8),
                Text(
                  '${shortMonths[curMonth - 1]} / $curYear',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: colors.textPrimary,
                  ),
                ),
                const SizedBox(width: 4),
                Icon(Icons.arrow_drop_down,
                    size: 18, color: colors.textSecondary),
              ],
            ),
          ),
        ),
        IconButton(
          tooltip: 'Próximo Mês',
          icon: const Icon(Icons.chevron_right, size: 20),
          onPressed: () {
            final nextYear = curMonth == 12 ? curYear + 1 : curYear;
            final nextMonth = curMonth == 12 ? 1 : curMonth + 1;
            onMonthChanged(
              '${nextYear.toString().padLeft(4, '0')}-${nextMonth.toString().padLeft(2, '0')}',
            );
          },
        ),
      ],
    );
  }
}
