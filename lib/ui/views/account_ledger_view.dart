import 'package:flutter/material.dart';
import '../../models/openmoney_models.dart';
import '../../store/money_store.dart';
import '../modals/account_modal.dart';
import '../modals/batch_delete_modal.dart';
import '../modals/transaction_modal.dart';
import '../theme/liquid_glass.dart';

class AccountLedgerView extends StatefulWidget {
  final MoneyStore store;
  final Account account;

  const AccountLedgerView({
    super.key,
    required this.store,
    required this.account,
  });

  @override
  State<AccountLedgerView> createState() => _AccountLedgerViewState();
}

class _AccountLedgerViewState extends State<AccountLedgerView> {
  final TextEditingController _dateCtrl =
      TextEditingController(text: fmtDate(todayISO()));
  final TextEditingController _payeeCtrl = TextEditingController();
  final TextEditingController _memoCtrl = TextEditingController();
  final TextEditingController _amtCtrl = TextEditingController();
  bool _isExpense = true;
  String _catSelection = '';
  String _mode = 'single'; // 'single', 'installment', 'recurring'
  int _installments = 2;
  String _freq = 'monthly';
  String? _customIk;
  List<PayeeSuggestion> _suggestions = [];

  @override
  void initState() {
    super.initState();
    _syncDefaultCategory();
  }

