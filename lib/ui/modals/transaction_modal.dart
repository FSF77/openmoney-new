import 'package:flutter/material.dart';
import '../../models/openmoney_models.dart';
import '../../services/currency_rate_service.dart';
import '../../store/money_store.dart';
import '../theme/liquid_glass.dart';
import '../widgets/category_select_form_field.dart';
import '../widgets/tag_input_field.dart';

Future<void> showTransactionCreateModal(
  BuildContext context,
  MoneyStore store, {
  String? initialAccountId,
  String? initialDateIso,
  String? initialPayee,
  int? initialAmountCents,
  String? initialCategory,
  String? initialMemo,
  bool? initialIsExpense,
  String? shortcutRawAccountName,
  bool fromShortcut = false,
}) async {
  await showDialog(
    context: context,
    builder: (ctx) => _TransactionCreateDialog(
      store: store,
      initialAccountId: initialAccountId,
      initialDateIso: initialDateIso,
      initialPayee: initialPayee,
      initialAmountCents: initialAmountCents,
      initialCategory: initialCategory,
      initialMemo: initialMemo,
      initialIsExpense: initialIsExpense,
      shortcutRawAccountName: shortcutRawAccountName,
      fromShortcut: fromShortcut,
    ),
  );
}

Future<void> showTransactionEditModal(
  BuildContext context,
  MoneyStore store,
  Transaction tx,
) async {
  await showDialog(
    context: context,
    builder: (ctx) => _TransactionEditDialog(store: store, tx: tx),
  );
}

Future<void> showTransactionCopyModal(
  BuildContext context,
  MoneyStore store,
  Transaction tx,
) async {
  await showDialog(
    context: context,
    builder: (ctx) => _TransactionCopyDialog(store: store, sourceTx: tx),
  );
}

Future<void> showDeleteTransactionDialog(
  BuildContext context,
  MoneyStore store,
  Transaction tx,
) async {
  if (tx.auto == true) return;
  final isSeries = tx.recId != null || tx.plan != null;
  final txCur =
      store.accById(tx.acc)?.effectiveCurrency ?? store.baseCurrency;

  if (!isSeries) {
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Excluir Lançamento'),
        content: Text(
          'Confirma a exclusão de "${tx.payee}" (${formatCurrency(tx.amt, txCur)}) em ${fmtDate(tx.date)}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () {
              store.deleteTransaction(tx.id, ScopeChoice.only);
              Navigator.pop(ctx);
            },
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    return;
  }

  await showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Excluir Lançamento em Série'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '"${tx.payee}" (${formatCurrency(tx.amt, txCur)}) faz parte de uma série ${tx.recId != null ? "recorrente" : "parcelada"}.\n\nNota: Lançamentos já conciliados nunca são excluídos em lote.',
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancelar'),
        ),
        OutlinedButton(
          onPressed: () {
            store.deleteTransaction(tx.id, ScopeChoice.only);
            Navigator.pop(ctx);
          },
          child: const Text('Apenas este'),
        ),
        OutlinedButton(
          onPressed: () {
            store.deleteTransaction(tx.id, ScopeChoice.forward);
            Navigator.pop(ctx);
          },
          child: const Text('Este e futuros não conciliados'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
          onPressed: () {
            store.deleteTransaction(tx.id, ScopeChoice.all);
            Navigator.pop(ctx);
          },
          child: const Text('Toda a série'),
        ),
      ],
    ),
  );
}

/// Alerta de confirmação exibido quando um lançamento ultrapassa o limite de gastos definido para o mês da categoria.
Future<bool> showBudgetExceededDialog(
  BuildContext context,
  BudgetCheckResult warning,
) async {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  final colors = OpenMoneyColors(isDark);

  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Row(
        children: [
          Icon(Icons.warning_amber_rounded, color: Colors.amber, size: 24),
          SizedBox(width: 8),
          Text(
            'Limite de Gastos Excedido',
            style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
          ),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'A categoria "${warning.categoryPath}" ultrapassará o limite de gastos definido para o mês de ${warning.monthLabel}.',
              style: const TextStyle(fontSize: 13, height: 1.4),
            ),
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: colors.borderGlass),
              ),
              child: Column(
                children: [
                  _budgetRow('Limite definido:', formatCurrency(warning.budgetCents, warning.currency)),
                  const SizedBox(height: 4),
                  _budgetRow('Gasto atual no mês:', formatCurrency(warning.currentSpentCents, warning.currency)),
                  const SizedBox(height: 4),
                  _budgetRow('Saldo disponível:', formatCurrency(warning.availableBeforeCents, warning.currency)),
                  const SizedBox(height: 4),
                  _budgetRow('Valor deste lançamento:', formatCurrency(warning.newAmountCents, warning.currency)),
                  const Divider(height: 14),
                  _budgetRow(
                    'Valor excedente:',
                    formatCurrency(warning.excessCents, warning.currency),
                    valueColor: Colors.redAccent,
                    isBold: true,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            const Text(
              'Deseja realmente continuar com este lançamento?',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Continuar'),
        ),
      ],
    ),
  );
  return result ?? false;
}

