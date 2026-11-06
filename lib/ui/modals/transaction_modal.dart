import 'package:flutter/material.dart';
import '../../models/openmoney_models.dart';
import '../../store/money_store.dart';
import '../theme/liquid_glass.dart';
import '../widgets/category_select_form_field.dart';

Future<void> showTransactionCreateModal(
  BuildContext context,
  MoneyStore store, {
  String? initialAccountId,
}) async {
  await showDialog(
    context: context,
    builder: (ctx) => _TransactionCreateDialog(
      store: store,
      initialAccountId: initialAccountId,
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

  if (!isSeries) {
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Excluir Lançamento'),
        content: Text(
          'Confirma a exclusão de "${tx.payee}" (${brl(tx.amt)}) em ${fmtDate(tx.date)}?',
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
            '"${tx.payee}" (${brl(tx.amt)}) faz parte de uma série ${tx.recId != null ? "recorrente" : "parcelada"}.\n\nNota: Lançamentos já conciliados nunca são excluídos em lote.',
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
  late bool _isExpense;
  late String _catSelection;
  late String? _customIk;
  ScopeChoice _scope = ScopeChoice.only;

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
        widget.store.db.accounts.where((a) => a.id != _accId).toList();

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

    return AlertDialog(
      backgroundColor: colors.bgSecondary,
      title: const Text('Editar Lançamento'),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
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
                      onChanged: (_) {
                        if (isCard && targetAcc != null && targetAcc.card != null) {
                          setState(() {
                            _customIk = invKeyFor(
                              targetAcc.card!,
                              _resolveIsoDate(),
                            );
                          });
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  SegmentedButton<bool>(
                    style: const ButtonStyle(
                      textStyle: WidgetStatePropertyAll(TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
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
                onChanged: (v) => setState(() => _catSelection = v),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _amtCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      style: const TextStyle(fontSize: 13),
                      decoration: const InputDecoration(
                        labelText: 'Valor (R\$)',
                        labelStyle: TextStyle(fontSize: 13),
                        prefixText: 'R\$ ',
                        prefixStyle: TextStyle(fontSize: 13),
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                        border: OutlineInputBorder(),
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
                        contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
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
            ],
          ),
        ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      actions: [
        LayoutBuilder(
          builder: (context, constraints) {
            final isNarrow = constraints.maxWidth < 480;
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

            final cancelBtn = TextButton(
              style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancelar'),
            );

            final saveBtn = FilledButton.icon(
              style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
              icon: const Icon(Icons.check, size: 18),
              label: const Text('Salvar Alterações'),
              onPressed: _handleSave,
            );

            if (isNarrow) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      if (widget.tx.auto != true) copyBtn,
                      if (widget.tx.auto != true) const SizedBox(width: 8),
                      deleteBtn,
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      cancelBtn,
                      const SizedBox(width: 8),
                      saveBtn,
                    ],
                  ),
                ],
              );
            }

            return Row(
              children: [
                if (widget.tx.auto != true) copyBtn,
                if (widget.tx.auto != true) const SizedBox(width: 6),
                deleteBtn,
                const Spacer(),
                cancelBtn,
                const SizedBox(width: 8),
                saveBtn,
              ],
            );
          },
        ),
      ],
    );
  }
}

class _TransactionCreateDialog extends StatefulWidget {
  final MoneyStore store;
  final String? initialAccountId;

  const _TransactionCreateDialog({
    required this.store,
    this.initialAccountId,
  });

  @override
  State<_TransactionCreateDialog> createState() =>
      _TransactionCreateDialogState();
}

class _TransactionCreateDialogState extends State<_TransactionCreateDialog> {
  late String _accId;
  late final TextEditingController _dateCtrl;
  late final TextEditingController _payeeCtrl;
  late final TextEditingController _memoCtrl;
  late final TextEditingController _amtCtrl;
  late final TextEditingController _endDateCtrl;
  late bool _isExpense;
  late String _catSelection;
  late String? _customIk;

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

    _dateCtrl = TextEditingController(text: fmtDate(todayISO()));
    _payeeCtrl = TextEditingController();
    _memoCtrl = TextEditingController();
    _amtCtrl = TextEditingController();
    _isExpense = true;

    final catPaths = widget.store.allCategoryPaths('Despesa');
    _catSelection = catPaths.isNotEmpty ? catPaths.first : '';

    final oneYearAhead = DateTime.now().add(const Duration(days: 365));
    _endDateCtrl =
        TextEditingController(text: fmtDate(isoFromDate(oneYearAhead)));

    final curAcc = widget.store.accById(_accId);
    if (curAcc?.type == kCardType && curAcc?.card != null) {
      _customIk = invKeyFor(curAcc!.card!, todayISO());
    } else {
      _customIk = null;
    }
  }

  @override
  void dispose() {
    _dateCtrl.dispose();
    _payeeCtrl.dispose();
    _memoCtrl.dispose();
    _amtCtrl.dispose();
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
        _isExpense = match.isExpense;
        if (match.category.isNotEmpty) {
          _catSelection = match.category;
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
      _isExpense = s.isExpense;
      if (s.category.isNotEmpty) {
        _catSelection = s.category;
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

  void _commitCreate() {
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
    );

    Navigator.of(context).pop();
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
        widget.store.activeAccounts.where((a) => a.id != _accId).toList();

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

    return AlertDialog(
      backgroundColor: colors.bgSecondary,
      title: Row(
        children: [
          Icon(Icons.add_circle, color: colors.accent, size: 20),
          const SizedBox(width: 8),
          const Text('Novo Lançamento'),
        ],
      ),
      content: SizedBox(
        width: 500,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Conta do Lançamento
              DropdownButtonFormField<String>(
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
                      onChanged: (_) {
                        if (isCard &&
                            targetAcc != null &&
                            targetAcc.card != null) {
                          setState(() {
                            _customIk = invKeyFor(
                              targetAcc.card!,
                              _resolveIsoDate(_dateCtrl.text),
                            );
                          });
                        }
                      },
                    ),
                  ),
                  if (!isXfer) ...[
                    const SizedBox(width: 12),
                    SegmentedButton<bool>(
                      style: const ButtonStyle(
                        textStyle: WidgetStatePropertyAll(TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
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
                            _catSelection =
                                paths.isNotEmpty ? paths.first : '';
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

              // Favorecido / Descrição com Autocompletar inteligente
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

              // Categoria ou Transferência
              CategorySelectFormField(
                store: widget.store,
                categoryType: catType,
                currentSelection: effectiveCat,
                excludeAccountId: _accId,
                labelText: 'Categoria ou Transferência',
                onChanged: (v) => setState(() => _catSelection = v),
              ),
              const SizedBox(height: 12),

              // Valor & Observação
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _amtCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      style: const TextStyle(fontSize: 13),
                      decoration: const InputDecoration(
                        labelText: 'Valor (R\$)',
                        labelStyle: TextStyle(fontSize: 13),
                        prefixText: 'R\$ ',
                        prefixStyle: TextStyle(fontSize: 13),
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                        border: OutlineInputBorder(),
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
                        contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Modo Flexível: Único, Recorrente, Parcelado
              if (!isXfer) ...[
                const Text(
                  'Modo do Lançamento:',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
                ),
                const SizedBox(height: 6),
                SegmentedButton<String>(
                  style: const ButtonStyle(
                    textStyle: WidgetStatePropertyAll(TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
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
          icon: const Icon(Icons.check, size: 18),
          label: const Text('Salvar Lançamento'),
          onPressed: _commitCreate,
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
  late final TextEditingController _endDateCtrl;
  late bool _isExpense;
  late String _catSelection;
  late String? _customIk;

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
  }

  @override
  void dispose() {
    _dateCtrl.dispose();
    _payeeCtrl.dispose();
    _memoCtrl.dispose();
    _amtCtrl.dispose();
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

  void _commitCopy() {
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
    );

    Navigator.of(context).pop();
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
        widget.store.activeAccounts.where((a) => a.id != _accId).toList();

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
            children: [
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
                      onChanged: (_) {
                        if (isCard && targetAcc != null && targetAcc.card != null) {
                          setState(() {
                            _customIk = invKeyFor(
                              targetAcc.card!,
                              _resolveIsoDate(_dateCtrl.text),
                            );
                          });
                        }
                      },
                    ),
                  ),
                  if (!isXfer) ...[
                    const SizedBox(width: 12),
                    SegmentedButton<bool>(
                      style: const ButtonStyle(
                        textStyle: WidgetStatePropertyAll(TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
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
                onChanged: (v) => setState(() => _catSelection = v),
              ),
              const SizedBox(height: 12),

              // Valor & Observação
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _amtCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      style: const TextStyle(fontSize: 13),
                      decoration: const InputDecoration(
                        labelText: 'Valor (R\$)',
                        labelStyle: TextStyle(fontSize: 13),
                        prefixText: 'R\$ ',
                        prefixStyle: TextStyle(fontSize: 13),
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                        border: OutlineInputBorder(),
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
                        contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),

              // Modo Flexível: Único, Recorrente, Parcelado
              if (!isXfer) ...[
                const Text(
                  'Modo do Lançamento:',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
                ),
                const SizedBox(height: 6),
                SegmentedButton<String>(
                  style: const ButtonStyle(
                    textStyle: WidgetStatePropertyAll(TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
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
          icon: const Icon(Icons.check, size: 18),
          label: const Text('Criar Lançamento'),
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
                  'Fatura de ${fmtMonth(summary.key)} • Saldo Restante: ${brl(summary.remainingCents)}',
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
                        decoration: const InputDecoration(
                          labelText: 'Valor a Pagar (R\$)',
                          prefixText: 'R\$ ',
                          border: OutlineInputBorder(),
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