  @override
  void didUpdateWidget(covariant AccountLedgerView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.account.id != widget.account.id) {
      _customIk = null;
      _syncDefaultCategory();
    }
  }

  void _syncDefaultCategory() {
    final paths =
        widget.store.allCategoryPaths(_isExpense ? 'Despesa' : 'Receita');
    if (paths.isNotEmpty &&
        (_catSelection.isEmpty ||
            (!_catSelection.startsWith('xfer:') &&
                !paths.contains(_catSelection)))) {
      _catSelection = paths.first;
    }
  }

  @override
  void dispose() {
    _dateCtrl.dispose();
    _payeeCtrl.dispose();
    _memoCtrl.dispose();
    _amtCtrl.dispose();
    super.dispose();
  }

  String _resolveIsoDate() {
    final raw = _dateCtrl.text.trim();
    if (RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(raw)) return raw;
    final parts = raw.split('/');
    if (parts.length == 3) {
      return '${parts[2].padLeft(4, '0')}-${parts[1].padLeft(2, '0')}-${parts[0].padLeft(2, '0')}';
    }
    return todayISO();
  }

  void _onPayeeChanged(String val) {
    final list = widget.store.payeeSuggestions(val);
    setState(() {
      _suggestions = list;
    });
  }

  void _applySuggestion(PayeeSuggestion s) {
    setState(() {
      _payeeCtrl.text = s.name;
      _isExpense = s.isExpense;
      if (s.category.isNotEmpty) {
        _catSelection = s.category;
      } else {
        _syncDefaultCategory();
      }
      _suggestions = [];
    });
  }

  void _submitQuickEntry() {
    if (widget.account.isInactive) return;
    final payee = _payeeCtrl.text.trim();
    final absCents = (parseCents(_amtCtrl.text) ?? 0).abs();
    if (payee.isEmpty || absCents == 0) return;

    final signedAmt = _isExpense ? -absCents : absCents;
    final isoDate = _resolveIsoDate();

    widget.store.addTransaction(
      accId: widget.account.id,
      date: isoDate,
      payee: payee,
      catSelection: _catSelection,
      memo: _memoCtrl.text.trim(),
      signedAmt: signedAmt,
      mode: _mode,
      freq: _freq,
      installments: _installments,
      customIk: _customIk,
    );

    setState(() {
      _payeeCtrl.clear();
      _memoCtrl.clear();
      _amtCtrl.clear();
      _mode = 'single';
      _suggestions = [];
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colors = OpenMoneyColors(isDark);
    final acc = widget.account;
    final monthData = widget.store.accountMonthData(acc.id, widget.store.month);
    final isCard = acc.type == kCardType && acc.card != null;
    final invSummary =
        isCard ? widget.store.invoiceSummary(acc.id, widget.store.month) : null;
    final pendingCount = widget.store.pendingCountForAccount(acc.id);

    // Group transactions day by day with running Real and Predicted balances
    final dayGroups = <_DayGroup>[];
    int runningReal = monthData.openingReal;
    int runningPred = monthData.openingPred;

    for (final tx in monthData.transactions) {
      if (tx.rec) runningReal += tx.amt;
      runningPred += tx.amt;

      if (dayGroups.isEmpty || dayGroups.last.date != tx.date) {
        dayGroups.add(
          _DayGroup(
            date: tx.date,
            items: [tx],
            closingReal: runningReal,
            closingPred: runningPred,
          ),
        );
      } else {
        dayGroups.last.items.add(tx);
        dayGroups.last.closingReal = runningReal;
        dayGroups.last.closingPred = runningPred;
      }
    }

    return Column(
      children: [
        // 1. Account Executive Header
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
          child: GlassCard(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Wrap(
                  spacing: 12,
                  runSpacing: 10,
                  alignment: WrapAlignment.spaceBetween,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          isCard
                              ? Icons.credit_card
                              : Icons.account_balance_wallet_outlined,
                          color: colors.accent,
                          size: 22,
                        ),
                        const SizedBox(width: 10),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  acc.name,
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w800,
                                    color: colors.textPrimary,
                                  ),
                                ),
                                if (acc.isFavorite) ...[
                                  const SizedBox(width: 6),
                                  const Icon(Icons.star,
                                      size: 16, color: Colors.amber),
                                ],
                                if (acc.isInactive) ...[
                                  const SizedBox(width: 8),
                                  StatusBadge(
                                    text: 'INATIVA',
                                    color: colors.warning,
                                  ),
                                ],
                              ],
                            ),
                            Text(
                              acc.type,
                              style: TextStyle(
                                fontSize: 12,
                                color: colors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(width: 8),
                        IconButton(
                          tooltip: 'Editar Conta',
                          icon: const Icon(Icons.settings_outlined, size: 18),
                          onPressed: () => showAccountModal(
                            context,
                            widget.store,
                            editingAccount: acc,
                          ),
                        ),
                      ],
                    ),
                    MonthYearPickerBar(
                      currentMonthYM: widget.store.month,
                      availableYears: widget.store.allYearsInDatabase(),
                      onMonthChanged: (ym) => widget.store.month = ym,
                    ),
                    Wrap(
                      spacing: 16,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        _HeaderBalancePill(
                          label: 'Saldo Conciliado (Real)',
                          cents: widget.store.balance(acc, predicted: false),
                          colors: colors,
                        ),
                        _HeaderBalancePill(
                          label: 'Previsto Final do Mês',
                          cents: widget.store.balance(acc, predicted: true),
                          colors: colors,
                        ),
                        OutlinedButton.icon(
                          icon: const Icon(Icons.auto_fix_high, size: 16),
                          label: const Text('Ajustar Previsões'),
                          onPressed: () {
                            final res = widget.store
                                .adjustPredictions(widget.store.month);
                            showPredictionsAdjustModal(context, res);
                          },
                        ),
                      ],
                    ),
                  ],
                ),
                if (invSummary != null) ...[
                  const Divider(height: 20),
                  Wrap(
                    spacing: 16,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    alignment: WrapAlignment.spaceBetween,
                    children: [
                      Wrap(
                        spacing: 14,
                        runSpacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            'Fatura ${fmtMonth(invSummary.key)}',
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                            ),
                          ),
                          Text(
                            'Fecha: ${fmtDate(invSummary.closeDate)} • Vence: ${fmtDate(invSummary.dueDate)} • Débito: ${invSummary.payAccountName}',
                            style: TextStyle(
                              fontSize: 12,
                              color: colors.textSecondary,
                            ),
                          ),
                          Text(
                            'Compras: ${brl(invSummary.chargesCents)}',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: colors.expense,
                            ),
                          ),
                          if (invSummary.paymentsCents > 0)
                            Text(
                              'Pago: ${brl(invSummary.paymentsCents)}',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: colors.income,
                              ),
                            ),
                          Text(
                            'Em Aberto: ${brl(invSummary.remainingCents)}',
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          if (invSummary.isFullyPaid)
                            StatusBadge(
                              text: 'LIQUIDADA',
                              color: colors.income,
                              icon: Icons.verified,
                            ),
                        ],
                      ),
                      FilledButton.tonalIcon(
                        icon: const Icon(Icons.payments_outlined, size: 16),
                        label: const Text('Pagar / Adiantar Fatura'),
                        onPressed: () => showInvoicePaymentModal(
                          context,
                          widget.store,
                          cardAccount: acc,
                          summary: invSummary,
                        ),
                      ),
                    ],
                  ),
                ],
                if (pendingCount > 0) ...[
                  const SizedBox(height: 10),
                  InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () {
                      widget.store.navigateTo(NavModule.dueBills);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: colors.warning.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: colors.warning.withValues(alpha: 0.4),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.notifications_active_outlined,
                            size: 16,
                            color: colors.warning,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Você possui $pendingCount lançamento(s) pendente(s) de conciliação nos próximos ${widget.store.reminderDaysAhead} dias nesta conta.',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: colors.warning,
                              ),
                            ),
                          ),
                          Text(
                            'Ver Vencimentos →',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: colors.warning,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),

        // 2. Quick Entry Bar (Barra de Inserção Rápida)
        if (!acc.isInactive)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: GlassCard(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      SizedBox(
                        width: 112,
                        child: TextField(
                          controller: _dateCtrl,
                          style: const TextStyle(fontSize: 13),
                          decoration: const InputDecoration(
                            labelText: 'Data',
                            isDense: true,
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: () {
                          setState(() {
                            _isExpense = !_isExpense;
                            _syncDefaultCategory();
                          });
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 9,
                          ),
                          decoration: BoxDecoration(
                            color: (_isExpense ? colors.expense : colors.income)
                                .withValues(alpha: 0.16),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color:
                                  _isExpense ? colors.expense : colors.income,
                            ),
                          ),
                          child: Text(
                            _isExpense ? '− Débito' : '+ Crédito',
                            style: TextStyle(
                              fontWeight: FontWeight.w800,
                              fontSize: 12,
                              color:
                                  _isExpense ? colors.expense : colors.income,
                            ),
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 220,
                        child: TextField(
                          controller: _payeeCtrl,
                          style: const TextStyle(fontSize: 13),
                          decoration: const InputDecoration(
                            labelText: 'Favorecido / Descrição',
                            hintText: 'Ex.: Supermercado, Previsão...',
                            isDense: true,
                            border: OutlineInputBorder(),
                          ),
                          onChanged: _onPayeeChanged,
                          onSubmitted: (_) => _submitQuickEntry(),
                        ),
                      ),
                      Builder(
                        builder: (context) {
                          final catType = _isExpense ? 'Despesa' : 'Receita';
                          final paths = widget.store.allCategoryPaths(catType);
                          final others = widget.store.activeAccounts
                              .where((a) => a.id != acc.id)
                              .toList();
                          final items = <DropdownMenuItem<String>>[
                            ...paths.map(
                              (p) => DropdownMenuItem(
                                value: p,
                                child: Text(
                                  p,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                            ...others.map(
                              (a) => DropdownMenuItem(
                                value: 'xfer:${a.id}',
                                child: Text(
                                  '⇄ Transferência: ${a.name}',
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                          ];
                          final val =
                              items.any((i) => i.value == _catSelection)
                                  ? _catSelection
                                  : (items.isNotEmpty
                                      ? items.first.value!
                                      : '');
                          return SizedBox(
                            width: 230,
                            child: DropdownButtonFormField<String>(
                              key: ValueKey('cat_$val'),
                              initialValue: val.isEmpty ? null : val,
                              isExpanded: true,
                              decoration: const InputDecoration(
                                labelText: 'Categoria / Transferência',
                                isDense: true,
                                border: OutlineInputBorder(),
                              ),
                              items: items,
                              onChanged: (v) {
                                if (v != null) {
                                  setState(() => _catSelection = v);
                                }
                              },
                            ),
                          );
                        },
                      ),
                      SizedBox(
                        width: 150,
                        child: TextField(
                          controller: _memoCtrl,
                          style: const TextStyle(fontSize: 13),
                          decoration: const InputDecoration(
                            labelText: 'Nota',
                            isDense: true,
                            border: OutlineInputBorder(),
                          ),
                          onSubmitted: (_) => _submitQuickEntry(),
                        ),
                      ),
                      SizedBox(
                        width: 120,
                        child: TextField(
                          controller: _amtCtrl,
                          style: const TextStyle(fontSize: 13),
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Valor (R\$)',
                            isDense: true,
                            border: OutlineInputBorder(),
                          ),
                          onSubmitted: (_) => _submitQuickEntry(),
                        ),
                      ),
                      SizedBox(
                        width: 135,
                        child: DropdownButtonFormField<String>(
                          initialValue: _mode,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Modalidade',
                            isDense: true,
                            border: OutlineInputBorder(),
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: 'single',
                              child: Text('Único'),
                            ),
                            DropdownMenuItem(
                              value: 'installment',
                              child: Text('Parcelado'),
                            ),
                            DropdownMenuItem(
                              value: 'recurring',
                              child: Text('Recorrente'),
                            ),
                          ],
                          onChanged: (v) {
                            if (v != null) setState(() => _mode = v);
                          },
                        ),
                      ),
                      if (_mode == 'installment')
                        SizedBox(
                          width: 95,
                          child: DropdownButtonFormField<int>(
                            initialValue: _installments,
                            decoration: const InputDecoration(
                              labelText: 'Parcelas',
                              isDense: true,
                              border: OutlineInputBorder(),
                            ),
                            items: List.generate(
                              47,
                              (i) => DropdownMenuItem(
                                value: i + 2,
                                child: Text('${i + 2}x'),
                              ),
                            ),
                            onChanged: (v) {
                              if (v != null) setState(() => _installments = v);
                            },
                          ),
                        ),
                      if (_mode == 'recurring')
                        SizedBox(
                          width: 130,
                          child: DropdownButtonFormField<String>(
                            initialValue: _freq,
                            decoration: const InputDecoration(
                              labelText: 'Frequência',
                              isDense: true,
                              border: OutlineInputBorder(),
                            ),
                            items: kRecurrenceFrequencyOptions
                                .map(
                                  (o) => DropdownMenuItem(
                                    value: o.id,
                                    child: Text(o.label),
                                  ),
                                )
                                .toList(),
                            onChanged: (v) {
                              if (v != null) setState(() => _freq = v);
                            },
                          ),
                        ),
                      FilledButton.icon(
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('Lançar'),
                        onPressed: _submitQuickEntry,
                      ),
                    ],
                  ),
                  if (_suggestions.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: _suggestions.map((s) {
                        return ActionChip(
                          avatar: Icon(
                            s.isExpense
                                ? Icons.trending_down
                                : Icons.trending_up,
                            size: 14,
                            color: s.isExpense ? colors.expense : colors.income,
                          ),
                          label: Text('${s.name} • ${s.category}'),
                          onPressed: () => _applySuggestion(s),
                        );
                      }).toList(),
                    ),
                  ],
                ],
              ),
            ),
          ),

        // 3. Opening Balance Bar + Day-by-Day Chronological Ledger
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            children: [
              // Opening balance row for the active month
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                margin: const EdgeInsets.only(bottom: 10),
                decoration: BoxDecoration(
                  color: colors.surfaceGlass,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: colors.borderGlass),
                ),
                child: SizedBox(
                  width: double.infinity,
                  child: Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: 12,
                    runSpacing: 4,
                    children: [
                      Text(
                        'Saldo Anterior Acumulado (Início de ${fmtMonth(widget.store.month)})',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: colors.textSecondary,
                        ),
                      ),
                      Wrap(
                        spacing: 16,
                        children: [
                          Text(
                            'Real: ${brl(monthData.openingReal)}',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: colors.textPrimary,
                              fontFeatures: const [
                                FontFeature.tabularFigures()
                              ],
                            ),
                          ),
                          Text(
                            'Previsto: ${brl(monthData.openingPred)}',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: colors.textSecondary,
                              fontFeatures: const [
                                FontFeature.tabularFigures()
                              ],
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              if (dayGroups.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 48),
                  child: Center(
                    child: Column(
                      children: [
                        Icon(
                          Icons.receipt_long_outlined,
                          size: 42,
                          color: colors.textMuted,
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'Nenhum lançamento em ${fmtMonth(widget.store.month)}.',
                          style: TextStyle(color: colors.textSecondary),
                        ),
                      ],
                    ),
                  ),
                ),
              ...dayGroups.map((group) {
                return GlassCard(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
                      // Day Header with Closing Real & Predicted Balances
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: colors.bgPrimary.withValues(alpha: 0.45),
                          border: Border(
                            bottom: BorderSide(color: colors.borderGlass),
                          ),
                        ),
                        child: SizedBox(
                          width: double.infinity,
                          child: Wrap(
                            alignment: WrapAlignment.spaceBetween,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            spacing: 12,
                            runSpacing: 4,
                            children: [
                              Text(
                                '${fmtDate(group.date)} · ${weekdayShort(group.date).toUpperCase()}',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w800,
                                  color: colors.accent,
                                ),
                              ),
                              Wrap(
                                spacing: 14,
                                children: [
                                  Text(
                                    'Saldo Real: ${brl(group.closingReal)}',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: colors.textPrimary,
                                      fontFeatures: const [
                                        FontFeature.tabularFigures()
                                      ],
                                    ),
                                  ),
                                  Text(
                                    'Previsto: ${brl(group.closingPred)}',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: colors.textSecondary,
                                      fontFeatures: const [
                                        FontFeature.tabularFigures()
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ),
                      ...group.items.map((tx) {
                        final isHighlighted =
                            widget.store.highlightedTxId == tx.id;
                        final isPred = isPredictionPayee(tx.payee);
                        return Container(
                          decoration: BoxDecoration(
                            color: isHighlighted
                                ? colors.accent.withValues(alpha: 0.22)
                                : Colors.transparent,
                            border: Border(
                              bottom: BorderSide(
                                color:
                                    colors.borderGlass.withValues(alpha: 0.5),
                              ),
                            ),
                          ),
                          child: ListTile(
                            dense: true,
                            onTap: () => showTransactionEditModal(
                              context,
                              widget.store,
                              tx,
                            ),
                            leading: IconButton(
                              tooltip: tx.rec
                                  ? 'Conciliado (Clique para desmarcar)'
                                  : 'Pendente (Clique para conciliar)',
                              icon: Icon(
                                tx.rec
                                    ? Icons.check_circle
                                    : Icons.radio_button_unchecked,
                                color: tx.rec
                                    ? colors.income
                                    : colors.textMuted,
                                size: 20,
                              ),
                              onPressed: () =>
                                  widget.store.toggleReconciled(tx.id),
                            ),
                            title: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    tx.payee,
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13.5,
                                      color: colors.textPrimary,
                                    ),
                                  ),
                                ),
                                if (isPred) ...[
                                  const SizedBox(width: 6),
                                  StatusBadge(
                                    text: 'PREVISÃO',
                                    color: colors.accentIndigo,
                                  ),
                                ],
                                if (tx.recId != null) ...[
                                  const SizedBox(width: 6),
                                  StatusBadge(
                                    text: recurrenceFrequencyLabel(tx.recFreq)
                                        .toUpperCase(),
                                    color: colors.accent,
                                    icon: Icons.repeat,
                                  ),
                                ],
                                if (tx.auto == true) ...[
                                  const SizedBox(width: 6),
                                  StatusBadge(
                                    text: 'FATURA AUTO',
                                    color: colors.warning,
                                  ),
                                ],
                              ],
                            ),
                            subtitle: Text(
                              [
                                tx.cat.isEmpty ? 'Sem categoria' : tx.cat,
                                if (tx.memo.isNotEmpty) tx.memo,
                                if (tx.ik != null && tx.ik!.isNotEmpty)
                                  'Fatura ${tx.ik}',
                              ].join(' • '),
                              style: TextStyle(
                                fontSize: 12,
                                color: colors.textSecondary,
                              ),
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  brl(tx.amt),
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 14,
                                    color: tx.amt >= 0
                                        ? colors.income
                                        : colors.expense,
                                    fontFeatures: const [
                                      FontFeature.tabularFigures()
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 4),
                                IconButton(
                                  tooltip: 'Excluir Lançamento',
                                  icon: Icon(
                                    Icons.delete_outline,
                                    size: 17,
                                    color: colors.textMuted,
                                  ),
                                  onPressed: tx.auto == true
                                      ? null
                                      : () => showDeleteTransactionDialog(
                                            context,
                                            widget.store,
                                            tx,
                                          ),
                                ),
                              ],
                            ),
                          ),
                        );
                      }),
                    ],
                  ),
                );
              }),
            ],
          ),
        ),
      ],
    );
  }
}

class _DayGroup {
  final String date;
  final List<Transaction> items;
  int closingReal;
  int closingPred;

  _DayGroup({
    required this.date,
    required this.items,
    required this.closingReal,
    required this.closingPred,
  });
}

class _HeaderBalancePill extends StatelessWidget {
  final String label;
  final int cents;
  final OpenMoneyColors colors;

  const _HeaderBalancePill({
    required this.label,
    required this.cents,
    required this.colors,
  });

  @override
  Widget build(BuildContext context) {
    final valColor = cents >= 0 ? colors.income : colors.expense;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 11, color: colors.textSecondary),
        ),
        Text(
          brl(cents),
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: valColor,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}