Widget _budgetRow(String label, String value, {Color? valueColor, bool isBold = false}) {
  return Row(
    mainAxisAlignment: MainAxisAlignment.spaceBetween,
    children: [
      Text(
        label,
        style: TextStyle(
          fontSize: 12,
          color: isBold ? null : Colors.grey,
          fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      Text(
        value,
        style: TextStyle(
          fontSize: 12,
          fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
          color: valueColor,
        ),
      ),
    ],
  );
}

class _TransactionEditDialog extends StatefulWidget {
  final MoneyStore store;
  final Transaction tx;

  const _TransactionEditDialog({
    required this.store,
    required this.tx,
  });

  @override
  State<_TransactionEditDialog> createState() => _TransactionEditDialogState();
}

class _TransactionEditDialogState extends State<_TransactionEditDialog> {
  late String _accId;
  late final TextEditingController _dateCtrl;
  late final TextEditingController _payeeCtrl;
  late final TextEditingController _memoCtrl;
  late final TextEditingController _amtCtrl;
  late final TextEditingController _peerAmtCtrl;
  late final TextEditingController _rateCtrl;
  late bool _isExpense;
  late String _catSelection;
  late String? _customIk;
  List<String> _tags = [];
  ScopeChoice _scope = ScopeChoice.only;
  bool _isUpdatingCross = false;

  @override
  void initState() {
    super.initState();
    final t = widget.tx;
    _accId = t.acc;
    _dateCtrl = TextEditingController(text: fmtDate(t.date));
    _payeeCtrl = TextEditingController(text: t.payee);
    _memoCtrl = TextEditingController(text: t.memo);
    _amtCtrl = TextEditingController(text: formatInputCents(t.amt));
    _isExpense = t.amt < 0;
    if (t.peer != null && t.xfer != null) {
      _catSelection = 'xfer:${t.peer}';
    } else {
      _catSelection = t.cat;
    }
    _customIk = t.ik;
    _tags = List<String>.from(t.tags ?? const []);

    // Inicializar campos cross-currency caso seja transferência entre moedas distintas
    int peerAbs = 0;
    if (t.xfer != null) {
      for (final candidate in widget.store.db.txs) {
        if (candidate.xfer == t.xfer && candidate.id != t.id) {
          peerAbs = candidate.amt.abs();
          break;
        }
      }
    }
    _peerAmtCtrl = TextEditingController(
      text: peerAbs > 0 ? formatInputCents(peerAbs) : '',
    );

    final curAcc = widget.store.accById(_accId);
    final curCur = curAcc?.effectiveCurrency ?? 'BRL';
    String destCur = curCur;
    if (_catSelection.startsWith('xfer:')) {
      final peerId = _catSelection.substring(5);
      destCur = widget.store.accById(peerId)?.effectiveCurrency ?? 'BRL';
    }
    final double initRate;
    if (curCur != destCur && t.amt.abs() > 0 && peerAbs > 0) {
      initRate = peerAbs / t.amt.abs();
    } else if (curCur != destCur) {
      initRate = exchangeRateBetween(
        fromCurrency: curCur,
        toCurrency: destCur,
        rates: widget.store.db.rates,
      );
    } else {
      final baseCur = widget.store.baseCurrency;
      final baseBrl =
          baseCur == 'BRL' ? 1.0 : widget.store.rateToBrl(baseCur);
      final rawBrlRate = (t.rate != null && t.rate! > 0)
          ? t.rate!
          : widget.store.rateToBrl(curCur);
      initRate = baseBrl > 0 ? (rawBrlRate / baseBrl) : rawBrlRate;
    }
    _rateCtrl = TextEditingController(
      text: initRate.toStringAsFixed(4).replaceAll('.', ','),
    );
  }

  @override
  void dispose() {
    _dateCtrl.dispose();
    _payeeCtrl.dispose();
    _memoCtrl.dispose();
    _amtCtrl.dispose();
    _peerAmtCtrl.dispose();
    _rateCtrl.dispose();
    super.dispose();
  }

  String _resolveIsoDate() {
    final raw = _dateCtrl.text.trim();
    if (RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(raw)) return raw;
    final parts = raw.split('/');
    if (parts.length == 3) {
      return '${parts[2].padLeft(4, '0')}-${parts[1].padLeft(2, '0')}-${parts[0].padLeft(2, '0')}';
    }
    return widget.tx.date;
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
        final targetAcc = widget.store.accById(_accId);
        if (targetAcc?.type == kCardType && targetAcc?.card != null) {
          _customIk = invKeyFor(targetAcc!.card!, isoFromDate(picked));
        }
      });
    }
  }

  Future<void> _handleSave() async {
    final isReconciledPast =
        widget.tx.rec && widget.tx.date.compareTo(todayISO()) < 0;
    if (isReconciledPast) {
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Lançamento Já Conciliado'),
          content: Text(
            'Este lançamento já está conciliado e possui data anterior a hoje (${fmtDate(widget.tx.date)}).\n\nDeseja realmente salvar as alterações?',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Salvar Alterações'),
            ),
          ],
        ),
      );
      if (confirm != true) return;
    }

    final isoDate = _resolveIsoDate();
    final absCents = (parseCents(_amtCtrl.text) ?? 0).abs();
    final signedAmt = _isExpense ? -absCents : absCents;

    int? peerSignedAmt;
    double? txRate;
    final curAcc = widget.store.accById(_accId);
    final curCur = curAcc?.effectiveCurrency ?? 'BRL';
    if (_catSelection.startsWith('xfer:')) {
      final peerId = _catSelection.substring(5);
      final peerAcc = widget.store.accById(peerId);
      final peerCur = peerAcc?.effectiveCurrency ?? 'BRL';
      if (curCur != peerCur) {
        final peerAbs = (parseCents(_peerAmtCtrl.text) ?? 0).abs();
        if (peerAbs > 0) {
          peerSignedAmt = signedAmt < 0 ? peerAbs : -peerAbs;
          if (curCur == 'BRL' && absCents > 0) {
            txRate = null;
          } else if (peerCur == 'BRL' && absCents > 0) {
            txRate = peerAbs / absCents;
          }
        }
      }
    } else if (curCur != 'BRL') {
      txRate = _resolveNonXferRateToBrl(
        widget.store,
        _rateCtrl,
        _accId,
        curCur,
        isoDate,
      );
    }

    widget.store.updateTransaction(
      txId: widget.tx.id,
      newAccId: _accId,
      newDate: isoDate,
      newPayee: _payeeCtrl.text.trim(),
      newCatSelection: _catSelection,
      newMemo: _memoCtrl.text.trim(),
      newSignedAmt: signedAmt,
      scope: _scope,
      newIk: _customIk,
      peerSignedAmt: peerSignedAmt,
      txRate: txRate,
      newTags: _tags,
    );
    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colors = OpenMoneyColors(isDark);
    final isSeries = widget.tx.recId != null || widget.tx.plan != null;
    final targetAcc = widget.store.accById(_accId);
    final isCard = targetAcc?.type == kCardType && targetAcc?.card != null;

    final catType = _isExpense ? 'Despesa' : 'Receita';
    final catOptions = widget.store.allCategoryOptions(catType);
    final otherAccounts =
        widget.store.transferDestinationAccounts(excludeId: _accId);

    final dropdownItems = <DropdownMenuItem<String>>[
      if (_catSelection.isNotEmpty &&
          !catOptions.any((c) => c.value == _catSelection) &&
          !_catSelection.startsWith('xfer:'))
        DropdownMenuItem(value: _catSelection, child: Text(_catSelection)),
      ...catOptions.map(
        (c) => DropdownMenuItem(value: c.value, child: Text(c.label)),
      ),
      ...otherAccounts.map(
        (a) => DropdownMenuItem(
          value: 'xfer:${a.id}',
          child: Text('⇄ Transferência: ${a.name}'),
        ),
      ),
    ];

    final effectiveCat = dropdownItems.any((i) => i.value == _catSelection)
        ? _catSelection
        : (dropdownItems.isNotEmpty ? dropdownItems.first.value! : '');

    final isSmallScreen = MediaQuery.of(context).size.width < 640;

    final formFields = <Widget>[
              DropdownButtonFormField<String>(
                initialValue: _accId,
                isDense: true,
                style: TextStyle(fontSize: 13, color: colors.textPrimary),
                decoration: const InputDecoration(
                  labelText: 'Conta do Lançamento (Mover entre Contas)',
                  labelStyle: TextStyle(fontSize: 13),
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  border: OutlineInputBorder(),
                ),
                items: widget.store.db.accounts
                    .map((a) =>
                        DropdownMenuItem(value: a.id, child: Text(a.name, style: const TextStyle(fontSize: 13))))
                    .toList(),
                onChanged: (v) {
                  if (v != null) {
                    setState(() {
                      _accId = v;
                      final newAcc = widget.store.accById(v);
                      if (newAcc?.type == kCardType && newAcc?.card != null) {
                        _customIk =
                            invKeyFor(newAcc!.card!, _resolveIsoDate());
                      } else {
                        _customIk = null;
                      }
                    });
                  }
                },
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _dateCtrl,
                      style: const TextStyle(fontSize: 13),
                      decoration: InputDecoration(
                        labelText: 'Data (DD/MM/AAAA)',
                        labelStyle: const TextStyle(fontSize: 13),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                        border: const OutlineInputBorder(),
                        suffixIconConstraints: const BoxConstraints(minWidth: 28, maxHeight: 24),
                        suffixIcon: IconButton(
                          padding: EdgeInsets.zero,
                          icon: const Icon(Icons.calendar_month, size: 18),
                          tooltip: 'Escolher data no calendário',
                          onPressed: _pickDate,
                        ),
                      ),
                      onChanged: (v) {
                        if (isCard && targetAcc != null && targetAcc.card != null) {
                          setState(() {
                            _customIk = invKeyFor(
                              targetAcc.card!,
                              _resolveIsoDate(),
                            );
                          });
                        } else if (_isCompleteDateInput(v)) {
                          setState(() {});
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  SegmentedButton<bool>(
                    style: SegmentedButton.styleFrom(
                      selectedBackgroundColor:
                          colors.accent.withValues(alpha: 0.18),
                      selectedForegroundColor: colors.accent,
                      foregroundColor: colors.textSecondary,
                      textStyle: const TextStyle(
                          fontSize: 12.5, fontWeight: FontWeight.w700),
                      visualDensity: VisualDensity.compact,
                    ),
                    segments: const [
                      ButtonSegment(value: true, label: Text('− Despesa')),
                      ButtonSegment(value: false, label: Text('+ Receita')),
                    ],
                    selected: {_isExpense},
                    onSelectionChanged: (s) {
                      setState(() => _isExpense = s.first);
                    },
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _payeeCtrl,
                style: const TextStyle(fontSize: 13),
                decoration: const InputDecoration(
                  labelText: 'Favorecido / Descrição',
                  labelStyle: TextStyle(fontSize: 13),
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              CategorySelectFormField(
                store: widget.store,
                categoryType: catType,
                currentSelection: effectiveCat,
                excludeAccountId: _accId,
                labelText: 'Categoria ou Transferência',
                onChanged: (v) {
                  setState(() {
                    _catSelection = v;
                    if (v.startsWith('xfer:')) {
                      final peerId = v.substring(5);
                      final srcCur = targetAcc?.effectiveCurrency ?? 'BRL';
                      final destCur =
                          widget.store.accById(peerId)?.effectiveCurrency ??
                              'BRL';
                      if (srcCur != destCur) {
                        final r = exchangeRateBetween(
                          fromCurrency: srcCur,
                          toCurrency: destCur,
                          rates: widget.store.db.rates,
                        );
                        _rateCtrl.text =
                            r.toStringAsFixed(4).replaceAll('.', ',');
                        final srcCents = (parseCents(_amtCtrl.text) ?? 0).abs();
                        if (srcCents > 0) {
                          _peerAmtCtrl.text =
                              formatInputCents((srcCents * r).round());
                        }
                      }
                    }
                  });
                },
              ),
              const SizedBox(height: 12),
              Builder(builder: (context) {
                final srcCur = targetAcc?.effectiveCurrency ?? 'BRL';
                final srcMeta = currencyMetaFor(srcCur);
                final isXfer = _catSelection.startsWith('xfer:');
                final peerId = isXfer ? _catSelection.substring(5) : null;
                final destCur = peerId != null
                    ? (widget.store.accById(peerId)?.effectiveCurrency ?? 'BRL')
                    : srcCur;
                final isCross = isXfer && srcCur != destCur;

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _amtCtrl,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            style: const TextStyle(fontSize: 13),
                            onChanged: (_) {
                              if (!isCross || _isUpdatingCross) return;
                              _isUpdatingCross = true;
                              final srcCents =
                                  (parseCents(_amtCtrl.text) ?? 0).abs();
                              final r = _parseRateInput(_rateCtrl.text) ?? 1.0;
                              _peerAmtCtrl.text =
                                  formatInputCents((srcCents * r).round());
                              _isUpdatingCross = false;
                            },
                            decoration: InputDecoration(
                              labelText: 'Valor (${srcMeta.symbol})',
                              labelStyle: const TextStyle(fontSize: 13),
                              prefixText: '${srcMeta.symbol} ',
                              prefixStyle: const TextStyle(fontSize: 13),
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 10),
                              border: const OutlineInputBorder(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: _memoCtrl,
                            style: const TextStyle(fontSize: 13),
                            decoration: const InputDecoration(
                              labelText: 'Nota / Observação',
                              labelStyle: TextStyle(fontSize: 13),
                              isDense: true,
                              contentPadding: EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 10),
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TagInputField(
                      tags: _tags,
                      onChanged: (list) => setState(() => _tags = list),
                      availableTags: widget.store.allTags,
                      colors: OpenMoneyColors(
                          Theme.of(context).brightness == Brightness.dark),
                    ),
                    if (isCross)
                      _CrossCurrencyTransferBox(
                        store: widget.store,
                        sourceCurrency: srcCur,
                        destCurrency: destCur,
                        dateIso: _resolveIsoDate(),
                        rateCtrl: _rateCtrl,
                        destAmtCtrl: _peerAmtCtrl,
                        colors: colors,
                        onRateChanged: () {
                          if (_isUpdatingCross) return;
                          _isUpdatingCross = true;
                          final srcCents =
                              (parseCents(_amtCtrl.text) ?? 0).abs();
                          final r = _parseRateInput(_rateCtrl.text);
                          if (r != null && srcCents > 0) {
                            _peerAmtCtrl.text =
                                formatInputCents((srcCents * r).round());
                          }
                          _isUpdatingCross = false;
                        },
                        onDestAmtChanged: () {
                          if (_isUpdatingCross) return;
                          _isUpdatingCross = true;
                          final srcCents =
                              (parseCents(_amtCtrl.text) ?? 0).abs();
                          final destCents =
                              (parseCents(_peerAmtCtrl.text) ?? 0).abs();
                          if (srcCents > 0 && destCents > 0) {
                            final r = destCents / srcCents;
                            _rateCtrl.text =
                                r.toStringAsFixed(4).replaceAll('.', ',');
                          }
                          _isUpdatingCross = false;
                        },
                      )
                    else if (!isXfer &&
                        srcCur != 'BRL' &&
                        srcCur != widget.store.baseCurrency)
                      _ForeignTransactionRateBox(
                        store: widget.store,
                        accountId: _accId,
                        sourceCurrency: srcCur,
                        dateIso: _resolveIsoDate(),
                        amtCtrl: _amtCtrl,
                        rateCtrl: _rateCtrl,
                        colors: colors,
                        preserveInitialValue: true,
                      ),
                  ],
                );
              }),
              if (isCard && targetAcc?.card != null) ...[
                const SizedBox(height: 12),
                Builder(
                  builder: (context) {
                    final opts = invoiceOptions(
                      card: targetAcc!.card!,
                      aroundDate: _resolveIsoDate(),
                      existingKeys:
                          _customIk != null ? [_customIk!] : const [],
                    );
                    final selIk = _customIk ??
                        invKeyFor(targetAcc.card!, _resolveIsoDate());
                    return DropdownButtonFormField<String>(
                      initialValue:
                          opts.any((o) => o.key == selIk) ? selIk : opts.first.key,
                      isExpanded: true,
                      isDense: true,
                      style: TextStyle(fontSize: 13, color: colors.textPrimary),
                      decoration: const InputDecoration(
                        labelText: 'Competência da Fatura do Cartão',
                        labelStyle: TextStyle(fontSize: 13),
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        border: OutlineInputBorder(),
                      ),
                      items: opts
                          .map((o) => DropdownMenuItem(
                                value: o.key,
                                child: Text(o.label, style: const TextStyle(fontSize: 13)),
                              ))
                          .toList(),
                      onChanged: (v) => setState(() => _customIk = v),
                    );
                  },
                ),
              ],
              if (isSeries) ...[
                const SizedBox(height: 14),
                const Text(
                  'Escopo de Alteração na Série:',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
                ),
                const SizedBox(height: 6),
                SegmentedButton<ScopeChoice>(
                  style: const ButtonStyle(
                    textStyle: WidgetStatePropertyAll(TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
                    visualDensity: VisualDensity.compact,
                  ),
                  segments: const [
                    ButtonSegment(
                      value: ScopeChoice.only,
                      label: Text('Apenas este'),
                    ),
                    ButtonSegment(
                      value: ScopeChoice.forward,
                      label: Text('Este e futuros não conciliados'),
                    ),
                  ],
                  selected: {_scope},
                  onSelectionChanged: (s) => setState(() => _scope = s.first),
                ),
              ],
            ];

    final copyBtn = widget.tx.auto != true
        ? TextButton.icon(
            style: TextButton.styleFrom(
              foregroundColor: colors.accent,
              visualDensity: VisualDensity.compact,
            ),
            icon: const Icon(Icons.copy_rounded, size: 17),
            label: const Text('Copiar'),
            onPressed: () {
              Navigator.pop(context);
              showTransactionCopyModal(context, widget.store, widget.tx);
            },
          )
        : const SizedBox.shrink();

    final deleteBtn = TextButton.icon(
      style: TextButton.styleFrom(
        foregroundColor: colors.expense,
        visualDensity: VisualDensity.compact,
      ),
      icon: const Icon(Icons.delete_outline, size: 17),
      label: const Text('Excluir'),
      onPressed: () {
        Navigator.pop(context);
        showDeleteTransactionDialog(context, widget.store, widget.tx);
      },
    );

    if (isSmallScreen) {
      return Dialog.fullscreen(
        backgroundColor: colors.bgSecondary,
        child: Scaffold(
          backgroundColor: colors.bgSecondary,
          resizeToAvoidBottomInset: true,
          appBar: AppBar(
            backgroundColor: colors.bgSecondary,
            leading: IconButton(
              icon: const Icon(Icons.close),
              tooltip: 'Cancelar',
              onPressed: () => Navigator.pop(context),
            ),
            title: const Text(
              'Editar Lançamento',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
            actions: [
              if (widget.tx.auto != true) copyBtn,
              deleteBtn,
            ],
          ),
          body: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ...formFields,
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Cancelar'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          icon: const Icon(Icons.check, size: 18),
                          label: const Text('Salvar'),
                          onPressed: _handleSave,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return AlertDialog(
      backgroundColor: colors.bgSecondary,
      title: const Text('Editar Lançamento'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: formFields,
          ),
        ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      actions: [
        Row(
          children: [
            if (widget.tx.auto != true) copyBtn,
            if (widget.tx.auto != true) const SizedBox(width: 6),
            deleteBtn,
            const Spacer(),
            TextButton(
              style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
              icon: const Icon(Icons.check, size: 18),
              label: const Text('Salvar'),
              onPressed: _handleSave,
            ),
          ],
        ),
      ],
    );
  }
}

class _TransactionCreateDialog extends StatefulWidget {
  final MoneyStore store;
  final String? initialAccountId;
  final String? initialDateIso;
  final String? initialPayee;
  final int? initialAmountCents;
  final String? initialCategory;
  final String? initialMemo;
  final bool? initialIsExpense;
  final String? shortcutRawAccountName;
  final bool fromShortcut;

  const _TransactionCreateDialog({
    required this.store,
    this.initialAccountId,
    this.initialDateIso,
    this.initialPayee,
    this.initialAmountCents,
    this.initialCategory,
    this.initialMemo,
    this.initialIsExpense,
    this.shortcutRawAccountName,
    this.fromShortcut = false,
  });

  @override
  State<_TransactionCreateDialog> createState() =>
      _TransactionCreateDialogState();
}

class _TransactionCreateDialogState extends State<_TransactionCreateDialog> {
  late String _accId;
  late final TextEditingController _dateCtrl;
  late final TextEditingController _payeeCtrl;
  late final FocusNode _payeeFocus;
  late final TextEditingController _memoCtrl;
  late final TextEditingController _amtCtrl;
  late final TextEditingController _peerAmtCtrl;
  late final TextEditingController _rateCtrl;
  late final TextEditingController _endDateCtrl;
  late String _txType; // 'expense', 'income', 'transfer'
  late bool _isExpense;
  late String _catSelection;
  late String? _customIk;
  List<String> _tags = [];
  bool _isUpdatingCross = false;

  String _mode = 'single';
  String _freq = 'monthly';
  int _installments = 2;
  bool _hasEndDate = false;

  List<PayeeSuggestion> _suggestions = [];

  @override
  void initState() {
    super.initState();
    final available = _availableAccounts();
    final candidateId = widget.initialAccountId;
    if (candidateId != null &&
        candidateId.isNotEmpty &&
        available.any((a) => a.id == candidateId)) {
      _accId = candidateId;
    } else {
      _accId = available.isNotEmpty ? available.first.id : 'a1';
    }

    final effectiveDateIso =
        (widget.initialDateIso != null && widget.initialDateIso!.isNotEmpty)
            ? widget.initialDateIso!
            : todayISO();
    final initialPayeeText = (widget.initialPayee ?? '').trim();
    final initialMemoText = (widget.initialMemo ?? '').trim();
    final initialCents = widget.initialAmountCents ?? 0;

    _dateCtrl = TextEditingController(text: fmtDate(effectiveDateIso));
    _payeeCtrl = TextEditingController(text: initialPayeeText);
    _payeeFocus = FocusNode();
    _memoCtrl = TextEditingController(text: initialMemoText);
    _amtCtrl = TextEditingController(
      text: initialCents > 0 ? formatInputCents(initialCents) : '',
    );

    final initialCat = widget.initialCategory?.trim() ?? '';
    if (initialCat.startsWith('xfer:')) {
      _txType = 'transfer';
      _isExpense = true;
      _catSelection = initialCat;
    } else {
      _isExpense = widget.initialIsExpense ?? true;
      _txType = _isExpense ? 'expense' : 'income';
      final catPaths =
          widget.store.allCategoryPaths(_isExpense ? 'Despesa' : 'Receita');
      if (initialCat.isNotEmpty) {
        _catSelection = initialCat;
      } else {
        _catSelection = catPaths.isNotEmpty ? catPaths.first : '';
      }
    }

    if (initialPayeeText.isNotEmpty) {
      _suggestions = widget.store.payeeSuggestions(initialPayeeText);
    }

    final oneYearAhead = DateTime.now().add(const Duration(days: 365));
    _endDateCtrl =
        TextEditingController(text: fmtDate(isoFromDate(oneYearAhead)));

    final curAcc = widget.store.accById(_accId);
    if (curAcc?.type == kCardType && curAcc?.card != null) {
      _customIk = invKeyFor(curAcc!.card!, effectiveDateIso);
    } else {
      _customIk = null;
    }

    _peerAmtCtrl = TextEditingController();
    final baseCur = widget.store.baseCurrency;
    final baseBrl = baseCur == 'BRL' ? 1.0 : widget.store.rateToBrl(baseCur);
    final initBrlRate =
        widget.store.resolveDefaultRateToBrl(_accId, effectiveDateIso);
    final initDisplayRate = baseBrl > 0 ? (initBrlRate / baseBrl) : initBrlRate;
    _rateCtrl = TextEditingController(
      text: initDisplayRate.toStringAsFixed(4).replaceAll('.', ','),
    );
  }

  @override
  void dispose() {
    _dateCtrl.dispose();
    _payeeCtrl.dispose();
    _payeeFocus.dispose();
    _memoCtrl.dispose();
    _amtCtrl.dispose();
    _peerAmtCtrl.dispose();
    _rateCtrl.dispose();
    _endDateCtrl.dispose();
    super.dispose();
  }

  List<Account> _availableAccounts() {
    final favs = widget.store.favoriteAccounts;
    final others = widget.store.regularActiveAccounts;
    final list = <Account>[...favs, ...others];
    if (list.isEmpty) {
      list.addAll(widget.store.db.accounts);
    }
    return list;
  }

  void _updateTransferDestination(String peerId) {
    _catSelection = 'xfer:$peerId';
    final targetAcc = widget.store.accById(_accId);
    final srcCur = targetAcc?.effectiveCurrency ?? 'BRL';
    final destCur =
        widget.store.accById(peerId)?.effectiveCurrency ?? 'BRL';
    if (srcCur != destCur) {
      final r = exchangeRateBetween(
        fromCurrency: srcCur,
        toCurrency: destCur,
        rates: widget.store.db.rates,
      );
      _rateCtrl.text = r.toStringAsFixed(4).replaceAll('.', ',');
      final srcCents = (parseCents(_amtCtrl.text) ?? 0).abs();
      if (srcCents > 0) {
        _peerAmtCtrl.text =
            formatInputCents((srcCents * r).round());
      }
    }
  }

  String _resolveIsoDate(String raw, {String? fallback}) {
    final trimmed = raw.trim();
    if (RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(trimmed)) return trimmed;
    final parts = trimmed.split('/');
    if (parts.length == 3) {
      return '${parts[2].padLeft(4, '0')}-${parts[1].padLeft(2, '0')}-${parts[0].padLeft(2, '0')}';
    }
    return fallback ?? todayISO();
  }

  Future<void> _pickDate(TextEditingController ctrl,
      {DateTime? firstDate}) async {
    final curIso = _resolveIsoDate(ctrl.text);
    final initialDate = dateFromISO(curIso);
    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: firstDate ?? DateTime(2000),
      lastDate: DateTime(2099, 12, 31),
    );
    if (picked != null) {
      setState(() {
        ctrl.text = fmtDate(isoFromDate(picked));
        final targetAcc = widget.store.accById(_accId);
        if (targetAcc?.type == kCardType && targetAcc?.card != null) {
          _customIk = invKeyFor(targetAcc!.card!, isoFromDate(picked));
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
        if (match.category.startsWith('xfer:')) {
          _txType = 'transfer';
          _isExpense = true;
          _catSelection = match.category;
        } else {
          _isExpense = match.isExpense;
          _txType = match.isExpense ? 'expense' : 'income';
          if (match.category.isNotEmpty) {
            _catSelection = match.category;
          }
        }
        if (match.accountId.isNotEmpty) {
          final matchedAcc = widget.store.accById(match.accountId);
          if (matchedAcc != null && !matchedAcc.isInactive) {
            _accId = match.accountId;
            if (matchedAcc.type == kCardType && matchedAcc.card != null) {
              _customIk = invKeyFor(
                  matchedAcc.card!, _resolveIsoDate(_dateCtrl.text));
            } else {
              _customIk = null;
            }
          }
        }
      }
    });
  }

  void _applySuggestion(PayeeSuggestion s) {
    setState(() {
      _payeeCtrl.text = s.name;
      if (s.category.startsWith('xfer:')) {
        _txType = 'transfer';
        _isExpense = true;
        _catSelection = s.category;
      } else {
        _isExpense = s.isExpense;
        _txType = s.isExpense ? 'expense' : 'income';
        if (s.category.isNotEmpty) {
          _catSelection = s.category;
        }
      }
      if (s.accountId.isNotEmpty) {
        final matchedAcc = widget.store.accById(s.accountId);
        if (matchedAcc != null && !matchedAcc.isInactive) {
          _accId = s.accountId;
          if (matchedAcc.type == kCardType && matchedAcc.card != null) {
            _customIk = invKeyFor(
                matchedAcc.card!, _resolveIsoDate(_dateCtrl.text));
          } else {
            _customIk = null;
          }
        }
      }
      _suggestions = [];
    });
  }

  Future<void> _commitCreate({bool andCreateAnother = false}) async {
    final absCents = (parseCents(_amtCtrl.text) ?? 0).abs();
    if (absCents <= 0) return;

    final isXfer = _txType == 'transfer' || _catSelection.startsWith('xfer:');
    final signedAmt = isXfer ? -absCents : (_isExpense ? -absCents : absCents);

    final rawPayee = _payeeCtrl.text.trim();
    final finalPayee = rawPayee.isEmpty
        ? (isXfer ? 'Transferência' : 'Sem descrição')
        : rawPayee;

    final trimmedMemo = _memoCtrl.text.trim();
    final dateStr = _resolveIsoDate(_dateCtrl.text);
    final endStr = (_mode == 'recurring' && _hasEndDate)
        ? _resolveIsoDate(_endDateCtrl.text)
        : null;

    final targetAcc = widget.store.accById(_accId);
    final isCard = targetAcc?.type == kCardType && targetAcc?.card != null;
    final ik = (isCard && _customIk != null && _customIk!.isNotEmpty)
        ? _customIk
        : null;

    if (widget.fromShortcut &&
        widget.shortcutRawAccountName != null &&
        widget.shortcutRawAccountName!.trim().isNotEmpty) {
      widget.store.addWalletAlias(widget.shortcutRawAccountName!.trim(), _accId);
    }

    int? peerSignedAmt;
    double? txRate;
    final curCur = targetAcc?.effectiveCurrency ?? 'BRL';
    if (isXfer) {
      final peerId = _catSelection.substring(5);
      final peerAcc = widget.store.accById(peerId);
      final peerCur = peerAcc?.effectiveCurrency ?? 'BRL';
      if (curCur != peerCur) {
        final peerAbs = (parseCents(_peerAmtCtrl.text) ?? 0).abs();
        if (peerAbs > 0) {
          peerSignedAmt = peerAbs;
          if (curCur != 'BRL' && peerCur == 'BRL' && absCents > 0) {
            txRate = peerAbs / absCents;
          }
        }
      }
    } else if (curCur != 'BRL') {
      txRate = _resolveNonXferRateToBrl(
        widget.store,
        _rateCtrl,
        _accId,
        curCur,
        dateStr,
      );
    }

    final warning = widget.store.checkBudgetExceeded(
      accId: _accId,
      date: dateStr,
      catSelection: _catSelection,
      signedAmt: signedAmt,
      mode: isXfer && _mode == 'installment' ? 'single' : _mode,
      installments: _installments,
      txRate: txRate,
    );

    if (warning != null && mounted) {
      final proceed = await showBudgetExceededDialog(context, warning);
      if (!proceed) return;
    }

    widget.store.addTransaction(
      accId: _accId,
      date: dateStr,
      payee: finalPayee,
      catSelection: _catSelection,
      memo: trimmedMemo,
      signedAmt: signedAmt,
      mode: isXfer && _mode == 'installment' ? 'single' : _mode,
      freq: _freq,
      installments: _installments,
      endDate: endStr,
      customIk: ik,
      peerSignedAmt: peerSignedAmt,
      txRate: txRate,
      tags: _tags,
    );

    if (!mounted) return;

    if (andCreateAnother) {
      setState(() {
        _amtCtrl.clear();
        _payeeCtrl.clear();
        _memoCtrl.clear();
        _peerAmtCtrl.clear();
        _tags = [];
        _suggestions = [];
      });
      _payeeFocus.requestFocus();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Lançamento salvo! Pronto para o próximo.'),
          duration: Duration(seconds: 2),
        ),
      );
    } else {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colors = OpenMoneyColors(isDark);
    final availableAccs = _availableAccounts();
    final targetAcc = widget.store.accById(_accId);
    final isCard = targetAcc?.type == kCardType && targetAcc?.card != null;
    final isXfer = _txType == 'transfer' || _catSelection.startsWith('xfer:');

    final catType = _isExpense ? 'Despesa' : 'Receita';
    final catOptions = widget.store.allCategoryOptions(catType);
    final otherAccounts =
        widget.store.transferDestinationAccounts(excludeId: _accId);

    final dropdownItems = <DropdownMenuItem<String>>[
      if (_catSelection.isNotEmpty &&
          !catOptions.any((c) => c.value == _catSelection) &&
          !_catSelection.startsWith('xfer:'))
        DropdownMenuItem(value: _catSelection, child: Text(_catSelection)),
      ...catOptions.map(
        (c) => DropdownMenuItem(value: c.value, child: Text(c.label)),
      ),
      ...otherAccounts.map(
        (a) => DropdownMenuItem(
          value: 'xfer:${a.id}',
          child: Text('⇄ Transferência: ${a.name}'),
        ),
      ),
    ];

    final effectiveCat = dropdownItems.any((i) => i.value == _catSelection)
        ? _catSelection
        : (dropdownItems.isNotEmpty ? dropdownItems.first.value! : '');

    final isSmallScreen = MediaQuery.of(context).size.width < 640;

    final formFields = <Widget>[
              if (widget.fromShortcut) ...[
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 9,
                  ),
                  decoration: BoxDecoration(
                    color: colors.accent.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: colors.accent.withValues(alpha: 0.35),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.phone_iphone_rounded,
                        size: 16,
                        color: colors.accent,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Dados preenchidos via parâmetro de URL / Atalho. Confira abaixo e clique em Salvar.',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: colors.textPrimary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              // Tipo de Lançamento (Despesa / Receita / Transferência)
              SizedBox(
                width: double.infinity,
                child: SegmentedButton<String>(
                  style: SegmentedButton.styleFrom(
                    selectedBackgroundColor:
                        colors.accent.withValues(alpha: 0.18),
                    selectedForegroundColor: colors.accent,
                    foregroundColor: colors.textSecondary,
                    textStyle: const TextStyle(
                        fontSize: 12.5, fontWeight: FontWeight.w700),
                    visualDensity: VisualDensity.compact,
                  ),
                  segments: const [
                    ButtonSegment(
                      value: 'expense',
                      label: Text('− Despesa'),
                      icon: Icon(Icons.arrow_downward_rounded, size: 16),
                    ),
                    ButtonSegment(
                      value: 'income',
                      label: Text('+ Receita'),
                      icon: Icon(Icons.arrow_upward_rounded, size: 16),
                    ),
                    ButtonSegment(
                      value: 'transfer',
                      label: Text('⇄ Transferência'),
                      icon: Icon(Icons.swap_horiz_rounded, size: 16),
                    ),
                  ],
                  selected: {_txType},
                  onSelectionChanged: (s) {
                    setState(() {
                      _txType = s.first;
                      if (_txType == 'transfer') {
                        final others = widget.store
                            .transferDestinationAccounts(excludeId: _accId);
                        final currentDest = _catSelection.startsWith('xfer:')
                            ? _catSelection.substring(5)
                            : '';
                        if (!others.any((a) => a.id == currentDest)) {
                          if (others.isNotEmpty) {
                            _updateTransferDestination(others.first.id);
                          }
                        }
                      } else {
                        _isExpense = _txType == 'expense';
                        final paths = widget.store.allCategoryPaths(
                          _isExpense ? 'Despesa' : 'Receita',
                        );
                        if (!paths.contains(_catSelection) ||
                            _catSelection.startsWith('xfer:')) {
                          _catSelection = paths.isNotEmpty ? paths.first : '';
                        }
                      }
                    });
                  },
                ),
              ),
              const SizedBox(height: 12),

              // Conta e Data lado a lado
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: DropdownButtonFormField<String>(
                      initialValue: _accId,
                      isDense: true,
                      style: TextStyle(fontSize: 13, color: colors.textPrimary),
                      decoration: const InputDecoration(
                        labelText: 'Conta',
                        labelStyle: TextStyle(fontSize: 13),
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        border: OutlineInputBorder(),
                      ),
                      items: availableAccs
                          .map((a) => DropdownMenuItem(
                                value: a.id,
                                child: Text(
                                  (a.isFavorite ? '★ ' : '') +
                                      a.name +
                                      (a.type == kCardType
                                          ? ' (Cartão)'
                                          : ' (${a.type})'),
                                  style: const TextStyle(fontSize: 13),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ))
                          .toList(),
                      onChanged: (v) {
                        if (v != null) {
                          setState(() {
                            _accId = v;
                            final newAcc = widget.store.accById(v);
                            if (newAcc?.type == kCardType && newAcc?.card != null) {
                              _customIk = invKeyFor(
                                  newAcc!.card!, _resolveIsoDate(_dateCtrl.text));
                            } else {
                              _customIk = null;
                            }
                            if (_catSelection.startsWith('xfer:')) {
                              final others = widget.store
                                  .transferDestinationAccounts(excludeId: v);
                              final currentDest = _catSelection.substring(5);
                              if (!others.any((a) => a.id == currentDest)) {
                                if (others.isNotEmpty) {
                                  _updateTransferDestination(others.first.id);
                                } else {
                                  _catSelection = '';
                                }
                              }
                            }
                          });
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: TextField(
                      controller: _dateCtrl,
                      style: const TextStyle(fontSize: 13),
                      decoration: InputDecoration(
                        labelText: 'Data (DD/MM/AAAA)',
                        labelStyle: const TextStyle(fontSize: 13),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                        border: const OutlineInputBorder(),
                        suffixIconConstraints: const BoxConstraints(minWidth: 28, maxHeight: 24),
                        suffixIcon: IconButton(
                          padding: EdgeInsets.zero,
                          icon: const Icon(Icons.calendar_month, size: 18),
                          tooltip: 'Escolher data no calendário',
                          onPressed: () => _pickDate(_dateCtrl),
                        ),
                      ),
                      onChanged: (v) {
                        if (isCard &&
                            targetAcc != null &&
                            targetAcc.card != null) {
                          setState(() {
                            _customIk = invKeyFor(
                              targetAcc.card!,
                              _resolveIsoDate(_dateCtrl.text),
                            );
                          });
                        } else if (_isCompleteDateInput(v)) {
                          setState(() {});
                        }
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Competência da Fatura se cartão
              if (isCard && targetAcc != null && targetAcc.card != null) ...[
                Builder(
                  builder: (context) {
                    final d = _resolveIsoDate(_dateCtrl.text);
                    final opts = invoiceOptions(
                      card: targetAcc.card!,
                      aroundDate: d,
                      existingKeys:
                          _customIk != null ? [_customIk!] : const [],
                    );
                    final defaultIk = invKeyFor(targetAcc.card!, d);
                    final selIk = (_customIk == null || _customIk!.isEmpty)
                        ? defaultIk
                        : _customIk!;
                    return DropdownButtonFormField<String>(
                      initialValue: opts.any((o) => o.key == selIk)
                          ? selIk
                          : opts.first.key,
                      isExpanded: true,
                      isDense: true,
                      style: TextStyle(fontSize: 13, color: colors.textPrimary),
                      decoration: const InputDecoration(
                        labelText: 'Fatura do Cartão (Competência)',
                        labelStyle: TextStyle(fontSize: 13),
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        border: OutlineInputBorder(),
                      ),
                      items: opts
                          .map((o) => DropdownMenuItem(
                                value: o.key,
                                child: Text(o.key == defaultIk
                                    ? '${o.label} [Padrão]'
                                    : o.label,
                                    style: const TextStyle(fontSize: 13)),
                              ))
                          .toList(),
                      onChanged: (v) => setState(() => _customIk = v),
                    );
                  },
                ),
                const SizedBox(height: 12),
              ],

              // Favorecido / Descrição com Autocompletar inteligente
              TextField(
                controller: _payeeCtrl,
                focusNode: _payeeFocus,
                style: const TextStyle(fontSize: 13),
                decoration: const InputDecoration(
                  labelText: 'Favorecido / Descrição',
                  labelStyle: TextStyle(fontSize: 13),
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                  border: OutlineInputBorder(),
                ),
                onChanged: _onPayeeChanged,
              ),
              if (_suggestions.isNotEmpty) ...[
                const SizedBox(height: 8),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: _suggestions.map((s) {
                    final accName = widget.store.accById(s.accountId)?.name;
                    return ActionChip(
                      avatar: Icon(
                        s.isExpense
                            ? Icons.trending_down
                            : Icons.trending_up,
                        size: 14,
                        color: s.isExpense ? colors.expense : colors.income,
                      ),
                      label: Text(
                        '${s.name} • ${s.category}${accName != null ? ' • $accName' : ''}',
                        style: const TextStyle(fontSize: 12),
                      ),
                      onPressed: () => _applySuggestion(s),
                    );
                  }).toList(),
                ),
              ],
              const SizedBox(height: 12),

              // Categoria ou Conta de Destino da Transferência
              if (isXfer) ...[
                DropdownButtonFormField<String>(
                  initialValue: _catSelection.startsWith('xfer:')
                      ? _catSelection.substring(5)
                      : (otherAccounts.isNotEmpty ? otherAccounts.first.id : null),
                  isDense: true,
                  style: TextStyle(fontSize: 13, color: colors.textPrimary),
                  decoration: const InputDecoration(
                    labelText: 'Conta de Destino',
                    labelStyle: TextStyle(fontSize: 13),
                    isDense: true,
                    contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.swap_horiz_rounded, size: 20),
                  ),
                  items: otherAccounts
                      .map((a) => DropdownMenuItem(
                            value: a.id,
                            child: Text(
                              (a.isFavorite ? '★ ' : '') +
                                  a.name +
                                  (a.type == kCardType
                                      ? ' (Cartão)'
                                      : ' (${a.type})'),
                              style: const TextStyle(fontSize: 13),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ))
                      .toList(),
                  onChanged: (destId) {
                    if (destId != null) {
                      setState(() => _updateTransferDestination(destId));
                    }
                  },
                ),
              ] else ...[
                CategorySelectFormField(
                  store: widget.store,
                  categoryType: catType,
                  currentSelection: effectiveCat,
                  excludeAccountId: _accId,
                  labelText: 'Categoria',
                  onChanged: (v) {
                    setState(() {
                      if (v.startsWith('xfer:')) {
                        _txType = 'transfer';
                        _updateTransferDestination(v.substring(5));
                      } else {
                        _catSelection = v;
                      }
                    });
                  },
                ),
              ],
              const SizedBox(height: 12),

              // Valor & Observação
              Builder(builder: (context) {
                final srcCur = targetAcc?.effectiveCurrency ?? 'BRL';
                final srcMeta = currencyMetaFor(srcCur);
                final peerId = isXfer ? _catSelection.substring(5) : null;
                final destCur = peerId != null
                    ? (widget.store.accById(peerId)?.effectiveCurrency ?? 'BRL')
                    : srcCur;
                final isCross = isXfer && srcCur != destCur;

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _amtCtrl,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            style: const TextStyle(fontSize: 13),
                            onChanged: (_) {
                              if (!isCross || _isUpdatingCross) return;
                              _isUpdatingCross = true;
                              final srcCents =
                                  (parseCents(_amtCtrl.text) ?? 0).abs();
                              final r = _parseRateInput(_rateCtrl.text) ?? 1.0;
                              _peerAmtCtrl.text =
                                  formatInputCents((srcCents * r).round());
                              _isUpdatingCross = false;
                            },
                            decoration: InputDecoration(
                              labelText: 'Valor (${srcMeta.symbol})',
                              labelStyle: const TextStyle(fontSize: 13),
                              prefixText: '${srcMeta.symbol} ',
                              prefixStyle: const TextStyle(fontSize: 13),
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 10),
                              border: const OutlineInputBorder(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: _memoCtrl,
                            style: const TextStyle(fontSize: 13),
                            decoration: const InputDecoration(
                              labelText: 'Nota / Observação',
                              labelStyle: TextStyle(fontSize: 13),
                              isDense: true,
                              contentPadding: EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 10),
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TagInputField(
                      tags: _tags,
                      onChanged: (list) => setState(() => _tags = list),
                      availableTags: widget.store.allTags,
                      colors: OpenMoneyColors(
                          Theme.of(context).brightness == Brightness.dark),
                    ),
                    if (isCross)
                      _CrossCurrencyTransferBox(
                        store: widget.store,
                        sourceCurrency: srcCur,
                        destCurrency: destCur,
                        dateIso: _resolveIsoDate(_dateCtrl.text),
                        rateCtrl: _rateCtrl,
                        destAmtCtrl: _peerAmtCtrl,
                        colors: colors,
                        onRateChanged: () {
                          if (_isUpdatingCross) return;
                          _isUpdatingCross = true;
                          final srcCents =
                              (parseCents(_amtCtrl.text) ?? 0).abs();
                          final r = _parseRateInput(_rateCtrl.text);
                          if (r != null && srcCents > 0) {
                            _peerAmtCtrl.text =
                                formatInputCents((srcCents * r).round());
                          }
                          _isUpdatingCross = false;
                        },
                        onDestAmtChanged: () {
                          if (_isUpdatingCross) return;
                          _isUpdatingCross = true;
                          final srcCents =
                              (parseCents(_amtCtrl.text) ?? 0).abs();
                          final destCents =
                              (parseCents(_peerAmtCtrl.text) ?? 0).abs();
                          if (srcCents > 0 && destCents > 0) {
                            final r = destCents / srcCents;
                            _rateCtrl.text =
                                r.toStringAsFixed(4).replaceAll('.', ',');
                          }
                          _isUpdatingCross = false;
                        },
                      )
                    else if (!isXfer &&
                        srcCur != 'BRL' &&
                        srcCur != widget.store.baseCurrency)
                      _ForeignTransactionRateBox(
                        store: widget.store,
                        accountId: _accId,
                        sourceCurrency: srcCur,
                        dateIso: _resolveIsoDate(_dateCtrl.text),
                        amtCtrl: _amtCtrl,
                        rateCtrl: _rateCtrl,
                        colors: colors,
                        preserveInitialValue: false,
                      ),
                  ],
                );
              }),
              const SizedBox(height: 12),

              // Modo Flexível: Único, Recorrente, Parcelado
              if (!isXfer) ...[
                const Text(
                  'Modo do Lançamento:',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
                ),
                const SizedBox(height: 6),
                SegmentedButton<String>(
                  style: SegmentedButton.styleFrom(
                    selectedBackgroundColor:
                        colors.accent.withValues(alpha: 0.18),
                    selectedForegroundColor: colors.accent,
                    foregroundColor: colors.textSecondary,
                    textStyle: const TextStyle(
                        fontSize: 12.5, fontWeight: FontWeight.w700),
                    visualDensity: VisualDensity.compact,
                  ),
                  segments: const [
                    ButtonSegment(value: 'single', label: Text('Único')),
                    ButtonSegment(
                        value: 'recurring', label: Text('Recorrente')),
                    ButtonSegment(
                        value: 'installment', label: Text('Parcelado')),
                  ],
                  selected: {_mode},
                  onSelectionChanged: (s) => setState(() => _mode = s.first),
                ),
                const SizedBox(height: 12),

                if (_mode == 'recurring') ...[
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: _freq,
                          isDense: true,
                          style: TextStyle(fontSize: 13, color: colors.textPrimary),
                          decoration: const InputDecoration(
                            labelText: 'Frequência',
                            labelStyle: TextStyle(fontSize: 13),
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            border: OutlineInputBorder(),
                          ),
                          items: kRecurrenceFrequencyOptions
                              .map((o) => DropdownMenuItem(
                                    value: o.id,
                                    child: Text(o.label, style: const TextStyle(fontSize: 13)),
                                  ))
                              .toList(),
                          onChanged: (v) {
                            if (v != null) setState(() => _freq = v);
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: const Text('Definir Data de Término', style: TextStyle(fontSize: 13)),
                    value: _hasEndDate,
                    onChanged: (v) => setState(() => _hasEndDate = v ?? false),
                  ),
                  if (_hasEndDate) ...[
                    const SizedBox(height: 4),
                    TextField(
                      controller: _endDateCtrl,
                      style: const TextStyle(fontSize: 13),
                      decoration: InputDecoration(
                        labelText: 'Data de Término (DD/MM/AAAA)',
                        labelStyle: const TextStyle(fontSize: 13),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                        border: const OutlineInputBorder(),
                        suffixIconConstraints: const BoxConstraints(minWidth: 28, maxHeight: 24),
                        suffixIcon: IconButton(
                          padding: EdgeInsets.zero,
                          icon: const Icon(Icons.calendar_month, size: 18),
                          tooltip: 'Escolher data de término',
                          onPressed: () {
                            final baseD = dateFromISO(
                                _resolveIsoDate(_dateCtrl.text));
                            _pickDate(_endDateCtrl, firstDate: baseD);
                          },
                        ),
                      ),
                    ),
                  ],
                ] else if (_mode == 'installment') ...[
                  DropdownButtonFormField<int>(
                    initialValue: _installments,
                    isDense: true,
                    style: TextStyle(fontSize: 13, color: colors.textPrimary),
                    decoration: const InputDecoration(
                      labelText: 'Número de Parcelas',
                      labelStyle: TextStyle(fontSize: 13),
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      border: OutlineInputBorder(),
                    ),
                    items: List.generate(
                      119,
                      (i) => DropdownMenuItem(
                        value: i + 2,
                        child: Text('${i + 2}x', style: const TextStyle(fontSize: 13)),
                      ),
                    ),
                    onChanged: (v) {
                      if (v != null) setState(() => _installments = v);
                    },
                  ),
                ],
              ],
            ];

    if (isSmallScreen) {
      return Dialog.fullscreen(
        backgroundColor: colors.bgSecondary,
        child: Scaffold(
          backgroundColor: colors.bgSecondary,
          resizeToAvoidBottomInset: true,
          appBar: AppBar(
            backgroundColor: colors.bgSecondary,
            leading: IconButton(
              icon: const Icon(Icons.close),
              tooltip: 'Cancelar',
              onPressed: () => Navigator.pop(context),
            ),
            title: Row(
              children: [
                Icon(
                  widget.fromShortcut ? Icons.bolt_rounded : Icons.add_circle,
                  color: colors.accent,
                  size: 18,
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    widget.fromShortcut
                        ? 'Confirmar Lançamento'
                        : 'Novo Lançamento',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
          body: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ...formFields,
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        flex: 5,
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 12),
                            visualDensity: VisualDensity.compact,
                          ),
                          onPressed: () => Navigator.pop(context),
                          child: const Text(
                            'Cancelar',
                            style: TextStyle(fontSize: 12),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        flex: 7,
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 12),
                            visualDensity: VisualDensity.compact,
                          ),
                          onPressed: () => _commitCreate(andCreateAnother: true),
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.add, size: 15),
                              SizedBox(width: 3),
                              Flexible(
                                child: Text(
                                  'Salvar e Outro',
                                  style: TextStyle(fontSize: 12),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        flex: 5,
                        child: FilledButton(
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 12),
                            visualDensity: VisualDensity.compact,
                          ),
                          onPressed: () => _commitCreate(andCreateAnother: false),
                          child: const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.check, size: 15),
                              SizedBox(width: 3),
                              Flexible(
                                child: Text(
                                  'Salvar',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return AlertDialog(
      backgroundColor: colors.bgSecondary,
      title: Row(
        children: [
          Icon(
            widget.fromShortcut ? Icons.bolt_rounded : Icons.add_circle,
            color: colors.accent,
            size: 20,
          ),
          const SizedBox(width: 8),
          Text(
            widget.fromShortcut
                ? 'Confirmar Lançamento (Atalho)'
                : 'Novo Lançamento',
          ),
        ],
      ),
      content: SizedBox(
        width: 500,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: formFields,
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        OutlinedButton.icon(
          icon: const Icon(Icons.add, size: 16),
          label: const Text('Salvar e Criar Outro'),
          onPressed: () => _commitCreate(andCreateAnother: true),
        ),
        FilledButton.icon(
          icon: const Icon(Icons.check, size: 18),
          label: const Text('Salvar'),
          onPressed: () => _commitCreate(andCreateAnother: false),
        ),
      ],
    );
  }
}

class _TransactionCopyDialog extends StatefulWidget {
  final MoneyStore store;
  final Transaction sourceTx;

  const _TransactionCopyDialog({
    required this.store,
    required this.sourceTx,
  });

  @override
  State<_TransactionCopyDialog> createState() => _TransactionCopyDialogState();
}

class _TransactionCopyDialogState extends State<_TransactionCopyDialog> {
  late String _accId;
  late final TextEditingController _dateCtrl;
  late final TextEditingController _payeeCtrl;
  late final TextEditingController _memoCtrl;
  late final TextEditingController _amtCtrl;
  late final TextEditingController _peerAmtCtrl;
  late final TextEditingController _rateCtrl;
  late final TextEditingController _endDateCtrl;
  late bool _isExpense;
  late String _catSelection;
  late String? _customIk;
  List<String> _tags = [];
  bool _isUpdatingCross = false;

  String _mode = 'single'; // 'single', 'installment', 'recurring'
  String _freq = 'monthly';
  int _installments = 2;
  bool _hasEndDate = false;

  @override
  void initState() {
    super.initState();
    final t = widget.sourceTx;
    final available = _availableAccounts();
    _accId = available.any((a) => a.id == t.acc)
        ? t.acc
        : (available.isNotEmpty ? available.first.id : t.acc);

    final todayStr = todayISO();
    _dateCtrl = TextEditingController(text: fmtDate(todayStr));

    // Regra: Limpar sufixos de parcelas anteriores como (1/12)
    final cleanPayee =
        t.payee.replaceAll(RegExp(r'\s*\(\d+\/\d+\)$'), '').trim();
    _payeeCtrl = TextEditingController(text: cleanPayee);
    _memoCtrl = TextEditingController(text: t.memo);
    _amtCtrl = TextEditingController(text: formatInputCents(t.amt.abs()));
    _isExpense = t.amt < 0;
    _tags = List<String>.from(t.tags ?? const []);

    if (t.peer != null && t.peer!.isNotEmpty) {
      _catSelection = 'xfer:${t.peer}';
    } else {
      _catSelection = t.cat;
    }

    if (t.recId != null) {
      _mode = 'recurring';
      _freq = t.recFreq ?? 'monthly';
    } else if (t.plan != null && t.pt != null) {
      _mode = 'installment';
      _installments = t.pt!.clamp(2, 120);
    } else {
      _mode = 'single';
    }

    final oneYearAhead = DateTime.now().add(const Duration(days: 365));
    _endDateCtrl = TextEditingController(text: fmtDate(isoFromDate(oneYearAhead)));

    final curAcc = widget.store.accById(_accId);
    if (curAcc?.type == kCardType && curAcc?.card != null) {
      _customIk = invKeyFor(curAcc!.card!, todayStr);
    } else {
      _customIk = null;
    }

    _peerAmtCtrl = TextEditingController();
    final curCur = curAcc?.effectiveCurrency ?? 'BRL';
    final destCur = (t.peer != null && t.peer!.isNotEmpty)
        ? (widget.store.accById(t.peer!)?.effectiveCurrency ?? curCur)
        : curCur;
    final r = curCur != destCur
        ? exchangeRateBetween(
            fromCurrency: curCur,
            toCurrency: destCur,
            rates: widget.store.db.rates,
          )
        : (() {
            final baseCur = widget.store.baseCurrency;
            final baseBrl =
                baseCur == 'BRL' ? 1.0 : widget.store.rateToBrl(baseCur);
            final rawBrl =
                widget.store.resolveDefaultRateToBrl(_accId, todayStr);
            return baseBrl > 0 ? (rawBrl / baseBrl) : rawBrl;
          })();
    _rateCtrl = TextEditingController(
      text: r.toStringAsFixed(4).replaceAll('.', ','),
    );
    if (curCur != destCur && t.amt.abs() > 0) {
      _peerAmtCtrl.text = formatInputCents((t.amt.abs() * r).round());
    }
  }

  @override
  void dispose() {
    _dateCtrl.dispose();
    _payeeCtrl.dispose();
    _memoCtrl.dispose();
    _amtCtrl.dispose();
    _peerAmtCtrl.dispose();
    _rateCtrl.dispose();
    _endDateCtrl.dispose();
    super.dispose();
  }

  List<Account> _availableAccounts() {
    final favs = widget.store.favoriteAccounts;
    final others = widget.store.regularActiveAccounts;
    final list = <Account>[...favs, ...others];
    final current = widget.store.accById(widget.sourceTx.acc);
    if (current != null && !list.any((a) => a.id == current.id)) {
      list.insert(0, current);
    }
    if (list.isEmpty) {
      list.addAll(widget.store.db.accounts);
    }
    return list;
  }

  String _resolveIsoDate(String raw, {String? fallback}) {
    final trimmed = raw.trim();
    if (RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(trimmed)) return trimmed;
    final parts = trimmed.split('/');
    if (parts.length == 3) {
      return '${parts[2].padLeft(4, '0')}-${parts[1].padLeft(2, '0')}-${parts[0].padLeft(2, '0')}';
    }
    return fallback ?? todayISO();
  }

  Future<void> _pickDate(TextEditingController ctrl, {DateTime? firstDate}) async {
    final curIso = _resolveIsoDate(ctrl.text);
    final initialDate = dateFromISO(curIso);
    final picked = await showDatePicker(
      context: context,
      initialDate: initialDate,
      firstDate: firstDate ?? DateTime(2000),
      lastDate: DateTime(2099, 12, 31),
    );
    if (picked != null) {
      setState(() {
        ctrl.text = fmtDate(isoFromDate(picked));
        final targetAcc = widget.store.accById(_accId);
        if (targetAcc?.type == kCardType && targetAcc?.card != null) {
          _customIk = invKeyFor(targetAcc!.card!, isoFromDate(picked));
        }
      });
    }
  }

  Future<void> _commitCopy() async {
    final absCents = (parseCents(_amtCtrl.text) ?? 0).abs();
    if (absCents <= 0) return;

    final isXfer = _catSelection.startsWith('xfer:');
    final signedAmt = isXfer ? -absCents : (_isExpense ? -absCents : absCents);

    final rawPayee = _payeeCtrl.text.trim();
    final finalPayee = rawPayee.isEmpty
        ? (isXfer ? 'Transferência' : 'Sem descrição')
        : rawPayee;

    final trimmedMemo = _memoCtrl.text.trim();
    final dateStr = _resolveIsoDate(_dateCtrl.text);
    final endStr = (_mode == 'recurring' && _hasEndDate)
        ? _resolveIsoDate(_endDateCtrl.text)
        : null;

    final targetAcc = widget.store.accById(_accId);
    final isCard = targetAcc?.type == kCardType && targetAcc?.card != null;
    final ik = (isCard && _customIk != null && _customIk!.isNotEmpty)
        ? _customIk
        : null;

    int? peerSignedAmt;
    double? txRate;
    final curCur = targetAcc?.effectiveCurrency ?? 'BRL';
    if (isXfer) {
      final peerId = _catSelection.substring(5);
      final peerAcc = widget.store.accById(peerId);
      final peerCur = peerAcc?.effectiveCurrency ?? 'BRL';
      if (curCur != peerCur) {
        final peerAbs = (parseCents(_peerAmtCtrl.text) ?? 0).abs();
        if (peerAbs > 0) {
          peerSignedAmt = peerAbs;
          if (curCur != 'BRL' && peerCur == 'BRL' && absCents > 0) {
            txRate = peerAbs / absCents;
          }
        }
      }
    } else if (curCur != 'BRL') {
      txRate = _resolveNonXferRateToBrl(
        widget.store,
        _rateCtrl,
        _accId,
        curCur,
        dateStr,
      );
    }

    final warning = widget.store.checkBudgetExceeded(
      accId: _accId,
      date: dateStr,
      catSelection: _catSelection,
      signedAmt: signedAmt,
      payee: finalPayee,
      mode: isXfer && _mode == 'installment' ? 'single' : _mode,
      installments: _installments,
      txRate: txRate,
    );

    if (warning != null && mounted) {
      final proceed = await showBudgetExceededDialog(context, warning);
      if (!proceed) return;
    }

    widget.store.addTransaction(
      accId: _accId,
      date: dateStr,
      payee: finalPayee,
      catSelection: _catSelection,
      memo: trimmedMemo,
      signedAmt: signedAmt,
      mode: isXfer && _mode == 'installment' ? 'single' : _mode,
      freq: _freq,
      installments: _installments,
      endDate: endStr,
      customIk: ik,
      peerSignedAmt: peerSignedAmt,
      txRate: txRate,
      tags: _tags,
    );

    if (mounted) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colors = OpenMoneyColors(isDark);
    final availableAccs = _availableAccounts();
    final targetAcc = widget.store.accById(_accId);
    final isCard = targetAcc?.type == kCardType && targetAcc?.card != null;
    final isXfer = _catSelection.startsWith('xfer:');

    final catType = _isExpense ? 'Despesa' : 'Receita';
    final catOptions = widget.store.allCategoryOptions(catType);
    final otherAccounts =
        widget.store.transferDestinationAccounts(excludeId: _accId);

    final dropdownItems = <DropdownMenuItem<String>>[
      if (_catSelection.isNotEmpty &&
          !catOptions.any((c) => c.value == _catSelection) &&
          !_catSelection.startsWith('xfer:'))
        DropdownMenuItem(value: _catSelection, child: Text(_catSelection)),
      ...catOptions.map(
        (c) => DropdownMenuItem(value: c.value, child: Text(c.label)),
      ),
      ...otherAccounts.map(
        (a) => DropdownMenuItem(
          value: 'xfer:${a.id}',
          child: Text('⇄ Transferência: ${a.name}'),
        ),
      ),
    ];

    final effectiveCat = dropdownItems.any((i) => i.value == _catSelection)
        ? _catSelection
        : (dropdownItems.isNotEmpty ? dropdownItems.first.value! : '');

    final isSmallScreen = MediaQuery.of(context).size.width < 640;

    final formFields = <Widget>[
              // Conta destino
              DropdownButtonFormField<String>(
                initialValue: _accId,
                isDense: true,
                style: TextStyle(fontSize: 13, color: colors.textPrimary),
                decoration: const InputDecoration(
                  labelText: 'Conta Destino',
                  labelStyle: TextStyle(fontSize: 13),
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  border: OutlineInputBorder(),
                ),
                items: availableAccs
                    .map((a) => DropdownMenuItem(
                          value: a.id,
                          child: Text(
                            (a.isFavorite ? '★ ' : '') +
                                a.name +
                                (a.type == kCardType
                                    ? ' (Cartão)'
                                    : ' (${a.type})'),
                            style: const TextStyle(fontSize: 13),
                          ),
                        ))
                    .toList(),
                onChanged: (v) {
                  if (v != null) {
                    setState(() {
                      _accId = v;
                      final newAcc = widget.store.accById(v);
                      if (newAcc?.type == kCardType && newAcc?.card != null) {
                        _customIk =
                            invKeyFor(newAcc!.card!, _resolveIsoDate(_dateCtrl.text));
                      } else {
                        _customIk = null;
                      }
                      if (_catSelection.startsWith('xfer:$v')) {
                        _catSelection = '';
                      }
                    });
                  }
                },
              ),
              const SizedBox(height: 12),

              // Tipo & Data
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _dateCtrl,
                      style: const TextStyle(fontSize: 13),
                      decoration: InputDecoration(
                        labelText: 'Data (DD/MM/AAAA)',
                        labelStyle: const TextStyle(fontSize: 13),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                        border: const OutlineInputBorder(),
                        suffixIconConstraints: const BoxConstraints(minWidth: 28, maxHeight: 24),
                        suffixIcon: IconButton(
                          padding: EdgeInsets.zero,
                          icon: const Icon(Icons.calendar_month, size: 18),
                          tooltip: 'Escolher data no calendário',
                          onPressed: () => _pickDate(_dateCtrl),
                        ),
                      ),
                      onChanged: (v) {
                        if (isCard && targetAcc != null && targetAcc.card != null) {
                          setState(() {
                            _customIk = invKeyFor(
                              targetAcc.card!,
                              _resolveIsoDate(_dateCtrl.text),
                            );
                          });
                        } else if (_isCompleteDateInput(v)) {
                          setState(() {});
                        }
                      },
                    ),
                  ),
                  if (!isXfer) ...[
                    const SizedBox(width: 12),
                    SegmentedButton<bool>(
                      style: SegmentedButton.styleFrom(
                        selectedBackgroundColor:
                            colors.accent.withValues(alpha: 0.18),
                        selectedForegroundColor: colors.accent,
                        foregroundColor: colors.textSecondary,
                        textStyle: const TextStyle(
                            fontSize: 12.5, fontWeight: FontWeight.w700),
                        visualDensity: VisualDensity.compact,
                      ),
                      segments: const [
                        ButtonSegment(value: true, label: Text('− Despesa')),
                        ButtonSegment(value: false, label: Text('+ Receita')),
                      ],
                      selected: {_isExpense},
                      onSelectionChanged: (s) {
                        setState(() {
                          _isExpense = s.first;
                          final paths = widget.store.allCategoryPaths(
                            _isExpense ? 'Despesa' : 'Receita',
                          );
                          if (!paths.contains(_catSelection) &&
                              !_catSelection.startsWith('xfer:')) {
                            _catSelection = paths.isNotEmpty ? paths.first : '';
                          }
                        });
                      },
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 12),

              // Competência da Fatura se cartão
              if (isCard && targetAcc != null && targetAcc.card != null) ...[
                Builder(
                  builder: (context) {
                    final d = _resolveIsoDate(_dateCtrl.text);
                    final opts = invoiceOptions(
                      card: targetAcc.card!,
                      aroundDate: d,
                      existingKeys:
                          _customIk != null ? [_customIk!] : const [],
                    );
                    final defaultIk = invKeyFor(targetAcc.card!, d);
                    final selIk = (_customIk == null || _customIk!.isEmpty)
                        ? defaultIk
                        : _customIk!;
                    return DropdownButtonFormField<String>(
                      initialValue: opts.any((o) => o.key == selIk)
                          ? selIk
                          : opts.first.key,
                      isExpanded: true,
                      isDense: true,
                      style: TextStyle(fontSize: 13, color: colors.textPrimary),
                      decoration: const InputDecoration(
                        labelText: 'Fatura do Cartão (Competência)',
                        labelStyle: TextStyle(fontSize: 13),
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        border: OutlineInputBorder(),
                      ),
                      items: opts
                          .map((o) => DropdownMenuItem(
                                value: o.key,
                                child: Text(o.key == defaultIk
                                    ? '${o.label} [Padrão]'
                                    : o.label,
                                    style: const TextStyle(fontSize: 13)),
                              ))
                          .toList(),
                      onChanged: (v) => setState(() => _customIk = v),
                    );
                  },
                ),
                const SizedBox(height: 12),
              ],

              // Favorecido / Descrição
              TextField(
                controller: _payeeCtrl,
                style: const TextStyle(fontSize: 13),
                decoration: const InputDecoration(
                  labelText: 'Favorecido / Descrição',
                  labelStyle: TextStyle(fontSize: 13),
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),

              // Categoria ou Transferência
              CategorySelectFormField(
                store: widget.store,
                categoryType: catType,
                currentSelection: effectiveCat,
                excludeAccountId: _accId,
                labelText: 'Categoria ou Transferência',
                onChanged: (v) {
                  setState(() {
                    _catSelection = v;
                    if (v.startsWith('xfer:')) {
                      final peerId = v.substring(5);
                      final srcCur = targetAcc?.effectiveCurrency ?? 'BRL';
                      final destCur =
                          widget.store.accById(peerId)?.effectiveCurrency ??
                              'BRL';
                      if (srcCur != destCur) {
                        final r = exchangeRateBetween(
                          fromCurrency: srcCur,
                          toCurrency: destCur,
                          rates: widget.store.db.rates,
                        );
                        _rateCtrl.text =
                            r.toStringAsFixed(4).replaceAll('.', ',');
                        final srcCents = (parseCents(_amtCtrl.text) ?? 0).abs();
                        if (srcCents > 0) {
                          _peerAmtCtrl.text =
                              formatInputCents((srcCents * r).round());
                        }
                      }
                    }
                  });
                },
              ),
              const SizedBox(height: 12),

              // Valor & Observação
              Builder(builder: (context) {
                final srcCur = targetAcc?.effectiveCurrency ?? 'BRL';
                final srcMeta = currencyMetaFor(srcCur);
                final peerId = isXfer ? _catSelection.substring(5) : null;
                final destCur = peerId != null
                    ? (widget.store.accById(peerId)?.effectiveCurrency ?? 'BRL')
                    : srcCur;
                final isCross = isXfer && srcCur != destCur;

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _amtCtrl,
                            keyboardType: const TextInputType.numberWithOptions(
                              decimal: true,
                            ),
                            style: const TextStyle(fontSize: 13),
                            onChanged: (_) {
                              if (!isCross || _isUpdatingCross) return;
                              _isUpdatingCross = true;
                              final srcCents =
                                  (parseCents(_amtCtrl.text) ?? 0).abs();
                              final r = _parseRateInput(_rateCtrl.text) ?? 1.0;
                              _peerAmtCtrl.text =
                                  formatInputCents((srcCents * r).round());
                              _isUpdatingCross = false;
                            },
                            decoration: InputDecoration(
                              labelText: 'Valor (${srcMeta.symbol})',
                              labelStyle: const TextStyle(fontSize: 13),
                              prefixText: '${srcMeta.symbol} ',
                              prefixStyle: const TextStyle(fontSize: 13),
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 10),
                              border: const OutlineInputBorder(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: _memoCtrl,
                            style: const TextStyle(fontSize: 13),
                            decoration: const InputDecoration(
                              labelText: 'Nota / Observação',
                              labelStyle: TextStyle(fontSize: 13),
                              isDense: true,
                              contentPadding: EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 10),
                              border: OutlineInputBorder(),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    TagInputField(
                      tags: _tags,
                      onChanged: (list) => setState(() => _tags = list),
                      availableTags: widget.store.allTags,
                      colors: OpenMoneyColors(
                          Theme.of(context).brightness == Brightness.dark),
                    ),
                    if (isCross)
                      _CrossCurrencyTransferBox(
                        store: widget.store,
                        sourceCurrency: srcCur,
                        destCurrency: destCur,
                        dateIso: _resolveIsoDate(_dateCtrl.text),
                        rateCtrl: _rateCtrl,
                        destAmtCtrl: _peerAmtCtrl,
                        colors: colors,
                        onRateChanged: () {
                          if (_isUpdatingCross) return;
                          _isUpdatingCross = true;
                          final srcCents =
                              (parseCents(_amtCtrl.text) ?? 0).abs();
                          final r = _parseRateInput(_rateCtrl.text);
                          if (r != null && srcCents > 0) {
                            _peerAmtCtrl.text =
                                formatInputCents((srcCents * r).round());
                          }
                          _isUpdatingCross = false;
                        },
                        onDestAmtChanged: () {
                          if (_isUpdatingCross) return;
                          _isUpdatingCross = true;
                          final srcCents =
                              (parseCents(_amtCtrl.text) ?? 0).abs();
                          final destCents =
                              (parseCents(_peerAmtCtrl.text) ?? 0).abs();
                          if (srcCents > 0 && destCents > 0) {
                            final r = destCents / srcCents;
                            _rateCtrl.text =
                                r.toStringAsFixed(4).replaceAll('.', ',');
                          }
                          _isUpdatingCross = false;
                        },
                      )
                    else if (!isXfer &&
                        srcCur != 'BRL' &&
                        srcCur != widget.store.baseCurrency)
                      _ForeignTransactionRateBox(
                        store: widget.store,
                        accountId: _accId,
                        sourceCurrency: srcCur,
                        dateIso: _resolveIsoDate(_dateCtrl.text),
                        amtCtrl: _amtCtrl,
                        rateCtrl: _rateCtrl,
                        colors: colors,
                        preserveInitialValue: false,
                      ),
                  ],
                );
              }),
              const SizedBox(height: 12),

              // Modo Flexível: Único, Recorrente, Parcelado
              if (!isXfer) ...[
                const Text(
                  'Modo do Lançamento:',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
                ),
                const SizedBox(height: 6),
                SegmentedButton<String>(
                  style: SegmentedButton.styleFrom(
                    selectedBackgroundColor:
                        colors.accent.withValues(alpha: 0.18),
                    selectedForegroundColor: colors.accent,
                    foregroundColor: colors.textSecondary,
                    textStyle: const TextStyle(
                        fontSize: 12.5, fontWeight: FontWeight.w700),
                    visualDensity: VisualDensity.compact,
                  ),
                  segments: const [
                    ButtonSegment(value: 'single', label: Text('Único')),
                    ButtonSegment(value: 'recurring', label: Text('Recorrente')),
                    ButtonSegment(value: 'installment', label: Text('Parcelado')),
                  ],
                  selected: {_mode},
                  onSelectionChanged: (s) => setState(() => _mode = s.first),
                ),
                const SizedBox(height: 12),

                if (_mode == 'recurring') ...[
                  Row(
                    children: [
                      Expanded(
                        child: DropdownButtonFormField<String>(
                          initialValue: _freq,
                          isDense: true,
                          style: TextStyle(fontSize: 13, color: colors.textPrimary),
                          decoration: const InputDecoration(
                            labelText: 'Frequência',
                            labelStyle: TextStyle(fontSize: 13),
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            border: OutlineInputBorder(),
                          ),
                          items: kRecurrenceFrequencyOptions
                              .map((o) => DropdownMenuItem(
                                    value: o.id,
                                    child: Text(o.label, style: const TextStyle(fontSize: 13)),
                                  ))
                              .toList(),
                          onChanged: (v) {
                            if (v != null) setState(() => _freq = v);
                          },
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: const Text('Definir Data de Término', style: TextStyle(fontSize: 13)),
                    value: _hasEndDate,
                    onChanged: (v) => setState(() => _hasEndDate = v ?? false),
                  ),
                  if (_hasEndDate) ...[
                    const SizedBox(height: 4),
                    TextField(
                      controller: _endDateCtrl,
                      style: const TextStyle(fontSize: 13),
                      decoration: InputDecoration(
                        labelText: 'Data de Término (DD/MM/AAAA)',
                        labelStyle: const TextStyle(fontSize: 13),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                        border: const OutlineInputBorder(),
                        suffixIconConstraints: const BoxConstraints(minWidth: 28, maxHeight: 24),
                        suffixIcon: IconButton(
                          padding: EdgeInsets.zero,
                          icon: const Icon(Icons.calendar_month, size: 18),
                          tooltip: 'Escolher data de término',
                          onPressed: () {
                            final baseD = dateFromISO(_resolveIsoDate(_dateCtrl.text));
                            _pickDate(_endDateCtrl, firstDate: baseD);
                          },
                        ),
                      ),
                    ),
                  ],
                ] else if (_mode == 'installment') ...[
                  DropdownButtonFormField<int>(
                    initialValue: _installments,
                    isDense: true,
                    style: TextStyle(fontSize: 13, color: colors.textPrimary),
                    decoration: const InputDecoration(
                      labelText: 'Número de Parcelas',
                      labelStyle: TextStyle(fontSize: 13),
                      isDense: true,
                      contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      border: OutlineInputBorder(),
                    ),
                    items: List.generate(
                      119,
                      (i) => DropdownMenuItem(
                        value: i + 2,
                        child: Text('${i + 2}x', style: const TextStyle(fontSize: 13)),
                      ),
                    ),
                    onChanged: (v) {
                      if (v != null) setState(() => _installments = v);
                    },
                  ),
                ],
              ],
            ];

    if (isSmallScreen) {
      return Dialog.fullscreen(
        backgroundColor: colors.bgSecondary,
        child: Scaffold(
          backgroundColor: colors.bgSecondary,
          resizeToAvoidBottomInset: true,
          appBar: AppBar(
            backgroundColor: colors.bgSecondary,
            leading: IconButton(
              icon: const Icon(Icons.close),
              tooltip: 'Cancelar',
              onPressed: () => Navigator.pop(context),
            ),
            title: Row(
              children: [
                Icon(Icons.copy_rounded, color: colors.accent, size: 18),
                const SizedBox(width: 8),
                const Text(
                  'Copiar Lançamento',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
                ),
              ],
            ),
          ),
          body: SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ...formFields,
                  const SizedBox(height: 20),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          onPressed: () => Navigator.pop(context),
                          child: const Text('Cancelar'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          icon: const Icon(Icons.check, size: 18),
                          label: const Text('Salvar'),
                          onPressed: _commitCopy,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return AlertDialog(
      backgroundColor: colors.bgSecondary,
      title: Row(
        children: [
          Icon(Icons.copy_rounded, color: colors.accent, size: 20),
          const SizedBox(width: 8),
          const Text('Copiar Lançamento'),
        ],
      ),
      content: SizedBox(
        width: 500,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: formFields,
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton.icon(
          icon: const Icon(Icons.check, size: 18),
          label: const Text('Salvar'),
          onPressed: _commitCopy,
        ),
      ],
    );
  }
}

Future<void> showInvoicePaymentModal(
  BuildContext context,
  MoneyStore store, {
  required Account cardAccount,
  required InvoiceSummary summary,
}) async {
  final amtCtrl = TextEditingController(
    text: formatInputCents(
      summary.remainingCents > 0
          ? summary.remainingCents
          : summary.chargesCents,
    ),
  );
  final dateCtrl = TextEditingController(text: fmtDate(todayISO()));
  final memoCtrl = TextEditingController(
    text: 'Pagamento da Fatura ${fmtMonth(summary.key)}',
  );
  final sourceAccounts =
      store.db.accounts.where((a) => a.id != cardAccount.id).toList();
  String sourceAccId = summary.payAccountId.isNotEmpty &&
          sourceAccounts.any((a) => a.id == summary.payAccountId)
      ? summary.payAccountId
      : (sourceAccounts.isNotEmpty ? sourceAccounts.first.id : '');

  await showDialog(
    context: context,
    builder: (ctx) => StatefulBuilder(
      builder: (context, setModalState) {
        return AlertDialog(
          title: Text('Pagar / Adiantar Fatura — ${cardAccount.name}'),
          content: SizedBox(
            width: 420,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Fatura de ${fmtMonth(summary.key)} • Saldo Restante: ${formatCurrency(summary.remainingCents, cardAccount.effectiveCurrency)}',
                  style: const TextStyle(fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 14),
                if (sourceAccounts.isNotEmpty)
                  DropdownButtonFormField<String>(
                    initialValue: sourceAccId,
                    decoration: const InputDecoration(
                      labelText: 'Debitar da Conta',
                      border: OutlineInputBorder(),
                    ),
                    items: sourceAccounts
                        .map((a) => DropdownMenuItem(
                              value: a.id,
                              child: Text(a.name),
                            ))
                        .toList(),
                    onChanged: (v) {
                      if (v != null) setModalState(() => sourceAccId = v);
                    },
                  ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: amtCtrl,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: InputDecoration(
                          labelText:
                              'Valor a Pagar (${currencyMetaFor(cardAccount.effectiveCurrency).symbol})',
                          prefixText:
                              '${currencyMetaFor(cardAccount.effectiveCurrency).symbol} ',
                          border: const OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: dateCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Data do Pagamento',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: memoCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Observação',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar'),
            ),
            FilledButton.icon(
              icon: const Icon(Icons.payments_outlined, size: 18),
              label: const Text('Confirmar Pagamento'),
              onPressed: () {
                final cents = (parseCents(amtCtrl.text) ?? 0).abs();
                if (cents <= 0 || sourceAccId.isEmpty) return;
                final rawD = dateCtrl.text.trim();
                final parts = rawD.split('/');
                final iso = parts.length == 3
                    ? '${parts[2].padLeft(4, '0')}-${parts[1].padLeft(2, '0')}-${parts[0].padLeft(2, '0')}'
                    : todayISO();
                store.payInvoice(
                  cardId: cardAccount.id,
                  invoiceKey: summary.key,
                  amountCents: cents,
                  paymentDate: iso,
                  sourceAccountId: sourceAccId,
                  memo: memoCtrl.text.trim(),
                );
                Navigator.pop(ctx);
              },
            ),
          ],
        );
      },
    ),
  );
}

bool _isCompleteDateInput(String raw) {
  final t = raw.trim();
  return RegExp(r'^\d{2}/\d{2}/\d{4}$').hasMatch(t) ||
      RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(t);
}

double? _resolveNonXferRateToBrl(
  MoneyStore store,
  TextEditingController rateCtrl,
  String accId,
  String curCur,
  String isoDate,
) {
  if (curCur == 'BRL') return null;
  if (curCur != store.baseCurrency) {
    final parsed = _parseRateInput(rateCtrl.text);
    if (parsed != null && parsed > 0) {
      final baseCur = store.baseCurrency;
      final baseBrl = baseCur == 'BRL' ? 1.0 : store.rateToBrl(baseCur);
      return baseCur == 'BRL' ? parsed : (parsed * baseBrl);
    }
  }
  return store.resolveDefaultRateToBrl(accId, isoDate);
}

double? _parseRateInput(String raw) {
  final trimmed = raw.trim().replaceAll(' ', '');
  if (trimmed.isEmpty) return null;
  final normalized = trimmed.contains(',')
      ? trimmed.replaceAll('.', '').replaceAll(',', '.')
      : trimmed;
  final v = double.tryParse(normalized);
  if (v == null || v.isNaN || v <= 0) return null;
  return v;
}

class _CrossCurrencyTransferBox extends StatefulWidget {
  final MoneyStore store;
  final String sourceCurrency;
  final String destCurrency;
  final String dateIso;
  final TextEditingController rateCtrl;
  final TextEditingController destAmtCtrl;
  final OpenMoneyColors colors;
  final VoidCallback onRateChanged;
  final VoidCallback onDestAmtChanged;

  const _CrossCurrencyTransferBox({
    required this.store,
    required this.sourceCurrency,
    required this.destCurrency,
    required this.dateIso,
    required this.rateCtrl,
    required this.destAmtCtrl,
    required this.colors,
    required this.onRateChanged,
    required this.onDestAmtChanged,
  });

  @override
  State<_CrossCurrencyTransferBox> createState() =>
      _CrossCurrencyTransferBoxState();
}

class _CrossCurrencyTransferBoxState extends State<_CrossCurrencyTransferBox> {
  bool _isLoadingHist = false;

  Future<void> _applyHistoricalTransferRate() async {
    if (_isLoadingHist) return;
    setState(() => _isLoadingHist = true);
    try {
      final srcBrl = widget.sourceCurrency == 'BRL'
          ? 1.0
          : (await CurrencyRateService.fetchHistoricalRateToBrl(
                widget.sourceCurrency,
                widget.dateIso,
              ))
                  ?.rateToBrl;
      final destBrl = widget.destCurrency == 'BRL'
          ? 1.0
          : (await CurrencyRateService.fetchHistoricalRateToBrl(
                widget.destCurrency,
                widget.dateIso,
              ))
                  ?.rateToBrl;
      if (!mounted) return;
      if (srcBrl != null && srcBrl > 0 && destBrl != null && destBrl > 0) {
        final pairRate = srcBrl / destBrl;
        widget.rateCtrl.text = pairRate.toStringAsFixed(4).replaceAll('.', ',');
        widget.onRateChanged();
      }
    } finally {
      if (mounted) setState(() => _isLoadingHist = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final destMeta = currencyMetaFor(widget.destCurrency);
    final info = widget.sourceCurrency != 'BRL'
        ? widget.store.rateInfoFor(widget.sourceCurrency)
        : widget.store.rateInfoFor(widget.destCurrency);
    final dateLabel = info != null && info.updatedAt.isNotEmpty
        ? ' · Atualizado ${formatRateDate(info.updatedAt)}'
        : '';
    final isPast = widget.dateIso.compareTo(todayISO()) < 0;

    return Container(
      padding: const EdgeInsets.all(10),
      margin: const EdgeInsets.only(top: 10),
      decoration: BoxDecoration(
        color: widget.colors.accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: widget.colors.accent.withValues(alpha: 0.28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.currency_exchange, size: 14, color: widget.colors.accent),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Conversão Cambial (${widget.sourceCurrency} → ${widget.destCurrency})$dateLabel',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: widget.colors.accent,
                  ),
                ),
              ),
              if (isPast)
                TextButton.icon(
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                  icon: _isLoadingHist
                      ? const SizedBox(
                          width: 11,
                          height: 11,
                          child: CircularProgressIndicator(strokeWidth: 1.5),
                        )
                      : const Icon(Icons.history, size: 13),
                  label: Text(
                    'BCB ${fmtDate(widget.dateIso)}',
                    style: const TextStyle(fontSize: 11),
                  ),
                  onPressed: _isLoadingHist ? null : _applyHistoricalTransferRate,
                ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: widget.rateCtrl,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  style: const TextStyle(fontSize: 13),
                  onChanged: (_) => widget.onRateChanged(),
                  decoration: InputDecoration(
                    labelText:
                        'Cotação (1 ${widget.sourceCurrency} = ? ${widget.destCurrency})',
                    labelStyle: const TextStyle(fontSize: 12),
                    isDense: true,
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                    border: const OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TextField(
                  controller: widget.destAmtCtrl,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  style: const TextStyle(fontSize: 13),
                  onChanged: (_) => widget.onDestAmtChanged(),
                  decoration: InputDecoration(
                    labelText: 'Valor na Conta Destino (${destMeta.symbol})',
                    labelStyle: const TextStyle(fontSize: 12),
                    prefixText: '${destMeta.symbol} ',
                    prefixStyle: const TextStyle(fontSize: 13),
                    isDense: true,
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                    border: const OutlineInputBorder(),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Text(
            'Você pode ajustar a cotação ou diretamente o valor creditado no destino para incluir taxas/IOF.',
            style: TextStyle(fontSize: 10.5, color: widget.colors.textSecondary),
          ),
        ],
      ),
    );
  }
}

class _ForeignTransactionRateBox extends StatefulWidget {
  final MoneyStore store;
  final String accountId;
  final String sourceCurrency;
  final String dateIso;
  final TextEditingController amtCtrl;
  final TextEditingController rateCtrl;
  final OpenMoneyColors colors;
  final bool preserveInitialValue;

  const _ForeignTransactionRateBox({
    required this.store,
    required this.accountId,
    required this.sourceCurrency,
    required this.dateIso,
    required this.amtCtrl,
    required this.rateCtrl,
    required this.colors,
    required this.preserveInitialValue,
  });

  @override
  State<_ForeignTransactionRateBox> createState() =>
      _ForeignTransactionRateBoxState();
}

class _ForeignTransactionRateBoxState
    extends State<_ForeignTransactionRateBox> {
  bool _editedManually = false;
  bool _isLoadingApi = false;
  String _sourceLabel = '';
  HistoricalRateResult? _apiResult;

  @override
  void initState() {
    super.initState();
    _initRateBox();
  }

  @override
  void didUpdateWidget(covariant _ForeignTransactionRateBox oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.accountId != widget.accountId ||
        oldWidget.sourceCurrency != widget.sourceCurrency ||
        oldWidget.dateIso != widget.dateIso) {
      if (oldWidget.accountId != widget.accountId ||
          oldWidget.sourceCurrency != widget.sourceCurrency) {
        _editedManually = false;
      }
      _apiResult = CurrencyRateService.cachedHistoricalRate(
        widget.sourceCurrency,
        widget.dateIso,
      );
      if (!widget.preserveInitialValue && !_editedManually) {
        _applyAutoSuggestion();
      } else {
        _prefetchHistoricalChipIfNeeded();
      }
    }
  }

  double _toDisplayRate(double rateToBrl) {
    final baseCur = widget.store.baseCurrency;
    if (baseCur == 'BRL') return rateToBrl;
    final baseBrl = widget.store.rateToBrl(baseCur);
    return baseBrl > 0 ? (rateToBrl / baseBrl) : rateToBrl;
  }

  void _setRateToBrl(double rateToBrl, String label, {bool manual = false}) {
    final disp = _toDisplayRate(rateToBrl);
    widget.rateCtrl.text = disp.toStringAsFixed(4).replaceAll('.', ',');
    setState(() {
      _sourceLabel = label;
      if (manual) _editedManually = true;
    });
  }

  void _initRateBox() {
    final isPast = widget.dateIso.compareTo(todayISO()) < 0;
    _apiResult = isPast
        ? CurrencyRateService.cachedHistoricalRate(
            widget.sourceCurrency,
            widget.dateIso,
          )
        : null;
    if (widget.preserveInitialValue) {
      _sourceLabel = 'Salva no lançamento';
      _prefetchHistoricalChipIfNeeded();
    } else {
      _applyAutoSuggestion();
    }
  }

  void _applyAutoSuggestion() {
    final isPast = widget.dateIso.compareTo(todayISO()) < 0;
    if (isPast) {
      final xfer = widget.store.lastTransferRateForAccount(
        widget.accountId,
        onOrBeforeDate: widget.dateIso,
      );
      if (xfer != null && xfer.rateToBrl > 0) {
        _setRateToBrl(xfer.rateToBrl, 'Transf. ${fmtDate(xfer.date)}');
        _prefetchHistoricalChipIfNeeded();
        return;
      }
      final cached = CurrencyRateService.cachedHistoricalRate(
        widget.sourceCurrency,
        widget.dateIso,
      );
      if (cached != null && cached.rateToBrl > 0) {
        _apiResult = cached;
        _setRateToBrl(
          cached.rateToBrl,
          '${cached.source} ${fmtDate(cached.quoteDateIso)}',
        );
        return;
      }
      _setRateToBrl(
        widget.store.rateToBrl(widget.sourceCurrency),
        'Cotação atual',
      );
      _fetchHistoricalRate(applyIfUnedited: true);
    } else {
      _setRateToBrl(
        widget.store.rateToBrl(widget.sourceCurrency),
        'Cotação atual',
      );
    }
  }

  void _prefetchHistoricalChipIfNeeded() {
    if (widget.dateIso.compareTo(todayISO()) >= 0) return;
    if (_apiResult == null) {
      _fetchHistoricalRate(applyIfUnedited: false);
    }
  }

  Future<void> _fetchHistoricalRate({required bool applyIfUnedited}) async {
    if (widget.dateIso.compareTo(todayISO()) >= 0) return;
    final reqCur = widget.sourceCurrency;
    final reqDate = widget.dateIso;
    if (mounted) setState(() => _isLoadingApi = true);
    try {
      final res =
          await CurrencyRateService.fetchHistoricalRateToBrl(reqCur, reqDate);
      if (!mounted) return;
      if (reqCur != widget.sourceCurrency || reqDate != widget.dateIso) return;
      setState(() {
        _apiResult = res;
        _isLoadingApi = false;
      });
      if (res != null &&
          res.rateToBrl > 0 &&
          applyIfUnedited &&
          !_editedManually) {
        _setRateToBrl(
          res.rateToBrl,
          '${res.source} ${fmtDate(res.quoteDateIso)}',
        );
      }
    } finally {
      if (mounted && _isLoadingApi) {
        setState(() => _isLoadingApi = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final baseCur = widget.store.baseCurrency;
    final isPast = widget.dateIso.compareTo(todayISO()) < 0;
    final xfer = widget.store.lastTransferRateForAccount(
      widget.accountId,
      onOrBeforeDate: widget.dateIso,
    );
    final currentBrl = widget.store.rateToBrl(widget.sourceCurrency);

    return Container(
      padding: const EdgeInsets.all(10),
      margin: const EdgeInsets.only(top: 10),
      decoration: BoxDecoration(
        color: widget.colors.accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: widget.colors.accent.withValues(alpha: 0.28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.currency_exchange, size: 14, color: widget.colors.accent),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Taxa de Câmbio (${widget.sourceCurrency} → $baseCur)'
                  '${_sourceLabel.isNotEmpty ? " · $_sourceLabel" : ""}',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: widget.colors.accent,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: widget.rateCtrl,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  style: const TextStyle(fontSize: 13),
                  onChanged: (_) {
                    if (!_editedManually || _sourceLabel != 'Manual') {
                      setState(() {
                        _editedManually = true;
                        _sourceLabel = 'Manual';
                      });
                    }
                  },
                  decoration: InputDecoration(
                    labelText: '1 ${widget.sourceCurrency} em $baseCur',
                    labelStyle: const TextStyle(fontSize: 12),
                    isDense: true,
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
                    border: const OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: widget.amtCtrl,
                builder: (context, amtVal, _) {
                  return ValueListenableBuilder<TextEditingValue>(
                    valueListenable: widget.rateCtrl,
                    builder: (context, rateVal, _) {
                      final absCents = (parseCents(amtVal.text) ?? 0).abs();
                      final r = _parseRateInput(rateVal.text);
                      final conv = (absCents > 0 && r != null)
                          ? (absCents * r).round()
                          : 0;
                      return Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: widget.colors.surfaceGlass,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: widget.colors.borderGlass),
                        ),
                        child: Text(
                          '≈ ${formatCurrency(conv, baseCur)}',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: widget.colors.textPrimary,
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              if (xfer != null)
                ActionChip(
                  visualDensity: VisualDensity.compact,
                  avatar: const Icon(Icons.swap_horiz, size: 14),
                  label: Text(
                    'Última transf. (${fmtDate(xfer.date)}): '
                    '${_toDisplayRate(xfer.rateToBrl).toStringAsFixed(4).replaceAll('.', ',')}',
                    style: const TextStyle(fontSize: 11),
                  ),
                  onPressed: () => _setRateToBrl(
                    xfer.rateToBrl,
                    'Transf. ${fmtDate(xfer.date)}',
                    manual: true,
                  ),
                ),
              if (isPast)
                ActionChip(
                  visualDensity: VisualDensity.compact,
                  avatar: _isLoadingApi
                      ? const SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(strokeWidth: 1.5),
                        )
                      : const Icon(Icons.history, size: 14),
                  label: Text(
                    _apiResult != null
                        ? '${_apiResult!.source} (${fmtDate(_apiResult!.quoteDateIso)}): '
                            '${_toDisplayRate(_apiResult!.rateToBrl).toStringAsFixed(4).replaceAll('.', ',')}'
                        : (_isLoadingApi
                            ? 'Buscando ${fmtDate(widget.dateIso)}...'
                            : 'Buscar BCB (${fmtDate(widget.dateIso)})'),
                    style: const TextStyle(fontSize: 11),
                  ),
                  onPressed: _isLoadingApi
                      ? null
                      : () async {
                          if (_apiResult != null) {
                            _setRateToBrl(
                              _apiResult!.rateToBrl,
                              '${_apiResult!.source} ${fmtDate(_apiResult!.quoteDateIso)}',
                              manual: true,
                            );
                          } else {
                            await _fetchHistoricalRate(applyIfUnedited: false);
                            if (mounted && _apiResult != null) {
                              _setRateToBrl(
                                _apiResult!.rateToBrl,
                                '${_apiResult!.source} ${fmtDate(_apiResult!.quoteDateIso)}',
                                manual: true,
                              );
                            }
                          }
                        },
                ),
              ActionChip(
                visualDensity: VisualDensity.compact,
                avatar: const Icon(Icons.today, size: 14),
                label: Text(
                  'Atual: ${_toDisplayRate(currentBrl).toStringAsFixed(4).replaceAll('.', ',')}',
                  style: const TextStyle(fontSize: 11),
                ),
                onPressed: () =>
                    _setRateToBrl(currentBrl, 'Cotação atual', manual: true),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
