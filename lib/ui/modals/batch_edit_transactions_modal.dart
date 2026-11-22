import 'package:flutter/material.dart';
import '../../models/openmoney_models.dart';
import '../../services/date_validator.dart';
import '../../store/money_store.dart';
import '../theme/liquid_glass.dart';
import '../widgets/date_input_formatter.dart';
import '../widgets/tag_input_field.dart';

class BatchEditTransactionsModal extends StatefulWidget {
  final MoneyStore store;
  final Set<String> selectedIds;

  const BatchEditTransactionsModal({
    super.key,
    required this.store,
    required this.selectedIds,
  });

  @override
  State<BatchEditTransactionsModal> createState() =>
      _BatchEditTransactionsModalState();
}

class _BatchEditTransactionsModalState
    extends State<BatchEditTransactionsModal> {
  bool _applyPayee = false;
  final TextEditingController _payeeCtrl = TextEditingController();

  bool _applyCategory = false;
  String _selectedCategory = '';

  bool _applyTags = false;
  BatchTagMode _tagMode = BatchTagMode.add;
  List<String> _tags = [];

  bool _applyMemo = false;
  final TextEditingController _memoCtrl = TextEditingController();

  bool _applyAmount = false;
  final TextEditingController _amtCtrl = TextEditingController();
  BatchAmountSignMode _amountSignMode = BatchAmountSignMode.keepOriginal;

  bool _applyDate = false;
  String _selectedDate = todayISO();
  late final TextEditingController _dateCtrl;
  String? _dateError;
  String? _dateWarning;

  bool _applyAccount = false;
  String _selectedAccountId = '';

  bool _applyReconciled = false;
  bool _reconciledValue = true;

  void _checkDateWarning() {
    final clean = _dateCtrl.text.trim();
    if (clean.length == 10 || RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(clean)) {
      final res = validateTransactionDate(clean);
      setState(() {
        _dateError = res.isValid ? null : res.error;
        _dateWarning = res.isWarning ? res.warningMessage : null;
        if (res.isValid && res.isoDate != null) {
          _selectedDate = res.isoDate!;
        }
      });
    } else {
      if (_dateError != null || _dateWarning != null) {
        setState(() {
          _dateError = null;
          _dateWarning = null;
        });
      }
    }
  }

  ({bool hasExpenses, bool hasIncomes}) _selectedTxTypes() {
    bool hasExp = false;
    bool hasInc = false;
    for (final tx in widget.store.db.txs) {
      if (!widget.selectedIds.contains(tx.id) || tx.auto == true) continue;
      final isXfer = (tx.xfer != null && tx.xfer!.isNotEmpty) ||
          (tx.peer != null && tx.peer!.isNotEmpty);
      if (isXfer) continue;
      if (tx.amt < 0) {
        hasExp = true;
      } else {
        hasInc = true;
      }
      if (hasExp && hasInc) break;
    }
    return (hasExpenses: hasExp, hasIncomes: hasInc);
  }

  bool get _isMixedTypes {
    final t = _selectedTxTypes();
    return t.hasExpenses && t.hasIncomes;
  }

  @override
  void initState() {
    super.initState();
    final store = widget.store;
    final types = _selectedTxTypes();
    final targetCatType =
        (types.hasIncomes && !types.hasExpenses) ? 'Receita' : 'Despesa';
    final catOpts = store.allCategoryOptions(targetCatType);
    if (catOpts.isNotEmpty) {
      _selectedCategory = catOpts.first.value;
    } else {
      final cats = store.allCategoryPaths(targetCatType);
      if (cats.isNotEmpty) {
        _selectedCategory = cats.first;
      }
    }
    final accs = store.db.accounts.where((a) => a.isInactive != true).toList();
    if (accs.isNotEmpty) {
      _selectedAccountId = accs.first.id;
    } else if (store.db.accounts.isNotEmpty) {
      _selectedAccountId = store.db.accounts.first.id;
    }
    _dateCtrl = TextEditingController(text: fmtDate(_selectedDate));
  }

  @override
  void dispose() {
    _payeeCtrl.dispose();
    _memoCtrl.dispose();
    _amtCtrl.dispose();
    _dateCtrl.dispose();
    super.dispose();
  }

  bool get _hasAnyFieldSelected =>
      _applyPayee ||
      (_applyCategory && !_isMixedTypes) ||
      _applyTags ||
      _applyMemo ||
      _applyAmount ||
      _applyDate ||
      _applyAccount ||
      _applyReconciled;

  Future<void> _pickDate(BuildContext context) async {
    final val = validateTransactionDate(_dateCtrl.text);
    final curIso =
        val.isValid && val.isoDate != null ? val.isoDate! : _selectedDate;
    final parsed = dateFromISO(curIso);
    final picked = await showDatePicker(
      context: context,
      initialDate: parsed,
      firstDate: DateTime(2000),
      lastDate: DateTime(2099, 12, 31),
    );
    if (picked != null) {
      final iso = isoFromDate(picked);
      setState(() {
        _selectedDate = iso;
        _dateCtrl.text = fmtDate(iso);
        _checkDateWarning();
      });
    }
  }

  Future<void> _submit(MoneyStore store) async {
    String effectiveDate = _selectedDate;
    if (_applyDate) {
      final dateVal = validateTransactionDate(_dateCtrl.text);
      if (!dateVal.isValid) {
        setState(() => _dateError = dateVal.error);
        await showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Data Inválida'),
            content: Text(dateVal.error ?? 'A data informada é inválida.'),
            actions: [
              FilledButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('OK'),
              ),
            ],
          ),
        );
        return;
      }
      if (dateVal.isWarning) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final ok = await confirmDateWarningDialog(
          context,
          dateVal.warningMessage!,
          colors: OpenMoneyColors(isDark),
        );
        if (!ok) return;
      }
      effectiveDate = dateVal.isoDate!;
    }

    final absCents = _applyAmount ? (parseCents(_amtCtrl.text) ?? 0).abs() : 0;
    final payload = BatchTransactionEditPayload(
      applyPayee: _applyPayee,
      payee: _payeeCtrl.text,
      applyCategory: _applyCategory && !_isMixedTypes,
      category: _selectedCategory,
      applyTags: _applyTags,
      tagMode: _tagMode,
      tags: _tags,
      applyMemo: _applyMemo,
      memo: _memoCtrl.text,
      applyAmount: _applyAmount,
      absAmountCents: absCents,
      amountSignMode: _amountSignMode,
      applyDate: _applyDate,
      date: effectiveDate,
      applyAccount: _applyAccount,
      accountId: _selectedAccountId,
      applyReconciled: _applyReconciled,
      reconciled: _reconciledValue,
    );

    final count = store.batchUpdateTransactions(
      ids: widget.selectedIds,
      payload: payload,
    );
    if (mounted) {
      Navigator.of(context).pop(count);
    }
  }

  Widget _buildFieldSection({
    required OpenMoneyColors colors,
    required bool enabled,
    required ValueChanged<bool> onToggle,
    required String title,
    String? subtitle,
    required Widget child,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: enabled ? colors.bgSecondary : colors.surfaceCard,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: enabled
              ? colors.accent.withValues(alpha: 0.45)
              : colors.borderGlass,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => onToggle(!enabled),
            borderRadius: BorderRadius.circular(6),
            child: Row(
              children: [
                Checkbox(
                  value: enabled,
                  onChanged: (v) => onToggle(v ?? false),
                  activeColor: colors.accent,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w600,
                          color: colors.textPrimary,
                        ),
                      ),
                      if (subtitle != null)
                        Text(
                          subtitle,
                          style: TextStyle(
                              fontSize: 11.5, color: colors.textMuted),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          if (enabled) ...[
            const SizedBox(height: 10),
            child,
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final store = widget.store;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final c = OpenMoneyColors(isDark);
    final isMobile = MediaQuery.sizeOf(context).width < 640;

    final types = _selectedTxTypes();
    final isMixedTypes = types.hasExpenses && types.hasIncomes;
    final allowedCatType =
        (types.hasIncomes && !types.hasExpenses) ? 'Receita' : 'Despesa';

    final seenCats = <String>{};
    final catOptions = <({String label, String value})>[];
    if (!isMixedTypes) {
      for (final opt in store.allCategoryOptions(allowedCatType)) {
        if (seenCats.add(opt.value)) {
          catOptions.add(opt);
        }
      }
      if (catOptions.isNotEmpty &&
          !catOptions.any((c) => c.value == _selectedCategory)) {
        _selectedCategory = catOptions.first.value;
      }
    }
    final accounts = store.db.accounts;

    return Dialog(
      backgroundColor: c.surfaceCard,
      insetPadding: EdgeInsets.symmetric(
        horizontal: isMobile ? 12 : 32,
        vertical: isMobile ? 16 : 24,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: c.borderGlass),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 620, maxHeight: 740),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Cabeçalho
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 12, 12),
              child: Row(
                children: [
                  Icon(Icons.drive_file_rename_outline,
                      color: c.accent, size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Edição em Lote',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w700,
                            color: c.textPrimary,
                          ),
                        ),
                        Text(
                          '${widget.selectedIds.length} lançamento(s) selecionado(s) — marque apenas os campos que deseja alterar',
                          style: TextStyle(fontSize: 12, color: c.textMuted),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: Icon(Icons.close, color: c.textMuted),
                    onPressed: () => Navigator.of(context).pop(0),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: c.borderGlass),

            // Campos
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildFieldSection(
                      colors: c,
                      enabled: _applyPayee,
                      onToggle: (v) => setState(() => _applyPayee = v),
                      title: 'Nome / Favorecido',
                      child: TextField(
                        controller: _payeeCtrl,
                        style: TextStyle(fontSize: 13, color: c.textPrimary),
                        decoration: InputDecoration(
                          hintText: 'Novo nome para os lançamentos selecionados',
                          isDense: true,
                          filled: true,
                          fillColor: c.surfaceCard,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ),

                    _buildFieldSection(
                      colors: c,
                      enabled: _applyCategory,
                      onToggle: (v) => setState(() => _applyCategory = v),
                      title: 'Categoria',
                      subtitle: isMixedTypes
                          ? 'Não permitido alterar categoria quando Despesas e Receitas estão misturadas'
                          : (allowedCatType == 'Receita'
                              ? 'Categorias de Receita (não altera transferências)'
                              : 'Categorias de Despesa (não altera transferências)'),
                      child: isMixedTypes
                          ? Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: Colors.orange.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: Colors.orange.withValues(alpha: 0.4),
                                ),
                              ),
                              child: Row(
                                children: [
                                  const Icon(
                                    Icons.warning_amber_rounded,
                                    color: Colors.orange,
                                    size: 18,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'A seleção contém Despesas e Receitas. Não é permitido alterar lançamentos de despesa para categorias de receita e vice-versa. Selecione apenas despesas ou apenas receitas.',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: c.textPrimary,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : DropdownButtonFormField<String>(
                              value: catOptions.any((c) => c.value == _selectedCategory)
                                  ? _selectedCategory
                                  : (catOptions.isNotEmpty ? catOptions.first.value : null),
                              isExpanded: true,
                              dropdownColor: c.surfaceCard,
                              style: TextStyle(fontSize: 13, color: c.textPrimary),
                              decoration: InputDecoration(
                                isDense: true,
                                filled: true,
                                fillColor: c.surfaceCard,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                              items: catOptions
                                  .map((opt) => DropdownMenuItem<String>(
                                        value: opt.value,
                                        child: Text(
                                          opt.label,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ))
                                  .toList(),
                              onChanged: (val) {
                                if (val != null) {
                                  setState(() => _selectedCategory = val);
                                }
                              },
                            ),
                    ),

                    _buildFieldSection(
                      colors: c,
                      enabled: _applyTags,
                      onToggle: (v) => setState(() => _applyTags = v),
                      title: 'Tags',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              ChoiceChip(
                                label: const Text('Adicionar'),
                                selected: _tagMode == BatchTagMode.add,
                                onSelected: (_) =>
                                    setState(() => _tagMode = BatchTagMode.add),
                              ),
                              ChoiceChip(
                                label: const Text('Substituir'),
                                selected: _tagMode == BatchTagMode.replace,
                                onSelected: (_) => setState(
                                    () => _tagMode = BatchTagMode.replace),
                              ),
                              ChoiceChip(
                                label: const Text('Remover'),
                                selected: _tagMode == BatchTagMode.remove,
                                onSelected: (_) => setState(
                                    () => _tagMode = BatchTagMode.remove),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          TagInputField(
                            tags: _tags,
                            onChanged: (list) => setState(() => _tags = list),
                            availableTags: store.allTags,
                            colors: c,
                            label: '',
                          ),
                        ],
                      ),
                    ),

                    _buildFieldSection(
                      colors: c,
                      enabled: _applyMemo,
                      onToggle: (v) => setState(() => _applyMemo = v),
                      title: 'Notas (Memo)',
                      child: TextField(
                        controller: _memoCtrl,
                        maxLines: 2,
                        style: TextStyle(fontSize: 13, color: c.textPrimary),
                        decoration: InputDecoration(
                          hintText: 'Deixe vazio para limpar as notas',
                          isDense: true,
                          filled: true,
                          fillColor: c.surfaceCard,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                    ),

                    _buildFieldSection(
                      colors: c,
                      enabled: _applyAmount,
                      onToggle: (v) => setState(() => _applyAmount = v),
                      title: 'Valor',
                      subtitle: 'Não altera transferências entre contas',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          TextField(
                            controller: _amtCtrl,
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            style: TextStyle(fontSize: 13, color: c.textPrimary),
                            decoration: InputDecoration(
                              hintText: 'Ex: 150,00',
                              isDense: true,
                              filled: true,
                              fillColor: c.surfaceCard,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              ChoiceChip(
                                label: const Text('Manter sinal original'),
                                selected: _amountSignMode ==
                                    BatchAmountSignMode.keepOriginal,
                                onSelected: (_) => setState(() =>
                                    _amountSignMode =
                                        BatchAmountSignMode.keepOriginal),
                              ),
                              ChoiceChip(
                                label: const Text('Forçar Despesa (-)'),
                                selected: _amountSignMode ==
                                    BatchAmountSignMode.expense,
                                onSelected: (_) => setState(() =>
                                    _amountSignMode =
                                        BatchAmountSignMode.expense),
                              ),
                              ChoiceChip(
                                label: const Text('Forçar Receita (+)'),
                                selected: _amountSignMode ==
                                    BatchAmountSignMode.income,
                                onSelected: (_) => setState(() =>
                                    _amountSignMode =
                                        BatchAmountSignMode.income),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    _buildFieldSection(
                      colors: c,
                      enabled: _applyDate,
                      onToggle: (v) => setState(() => _applyDate = v),
                      title: 'Data',
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          TextField(
                            controller: _dateCtrl,
                            keyboardType: TextInputType.number,
                            inputFormatters: [DateInputFormatter()],
                            style:
                                TextStyle(fontSize: 13, color: c.textPrimary),
                            onChanged: (_) => _checkDateWarning(),
                            decoration: InputDecoration(
                              hintText: 'DD/MM/AAAA',
                              errorText: _dateError,
                              isDense: true,
                              filled: true,
                              fillColor: c.surfaceCard,
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(8),
                              ),
                              suffixIcon: IconButton(
                                icon:
                                    const Icon(Icons.calendar_month, size: 18),
                                tooltip: 'Escolher data no calendário',
                                onPressed: () => _pickDate(context),
                              ),
                            ),
                          ),
                          if (_dateWarning != null) ...[
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                const Icon(
                                  Icons.warning_amber_rounded,
                                  size: 14,
                                  color: Colors.amber,
                                ),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    _dateWarning!,
                                    style: const TextStyle(
                                      fontSize: 11,
                                      color: Colors.amber,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ),

                    _buildFieldSection(
                      colors: c,
                      enabled: _applyAccount,
                      onToggle: (v) => setState(() => _applyAccount = v),
                      title: 'Conta',
                      subtitle: 'Não altera transferências entre contas',
                      child: DropdownButtonFormField<String>(
                        initialValue:
                            accounts.any((a) => a.id == _selectedAccountId)
                                ? _selectedAccountId
                                : (accounts.isNotEmpty
                                    ? accounts.first.id
                                    : null),
                        isExpanded: true,
                        dropdownColor: c.surfaceCard,
                        style: TextStyle(fontSize: 13, color: c.textPrimary),
                        decoration: InputDecoration(
                          isDense: true,
                          filled: true,
                          fillColor: c.surfaceCard,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        items: accounts
                            .map((a) => DropdownMenuItem(
                                  value: a.id,
                                  child: Text(
                                    a.name,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ))
                            .toList(),
                        onChanged: (val) {
                          if (val != null) {
                            setState(() => _selectedAccountId = val);
                          }
                        },
                      ),
                    ),

                    _buildFieldSection(
                      colors: c,
                      enabled: _applyReconciled,
                      onToggle: (v) => setState(() => _applyReconciled = v),
                      title: 'Status de Conciliação',
                      child: Wrap(
                        spacing: 8,
                        children: [
                          ChoiceChip(
                            label: const Text('Conciliado'),
                            selected: _reconciledValue,
                            onSelected: (_) =>
                                setState(() => _reconciledValue = true),
                          ),
                          ChoiceChip(
                            label: const Text('Pendente'),
                            selected: !_reconciledValue,
                            onSelected: (_) =>
                                setState(() => _reconciledValue = false),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),

            Divider(height: 1, color: c.borderGlass),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(0),
                    child:
                        Text('Cancelar', style: TextStyle(color: c.textMuted)),
                  ),
                  const SizedBox(width: 10),
                  ElevatedButton.icon(
                    onPressed:
                        _hasAnyFieldSelected ? () => _submit(store) : null,
                    icon: const Icon(Icons.check, size: 18),
                    label: Text(
                      'Aplicar em ${widget.selectedIds.length}',
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: c.accent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 11,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
