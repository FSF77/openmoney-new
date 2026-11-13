import 'package:flutter/material.dart';
import '../../models/openmoney_models.dart';
import '../../services/bank_logo_registry.dart';
import '../../services/currency_rate_service.dart';
import '../../services/importers_exporters.dart';
import '../../services/pdf_report_generator.dart';
import '../../store/money_store.dart';
import '../modals/account_modal.dart';
import '../modals/batch_delete_modal.dart';
import '../modals/transaction_modal.dart';
import '../theme/liquid_glass.dart';
import '../widgets/category_select_form_field.dart';
import '../widgets/csv_export.dart';
import '../widgets/datagrid_transaction_table.dart';

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
  final TextEditingController _quickRateCtrl = TextEditingController();
  final TextEditingController _searchCtrl = TextEditingController();
  bool _quickRateEditedManually = false;
  String _quickRateSourceLabel = '';
  bool _isExpense = true;
  String _catSelection = '';
  String _mode = 'single'; // 'single', 'installment', 'recurring'
  int _installments = 2;
  String _freq = 'monthly';
  String? _customIk;
  bool _filterCardByInvoice = true;
  bool _mobileShowQuickEntry = false;
  bool _mobileShowHeaderTools = false;
  List<PayeeSuggestion> _suggestions = [];

  @override
  void initState() {
    super.initState();
    _checkCreditCardOpenInvoice();
    _syncDefaultCategory();
    _syncQuickRateForDate();
  }

  @override
  void didUpdateWidget(covariant AccountLedgerView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.account.id != widget.account.id) {
      _customIk = null;
      _quickRateEditedManually = false;
      _checkCreditCardOpenInvoice();
      _syncDefaultCategory();
      _syncQuickRateForDate();
    }
  }

  void _checkCreditCardOpenInvoice() {
    final acc = widget.account;
    if (acc.type == kCardType && acc.card != null) {
      final openIk = invKeyFor(acc.card!, todayISO());
      if (widget.store.month.compareTo(openIk) < 0) {
        widget.store.month = openIk;
      }
    } else {
      final curMonth = todayISO().substring(0, 7);
      if (widget.store.month != curMonth) {
        widget.store.month = curMonth;
      }
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
    _quickRateCtrl.dispose();
    _searchCtrl.dispose();
    super.dispose();
  }

  double? _parseQuickRate(String raw) {
    final trimmed = raw.trim().replaceAll(' ', '');
    if (trimmed.isEmpty) return null;
    final normalized = trimmed.contains(',')
        ? trimmed.replaceAll('.', '').replaceAll(',', '.')
        : trimmed;
    final v = double.tryParse(normalized);
    if (v == null || v.isNaN || v <= 0) return null;
    return v;
  }

  void _applyQuickRateDisplay(double rateToBrl, String sourceLabel) {
    final baseCur = widget.store.baseCurrency;
    final baseBrl = baseCur == 'BRL' ? 1.0 : widget.store.rateToBrl(baseCur);
    final displayRate = baseBrl > 0 ? (rateToBrl / baseBrl) : rateToBrl;
    _quickRateCtrl.text = displayRate.toStringAsFixed(4).replaceAll('.', ',');
    _quickRateSourceLabel = sourceLabel;
  }

  void _syncQuickRateForDate() {
    final accCur = widget.account.effectiveCurrency;
    final baseCur = widget.store.baseCurrency;
    if (accCur == 'BRL' || accCur == baseCur) {
      _quickRateCtrl.clear();
      _quickRateSourceLabel = '';
      return;
    }
    final iso = _resolveIsoDate();
    if (iso.compareTo(todayISO()) < 0) {
      final xfer = widget.store.lastTransferRateForAccount(
        widget.account.id,
        onOrBeforeDate: iso,
      );
      if (xfer != null && xfer.rateToBrl > 0) {
        _applyQuickRateDisplay(xfer.rateToBrl, 'Transf. ${fmtDate(xfer.date)}');
        return;
      }
      final cached = CurrencyRateService.cachedHistoricalRate(accCur, iso);
      if (cached != null && cached.rateToBrl > 0) {
        _applyQuickRateDisplay(
          cached.rateToBrl,
          '${cached.source} ${fmtDate(cached.quoteDateIso)}',
        );
        return;
      }
      _applyQuickRateDisplay(widget.store.rateToBrl(accCur), 'Cotação atual');
      CurrencyRateService.fetchHistoricalRateToBrl(accCur, iso).then((res) {
        if (!mounted || res == null || res.rateToBrl <= 0) return;
        if (_quickRateEditedManually) return;
        if (_resolveIsoDate() != iso || widget.account.effectiveCurrency != accCur) {
          return;
        }
        setState(() {
          _applyQuickRateDisplay(
            res.rateToBrl,
            '${res.source} ${fmtDate(res.quoteDateIso)}',
          );
        });
      });
    } else {
      _applyQuickRateDisplay(widget.store.rateToBrl(accCur), 'Cotação atual');
    }
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

  Future<void> _pickDate() async {
    final curIso = _resolveIsoDate();
    final initialDate = dateFromISO(curIso);
    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: DateTime(2000),
      lastDate: DateTime(2099, 12, 31),
    );
    if (picked != null) {
      setState(() {
        _dateCtrl.text = fmtDate(isoFromDate(picked));
        if (!_quickRateEditedManually) {
          _syncQuickRateForDate();
        }
      });
    }
  }

  void _onPayeeChanged(String val) {
    final clean = val.trim();
    final list = widget.store.payeeSuggestions(val);
    final match = widget.store.lastCategoryAndType(clean);
    setState(() {
      _suggestions = list;
      if (match != null) {
        _isExpense = match.isExpense;
        if (match.category.isNotEmpty) {
          _catSelection = match.category;
        }
      }
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

  Future<void> _submitQuickEntry() async {
    if (widget.account.isInactive) return;
    final payee = _payeeCtrl.text.trim();
    final absCents = (parseCents(_amtCtrl.text) ?? 0).abs();
    if (payee.isEmpty || absCents == 0) return;

    final signedAmt = _isExpense ? -absCents : absCents;
    final isoDate = _resolveIsoDate();

    double? txRate;
    final accCur = widget.account.effectiveCurrency;
    final baseCur = widget.store.baseCurrency;
    if (accCur != 'BRL' && accCur != baseCur) {
      final parsedRate = _parseQuickRate(_quickRateCtrl.text);
      if (parsedRate != null && parsedRate > 0) {
        final baseBrl = baseCur == 'BRL' ? 1.0 : widget.store.rateToBrl(baseCur);
        txRate = baseCur == 'BRL' ? parsedRate : (parsedRate * baseBrl);
      }
    }

    final warning = widget.store.checkBudgetExceeded(
      accId: widget.account.id,
      date: isoDate,
      catSelection: _catSelection,
      signedAmt: signedAmt,
      payee: payee,
      mode: _mode,
      installments: _installments,
      txRate: txRate,
    );

    if (warning != null && mounted) {
      final proceed = await showBudgetExceededDialog(context, warning);
      if (!proceed) return;
    }

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
      txRate: txRate,
    );

    if (!mounted) return;
    setState(() {
      _payeeCtrl.clear();
      _memoCtrl.clear();
      _amtCtrl.clear();
      _quickRateEditedManually = false;
      _syncQuickRateForDate();
      _mode = 'single';
      _suggestions = [];
      _mobileShowQuickEntry = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colors = OpenMoneyColors(isDark);
    final acc = widget.account;
    final isCard = acc.type == kCardType && acc.card != null;
    final useInvoiceTxs = isCard && _filterCardByInvoice;
    final monthData = useInvoiceTxs
        ? widget.store.cardInvoiceMonthData(acc.id, widget.store.month)
        : widget.store.accountMonthData(acc.id, widget.store.month);
    final invSummary =
        isCard ? widget.store.invoiceSummary(acc.id, widget.store.month) : null;
    final invTxs = isCard
        ? widget.store.invoiceTransactions(acc.id, widget.store.month)
        : <Transaction>[];
    final pendingCount = widget.store.pendingCountForAccount(acc.id);

    // Search / filter transactions in month
    final q = _searchCtrl.text.trim().toLowerCase();
    final filteredTxs = q.isEmpty
        ? monthData.transactions
        : monthData.transactions.where((t) {
            final amtStr = (t.amt / 100.0).toStringAsFixed(2);
            final amtBrl = formatCurrency(t.amt, acc.effectiveCurrency).toLowerCase();
            return t.payee.toLowerCase().contains(q) ||
                t.memo.toLowerCase().contains(q) ||
                t.cat.toLowerCase().contains(q) ||
                amtStr.contains(q) ||
                amtBrl.contains(q);
          }).toList();

    // Group transactions day by day with running Real and Predicted balances
    final dayGroups = <_DayGroup>[];
    final activeTxs = filteredTxs;
    int runningReal = monthData.openingReal;
    int runningPred = monthData.openingPred;

    for (final tx in activeTxs) {
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

    final displayGroups = widget.store.sortAscendingDate
        ? dayGroups
        : dayGroups.reversed
            .map((g) => _DayGroup(
                  date: g.date,
                  items: g.items.reversed.toList(),
                  closingReal: g.closingReal,
                  closingPred: g.closingPred,
                ))
            .toList();

    final isMobile = MediaQuery.sizeOf(context).width < 720;

    return Column(
      children: [
        // 1. Account Executive Header
        Padding(
          padding: EdgeInsets.fromLTRB(
            isMobile ? 10 : 16,
            isMobile ? 8 : 14,
            isMobile ? 10 : 16,
            isMobile ? 4 : 8,
          ),
          child: GlassCard(
            padding: EdgeInsets.symmetric(
              horizontal: isMobile ? 12 : 16,
              vertical: isMobile ? 10 : 12,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (isMobile) ...[
                  // Layout Mobile Compacto: Nome + Botões de topo
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      AccountLogoWidget(
                        account: acc,
                        size: 36,
                        cornerRadius: 8,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    acc.name,
                                    style: TextStyle(
                                      fontSize: 15.5,
                                      fontWeight: FontWeight.w800,
                                      color: colors.textPrimary,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (acc.isFavorite) ...[
                                  const SizedBox(width: 4),
                                  const Icon(Icons.star,
                                      size: 14, color: Colors.amber),
                                ],
                                if (acc.isInactive) ...[
                                  const SizedBox(width: 4),
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
                                fontSize: 11,
                                color: colors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (!acc.isInactive) ...[
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                          tooltip: 'Novo Lançamento nesta conta',
                          icon: Container(
                            padding: const EdgeInsets.all(5),
                            decoration: BoxDecoration(
                              color: colors.accent.withValues(alpha: 0.16),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              (widget.store.showInlineTransactionEntry && _mobileShowQuickEntry)
                                  ? Icons.close
                                  : Icons.add,
                              size: 16,
                              color: colors.accent,
                            ),
                          ),
                          onPressed: () {
                            if (!widget.store.showInlineTransactionEntry) {
                              showTransactionCreateModal(
                                context,
                                widget.store,
                                initialAccountId: acc.id,
                              );
                            } else {
                              setState(() =>
                                  _mobileShowQuickEntry = !_mobileShowQuickEntry);
                            }
                          },
                        ),
                        const SizedBox(width: 4),
                      ],
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.all(4),
                        constraints: const BoxConstraints(),
                        tooltip: 'Editar Conta',
                        icon: const Icon(Icons.settings_outlined, size: 18),
                        onPressed: () => showAccountModal(
                          context,
                          widget.store,
                          editingAccount: acc,
                        ),
                      ),
                      const SizedBox(width: 4),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        padding: const EdgeInsets.all(4),
                        constraints: const BoxConstraints(),
                        tooltip: 'Opções, Busca e Exportação',
                        icon: Icon(
                          _mobileShowHeaderTools
                              ? Icons.expand_less
                              : Icons.tune,
                          size: 18,
                          color: (_mobileShowHeaderTools ||
                                  _searchCtrl.text.isNotEmpty)
                              ? colors.accent
                              : null,
                        ),
                        onPressed: () => setState(() =>
                            _mobileShowHeaderTools = !_mobileShowHeaderTools),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  // Saldos lado a lado ocupando a largura de forma limpa
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: colors.bgPrimary.withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: colors.borderGlass),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Saldo atual',
                                style: TextStyle(
                                    fontSize: 10.5,
                                    color: colors.textSecondary),
                              ),
                              Text(
                                formatCurrency(
                                  widget.store.balance(acc, predicted: false),
                                  acc.effectiveCurrency,
                                ),
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w800,
                                  color: widget.store.balance(acc,
                                              predicted: false) >=
                                          0
                                      ? colors.income
                                      : colors.expense,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures()
                                  ],
                                ),
                              ),
                              if (acc.effectiveCurrency !=
                                  widget.store.baseCurrency)
                                Text(
                                  '≈ ${formatCurrency(widget.store.convertToBase(widget.store.balance(acc, predicted: false), acc.effectiveCurrency), widget.store.baseCurrency)}',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: colors.textMuted,
                                    fontFeatures: const [
                                      FontFeature.tabularFigures()
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ),
                        Container(
                          width: 1,
                          height: 26,
                          color: colors.borderGlass,
                          margin: const EdgeInsets.symmetric(horizontal: 8),
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                isCard
                                    ? 'Previsto (Fatura)'
                                    : 'Saldo previsto',
                                style: TextStyle(
                                    fontSize: 10.5,
                                    color: colors.textSecondary),
                              ),
                              Text(
                                formatCurrency(
                                  widget.store.balance(acc, predicted: true),
                                  acc.effectiveCurrency,
                                ),
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w800,
                                  color: widget.store.balance(acc,
                                              predicted: true) >=
                                          0
                                      ? colors.income
                                      : colors.expense,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures()
                                  ],
                                ),
                              ),
                              if (acc.effectiveCurrency !=
                                  widget.store.baseCurrency)
                                Text(
                                  '≈ ${formatCurrency(widget.store.convertToBase(widget.store.balance(acc, predicted: true), acc.effectiveCurrency), widget.store.baseCurrency)}',
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: colors.textMuted,
                                    fontFeatures: const [
                                      FontFeature.tabularFigures()
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  // Seletor de Mês/Ano sempre visível de forma compacta
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: MonthYearPickerBar(
                      currentMonthYM: widget.store.month,
                      availableYears: widget.store.allYearsInDatabase(),
                      onMonthChanged: (ym) => widget.store.month = ym,
                    ),
                  ),
                  if (_mobileShowHeaderTools) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        SizedBox(
                          width: 210,
                          height: 34,
                          child: TextField(
                            controller: _searchCtrl,
                            style: const TextStyle(fontSize: 12.5),
                            decoration: InputDecoration(
                              hintText: 'Filtrar no mês...',
                              hintStyle: TextStyle(
                                fontSize: 12,
                                color: colors.textMuted,
                              ),
                              prefixIcon: Icon(
                                Icons.filter_list,
                                size: 16,
                                color: colors.textSecondary,
                              ),
                              suffixIcon: _searchCtrl.text.isNotEmpty
                                  ? IconButton(
                                      icon: const Icon(Icons.clear, size: 14),
                                      onPressed: () =>
                                          setState(() => _searchCtrl.clear()),
                                    )
                                  : null,
                              border: const OutlineInputBorder(),
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 6),
                            ),
                            onChanged: (_) => setState(() {}),
                          ),
                        ),
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            minimumSize: const Size(0, 34),
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                          ),
                          icon: const Icon(Icons.auto_fix_high, size: 14),
                          label: const Text('Previsões',
                              style: TextStyle(fontSize: 11.5)),
                          onPressed: () {
                            final res = widget.store
                                .adjustPredictions(widget.store.month);
                            showPredictionsAdjustModal(context, res);
                          },
                        ),
                        PopupMenuButton<String>(
                          tooltip: 'Modo de abatimento das previsões',
                          icon: const Icon(Icons.tune, size: 18),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                          initialValue: widget.store.db.predMode,
                          onSelected: widget.store.setPredMode,
                          itemBuilder: (_) => const [
                            PopupMenuItem(
                                value: 'month', child: Text('Por mês')),
                            PopupMenuItem(
                                value: 'invoice',
                                child: Text('Por fatura (cartão)')),
                          ],
                        ),
                        Tooltip(
                          message: 'Exportar CSV',
                          child: OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              minimumSize: const Size(36, 34),
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                            ),
                            onPressed: () {
                              final exportTxs = isCard
                                  ? widget.store.invoiceTransactions(
                                      acc.id,
                                      widget.store.month,
                                    )
                                  : monthData.transactions;
                              final safeAccName = acc.name
                                  .toLowerCase()
                                  .replaceAll(' ', '-')
                                  .replaceAll(RegExp(r'[^a-z0-9_-]'), '');
                              final defaultName =
                                  'openmoney-${safeAccName.isEmpty ? "conta" : safeAccName}-${widget.store.month}.csv';
                              final csvContent = CSVExporter.generateCSV(
                                transactions: exportTxs,
                                accounts: widget.store.db.accounts,
                                baseCurrency: widget.store.baseCurrency,
                                rates: widget.store.db.rates,
                                allTransactionsForPairs: widget.store.db.txs,
                              );
                              exportCsvWithFeedback(
                                context,
                                csv: csvContent,
                                defaultName: defaultName,
                                title:
                                    'Exportar Lançamentos de ${acc.name} (CSV)',
                              );
                            },
                            child: const Icon(Icons.download, size: 16),
                          ),
                        ),
                        Tooltip(
                          message: isCard
                              ? 'Exportar Fatura PDF'
                              : 'Exportar Extrato PDF',
                          child: OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              minimumSize: const Size(36, 34),
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                            ),
                            onPressed: () {
                              final exportTxs = isCard
                                  ? widget.store.invoiceTransactions(
                                      acc.id,
                                      widget.store.month,
                                    )
                                  : monthData.transactions;
                              final pdfBytes = PdfReportGenerator
                                  .buildStatementOrInvoicePdfBytes(
                                store: widget.store,
                                account: acc,
                                monthYM: widget.store.month,
                                transactions: exportTxs,
                                invoiceSummary: invSummary,
                              );
                              final defaultName = isCard
                                  ? 'Fatura-${acc.name}-${widget.store.month}.pdf'
                                  : 'Extrato-${acc.name}-${widget.store.month}.pdf';
                              PdfReportGenerator.saveAndOpenPdfBytes(
                                context,
                                pdfBytes: pdfBytes,
                                defaultFileName: defaultName,
                              );
                            },
                            child: const Icon(Icons.picture_as_pdf, size: 16),
                          ),
                        ),
                      ],
                    ),
                  ],
                  if (invSummary != null) ...[
                    const Divider(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      alignment: WrapAlignment.spaceBetween,
                      children: [
                        Text(
                          'Fatura ${fmtMonth(invSummary.key)} • Vence ${fmtDate(invSummary.dueDate)} • Aberto: ${formatCurrency(invSummary.remainingCents, acc.effectiveCurrency)}',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: colors.textPrimary,
                          ),
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            FilterChip(
                              visualDensity: VisualDensity.compact,
                              selectedColor:
                                  colors.accent.withValues(alpha: 0.16),
                              backgroundColor:
                                  colors.bgSecondary.withValues(alpha: 0.5),
                              side: BorderSide(
                                color: _filterCardByInvoice
                                    ? colors.accent.withValues(alpha: 0.35)
                                    : colors.borderGlass,
                              ),
                              labelStyle: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: _filterCardByInvoice
                                    ? colors.accent
                                    : colors.textPrimary,
                              ),
                              checkmarkColor: colors.accent,
                              label: Text(
                                _filterCardByInvoice ? 'Fatura' : 'Mês Civil',
                              ),
                              selected: _filterCardByInvoice,
                              onSelected: (v) =>
                                  setState(() => _filterCardByInvoice = v),
                            ),
                            const SizedBox(width: 6),
                            FilledButton.icon(
                              style: FilledButton.styleFrom(
                                backgroundColor:
                                    colors.accent.withValues(alpha: 0.16),
                                foregroundColor: colors.accent,
                                elevation: 0,
                                side: BorderSide(
                                  color: colors.accent.withValues(alpha: 0.35),
                                ),
                                visualDensity: VisualDensity.compact,
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 4),
                              ),
                              icon:
                                  const Icon(Icons.payments_outlined, size: 14),
                              label: const Text('Pagar Fatura',
                                  style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700)),
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
                    ),
                  ],
                ] else ...[
                // Linha Superior Desktop (Inalterada)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    AccountLogoWidget(
                      account: acc,
                      size: 48,
                      cornerRadius: 10,
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Wrap(
                            spacing: 8,
                            runSpacing: 4,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text(
                                acc.name,
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                  color: colors.textPrimary,
                                ),
                              ),
                              if (acc.isFavorite)
                                const Icon(Icons.star,
                                    size: 16, color: Colors.amber),
                              if (acc.isInactive)
                                StatusBadge(
                                  text: 'INATIVA',
                                  color: colors.warning,
                                ),
                              Text(
                                acc.type,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: colors.textSecondary,
                                ),
                              ),
                              if (acc.effectiveCurrency !=
                                  widget.store.baseCurrency)
                                Builder(builder: (context) {
                                  final cur = acc.effectiveCurrency;
                                  final base = widget.store.baseCurrency;
                                  final meta = currencyMetaFor(cur);
                                  final baseMeta = currencyMetaFor(base);
                                  final rate = widget.store.rateToBase(cur);
                                  final info = widget.store.rateInfoFor(cur);
                                  final dtStr = info != null && info.updatedAt.isNotEmpty
                                      ? ' · ${formatRateDate(info.updatedAt)}'
                                      : '';
                                  return Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color:
                                          colors.accent.withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: colors.accent
                                            .withValues(alpha: 0.35),
                                      ),
                                    ),
                                    child: Text(
                                      '${meta.flag} $cur • 1 $cur ≈ ${baseMeta.symbol} ${rate.toStringAsFixed(4).replaceAll('.', ',')}$dtStr',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: colors.accent,
                                      ),
                                    ),
                                  );
                                }),
                              if (!widget.store.showInlineTransactionEntry && !acc.isInactive)
                                IconButton(
                                  visualDensity: VisualDensity.compact,
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                                  tooltip: 'Novo Lançamento nesta conta',
                                  icon: Container(
                                    padding: const EdgeInsets.all(4),
                                    decoration: BoxDecoration(
                                      color: colors.accent.withValues(alpha: 0.16),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(Icons.add, size: 16, color: colors.accent),
                                  ),
                                  onPressed: () => showTransactionCreateModal(
                                    context,
                                    widget.store,
                                    initialAccountId: acc.id,
                                  ),
                                ),
                              IconButton(
                                tooltip: 'Editar Conta',
                                icon: const Icon(Icons.settings_outlined,
                                    size: 18),
                                onPressed: () => showAccountModal(
                                  context,
                                  widget.store,
                                  editingAccount: acc,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 16),
                    // Lado direito: Saldo atual e Saldo previsto
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        _HeaderBalancePill(
                          label: 'Saldo atual',
                          cents: widget.store.balance(acc, predicted: false),
                          colors: colors,
                          currency: acc.effectiveCurrency,
                          baseCurrency: widget.store.baseCurrency,
                          convertedBaseCents: acc.effectiveCurrency !=
                                  widget.store.baseCurrency
                              ? widget.store.convertToBase(
                                  widget.store.balance(acc, predicted: false),
                                  acc.effectiveCurrency,
                                )
                              : null,
                        ),
                        const SizedBox(width: 14),
                        _HeaderBalancePill(
                          label: isCard
                              ? 'Previsto (Fatura)'
                              : 'Saldo previsto',
                          cents: widget.store.balance(acc, predicted: true),
                          colors: colors,
                          currency: acc.effectiveCurrency,
                          baseCurrency: widget.store.baseCurrency,
                          convertedBaseCents: acc.effectiveCurrency !=
                                  widget.store.baseCurrency
                              ? widget.store.convertToBase(
                                  widget.store.balance(acc, predicted: true),
                                  acc.effectiveCurrency,
                                )
                              : null,
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // Linha de Controles: Seleção de meses, Previsões, Parâmetros, CSV, PDF e Busca
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    MonthYearPickerBar(
                      currentMonthYM: widget.store.month,
                      availableYears: widget.store.allYearsInDatabase(),
                      onMonthChanged: (ym) => widget.store.month = ym,
                    ),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        visualDensity: VisualDensity.compact,
                        minimumSize: const Size(0, 34),
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                      ),
                      icon: const Icon(Icons.auto_fix_high, size: 14),
                      label: const Text('Previsões',
                          style: TextStyle(fontSize: 11.5)),
                      onPressed: () {
                        final res = widget.store
                            .adjustPredictions(widget.store.month);
                        showPredictionsAdjustModal(context, res);
                      },
                    ),
                    PopupMenuButton<String>(
                      tooltip:
                          'Modo de abatimento das previsões: por mês ou por fatura do cartão (mês atual + 2 seguintes)',
                      icon: const Icon(Icons.tune, size: 18),
                      padding: EdgeInsets.zero,
                      constraints:
                          const BoxConstraints(minWidth: 32, minHeight: 32),
                      initialValue: widget.store.db.predMode,
                      onSelected: widget.store.setPredMode,
                      itemBuilder: (_) => const [
                        PopupMenuItem(
                            value: 'month', child: Text('Por mês')),
                        PopupMenuItem(
                            value: 'invoice',
                            child: Text('Por fatura (cartão)')),
                      ],
                    ),
                    Tooltip(
                      message: 'Exportar CSV',
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          minimumSize: const Size(36, 34),
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                        ),
                        onPressed: () {
                          final exportTxs = isCard
                              ? widget.store.invoiceTransactions(
                                  acc.id,
                                  widget.store.month,
                                )
                              : monthData.transactions;
                          final safeAccName = acc.name
                              .toLowerCase()
                              .replaceAll(' ', '-')
                              .replaceAll(RegExp(r'[^a-z0-9_-]'), '');
                          final defaultName =
                              'openmoney-${safeAccName.isEmpty ? "conta" : safeAccName}-${widget.store.month}.csv';
                          final csvContent = CSVExporter.generateCSV(
                            transactions: exportTxs,
                            accounts: widget.store.db.accounts,
                            baseCurrency: widget.store.baseCurrency,
                            rates: widget.store.db.rates,
                            allTransactionsForPairs: widget.store.db.txs,
                          );
                          exportCsvWithFeedback(
                            context,
                            csv: csvContent,
                            defaultName: defaultName,
                            title:
                                'Exportar Lançamentos de ${acc.name} (CSV)',
                          );
                        },
                        child: const Icon(Icons.download, size: 17),
                      ),
                    ),
                    Tooltip(
                      message: isCard
                          ? 'Exportar Fatura PDF'
                          : 'Exportar Extrato PDF',
                      child: OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          minimumSize: const Size(36, 34),
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                        ),
                        onPressed: () {
                          final exportTxs = isCard
                              ? widget.store.invoiceTransactions(
                                  acc.id,
                                  widget.store.month,
                                )
                              : monthData.transactions;
                          final pdfBytes =
                              PdfReportGenerator.buildStatementOrInvoicePdfBytes(
                            store: widget.store,
                            account: acc,
                            monthYM: widget.store.month,
                            transactions: exportTxs,
                            invoiceSummary: invSummary,
                          );
                          final defaultName = isCard
                              ? 'Fatura-${acc.name}-${widget.store.month}.pdf'
                              : 'Extrato-${acc.name}-${widget.store.month}.pdf';
                          PdfReportGenerator.saveAndOpenPdfBytes(
                            context,
                            pdfBytes: pdfBytes,
                            defaultFileName: defaultName,
                          );
                        },
                        child: const Icon(Icons.picture_as_pdf, size: 17),
                      ),
                    ),
                    Container(
                      width: 200,
                      height: 34,
                      decoration: BoxDecoration(
                        color: colors.surfaceGlass,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: colors.borderGlass),
                      ),
                      child: TextField(
                        controller: _searchCtrl,
                        style: const TextStyle(fontSize: 12),
                        textAlignVertical: TextAlignVertical.center,
                        decoration: InputDecoration(
                          hintText: 'Filtrar no mês...',
                          hintStyle: TextStyle(
                            fontSize: 12,
                            color: colors.textMuted,
                          ),
                          prefixIcon: Icon(
                            Icons.filter_list,
                            size: 16,
                            color: colors.textSecondary,
                          ),
                          suffixIcon: _searchCtrl.text.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear, size: 14),
                                  splashRadius: 14,
                                  onPressed: () {
                                    setState(() => _searchCtrl.clear());
                                  },
                                )
                              : null,
                          border: InputBorder.none,
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 8,
                          ),
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                  ],
                ),
                if (invSummary != null) ...[
                  const Divider(height: 18),
                  // Linha 1 da Fatura: Nome da fatura, quando fecha, quando vence, onde debita | Ações da fatura
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    alignment: WrapAlignment.spaceBetween,
                    children: [
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
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
                            '• Fecha: ${fmtDate(invSummary.closeDate)} • Vence: ${fmtDate(invSummary.dueDate)} • Débito: ${invSummary.payAccountName}',
                            style: TextStyle(
                              fontSize: 12,
                              color: colors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          FilterChip(
                            selectedColor:
                                colors.accent.withValues(alpha: 0.16),
                            backgroundColor:
                                colors.bgSecondary.withValues(alpha: 0.5),
                            side: BorderSide(
                              color: _filterCardByInvoice
                                  ? colors.accent.withValues(alpha: 0.35)
                                  : colors.borderGlass,
                            ),
                            labelStyle: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: _filterCardByInvoice
                                  ? colors.accent
                                  : colors.textPrimary,
                            ),
                            checkmarkColor: colors.accent,
                            label: Text(
                              _filterCardByInvoice
                                  ? 'Exibindo Fatura (${invTxs.length} lanç.)'
                                  : 'Exibindo Mês Civil (${monthData.transactions.length} lanç.)',
                            ),
                            selected: _filterCardByInvoice,
                            onSelected: (v) =>
                                setState(() => _filterCardByInvoice = v),
                          ),
                          FilledButton.icon(
                            style: FilledButton.styleFrom(
                              backgroundColor:
                                  colors.accent.withValues(alpha: 0.16),
                              foregroundColor: colors.accent,
                              elevation: 0,
                              side: BorderSide(
                                color: colors.accent.withValues(alpha: 0.35),
                              ),
                              visualDensity: VisualDensity.compact,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 8),
                            ),
                            icon: const Icon(Icons.payments_outlined, size: 16),
                            label: const Text('Pagar / Adiantar Fatura',
                                style: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w700)),
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
                  ),
                  const SizedBox(height: 6),
                  // Linha 2 da Fatura: Valores na nova linha com fonte equalizada (12px)
                  Wrap(
                    spacing: 14,
                    runSpacing: 6,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        'Compras: ${formatCurrency(invSummary.chargesCents, acc.effectiveCurrency)}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: colors.expense,
                        ),
                      ),
                      if (invSummary.paymentsCents > 0)
                        Text(
                          'Pago: ${formatCurrency(invSummary.paymentsCents, acc.effectiveCurrency)}',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: colors.income,
                          ),
                        ),
                      Text(
                        'Em Aberto: ${formatCurrency(invSummary.remainingCents, acc.effectiveCurrency)}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: invSummary.remainingCents > 0
                              ? colors.expense
                              : colors.textPrimary,
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
                ],
                ],
                if (pendingCount > 0) ...[
                  SizedBox(height: isMobile ? 6 : 10),
                  InkWell(
                    borderRadius: BorderRadius.circular(10),
                    onTap: () {
                      widget.store.navigateTo(NavModule.dueBills);
                    },
                    child: Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: isMobile ? 10 : 12,
                        vertical: isMobile ? 6 : 8,
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
                              isMobile
                                  ? '$pendingCount pendente(s) nos próximos ${widget.store.reminderDaysAhead} dias.'
                                  : 'Você possui $pendingCount lançamento(s) pendente(s) de conciliação nos próximos ${widget.store.reminderDaysAhead} dias nesta conta.',
                              style: TextStyle(
                                fontSize: isMobile ? 11.5 : 12,
                                fontWeight: FontWeight.w600,
                                color: colors.warning,
                              ),
                            ),
                          ),
                          Text(
                            isMobile ? 'Ver →' : 'Ver Vencimentos →',
                            style: TextStyle(
                              fontSize: isMobile ? 11.5 : 12,
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

        // 2. Quick Entry Bar (Barra de Inserção Rápida — recolhível no celular para liberar espaço para rolar os lançamentos)
        if (!acc.isInactive && widget.store.showInlineTransactionEntry && (!isMobile || _mobileShowQuickEntry))
          Padding(
            padding: EdgeInsets.symmetric(
              horizontal: isMobile ? 10 : 16,
              vertical: 4,
            ),
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
                      Padding(
                        padding: const EdgeInsets.only(top: 2.0),
                        child: SizedBox(
                          height: 30,
                          child: FilledButton.tonal(
                            style: FilledButton.styleFrom(
                              backgroundColor: (_isExpense ? colors.expense : colors.income)
                                  .withValues(alpha: 0.16),
                              foregroundColor:
                                  _isExpense ? colors.expense : colors.income,
                              padding: const EdgeInsets.symmetric(horizontal: 14),
                              shape: StadiumBorder(
                                side: BorderSide(
                                  color: _isExpense ? colors.expense : colors.income,
                                ),
                              ),
                              textStyle: const TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 12,
                              ),
                            ),
                            onPressed: () {
                              setState(() {
                                _isExpense = !_isExpense;
                                _syncDefaultCategory();
                              });
                            },
                            child: Text(
                              _isExpense ? '− Despesa' : '+ Receita',
                            ),
                          ),
                        ),
                      ),
                      SizedBox(
                        width: 118,
                        child: TextField(
                          controller: _dateCtrl,
                          style: const TextStyle(fontSize: 13),
                          onChanged: (val) {
                            final trimmed = val.trim();
                            if (RegExp(r'^\d{2}/\d{2}/\d{4}$').hasMatch(trimmed) ||
                                RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(trimmed)) {
                              if (!_quickRateEditedManually) {
                                setState(() => _syncQuickRateForDate());
                              }
                            }
                          },
                          decoration: InputDecoration(
                            labelText: 'Data',
                            labelStyle: const TextStyle(fontSize: 13),
                            isDense: true,
                            contentPadding: const EdgeInsets.fromLTRB(8, 10, 2, 10),
                            border: const OutlineInputBorder(),
                            suffixIconConstraints: const BoxConstraints(
                              minWidth: 24,
                              maxHeight: 24,
                            ),
                            suffixIcon: IconButton(
                              icon: const Icon(Icons.calendar_month, size: 17),
                              tooltip: 'Escolher data no calendário',
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(),
                              onPressed: _pickDate,
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
                            labelStyle: TextStyle(fontSize: 13),
                            hintText: 'Ex.: Supermercado, Previsão...',
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 10,
                            ),
                            border: OutlineInputBorder(),
                          ),
                          onChanged: _onPayeeChanged,
                          onSubmitted: (_) => _submitQuickEntry(),
                        ),
                      ),
                      CategorySelectFormField(
                        store: widget.store,
                        categoryType: _isExpense ? 'Despesa' : 'Receita',
                        currentSelection: _catSelection,
                        excludeAccountId: acc.id,
                        width: 230,
                        onChanged: (val) {
                          setState(() => _catSelection = val);
                        },
                      ),
                      SizedBox(
                        width: 150,
                        child: TextField(
                          controller: _memoCtrl,
                          style: const TextStyle(fontSize: 13),
                          decoration: const InputDecoration(
                            labelText: 'Nota',
                            labelStyle: TextStyle(fontSize: 13),
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 10,
                            ),
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
                          decoration: InputDecoration(
                            labelText:
                                'Valor (${currencyMetaFor(acc.effectiveCurrency).symbol})',
                            labelStyle: const TextStyle(fontSize: 13),
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 10,
                            ),
                            border: const OutlineInputBorder(),
                          ),
                          onSubmitted: (_) => _submitQuickEntry(),
                        ),
                      ),
                      if (acc.effectiveCurrency != 'BRL' &&
                          acc.effectiveCurrency != widget.store.baseCurrency)
                        Tooltip(
                          message: _quickRateSourceLabel.isEmpty
                              ? 'Cotação para conversão na moeda padrão'
                              : 'Origem da sugestão: $_quickRateSourceLabel',
                          child: SizedBox(
                            width: 106,
                            child: TextField(
                              controller: _quickRateCtrl,
                              style: const TextStyle(fontSize: 13),
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                decimal: true,
                              ),
                              onChanged: (_) {
                                _quickRateEditedManually = true;
                                _quickRateSourceLabel = 'Manual';
                              },
                              onSubmitted: (_) => _submitQuickEntry(),
                              decoration: InputDecoration(
                                labelText:
                                    'Taxa (${currencyMetaFor(widget.store.baseCurrency).symbol})',
                                labelStyle: const TextStyle(fontSize: 12),
                                isDense: true,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 10,
                                ),
                                border: const OutlineInputBorder(),
                              ),
                            ),
                          ),
                        ),
                      SizedBox(
                        width: 118,
                        child: DropdownButtonFormField<String>(
                          initialValue: _mode,
                          isExpanded: true,
                          style: TextStyle(
                            fontSize: 13,
                            color: colors.textPrimary,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Modalidade',
                            labelStyle: TextStyle(fontSize: 13),
                            isDense: true,
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 8,
                            ),
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: 'single',
                              child: Text('Único',
                                  style: TextStyle(fontSize: 13),
                                  overflow: TextOverflow.ellipsis),
                            ),
                            DropdownMenuItem(
                              value: 'installment',
                              child: Text('Parcelado',
                                  style: TextStyle(fontSize: 13),
                                  overflow: TextOverflow.ellipsis),
                            ),
                            DropdownMenuItem(
                              value: 'recurring',
                              child: Text('Recorrente',
                                  style: TextStyle(fontSize: 13),
                                  overflow: TextOverflow.ellipsis),
                            ),
                          ],
                          onChanged: (v) {
                            if (v != null) setState(() => _mode = v);
                          },
                        ),
                      ),
                      if (_mode == 'installment')
                        SizedBox(
                          width: 88,
                          child: DropdownButtonFormField<int>(
                            initialValue: _installments,
                            isExpanded: true,
                            style: TextStyle(
                              fontSize: 13,
                              color: colors.textPrimary,
                            ),
                            decoration: const InputDecoration(
                              labelText: 'Parcelas',
                              labelStyle: TextStyle(fontSize: 13),
                              isDense: true,
                              border: OutlineInputBorder(),
                              contentPadding: EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 8,
                              ),
                            ),
                            items: List.generate(
                              47,
                              (i) => DropdownMenuItem(
                                value: i + 2,
                                child: Text('${i + 2}x',
                                    style: const TextStyle(fontSize: 13)),
                              ),
                            ),
                            onChanged: (v) {
                              if (v != null) setState(() => _installments = v);
                            },
                          ),
                        ),
                      if (_mode == 'recurring')
                        SizedBox(
                          width: 120,
                          child: DropdownButtonFormField<String>(
                            initialValue: _freq,
                            isExpanded: true,
                            style: TextStyle(
                              fontSize: 13,
                              color: colors.textPrimary,
                            ),
                            decoration: const InputDecoration(
                              labelText: 'Frequência',
                              labelStyle: TextStyle(fontSize: 13),
                              isDense: true,
                              border: OutlineInputBorder(),
                              contentPadding: EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 8,
                              ),
                            ),
                            items: kRecurrenceFrequencyOptions
                                .map(
                                  (o) => DropdownMenuItem(
                                    value: o.id,
                                    child: Text(
                                      o.label,
                                      style: const TextStyle(fontSize: 13),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                )
                                .toList(),
                            onChanged: (v) {
                              if (v != null) setState(() => _freq = v);
                            },
                          ),
                        ),
                      Padding(
                        padding: const EdgeInsets.only(top: 2.0),
                        child: SizedBox(
                          height: 30,
                          child: FilledButton.icon(
                            style: FilledButton.styleFrom(
                              padding: const EdgeInsets.symmetric(horizontal: 14),
                              shape: const StadiumBorder(),
                              textStyle: const TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            icon: const Icon(Icons.check, size: 18),
                            label: const Text('Salvar'),
                            onPressed: _submitQuickEntry,
                          ),
                        ),
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
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          Text(
                            'Real: ${formatCurrency(monthData.openingReal, acc.effectiveCurrency)}',
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
                            'Previsto: ${formatCurrency(monthData.openingPred, acc.effectiveCurrency)}',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: colors.textSecondary,
                              fontFeatures: const [
                                FontFeature.tabularFigures()
                              ],
                            ),
                          ),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                visualDensity: VisualDensity.compact,
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                                tooltip: widget.store.sortAscendingDate
                                    ? 'Ordem de Data: Mais antigos primeiro (Clique para Mais recentes primeiro)'
                                    : 'Ordem de Data: Mais recentes primeiro (Clique para Mais antigos primeiro)',
                                icon: Icon(
                                  widget.store.sortAscendingDate
                                      ? Icons.arrow_upward_rounded
                                      : Icons.arrow_downward_rounded,
                                  size: 16,
                                  color: colors.accent,
                                ),
                                onPressed: widget.store.toggleSortAscendingDate,
                              ),
                              const SizedBox(width: 8),
                              Container(
                                height: 14,
                                width: 1,
                                color: colors.borderGlass,
                              ),
                              const SizedBox(width: 8),
                              IconButton(
                                visualDensity: VisualDensity.compact,
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                                tooltip: 'Visualização em Lista Diária',
                                icon: Icon(
                                  Icons.view_agenda_outlined,
                                  size: 16,
                                  color: widget.store.ledgerViewMode == 'list'
                                      ? colors.accent
                                      : colors.textMuted,
                                ),
                                onPressed: () =>
                                    widget.store.setLedgerViewMode('list'),
                              ),
                              const SizedBox(width: 4),
                              IconButton(
                                visualDensity: VisualDensity.compact,
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                                tooltip: 'Visualização em Tabela Datagrid',
                                icon: Icon(
                                  Icons.table_chart_outlined,
                                  size: 16,
                                  color: widget.store.ledgerViewMode == 'table'
                                      ? colors.accent
                                      : colors.textMuted,
                                ),
                                onPressed: () =>
                                    widget.store.setLedgerViewMode('table'),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              if (widget.store.ledgerViewMode == 'table')
                DatagridTransactionTable(
                  transactions: widget.store.sortAscendingDate
                      ? filteredTxs
                      : filteredTxs.reversed.toList(),
                  store: widget.store,
                  showAccountColumn: false,
                )
              else ...[
                if (displayGroups.isEmpty)
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
                            _searchCtrl.text.trim().isNotEmpty
                                ? 'Nenhum lançamento encontrado para "${_searchCtrl.text.trim()}".'
                                : 'Nenhum lançamento em ${fmtMonth(widget.store.month)}.',
                            style: TextStyle(color: colors.textSecondary),
                          ),
                          if (_searchCtrl.text.trim().isNotEmpty) ...[
                            const SizedBox(height: 8),
                            TextButton.icon(
                              icon: const Icon(Icons.clear, size: 14),
                              label: const Text('Limpar filtro'),
                              onPressed: () {
                                setState(() => _searchCtrl.clear());
                              },
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ...displayGroups.map((group) {
                return GlassCard(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: EdgeInsets.zero,
                  child: Column(
                    children: [
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
                            contentPadding: isMobile
                                ? const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 2)
                                : null,
                            horizontalTitleGap: isMobile ? 6 : null,
                            onTap: () => showTransactionEditModal(
                              context,
                              widget.store,
                              tx,
                            ),
                            leading: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  visualDensity:
                                      isMobile ? VisualDensity.compact : null,
                                  padding: isMobile
                                      ? const EdgeInsets.all(4)
                                      : null,
                                  constraints: isMobile
                                      ? const BoxConstraints()
                                      : null,
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
                                    size: isMobile ? 19 : 20,
                                  ),
                                  onPressed: () =>
                                      widget.store.toggleReconciled(tx.id),
                                ),
                                Container(
                                  width: isMobile ? 22 : 26,
                                  alignment: Alignment.center,
                                  child: Text(
                                    tx.date.split('-').last,
                                    style: TextStyle(
                                      fontSize: isMobile ? 11.5 : 12.5,
                                      fontWeight: FontWeight.w700,
                                      color: colors.textSecondary,
                                      fontFeatures: const [
                                        FontFeature.tabularFigures()
                                      ],
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            title: isMobile
                                ? Text(
                                    tx.payee,
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13,
                                      color: colors.textPrimary,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  )
                                : Row(
                              children: [
                                Flexible(
                                  flex: 3,
                                  child: Text(
                                    tx.payee,
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      fontSize: 13.5,
                                      color: colors.textPrimary,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 6),
                                  child: Text(
                                    '•',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: colors.textMuted,
                                    ),
                                  ),
                                ),
                                Flexible(
                                  flex: 4,
                                  child: Text(
                                    tx.cat.isEmpty ? 'Sem categoria' : tx.cat,
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: FontWeight.w500,
                                      color: tx.cat.isEmpty
                                          ? colors.textMuted
                                          : colors.textSecondary,
                                      fontStyle: tx.cat.isEmpty
                                          ? FontStyle.italic
                                          : FontStyle.normal,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (isPred) ...[
                                  const SizedBox(width: 5),
                                  StatusBadge(
                                    text: 'PREVISÃO',
                                    color: colors.accentCyan,
                                    fontSize: 8.5,
                                  ),
                                ],
                                if (tx.recId != null) ...[
                                  const SizedBox(width: 5),
                                  StatusBadge(
                                    text: recurrenceFrequencyLabel(tx.recFreq)
                                        .toUpperCase(),
                                    color: colors.accent,
                                    icon: Icons.repeat,
                                    fontSize: 8.5,
                                  ),
                                ],
                                if (tx.auto == true) ...[
                                  const SizedBox(width: 5),
                                  StatusBadge(
                                    text: 'FATURA AUTO',
                                    color: colors.warning,
                                    fontSize: 8.5,
                                  ),
                                ],
                                if (tx.ik != null && tx.ik!.isNotEmpty && tx.auto != true) ...[
                                  const SizedBox(width: 5),
                                  StatusBadge(
                                    text: 'FATURA ${formatInvoiceKeyForDisplay(tx.ik!)}',
                                    color: colors.accentIndigo,
                                    icon: Icons.receipt_outlined,
                                    fontSize: 8.5,
                                  ),
                                ],
                              ],
                            ),
                            subtitle: isMobile
                                ? Padding(
                                    padding: const EdgeInsets.only(top: 2),
                                    child: Wrap(
                                      spacing: 4,
                                      runSpacing: 3,
                                      crossAxisAlignment:
                                          WrapCrossAlignment.center,
                                      children: [
                                        Text(
                                          tx.cat.isEmpty
                                              ? 'Sem categoria'
                                              : tx.cat,
                                          style: TextStyle(
                                            fontSize: 11.5,
                                            fontWeight: FontWeight.w500,
                                            color: tx.cat.isEmpty
                                                ? colors.textMuted
                                                : colors.textSecondary,
                                            fontStyle: tx.cat.isEmpty
                                                ? FontStyle.italic
                                                : FontStyle.normal,
                                          ),
                                        ),
                                        if (tx.memo.trim().isNotEmpty)
                                          Text(
                                            '• ${tx.memo.trim()}',
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: colors.textSecondary,
                                            ),
                                          ),
                                        if (isPred)
                                          StatusBadge(
                                            text: 'PREVISÃO',
                                            color: colors.accentCyan,
                                            fontSize: 8.5,
                                          ),
                                        if (tx.recId != null)
                                          StatusBadge(
                                            text: recurrenceFrequencyLabel(
                                                    tx.recFreq)
                                                .toUpperCase(),
                                            color: colors.accent,
                                            icon: Icons.repeat,
                                            fontSize: 8.5,
                                          ),
                                        if (tx.auto == true)
                                          StatusBadge(
                                            text: 'FATURA AUTO',
                                            color: colors.warning,
                                            fontSize: 8.5,
                                          ),
                                        if (tx.ik != null &&
                                            tx.ik!.isNotEmpty &&
                                            tx.auto != true)
                                          StatusBadge(
                                            text:
                                                'FAT. ${formatInvoiceKeyForDisplay(tx.ik!)}',
                                            color: colors.accentIndigo,
                                            fontSize: 8.5,
                                          ),
                                      ],
                                    ),
                                  )
                                : (tx.memo.trim().isNotEmpty
                                    ? Padding(
                                        padding: const EdgeInsets.only(top: 2),
                                        child: Text(
                                          tx.memo.trim(),
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: colors.textSecondary,
                                          ),
                                        ),
                                      )
                                    : null),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  formatCurrency(tx.amt, acc.effectiveCurrency),
                                  style: TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: isMobile ? 13 : 14,
                                    color: tx.amt >= 0
                                        ? colors.income
                                        : colors.expense,
                                    fontFeatures: const [
                                      FontFeature.tabularFigures()
                                    ],
                                  ),
                                ),
                                SizedBox(width: isMobile ? 2 : 4),
                                if (tx.auto != true) ...[
                                  IconButton(
                                    visualDensity:
                                        isMobile ? VisualDensity.compact : null,
                                    padding: isMobile
                                        ? const EdgeInsets.all(3)
                                        : null,
                                    constraints: isMobile
                                        ? const BoxConstraints()
                                        : null,
                                    tooltip: 'Copiar Lançamento',
                                    icon: Icon(
                                      Icons.copy_rounded,
                                      size: isMobile ? 15 : 16,
                                      color: colors.textMuted,
                                    ),
                                    onPressed: () => showTransactionCopyModal(
                                      context,
                                      widget.store,
                                      tx,
                                    ),
                                  ),
                                  if (!isMobile) const SizedBox(width: 2),
                                ],
                                IconButton(
                                  visualDensity:
                                      isMobile ? VisualDensity.compact : null,
                                  padding:
                                      isMobile ? const EdgeInsets.all(3) : null,
                                  constraints: isMobile
                                      ? const BoxConstraints()
                                      : null,
                                  tooltip: 'Excluir Lançamento',
                                  icon: Icon(
                                    Icons.delete_outline,
                                    size: isMobile ? 16 : 17,
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
                      // Day Footer with Closing Real & Predicted Balances
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 7,
                        ),
                        decoration: BoxDecoration(
                          color: colors.bgPrimary.withValues(alpha: 0.35),
                          borderRadius: const BorderRadius.only(
                            bottomLeft: Radius.circular(12),
                            bottomRight: Radius.circular(12),
                          ),
                          border: Border(
                            top: BorderSide(color: colors.borderGlass),
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
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w800,
                                  color: colors.accent,
                                ),
                              ),
                              Wrap(
                                spacing: 14,
                                children: [
                                  Text(
                                    'Saldo Real: ${formatCurrency(group.closingReal, acc.effectiveCurrency)}',
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
                                    'Previsto: ${formatCurrency(group.closingPred, acc.effectiveCurrency)}',
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
                    ],
                  ),
                );
              }),
            ],
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
  final String currency;
  final String? baseCurrency;
  final int? convertedBaseCents;

  const _HeaderBalancePill({
    required this.label,
    required this.cents,
    required this.colors,
    this.currency = 'BRL',
    this.baseCurrency,
    this.convertedBaseCents,
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
          formatCurrency(cents, currency),
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w800,
            color: valColor,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
        if (convertedBaseCents != null && baseCurrency != null)
          Text(
            '≈ ${formatCurrency(convertedBaseCents!, baseCurrency!)}',
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w500,
              color: colors.textMuted,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
      ],
    );
  }
}
