import 'package:flutter/material.dart';
import '../../store/money_store.dart';
import '../theme/liquid_glass.dart';

/// Pílula reutilizável para controle rápido do zoom de fontes (Acessibilidade)
/// Exibida no cabeçalho dos Relatórios, no Fluxo de Caixa e no rodapé da barra lateral.
class ZoomControlPill extends StatelessWidget {
  final MoneyStore store;
  final OpenMoneyColors colors;
  final bool compact;

  const ZoomControlPill({
    super.key,
    required this.store,
    required this.colors,
    this.compact = false,
  });

  @override
  Widget build(BuildContext context) {
    final pct = (store.fontScale * 100).round();
    final isMin = store.fontScale <= 0.90;
    final isMax = store.fontScale >= 1.45;

    return Container(
      decoration: BoxDecoration(
        color: colors.surfaceGlass,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.borderGlass),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Tooltip(
            message: 'Diminuir tamanho da fonte (⌘ -)',
            child: InkWell(
              borderRadius: const BorderRadius.horizontal(left: Radius.circular(7)),
              onTap: isMin ? null : store.zoomOut,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
                child: Icon(
                  Icons.text_decrease,
                  size: 15,
                  color: isMin
                      ? colors.textMuted.withValues(alpha: 0.35)
                      : colors.textPrimary,
                ),
              ),
            ),
          ),
          PopupMenuButton<double>(
            tooltip: 'Tamanho das Fontes',
            initialValue: store.fontScale,
            onSelected: store.setFontScale,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
              side: BorderSide(color: colors.borderGlass),
            ),
            color: colors.bgSecondary,
            elevation: 4,
            itemBuilder: (context) => [
              for (final s in MoneyStore.kFontScales)
                PopupMenuItem<double>(
                  value: s,
                  child: Row(
                    children: [
                      if ((store.fontScale - s).abs() < 0.01)
                        Icon(Icons.check, size: 16, color: colors.accent)
                      else
                        const SizedBox(width: 16),
                      const SizedBox(width: 8),
                      Text(
                        _scaleLabel(s),
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: (store.fontScale - s).abs() < 0.01
                              ? FontWeight.w700
                              : FontWeight.normal,
                          color: colors.textPrimary,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '$pct%',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: colors.textPrimary,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  const SizedBox(width: 2),
                  Icon(
                    Icons.arrow_drop_down,
                    size: 14,
                    color: colors.textSecondary,
                  ),
                ],
              ),
            ),
          ),
          Tooltip(
            message: 'Aumentar tamanho da fonte (⌘ +)',
            child: InkWell(
              borderRadius: const BorderRadius.horizontal(right: Radius.circular(7)),
              onTap: isMax ? null : store.zoomIn,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
                child: Icon(
                  Icons.text_increase,
                  size: 15,
                  color: isMax
                      ? colors.textMuted.withValues(alpha: 0.35)
                      : colors.textPrimary,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _scaleLabel(double s) {
    if ((s - 1.0).abs() < 0.01) return '100% (Padrão)';
    if (s <= 0.90) return '90% (Compacto)';
    if (s <= 1.15) return '115% (Médio)';
    if (s <= 1.30) return '130% (Grande)';
    return '145% (Extra Grande)';
  }
}
