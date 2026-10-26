import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../models/openmoney_models.dart';
import '../../services/importers_exporters.dart';
import '../../services/native_file_picker.dart';
import '../../store/money_store.dart';
import '../theme/liquid_glass.dart';

/// Abre o seletor nativo para escolher o arquivo .json exportado pelo celular
/// (ex: openmoney_inbox.json), importa os lançamentos e exibe o modal de revisão.
Future<void> showMobileInboxImportFlow(
  BuildContext context,
  MoneyStore store,
) async {
  if (kIsWeb) return;
  final selectedPath = await NativeFilePicker.pickFile(
    title: 'Importar Lançamentos do Celular (openmoney_inbox.json)',
    allowedExtensions: ['json'],
  );
  if (selectedPath == null || selectedPath.isEmpty) return;

  try {
    final file = File(selectedPath);
    if (!file.existsSync()) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Arquivo não encontrado: $selectedPath'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
      return;
    }

    final bytes = file.readAsBytesSync();
    final result = store.importMobileInboxBytes(bytes);

    if (context.mounted) {
      await showMobileInboxReviewModal(context, result);
    }
  } catch (e) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro ao importar arquivo do celular: $e'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }
}

/// Modal detalhado de conferência dos lançamentos importados do celular
Future<void> showMobileInboxReviewModal(
  BuildContext context,
  MobileInboxImportResult result,
) async {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  final colors = OpenMoneyColors(isDark);

  final totalExpenseCents = result.items
      .where((i) => i.amt < 0)
      .fold<int>(0, (sum, i) => sum + i.amt);
  final totalIncomeCents = result.items
      .where((i) => i.amt > 0)
      .fold<int>(0, (sum, i) => sum + i.amt);

  await showDialog(
    context: context,
    builder: (ctx) => Dialog(
      backgroundColor: colors.bgSecondary,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colors.borderGlass),
      ),
      child: SizedBox(
        width: 680,
        height: 500,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.all(18),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: colors.income.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.phone_iphone,
                      color: colors.income,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Lançamentos Importados do Celular',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w800,
                            color: colors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${result.items.length} lançamento(s) novo(s) importado(s) com sucesso${result.skippedCount > 0 ? " • ${result.skippedCount} duplicado(s) ignorado(s)" : ""}',
                          style: TextStyle(
                            fontSize: 12,
                            color: colors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),

            // Metrics bar
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              child: Wrap(
                spacing: 12,
                runSpacing: 8,
                children: [
                  _MetricChip(
                    icon: Icons.download_done,
                    iconColor: colors.accent,
                    bgColor: colors.borderGlass.withValues(alpha: 0.2),
                    label: 'Importados',
                    value: '${result.items.length}',
                    valueColor: colors.textPrimary,
                  ),
                  if (totalExpenseCents < 0)
                    _MetricChip(
                      icon: Icons.arrow_downward_rounded,
                      iconColor: colors.expense,
                      bgColor: colors.expense.withValues(alpha: 0.1),
                      label: 'Total Despesas',
                      value: brl(totalExpenseCents),
                      valueColor: colors.expense,
                    ),
                  if (totalIncomeCents > 0)
                    _MetricChip(
                      icon: Icons.arrow_upward_rounded,
                      iconColor: colors.income,
                      bgColor: colors.income.withValues(alpha: 0.1),
                      label: 'Total Receitas',
                      value: brl(totalIncomeCents),
                      valueColor: colors.income,
                    ),
                  if (result.skippedCount > 0)
                    _MetricChip(
                      icon: Icons.shield_outlined,
                      iconColor: colors.warning,
                      bgColor: colors.warning.withValues(alpha: 0.1),
                      label: 'Duplicados Ignorados',
                      value: '${result.skippedCount}',
                      valueColor: colors.warning,
                    ),
                ],
              ),
            ),
            const Divider(height: 1),

            // List of imported items
            Expanded(
              child: result.items.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.inbox_outlined,
                            size: 42,
                            color: colors.textMuted,
                          ),
                          const SizedBox(height: 10),
                          Text(
                            'Nenhum novo lançamento foi importado.',
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                              color: colors.textSecondary,
                            ),
                          ),
                          if (result.skippedCount > 0) ...[
                            const SizedBox(height: 4),
                            Text(
                              'Todos os lançamentos do arquivo já existiam na sua base.',
                              style: TextStyle(
                                fontSize: 12.5,
                                color: colors.textMuted,
                              ),
                            ),
                          ],
                        ],
                      ),
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.all(16),
                      itemCount: result.items.length,
                      separatorBuilder: (_, _) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final item = result.items[index];
                        return Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: colors.surfaceGlass,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: colors.borderGlass),
                          ),
                          child: Row(
                            children: [
                              SizedBox(
                                width: 105,
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      fmtDate(item.date),
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    Text(
                                      item.accountName,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: colors.textSecondary,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      item.payee,
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    if (item.memo.isNotEmpty)
                                      Text(
                                        item.memo,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: colors.textSecondary,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              if (item.cat.isNotEmpty) ...[
                                const SizedBox(width: 8),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: colors.borderGlass
                                        .withValues(alpha: 0.25),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    item.cat,
                                    style: const TextStyle(fontSize: 11),
                                  ),
                                ),
                              ],
                              const SizedBox(width: 12),
                              Text(
                                brl(item.amt),
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w800,
                                  color: item.amt < 0
                                      ? colors.expense
                                      : colors.income,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures()
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
            const Divider(height: 1),

            // Footer
            Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  if (result.newCatsCount > 0)
                    Text(
                      '📁 ${result.newCatsCount} nova(s) categoria(s) cadastrada(s) automaticamente.',
                      style: TextStyle(
                        fontSize: 12,
                        color: colors.textSecondary,
                      ),
                    )
                  else
                    const SizedBox(),
                  FilledButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Concluir'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class _MetricChip extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final Color bgColor;
  final String label;
  final String value;
  final Color valueColor;

  const _MetricChip({
    required this.icon,
    required this.iconColor,
    required this.bgColor,
    required this.label,
    required this.value,
    required this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: iconColor),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                value,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: valueColor,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
