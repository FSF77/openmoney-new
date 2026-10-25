import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../models/openmoney_models.dart';
import '../../store/money_store.dart';
import '../theme/liquid_glass.dart';

Future<void> showBatchDeleteModal(
  BuildContext context,
  MoneyStore store,
) async {
  await showDialog(
    context: context,
    builder: (ctx) => _BatchDeleteDialog(store: store),
  );
}

class _BatchDeleteDialog extends StatefulWidget {
  final MoneyStore store;
  const _BatchDeleteDialog({required this.store});

  @override
  State<_BatchDeleteDialog> createState() => _BatchDeleteDialogState();
}

class _BatchDeleteDialogState extends State<_BatchDeleteDialog> {
  String _selectedAccId = 'all';
  bool _isAllTime = false;
  late final TextEditingController _startCtrl;
  late final TextEditingController _endCtrl;
  bool _deleteCounterparts = true;

  @override
  void initState() {
    super.initState();
    final today = todayISO();
    final yearStart = '${today.substring(0, 4)}-01-01';
    _startCtrl = TextEditingController(text: yearStart);
    _endCtrl = TextEditingController(text: today);
  }

  @override
  void dispose() {
    _startCtrl.dispose();
    _endCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colors = OpenMoneyColors(isDark);

    final preview = widget.store.previewBatchDelete(
      accountId: _selectedAccId == 'all' ? null : _selectedAccId,
      isAllTime: _isAllTime,
      startDate: _startCtrl.text.trim(),
      endDate: _endCtrl.text.trim(),
      deleteTransferCounterparts: _deleteCounterparts,
    );

    return AlertDialog(
      backgroundColor: colors.bgSecondary,
      title: const Row(
        children: [
          Icon(Icons.cleaning_services_outlined, color: Colors.amber),
          SizedBox(width: 10),
          Text('Limpeza / Exclusão de Lançamentos em Lote'),
        ],
      ),
      content: SizedBox(
        width: 500,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DropdownButtonFormField<String>(
                initialValue: _selectedAccId,
                decoration: const InputDecoration(
                  labelText: 'Escopo de Conta',
                  border: OutlineInputBorder(),
                ),
                items: [
                  const DropdownMenuItem(
                    value: 'all',
                    child: Text('Todas as Contas'),
                  ),
                  ...widget.store.db.accounts.map(
                    (a) => DropdownMenuItem(value: a.id, child: Text(a.name)),
                  ),
                ],
                onChanged: (v) {
                  if (v != null) setState(() => _selectedAccId = v);
                },
              ),
              const SizedBox(height: 12),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text('Todo o Histórico da Base'),
                value: _isAllTime,
                onChanged: (v) => setState(() => _isAllTime = v),
              ),
              if (!_isAllTime) ...[
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _startCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Data Inicial (AAAA-MM-DD)',
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _endCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Data Final (AAAA-MM-DD)',
                          border: OutlineInputBorder(),
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  children: [
                    ActionChip(
                      label: const Text('Ano Atual'),
                      onPressed: () {
                        final y = todayISO().substring(0, 4);
                        setState(() {
                          _startCtrl.text = '$y-01-01';
                          _endCtrl.text = '$y-12-31';
                        });
                      },
                    ),
                    ActionChip(
                      label: const Text('Ano Anterior'),
                      onPressed: () {
                        final y =
                            (int.tryParse(todayISO().substring(0, 4)) ?? 2026) -
                                1;
                        setState(() {
                          _startCtrl.text = '$y-01-01';
                          _endCtrl.text = '$y-12-31';
                        });
                      },
                    ),
                    ActionChip(
                      label: const Text('Até Hoje'),
                      onPressed: () {
                        setState(() {
                          _startCtrl.text = '1970-01-01';
                          _endCtrl.text = todayISO();
                        });
                      },
                    ),
                  ],
                ),
              ],
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text(
                    'Excluir também pernas espelhadas de transferências'),
                value: _deleteCounterparts,
                onChanged: (v) => setState(() => _deleteCounterparts = v),
              ),
              const SizedBox(height: 12),
              GlassCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Pré-visualização ao Vivo do Impacto:',
                      style:
                          TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
                    ),
                    const SizedBox(height: 8),
                    Text('• Lançamentos selecionados: ${preview.count}'),
                    Text(
                        '• Contas afetadas: ${preview.affectedAccountsCount}'),
                    Text(
                      '• Total de Receitas: ${brl(preview.incomeCents)}',
                      style: TextStyle(color: colors.income),
                    ),
                    Text(
                      '• Total de Despesas: ${brl(preview.expenseCents)}',
                      style: TextStyle(color: colors.expense),
                    ),
                    Text(
                      '• Impacto Líquido: ${brl(preview.netCents)}',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Segurança: Um backup automático em JSON será salvo na pasta da base antes de executar a exclusão.',
                style: TextStyle(fontSize: 12, color: colors.textSecondary),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
          icon: const Icon(Icons.delete_sweep, size: 18),
          label: Text('Backup + Excluir (${preview.count})'),
          onPressed: preview.count == 0
              ? null
              : () {
                  if (!kIsWeb && widget.store.dbPath.isNotEmpty) {
                    try {
                      final backupPath =
                          '${widget.store.dbPath}.backup-pre-exclusao-${todayISO()}.json';
                      File(backupPath).writeAsStringSync(
                        widget.store.exportDatabaseJson(),
                        flush: true,
                      );
                    } catch (_) {}
                  }
                  widget.store.executeBatchDelete(
                    accountId:
                        _selectedAccId == 'all' ? null : _selectedAccId,
                    isAllTime: _isAllTime,
                    startDate: _startCtrl.text.trim(),
                    endDate: _endCtrl.text.trim(),
                    deleteTransferCounterparts: _deleteCounterparts,
                  );
                  Navigator.pop(context);
                },
        ),
      ],
    );
  }
}

