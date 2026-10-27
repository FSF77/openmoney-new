import 'package:flutter/material.dart';
import '../../models/openmoney_models.dart';
import '../../store/money_store.dart';
import '../theme/liquid_glass.dart';

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

  void _handleSave() {
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
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colors = OpenMoneyColors(isDark);
    final isSeries = widget.tx.recId != null || widget.tx.plan != null;
    final targetAcc = widget.store.accById(_accId);
    final isCard = targetAcc?.type == kCardType && targetAcc?.card != null;

    final catType = _isExpense ? 'Despesa' : 'Receita';
    final catPaths = widget.store.allCategoryPaths(catType);
    final otherAccounts =
        widget.store.db.accounts.where((a) => a.id != _accId).toList();

    final dropdownItems = <DropdownMenuItem<String>>[
      if (_catSelection.isNotEmpty &&
          !catPaths.contains(_catSelection) &&
          !_catSelection.startsWith('xfer:'))
        DropdownMenuItem(value: _catSelection, child: Text(_catSelection)),
      ...catPaths.map((p) => DropdownMenuItem(value: p, child: Text(p))),
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
                decoration: const InputDecoration(
                  labelText: 'Conta do Lançamento (Mover entre Contas)',
                  border: OutlineInputBorder(),
                ),
                items: widget.store.db.accounts
                    .map((a) =>
                        DropdownMenuItem(value: a.id, child: Text(a.name)))
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
                      decoration: InputDecoration(
                        labelText: 'Data (DD/MM/AAAA)',
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.calendar_month, size: 20),
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
                decoration: const InputDecoration(
                  labelText: 'Favorecido / Descrição',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              if (dropdownItems.isNotEmpty)
                DropdownButtonFormField<String>(
                  initialValue: effectiveCat,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Categoria ou Transferência',
                    border: OutlineInputBorder(),
                  ),
                  items: dropdownItems,
                  onChanged: (v) {
                    if (v != null) setState(() => _catSelection = v);
                  },
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
                      decoration: const InputDecoration(
                        labelText: 'Valor (R\$)',
                        prefixText: 'R\$ ',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _memoCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Nota / Observação',
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
                      decoration: const InputDecoration(
                        labelText: 'Competência da Fatura do Cartão',
                        border: OutlineInputBorder(),
                      ),
                      items: opts
                          .map((o) => DropdownMenuItem(
                                value: o.key,
                                child: Text(o.label),
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
      actions: [
        if (widget.tx.auto != true)
          TextButton.icon(
            style: TextButton.styleFrom(foregroundColor: colors.accent),
            icon: const Icon(Icons.copy_rounded, size: 18),
            label: const Text('Copiar'),
            onPressed: () {
              Navigator.pop(context);
              showTransactionCopyModal(context, widget.store, widget.tx);
            },
          ),
        TextButton.icon(
          style: TextButton.styleFrom(foregroundColor: colors.expense),
          icon: const Icon(Icons.delete_outline, size: 18),
          label: const Text('Excluir'),
          onPressed: () {
            Navigator.pop(context);
            showDeleteTransactionDialog(context, widget.store, widget.tx);
          },
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton.icon(
          icon: const Icon(Icons.check, size: 18),
          label: const Text('Salvar Alterações'),
          onPressed: _handleSave,
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
    final list = List<Account>.from(widget.store.activeAccounts);
    final current = widget.store.accById(widget.sourceTx.acc);
    if (current != null && !list.any((a) => a.id == current.id)) {
      list.insert(0, current);
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
    final catPaths = widget.store.allCategoryPaths(catType);
    final otherAccounts =
        widget.store.activeAccounts.where((a) => a.id != _accId).toList();

    final dropdownItems = <DropdownMenuItem<String>>[
      if (_catSelection.isNotEmpty &&
          !catPaths.contains(_catSelection) &&
          !_catSelection.startsWith('xfer:'))
        DropdownMenuItem(value: _catSelection, child: Text(_catSelection)),
      ...catPaths.map((p) => DropdownMenuItem(value: p, child: Text(p))),
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
                decoration: const InputDecoration(
                  labelText: 'Conta Destino',
                  border: OutlineInputBorder(),
                ),
                items: availableAccs
                    .map((a) => DropdownMenuItem(
                          value: a.id,
                          child: Text(
                            a.name +
                                (a.type == kCardType
                                    ? ' (Cartão)'
                                    : ' (${a.type})'),
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
                      decoration: InputDecoration(
                        labelText: 'Data (DD/MM/AAAA)',
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.calendar_month, size: 20),
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
                      decoration: const InputDecoration(
                        labelText: 'Fatura do Cartão (Competência)',
                        border: OutlineInputBorder(),
                      ),
                      items: opts
                          .map((o) => DropdownMenuItem(
                                value: o.key,
                                child: Text(o.key == defaultIk
                                    ? '${o.label} [Padrão]'
                                    : o.label),
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
                decoration: const InputDecoration(
                  labelText: 'Favorecido / Descrição',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),

              // Categoria ou Transferência
              if (dropdownItems.isNotEmpty)
                DropdownButtonFormField<String>(
                  initialValue: effectiveCat,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Categoria ou Transferência',
                    border: OutlineInputBorder(),
                  ),
                  items: dropdownItems,
                  onChanged: (v) {
                    if (v != null) setState(() => _catSelection = v);
                  },
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
                      decoration: const InputDecoration(
                        labelText: 'Valor (R\$)',
                        prefixText: 'R\$ ',
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _memoCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Nota / Observação',
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
                          decoration: const InputDecoration(
                            labelText: 'Frequência',
                            border: OutlineInputBorder(),
                          ),
                          items: kRecurrenceFrequencyOptions
                              .map((o) => DropdownMenuItem(
                                    value: o.id,
                                    child: Text(o.label),
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
                    title: const Text('Definir Data de Término'),
                    value: _hasEndDate,
                    onChanged: (v) => setState(() => _hasEndDate = v ?? false),
                  ),
                  if (_hasEndDate) ...[
                    const SizedBox(height: 4),
                    TextField(
                      controller: _endDateCtrl,
                      decoration: InputDecoration(
                        labelText: 'Data de Término (DD/MM/AAAA)',
                        border: const OutlineInputBorder(),
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.calendar_month, size: 20),
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
                    decoration: const InputDecoration(
                      labelText: 'Número de Parcelas',
                      border: OutlineInputBorder(),
                    ),
                    items: List.generate(
                      119,
                      (i) => DropdownMenuItem(
                        value: i + 2,
                        child: Text('${i + 2}x'),
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
