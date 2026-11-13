import 'package:flutter/material.dart';
import '../../models/openmoney_models.dart';
import '../../models/prediction_models.dart';
import '../../store/money_store.dart';
import '../theme/liquid_glass.dart';
import '../modals/transaction_modal.dart';
import '../modals/batch_delete_modal.dart';
import '../widgets/category_select_form_field.dart';

class PredictionsManagementView extends StatefulWidget {
  final MoneyStore store;

  const PredictionsManagementView({super.key, required this.store});

  @override
  State<PredictionsManagementView> createState() => _PredictionsManagementViewState();
}

class _PredictionsManagementViewState extends State<PredictionsManagementView> {
  final Set<String> _expandedCategories = {};

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colors = OpenMoneyColors(isDark);
    final report = widget.store.getPredictionsReport(widget.store.month);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildHeader(context, colors),
          const Divider(height: 1),
          _buildKpiCards(context, report, colors),
          const Divider(height: 1),
          Expanded(child: _buildContent(context, report, colors)),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context, OpenMoneyColors colors) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      child: Row(
        children: [
          Icon(Icons.auto_fix_high, color: colors.accent, size: 22),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Previsões',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              Text(
                'Gerencie tetos de gastos previstos e acompanhe os abatimentos reais por categoria',
                style: TextStyle(fontSize: 11, color: colors.textSecondary),
              ),
            ],
          ),
          const Spacer(),
          _buildMonthSelector(colors),
          const SizedBox(width: 12),
          PopupMenuButton<String>(
            tooltip: 'Modo de apuração',
            icon: const Icon(Icons.tune, size: 20),
            initialValue: widget.store.db.predMode,
            onSelected: widget.store.setPredMode,
            itemBuilder: (ctx) => const [
              PopupMenuItem(value: 'month', child: Text('Por Mês')),
              PopupMenuItem(value: 'invoice', child: Text('Por Fatura do Cartão')),
            ],
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            icon: const Icon(Icons.auto_fix_normal, size: 16),
            label: const Text('Ajustar'),
            onPressed: () {
              final res = widget.store.adjustPredictions(widget.store.month);
              showPredictionsAdjustModal(context, res);
            },
          ),
          const SizedBox(width: 8),
          FilledButton.icon(
            icon: const Icon(Icons.add, size: 16),
            label: const Text('Nova Previsão'),
            onPressed: () => _openNewPredictionDialog(context),
          ),
        ],
      ),
    );
  }

  Widget _buildMonthSelector(OpenMoneyColors colors) {
    return Container(
      decoration: BoxDecoration(
        color: colors.surfaceCard,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: colors.borderGlass),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.chevron_left, size: 16),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            onPressed: () {
              widget.store.month = addMonthsYM(widget.store.month, -1);
            },
          ),
          Text(
            fmtMonth(widget.store.month),
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
          ),
          IconButton(
            icon: const Icon(Icons.chevron_right, size: 16),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
            onPressed: () {
              widget.store.month = addMonthsYM(widget.store.month, 1);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildKpiCards(BuildContext context, PredictionsSummaryReport report, OpenMoneyColors colors) {
    final cur = widget.store.baseCurrency;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Expanded(child: _kpiCard('TETO PREVISTO', formatCurrency(report.totalPlannedBaseCents, cur), colors.textPrimary, colors)),
          const SizedBox(width: 12),
          Expanded(child: _kpiCard('TOTAL ABATIDO', formatCurrency(report.totalDeductedCents, cur), colors.warning, colors)),
          const SizedBox(width: 12),
          Expanded(child: _kpiCard('SALDO REMANESCENTE', formatCurrency(report.totalRemainingCents, cur), report.totalRemainingCents > 0 ? colors.income : colors.expense, colors)),
          const SizedBox(width: 12),
          Expanded(child: _kpiCard('PREVISÕES', '${report.allPredictions.length}', colors.accent, colors)),
        ],
      ),
    );
  }

  Widget _kpiCard(String title, String value, Color valColor, OpenMoneyColors colors) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: colors.surfaceCard,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.borderGlass),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: colors.textSecondary)),
          const SizedBox(height: 4),
          Text(value, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: valColor)),
        ],
      ),
    );
  }

  Widget _buildContent(BuildContext context, PredictionsSummaryReport report, OpenMoneyColors colors) {
    if (report.groups.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.auto_fix_high, size: 48, color: colors.textMuted.withValues(alpha: 0.4)),
            const SizedBox(height: 12),
            const Text('Nenhuma Previsão Encontrada', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text('Crie previsões com o prefixo "Previsão" para reservar tetos no mês.', style: TextStyle(fontSize: 12, color: colors.textSecondary)),
            const SizedBox(height: 16),
            FilledButton.icon(
              icon: const Icon(Icons.add),
              label: const Text('Criar Primeira Previsão'),
              onPressed: () => _openNewPredictionDialog(context),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: report.groups.length,
      itemBuilder: (ctx, idx) => _buildCategoryCard(report.groups[idx], colors),
    );
  }

  Widget _buildCategoryCard(PredictionCategoryGroup grp, OpenMoneyColors colors) {
    final cur = widget.store.baseCurrency;
    final isExpanded = _expandedCategories.contains(grp.category);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colors.surfaceCard,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colors.borderGlass),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.label, size: 18, color: colors.accent),
              const SizedBox(width: 8),
              Text(
                grp.category.isEmpty ? 'Sem Categoria' : grp.category,
                style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              Text('Base: ${formatCurrency(grp.totalBaseCents, cur)}', style: TextStyle(fontSize: 11, color: colors.textSecondary)),
              const SizedBox(width: 10),
              Text('Gasto: ${formatCurrency(grp.totalSpentCents, cur)}', style: TextStyle(fontSize: 11, color: colors.expense)),
              const SizedBox(width: 10),
              Text(
                'Saldo: ${formatCurrency(grp.remainingCents, cur)}',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: grp.remainingCents > 0 ? colors.income : colors.expense,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: grp.percentSpent,
              minHeight: 6,
              backgroundColor: colors.borderGlass,
              valueColor: AlwaysStoppedAnimation(
                grp.percentSpent >= 1.0 ? colors.expense : (grp.percentSpent > 0.7 ? colors.warning : colors.income),
              ),
            ),
          ),
          const SizedBox(height: 10),
          ...grp.predictions.map((p) => Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              children: [
                Text(p.tx.payee, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
                const SizedBox(width: 4),
                Text('(${p.accountName})', style: TextStyle(fontSize: 10, color: colors.textSecondary)),
                if (p.isExhausted) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: colors.expense,
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: const Text(
                      'ESGOTADA',
                      style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.white),
                    ),
                  ),
                ],
                const Spacer(),
                Text(
                  formatCurrency(p.currentCents, p.accountCurrency),
                  style: TextStyle(fontSize: 12, color: p.isExhausted ? colors.textMuted : colors.textPrimary),
                ),
                const SizedBox(width: 8),
                IconButton(
                  icon: const Icon(Icons.edit, size: 14),
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                  onPressed: () {
                    showTransactionEditModal(context, widget.store, p.tx);
                  },
                ),
                IconButton(
                  icon: const Icon(Icons.refresh, size: 14),
                  tooltip: 'Restaurar teto original',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                  onPressed: () => widget.store.restorePredictionBase(p.tx.id),
                ),
              ],
            ),
          )),
          if (grp.spentTransactions.isNotEmpty) ...[
            const SizedBox(height: 6),
            InkWell(
              onTap: () {
                setState(() {
                  if (isExpanded) {
                    _expandedCategories.remove(grp.category);
                  } else {
                    _expandedCategories.add(grp.category);
                  }
                });
              },
              child: Row(
                children: [
                  Icon(isExpanded ? Icons.expand_more : Icons.chevron_right, size: 14, color: colors.textSecondary),
                  const SizedBox(width: 4),
                  Text(
                    'Ver ${grp.spentTransactions.length} lançamentos que abateram este teto',
                    style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: colors.textSecondary),
                  ),
                ],
              ),
            ),
            if (isExpanded)
              Padding(
                padding: const EdgeInsets.only(left: 14, top: 6),
                child: Column(
                  children: grp.spentTransactions.map((st) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      children: [
                        Text(fmtDate(st.date), style: TextStyle(fontSize: 10, color: colors.textSecondary)),
                        const SizedBox(width: 8),
                        Text(st.payee, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500)),
                        if (st.memo.trim().isNotEmpty) ...[
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              '• ${st.memo.trim()}',
                              style: TextStyle(fontSize: 10, color: colors.textSecondary),
                              overflow: TextOverflow.ellipsis,
                              maxLines: 1,
                            ),
                          ),
                        ] else
                          const Spacer(),
                        Text(
                          formatCurrency(st.amt.abs(), widget.store.accById(st.acc)?.effectiveCurrency ?? cur),
                          style: TextStyle(fontSize: 11, color: colors.expense),
                        ),
                      ],
                    ),
                  )).toList(),
                ),
              ),
          ],
        ],
      ),
    );
  }

  void _openNewPredictionDialog(BuildContext context) {
    final accounts = widget.store.activeAccounts;
    if (accounts.isEmpty) return;

    String selectedAccId = accounts.first.id;
    String category = '';
    String dateIso = '${widget.store.month}-01';
    final descCtrl = TextEditingController();
    final amountCtrl = TextEditingController();
    final notesCtrl = TextEditingController();
    bool autoAdjust = true;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDlgState) => AlertDialog(
          title: const Text('Nova Previsão'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                DropdownButtonFormField<String>(
                  value: selectedAccId,
                  decoration: const InputDecoration(labelText: 'Conta'),
                  items: accounts.map((a) => DropdownMenuItem(value: a.id, child: Text(a.name))).toList(),
                  onChanged: (v) { if (v != null) setDlgState(() => selectedAccId = v); },
                ),
                const SizedBox(height: 8),
                TextFormField(
                  readOnly: true,
                  decoration: const InputDecoration(
                    labelText: 'Data',
                    suffixIcon: Icon(Icons.calendar_today, size: 18),
                  ),
                  controller: TextEditingController(text: fmtDate(dateIso)),
                  onTap: () async {
                    final current = DateTime.tryParse(dateIso) ?? DateTime.now();
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: current,
                      firstDate: DateTime(2000),
                      lastDate: DateTime(2100),
                    );
                    if (picked != null) {
                      setDlgState(() {
                        dateIso = '${picked.year.toString().padLeft(4, '0')}-${pad2(picked.month)}-${pad2(picked.day)}';
                      });
                    }
                  },
                ),
                const SizedBox(height: 8),
                CategorySelectFormField(
                  store: widget.store,
                  categoryType: 'Despesa',
                  currentSelection: category,
                  labelText: 'Categoria',
                  onChanged: (val) {
                    setDlgState(() => category = val);
                  },
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: descCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Complemento da Descrição',
                    prefixText: 'Previsão ',
                    hintText: 'ex: Mercado, Posto...',
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: amountCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(labelText: 'Valor do Teto (R\$)'),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: notesCtrl,
                  decoration: const InputDecoration(labelText: 'Observações'),
                ),
                const SizedBox(height: 8),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text('Ajustar imediatamente com gastos do mês', style: TextStyle(fontSize: 12)),
                  value: autoAdjust,
                  onChanged: (v) => setDlgState(() => autoAdjust = v ?? true),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancelar')),
            FilledButton(
              onPressed: () {
                final cents = parseCents(amountCtrl.text);
                if (cents == null || cents <= 0 || category.isEmpty) return;

                final suffix = descCtrl.text.trim();
                final payee = suffix.isEmpty ? 'Previsão' : 'Previsão $suffix';
                final memoTag = memoWithBaseTag(notesCtrl.text, cents);

                widget.store.addTransaction(
                  accId: selectedAccId,
                  date: dateIso,
                  payee: payee,
                  catSelection: category,
                  memo: memoTag,
                  signedAmt: -cents,
                  mode: 'normal',
                  freq: '',
                  installments: 1,
                );

                final targetMonth = dateIso.substring(0, 7);
                if (autoAdjust) {
                  widget.store.adjustPredictions(targetMonth);
                }

                Navigator.pop(ctx);
              },
              child: const Text('Salvar'),
            ),
          ],
        ),
      ),
    );
  }
}
