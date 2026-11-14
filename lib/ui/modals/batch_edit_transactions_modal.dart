import 'package:flutter/material.dart';
import '../../models/openmoney_models.dart';
import '../../store/money_store.dart';
import '../theme/liquid_glass.dart';
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

  bool _applyAccount = false;
  String _selectedAccountId = '';

  bool _applyReconciled = false;
  bool _reconciledValue = true;

  @override
  void initState() {
    super.initState();
    final store = widget.store;
    final cats = store.allCatNames();
    if (cats.isNotEmpty) {
      _selectedCategory = cats.first;
    }
    final accs = store.db.accounts.where((a) => a.isInactive != true).toList();
    if (accs.isNotEmpty) {
      _selectedAccountId = accs.first.id;
    } else if (store.db.accounts.isNotEmpty) {
      _selectedAccountId = store.db.accounts.first.id;
    }
  }

  @override
  void dispose() {
    _payeeCtrl.dispose();
    _memoCtrl.dispose();
    _amtCtrl.dispose();
    super.dispose();
  }

  bool get _hasAnyFieldSelected =>
      _applyPayee ||
      _applyCategory ||
      _applyTags ||
      _applyMemo ||
      _applyAmount ||
      _applyDate ||
      _applyAccount ||
      _applyReconciled;

  Future<void> _pickDate(BuildContext context) async {
    final parsed = DateTime.tryParse(_selectedDate) ?? DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: parsed,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      locale: const Locale('pt', 'BR'),
    );
    if (picked != null) {
      setState(() {
        _selectedDate =
            '${picked.year.toString().padLeft(4, '0')}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
      });
    }
  }

  void _submit(MoneyStore store) {
    final absCents = _applyAmount ? (parseCents(_amtCtrl.text) ?? 0).abs() : 0;
    final payload = BatchTransactionEditPayload(
      applyPayee: _applyPayee,
      payee: _payeeCtrl.text,
      applyCategory: _applyCategory,
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
      date: _selectedDate,
      applyAccount: _applyAccount,
      accountId: _selectedAccountId,
      applyReconciled: _applyReconciled,
      reconciled: _reconciledValue,
    );

    final count = store.batchUpdateTransactions(
      ids: widget.selectedIds,
      payload: payload,
    );
    Navigator.of(context).pop(count);
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

    final categories = store.allCatNames();
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
                      subtitle: 'Não altera transferências entre contas',
                      child: DropdownButtonFormField<String>(
                        initialValue: categories.contains(_selectedCategory)
                            ? _selectedCategory
                            : (categories.isNotEmpty ? categories.first : null),
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
                        items: categories
                            .map((cat) => DropdownMenuItem(
                                  value: cat,
                                  child: Text(
                                    cat.replaceAll(':', ' › '),
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
                      child: OutlinedButton.icon(
                        onPressed: () => _pickDate(context),
                        icon: const Icon(Icons.calendar_today, size: 16),
                        label: Text(fmtDate(_selectedDate)),
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