Future<void> showPredictionsAdjustModal(
  BuildContext context,
  PredictionsAdjustResult result,
) async {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  final colors = OpenMoneyColors(isDark);

  await showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: colors.bgSecondary,
      title: Row(
        children: [
          Icon(
            result.hasExhausted
                ? Icons.warning_amber_rounded
                : Icons.auto_fix_high,
            color: result.hasExhausted ? colors.warning : colors.accent,
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(result.title)),
        ],
      ),
      content: SizedBox(
        width: 540,
        child: result.items.isEmpty
            ? Text(result.message)
            : SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    GlassCard(
                      padding: const EdgeInsets.all(12),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          Column(
                            children: [
                              Text(
                                'Total Abatido',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: colors.textSecondary,
                                ),
                              ),
                              Text(
                                brl(result.totalDeductedCents),
                                style: TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 16,
                                  color: colors.accent,
                                ),
                              ),
                            ],
                          ),
                          Column(
                            children: [
                              Text(
                                'Previsões Analisadas',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: colors.textSecondary,
                                ),
                              ),
                              Text(
                                '${result.items.length}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 16,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    ...result.items.map((item) {
                      final badgeColor =
                          item.status == PredictionAdjustStatus.exhausted
                              ? colors.expense
                              : (item.status == PredictionAdjustStatus.adjusted
                                  ? colors.income
                                  : colors.textSecondary);
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: GlassCard(
                          padding: const EdgeInsets.all(12),
                          child: Row(
                            children: [
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      item.payee,
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    Text(
                                      '${item.accountName} • ${item.category}',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: colors.textSecondary,
                                      ),
                                    ),
                                    const SizedBox(height: 4),
                                    Text(
                                      'Base: ${brl(item.baseCents)} − Gastos: ${brl(item.spentCents)} = Saldo: ${brl(item.remainingCents)}',
                                      style: const TextStyle(fontSize: 12),
                                    ),
                                  ],
                                ),
                              ),
                              StatusBadge(
                                text: item.status.label.toUpperCase(),
                                color: badgeColor,
                              ),
                            ],
                          ),
                        ),
                      );
                    }),
                  ],
                ),
              ),
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Fechar'),
        ),
      ],
    ),
  );
}
