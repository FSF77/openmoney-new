import 'dart:typed_data';
import 'package:flutter/material.dart';
import '../../models/openmoney_models.dart';
import '../../services/native_file_picker.dart';
import '../../services/ofx_reconciliation_service.dart';
import '../../services/platform_io.dart';
import '../../store/money_store.dart';
import '../theme/liquid_glass.dart';
import '../widgets/category_select_form_field.dart';
import '../widgets/tag_input_field.dart';

enum _OfxFilterMode {
  all,
  reconcile,
  createNew,
  ignored,
}

Future<void> showOfxReconciliationModal(
  BuildContext context,
  MoneyStore store, {
  String? preferredAccountId,
  String? preferredInvoiceKey,
  List<int>? preloadedBytes,
  String? preloadedFileName,
}) async {
  List<int>? bytes = preloadedBytes;
  String fileName = preloadedFileName ?? 'extrato.ofx';

  if (bytes == null) {
    final selectedPath = await NativeFilePicker.pickFile(
      title: 'Selecionar Extrato ou Fatura OFX / QFX',
      allowedExtensions: const ['ofx', 'qfx'],
    );
    if (selectedPath == null || selectedPath.trim().isEmpty) return;
    final cleanPath = selectedPath.trim();
    fileName = cleanPath.split(RegExp(r'[/\\]')).last;
    try {
      bytes = await File(cleanPath).readAsBytes();
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Não foi possível ler o arquivo OFX: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
      return;
    }
  }

  final rawBytes = bytes is Uint8List ? bytes : Uint8List.fromList(bytes);
  final statements = OfxReconciliationService.parseBytes(rawBytes);

  if (statements.isEmpty) {
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Nenhum extrato ou fatura válido encontrado no arquivo OFX/QFX selecionado.',
          ),
          backgroundColor: Colors.orange,
        ),
      );
    }
    return;
  }

  if (context.mounted) {
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _OfxReconciliationDialog(
        store: store,
        statements: statements,
        fileName: fileName,
        preferredAccountId: preferredAccountId,
        preferredInvoiceKey: preferredInvoiceKey,
      ),
    );
  }
}

class _OfxReconciliationDialog extends StatefulWidget {
  final MoneyStore store;
  final List<OfxStatement> statements;
  final String fileName;
  final String? preferredAccountId;
  final String? preferredInvoiceKey;

  const _OfxReconciliationDialog({
    required this.store,
    required this.statements,
    required this.fileName,
    this.preferredAccountId,
    this.preferredInvoiceKey,
  });

  @override
  State<_OfxReconciliationDialog> createState() =>
      _OfxReconciliationDialogState();
}

class _OfxReconciliationDialogState extends State<_OfxReconciliationDialog> {
  int _statementIndex = 0;
  String _targetAccountId = '';
  bool _accountAutoMatched = false;
  String? _targetInvoiceKey;
  bool _invertSigns = false;
  bool _defaultUpdateDateOnMatch = true;
  bool _rememberAccountMapping = true;
  bool _includeBalanceAdjustment = false;
  final String _adjustmentCategory = 'Outros';

  _OfxFilterMode _filterMode = _OfxFilterMode.all;
  String _searchQuery = '';
  List<OfxReconcileDraftItem> _drafts = [];
  String? _selectedDraftId;

  late final TextEditingController _searchCtrl;

  OfxStatement get _currentStatement => widget.statements[_statementIndex];

  Account? get _targetAccount => widget.store.accById(_targetAccountId);

  bool get _isCreditCardAccount =>
      _targetAccount?.type == kCardType && _targetAccount?.card != null;

  @override
  void initState() {
    super.initState();
    _searchCtrl = TextEditingController();
    _initForStatement(0);
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  void _initForStatement(int index) {
    _statementIndex = index.clamp(0, widget.statements.length - 1);
    final stmt = _currentStatement;
    final accRes = OfxReconciliationService.detectTargetAccount(
      statement: stmt,
      accounts: widget.store.db.accounts,
      preferredAccountId: widget.preferredAccountId,
      fileName: widget.fileName,
    );
    _targetAccountId = accRes.accountId;
    _accountAutoMatched = accRes.autoMatched;

    final acc = _targetAccount;
    final isCard = acc?.type == kCardType || stmt.isCreditCard;
    // Em conta corrente, por padrão atualiza data pendente para data do banco; em cartão, preserva data original.
    _defaultUpdateDateOnMatch = !isCard;

    _syncTargetInvoiceKey();
    _rebuildDrafts();
  }

  void _syncTargetInvoiceKey() {
    final acc = _targetAccount;
    if (acc != null && acc.type == kCardType && acc.card != null) {
      _targetInvoiceKey = OfxReconciliationService.detectTargetInvoiceKey(
        statement: _currentStatement,
        cardAccount: acc,
        preferredInvoiceKey: widget.preferredInvoiceKey,
        fileName: widget.fileName,
        currentStoreMonth: widget.store.month,
      );
    } else {
      _targetInvoiceKey = null;
    }
  }

  void _rebuildDrafts() {
    _drafts = OfxReconciliationService.buildReconciliationDrafts(
      statement: _currentStatement,
      targetAccountId: _targetAccountId,
      targetInvoiceKey: _targetInvoiceKey,
      invertSigns: _invertSigns,
      defaultUpdateDateOnMatch: _defaultUpdateDateOnMatch,
      store: widget.store,
    );
    _includeBalanceAdjustment = false;
    final visible = _filteredDrafts;
    if (visible.isNotEmpty) {
      _selectDraft(visible.first.id);
    } else if (_drafts.isNotEmpty) {
      _selectDraft(_drafts.first.id);
    } else {
      _selectedDraftId = null;
    }
  }

  List<OfxReconcileDraftItem> get _filteredDrafts {
    final q = _searchQuery.trim().toLowerCase();
    return _drafts.where((d) {
      switch (_filterMode) {
        case _OfxFilterMode.all:
          break;
        case _OfxFilterMode.reconcile:
          if (d.action != OfxReconcileAction.reconcileExisting) return false;
          break;
        case _OfxFilterMode.createNew:
          if (d.action != OfxReconcileAction.createNew) return false;
          break;
        case _OfxFilterMode.ignored:
          if (d.action != OfxReconcileAction.ignore) return false;
          break;
      }
      if (q.isEmpty) return true;
      final amtStr = (d.effectiveAmountCents.abs() / 100.0).toStringAsFixed(2);
      return d.payee.toLowerCase().contains(q) ||
          d.memo.toLowerCase().contains(q) ||
          d.raw.rawDescription.toLowerCase().contains(q) ||
          amtStr.contains(q) ||
          fmtDate(d.date).contains(q);
    }).toList();
  }

  OfxReconcileDraftItem? get _selectedDraft {
    if (_selectedDraftId == null) return null;
    for (final d in _drafts) {
      if (d.id == _selectedDraftId) return d;
    }
    return null;
  }

  void _selectDraft(String id) {
    _selectedDraftId = id;
  }

  Transaction? _txById(String? id) {
    if (id == null) return null;
    for (final tx in widget.store.db.txs) {
      if (tx.id == id) return tx;
    }
    return null;
  }

  Future<void> _pickDraftDate(OfxReconcileDraftItem draft) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: dateFromISO(draft.date),
      firstDate: DateTime(1990),
      lastDate: DateTime(2099, 12, 31),
    );
    if (picked != null && mounted) {
      setState(() {
        draft.date = isoFromDate(picked);
      });
    }
  }

  void _applyAndClose(OfxBalanceComparison balComp) {
    final adjCat = _adjustmentCategory.isNotEmpty
        ? _adjustmentCategory
        : (balComp.differenceCents < 0 ? 'Outros' : 'Outras Rendas');

    final summary = widget.store.applyOfxReconciliation(
      statement: _currentStatement,
      targetAccountId: _targetAccountId,
      targetInvoiceKey: _targetInvoiceKey,
      drafts: _drafts,
      rememberAccountMapping: _rememberAccountMapping,
      includeBalanceAdjustment: _includeBalanceAdjustment,
      adjustmentCents: balComp.differenceCents,
      adjustmentDate: balComp.referenceDate,
      adjustmentCategory: adjCat,
    );

    if (!mounted) return;
    Navigator.of(context).pop();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(summary.formattedMessage),
        backgroundColor: Colors.green.shade700,
        duration: const Duration(seconds: 5),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colors = OpenMoneyColors(isDark);
    final size = MediaQuery.sizeOf(context);
    final isWide = size.width >= 880;
    final isMobile = size.width < 680;

    final acc = _targetAccount;
    final accCur = acc?.effectiveCurrency ?? _currentStatement.currency;
    final balComp = OfxReconciliationService.computeBalanceComparison(
      statement: _currentStatement,
      targetAccountId: _targetAccountId,
      targetInvoiceKey: _targetInvoiceKey,
      drafts: _drafts,
      store: widget.store,
    );

    final reconcileCount = _drafts
        .where((d) => d.action == OfxReconcileAction.reconcileExisting)
        .length;
    final createCount = _drafts
        .where((d) => d.action == OfxReconcileAction.createNew)
        .length;
    final ignoredCount =
        _drafts.where((d) => d.action == OfxReconcileAction.ignore).length;

    final visibleDrafts = _filteredDrafts;

    return Dialog(
      backgroundColor: colors.bgSecondary,
      surfaceTintColor: Colors.transparent,
      insetPadding: EdgeInsets.symmetric(
        horizontal: isMobile ? 8 : 24,
        vertical: isMobile ? 12 : 20,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colors.borderGlass),
      ),
      child: SizedBox(
        width: isWide ? 1060 : size.width * 0.96,
        height: isMobile ? size.height * 0.92 : 700,
        child: Column(
          children: [
            // Cabeçalho
            Container(
              padding: EdgeInsets.symmetric(
                horizontal: isMobile ? 14 : 20,
                vertical: isMobile ? 10 : 14,
              ),
              decoration: BoxDecoration(
                color: colors.bgPrimary.withValues(alpha: 0.65),
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(16)),
                border: Border(bottom: BorderSide(color: colors.borderGlass)),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: colors.accent.withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      _currentStatement.isCreditCard
                          ? Icons.credit_score_outlined
                          : Icons.account_balance_outlined,
                      color: colors.accent,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _currentStatement.isCreditCard
                              ? 'Conciliação OFX — Fatura de Cartão'
                              : 'Conciliação OFX — Extrato Bancário',
                          style: TextStyle(
                            fontSize: isMobile ? 15 : 17,
                            fontWeight: FontWeight.w800,
                            color: colors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${widget.fileName} • ${_drafts.length} lançamento(s) lido(s)',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: colors.textSecondary,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: () => Navigator.of(context).pop(),
                    tooltip: 'Fechar',
                  ),
                ],
              ),
            ),

            // Barra de Contexto: Conta, Fatura, Opções e Painel LEDGERBAL
            Container(
              padding: EdgeInsets.symmetric(
                horizontal: isMobile ? 12 : 18,
                vertical: 10,
              ),
              decoration: BoxDecoration(
                color: colors.bgSecondary,
                border: Border(bottom: BorderSide(color: colors.borderGlass)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 10,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (widget.statements.length > 1)
                        SizedBox(
                          width: isMobile ? size.width - 48 : 260,
                          child: DropdownButtonFormField<int>(
                            initialValue: _statementIndex,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              labelText: 'Bloco OFX',
                              isDense: true,
                              border: OutlineInputBorder(),
                              contentPadding: EdgeInsets.symmetric(
                                  horizontal: 10, vertical: 8),
                            ),
                            items: [
                              for (int i = 0; i < widget.statements.length; i++)
                                DropdownMenuItem(
                                  value: i,
                                  child: Text(
                                    widget.statements[i].displayLabel,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 12.5),
                                  ),
                                ),
                            ],
                            onChanged: (idx) {
                              if (idx != null) {
                                setState(() => _initForStatement(idx));
                              }
                            },
                          ),
                        ),
                      SizedBox(
                        width: isMobile ? size.width - 48 : 270,
                        child: DropdownButtonFormField<String>(
                          initialValue: widget.store.db.accounts
                                  .any((a) => a.id == _targetAccountId)
                              ? _targetAccountId
                              : null,
                          isExpanded: true,
                          decoration: InputDecoration(
                            labelText: _accountAutoMatched
                                ? 'Conta de Destino (auto)'
                                : 'Conta de Destino',
                            isDense: true,
                            border: const OutlineInputBorder(),
                            contentPadding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 8),
                          ),
                          items: widget.store.db.accounts
                              .map(
                                (a) => DropdownMenuItem(
                                  value: a.id,
                                  child: Text(
                                    '${a.name} (${a.type})',
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontSize: 12.5),
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: (v) {
                            if (v == null || v == _targetAccountId) return;
                            setState(() {
                              _targetAccountId = v;
                              _accountAutoMatched = true;
                              final newAcc = widget.store.accById(v);
                              _defaultUpdateDateOnMatch =
                                  newAcc?.type != kCardType;
                              _syncTargetInvoiceKey();
                              _rebuildDrafts();
                            });
                          },
                        ),
                      ),
                      if (_isCreditCardAccount && acc?.card != null)
                        SizedBox(
                          width: isMobile ? size.width - 48 : 240,
                          child: Builder(builder: (_) {
                            final opts = invoiceOptions(
                              card: acc!.card!,
                              aroundDate: _currentStatement.endDate.isNotEmpty
                                  ? _currentStatement.endDate
                                  : todayISO(),
                              existingKeys: [
                                ?_targetInvoiceKey,
                              ],
                            );
                            return DropdownButtonFormField<String>(
                              initialValue: opts.any(
                                      (o) => o.key == _targetInvoiceKey)
                                  ? _targetInvoiceKey
                                  : (opts.isNotEmpty ? opts.first.key : null),
                              isExpanded: true,
                              decoration: const InputDecoration(
                                labelText: 'Fatura Alvo (Competência)',
                                isDense: true,
                                border: OutlineInputBorder(),
                                contentPadding: EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 8),
                              ),
                              items: opts
                                  .map(
                                    (o) => DropdownMenuItem(
                                      value: o.key,
                                      child: Text(
                                        o.label,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(fontSize: 12),
                                      ),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (v) {
                                if (v == null) return;
                                setState(() {
                                  _targetInvoiceKey = v;
                                  _rebuildDrafts();
                                });
                              },
                            );
                          }),
                        ),
                      PopupMenuButton<String>(
                        tooltip: 'Opções de Conciliação',
                        onSelected: (action) {
                          setState(() {
                            if (action == 'toggle_date') {
                              _defaultUpdateDateOnMatch =
                                  !_defaultUpdateDateOnMatch;
                              for (final d in _drafts) {
                                if (d.action ==
                                        OfxReconcileAction.reconcileExisting &&
                                    !d.alreadyReconciledInDb) {
                                  d.updateDateOnMatch =
                                      _defaultUpdateDateOnMatch;
                                }
                              }
                            } else if (action == 'toggle_invert') {
                              _invertSigns = !_invertSigns;
                              _rebuildDrafts();
                            } else if (action == 'toggle_remember') {
                              _rememberAccountMapping =
                                  !_rememberAccountMapping;
                            } else if (action == 'ignore_new') {
                              for (final d in _drafts) {
                                if (d.action == OfxReconcileAction.createNew) {
                                  d.action = OfxReconcileAction.ignore;
                                }
                              }
                            } else if (action == 'restore_new') {
                              for (final d in _drafts) {
                                if (d.action == OfxReconcileAction.ignore &&
                                    !d.isFitIdAlreadyImported &&
                                    !d.isInvoicePaymentCredit &&
                                    d.matchedTxId == null) {
                                  d.action = OfxReconcileAction.createNew;
                                }
                              }
                            }
                          });
                        },
                        itemBuilder: (_) => [
                          CheckedPopupMenuItem<String>(
                            value: 'toggle_date',
                            checked: _defaultUpdateDateOnMatch,
                            child: const Text(
                              'Atualizar data dos pareados p/ data do banco',
                              style: TextStyle(fontSize: 12.5),
                            ),
                          ),
                          CheckedPopupMenuItem<String>(
                            value: 'toggle_invert',
                            checked: _invertSigns,
                            child: const Text(
                              'Inverter sinais (+/-) do arquivo OFX',
                              style: TextStyle(fontSize: 12.5),
                            ),
                          ),
                          CheckedPopupMenuItem<String>(
                            value: 'toggle_remember',
                            checked: _rememberAccountMapping,
                            child: const Text(
                              'Memorizar conta para próximas importações OFX',
                              style: TextStyle(fontSize: 12.5),
                            ),
                          ),
                          const PopupMenuDivider(),
                          const PopupMenuItem<String>(
                            value: 'ignore_new',
                            child: Text(
                              'Ignorar todos os novos (conciliar apenas pareados)',
                              style: TextStyle(fontSize: 12.5),
                            ),
                          ),
                          const PopupMenuItem<String>(
                            value: 'restore_new',
                            child: Text(
                              'Restaurar novos ignorados',
                              style: TextStyle(fontSize: 12.5),
                            ),
                          ),
                        ],
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 8),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: colors.borderGlass),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.tune,
                                  size: 16, color: colors.textSecondary),
                              const SizedBox(width: 6),
                              const Text(
                                'Opções',
                                style: TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w600),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (balComp.hasLedgerBalance) ...[
                    const SizedBox(height: 10),
                    _buildBalanceBanner(balComp, accCur, colors, isMobile),
                  ],
                ],
              ),
            ),

            // Barra de Filtros e Busca
            Padding(
              padding: EdgeInsets.symmetric(
                horizontal: isMobile ? 12 : 18,
                vertical: 8,
              ),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                alignment: WrapAlignment.spaceBetween,
                children: [
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      _filterChip(
                        label: 'Todos (${_drafts.length})',
                        mode: _OfxFilterMode.all,
                        colors: colors,
                      ),
                      _filterChip(
                        label: 'Conciliar ($reconcileCount)',
                        mode: _OfxFilterMode.reconcile,
                        colors: colors,
                        badgeColor: colors.income,
                      ),
                      _filterChip(
                        label: 'Novos ($createCount)',
                        mode: _OfxFilterMode.createNew,
                        colors: colors,
                        badgeColor: colors.accent,
                      ),
                      _filterChip(
                        label: 'Ignorados / Já Conc. ($ignoredCount)',
                        mode: _OfxFilterMode.ignored,
                        colors: colors,
                      ),
                    ],
                  ),
                  SizedBox(
                    width: isMobile ? size.width - 48 : 220,
                    height: 34,
                    child: TextField(
                      controller: _searchCtrl,
                      style: const TextStyle(fontSize: 12),
                      decoration: InputDecoration(
                        hintText: 'Filtrar extrato...',
                        prefixIcon: const Icon(Icons.search, size: 16),
                        suffixIcon: _searchQuery.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.clear, size: 14),
                                onPressed: () => setState(() {
                                  _searchCtrl.clear();
                                  _searchQuery = '';
                                }),
                              )
                            : null,
                        border: const OutlineInputBorder(),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 6),
                      ),
                      onChanged: (v) => setState(() => _searchQuery = v),
                    ),
                  ),
                ],
              ),
            ),

            // Corpo Principal: Master-Detail (Desktop) ou Lista (Mobile)
            Expanded(
              child: visibleDrafts.isEmpty
                  ? Center(
                      child: Text(
                        'Nenhum lançamento neste filtro.',
                        style: TextStyle(color: colors.textSecondary),
                      ),
                    )
                  : isWide
                      ? Row(
                          children: [
                            Expanded(
                              flex: 5,
                              child: Container(
                                decoration: BoxDecoration(
                                  border: Border(
                                    top: BorderSide(color: colors.borderGlass),
                                    right:
                                        BorderSide(color: colors.borderGlass),
                                  ),
                                ),
                                child: _buildDraftList(
                                  visibleDrafts,
                                  accCur,
                                  colors,
                                  isMobile: false,
                                ),
                              ),
                            ),
                            Expanded(
                              flex: 6,
                              child: Container(
                                decoration: BoxDecoration(
                                  border: Border(
                                    top: BorderSide(color: colors.borderGlass),
                                  ),
                                ),
                                child: _selectedDraft != null
                                    ? SingleChildScrollView(
                                        padding: const EdgeInsets.all(16),
                                        child: _buildDraftInspector(
                                          _selectedDraft!,
                                          accCur,
                                          colors,
                                        ),
                                      )
                                    : Center(
                                        child: Text(
                                          'Selecione um lançamento para revisar.',
                                          style: TextStyle(
                                              color: colors.textSecondary),
                                        ),
                                      ),
                              ),
                            ),
                          ],
                        )
                      : Container(
                          decoration: BoxDecoration(
                            border: Border(
                              top: BorderSide(color: colors.borderGlass),
                            ),
                          ),
                          child: _buildDraftList(
                            visibleDrafts,
                            accCur,
                            colors,
                            isMobile: true,
                          ),
                        ),
            ),

            // Rodapé
            Container(
              padding: EdgeInsets.symmetric(
                horizontal: isMobile ? 14 : 20,
                vertical: 12,
              ),
              decoration: BoxDecoration(
                color: colors.bgPrimary.withValues(alpha: 0.65),
                borderRadius:
                    const BorderRadius.vertical(bottom: Radius.circular(16)),
                border: Border(top: BorderSide(color: colors.borderGlass)),
              ),
              child: Row(
                children: [
                  if (!isMobile)
                    Expanded(
                      child: Text(
                        '$reconcileCount conciliar • $createCount novo(s) • $ignoredCount ignorado(s)',
                        style: TextStyle(
                          fontSize: 12,
                          color: colors.textSecondary,
                        ),
                      ),
                    )
                  else
                    const Spacer(),
                  TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Cancelar'),
                  ),
                  const SizedBox(width: 10),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: colors.accent,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 10),
                    ),
                    icon: const Icon(Icons.check_circle_outline, size: 18),
                    label: Text(
                      'Confirmar Conciliação (${reconcileCount + createCount})',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    onPressed: (reconcileCount + createCount == 0 &&
                            !(_includeBalanceAdjustment &&
                                balComp.differenceCents != 0))
                        ? null
                        : () => _applyAndClose(balComp),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBalanceBanner(
    OfxBalanceComparison bal,
    String currency,
    OpenMoneyColors colors,
    bool isMobile,
  ) {
    final isConverged = bal.differenceCents == 0;
    final statusColor = isConverged ? colors.income : Colors.amber.shade700;
    final ofxLabel = bal.isCreditCardMode
        ? 'Total Fatura OFX'
        : 'Saldo OFX (${fmtDate(bal.referenceDate)})';
    final projLabel = bal.isCreditCardMode
        ? 'Fatura Projetada'
        : 'Saldo Conciliado Projetado';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: statusColor.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: statusColor.withValues(alpha: 0.35)),
      ),
      child: Wrap(
        spacing: 16,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        alignment: WrapAlignment.spaceBetween,
        children: [
          Wrap(
            spacing: 16,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              _balMetric(
                ofxLabel,
                formatCurrency(bal.ofxLedgerCents, currency),
                colors.textPrimary,
                colors,
              ),
              _balMetric(
                projLabel,
                formatCurrency(bal.projectedReconciledCents, currency),
                colors.textPrimary,
                colors,
              ),
              _balMetric(
                'Diferença',
                isConverged
                    ? '✓ R\$ 0,00 (Convergido)'
                    : formatCurrency(bal.differenceCents, currency),
                statusColor,
                colors,
              ),
            ],
          ),
          if (!isConverged)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Checkbox(
                  value: _includeBalanceAdjustment,
                  visualDensity: VisualDensity.compact,
                  onChanged: (v) => setState(
                      () => _includeBalanceAdjustment = v ?? false),
                ),
                GestureDetector(
                  onTap: () => setState(() =>
                      _includeBalanceAdjustment = !_includeBalanceAdjustment),
                  child: Text(
                    'Criar lançamento de ajuste (${formatCurrency(bal.differenceCents, currency)})',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: colors.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _balMetric(
    String label,
    String value,
    Color valueColor,
    OpenMoneyColors colors,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: TextStyle(fontSize: 10.5, color: colors.textSecondary),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w800,
            color: valueColor,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }

  Widget _filterChip({
    required String label,
    required _OfxFilterMode mode,
    required OpenMoneyColors colors,
    Color? badgeColor,
  }) {
    final selected = _filterMode == mode;
    final activeColor = badgeColor ?? colors.accent;
    return ChoiceChip(
      label: Text(
        label,
        style: TextStyle(
          fontSize: 11.5,
          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          color: selected ? activeColor : colors.textPrimary,
        ),
      ),
      selected: selected,
      selectedColor: activeColor.withValues(alpha: 0.16),
      side: BorderSide(
        color: selected
            ? activeColor.withValues(alpha: 0.45)
            : colors.borderGlass,
      ),
      visualDensity: VisualDensity.compact,
      onSelected: (_) => setState(() => _filterMode = mode),
    );
  }

  Widget _buildDraftList(
    List<OfxReconcileDraftItem> items,
    String currency,
    OpenMoneyColors colors, {
    required bool isMobile,
  }) {
    return ListView.separated(
      itemCount: items.length,
      separatorBuilder: (_, _) =>
          Divider(height: 1, color: colors.borderGlass.withValues(alpha: 0.5)),
      itemBuilder: (ctx, i) {
        final d = items[i];
        final isSelected = d.id == _selectedDraftId;
        final matchedTx = _txById(d.matchedTxId);

        final Color badgeColor;
        final String badgeText;
        final IconData statusIcon;

        switch (d.action) {
          case OfxReconcileAction.reconcileExisting:
            badgeColor = d.alreadyReconciledInDb
                ? Colors.teal
                : colors.income;
            badgeText = d.alreadyReconciledInDb
                ? 'Vincular FITID'
                : 'Conciliar';
            statusIcon = d.alreadyReconciledInDb
                ? Icons.verified_outlined
                : Icons.sync_alt;
            break;
          case OfxReconcileAction.createNew:
            badgeColor = colors.accent;
            badgeText = d.categorySelection.startsWith('xfer:')
                ? 'Nova Transf.'
                : 'Novo';
            statusIcon = Icons.add_circle_outline;
            break;
          case OfxReconcileAction.ignore:
            badgeColor = colors.textMuted;
            badgeText = d.isFitIdAlreadyImported
                ? 'Já Conciliado'
                : (d.isInvoicePaymentCredit ? 'Pgto Fatura Ant.' : 'Ignorado');
            statusIcon = d.isFitIdAlreadyImported
                ? Icons.check_circle_outline
                : Icons.block;
            break;
        }

        final String subtitleLine;
        if (d.action == OfxReconcileAction.reconcileExisting &&
            matchedTx != null) {
          subtitleLine =
              '⇄ ${matchedTx.payee} (${fmtDate(matchedTx.date)}) • ${matchedTx.cat}';
        } else if (d.action == OfxReconcileAction.createNew) {
          if (d.categorySelection.startsWith('xfer:')) {
            final peerName = widget.store
                    .accById(d.categorySelection.substring(5))
                    ?.name ??
                'Outra conta';
            subtitleLine = '⇄ Transferência: $peerName';
          } else {
            subtitleLine = d.categorySelection;
          }
        } else {
          subtitleLine = d.matchReason;
        }

        return InkWell(
          onTap: () {
            setState(() => _selectDraft(d.id));
            if (isMobile) {
              _openMobileDraftEditor(d, currency, colors);
            }
          },
          child: Container(
            color: (!isMobile && isSelected)
                ? colors.accent.withValues(alpha: 0.1)
                : null,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Row(
              children: [
                Icon(statusIcon, size: 18, color: badgeColor),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              d.payee.isEmpty ? d.raw.rawDescription : d.payee,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: d.action == OfxReconcileAction.ignore
                                    ? colors.textSecondary
                                    : colors.textPrimary,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: badgeColor.withValues(alpha: 0.14),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              badgeText,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: badgeColor,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${fmtDate(d.date)} • $subtitleLine',
                        style: TextStyle(
                          fontSize: 11,
                          color: colors.textSecondary,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  formatCurrency(d.effectiveAmountCents, currency),
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: d.effectiveAmountCents < 0
                        ? colors.expense
                        : colors.income,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _openMobileDraftEditor(
    OfxReconcileDraftItem draft,
    String currency,
    OpenMoneyColors colors,
  ) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: colors.bgSecondary,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: EdgeInsets.fromLTRB(
            16,
            16,
            16,
            MediaQuery.viewInsetsOf(ctx).bottom + 20,
          ),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Text(
                      'Revisar Item OFX',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(ctx),
                    ),
                  ],
                ),
                _buildDraftInspector(
                  draft,
                  currency,
                  colors,
                  onChanged: () {
                    setSheetState(() {});
                    setState(() {});
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildDraftInspector(
    OfxReconcileDraftItem draft,
    String currency,
    OpenMoneyColors colors, {
    VoidCallback? onChanged,
  }) {
    void refresh([VoidCallback? fn]) {
      setState(() {
        fn?.call();
      });
      onChanged?.call();
    }

    final candidates =
        OfxReconciliationService.candidateTransactionsForManualLink(
      draft: draft,
      allDrafts: _drafts,
      targetAccountId: _targetAccountId,
      targetInvoiceKey: _targetInvoiceKey,
      store: widget.store,
    );
    final matchedTx = _txById(draft.matchedTxId);
    final isExpense = draft.effectiveAmountCents < 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Cartão com dados originais do banco (OFX)
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: colors.bgPrimary,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: colors.borderGlass),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      draft.raw.cleanPayee,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: colors.textPrimary,
                      ),
                    ),
                  ),
                  Text(
                    formatCurrency(draft.effectiveAmountCents, currency),
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: isExpense ? colors.expense : colors.income,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'Data OFX: ${fmtDate(draft.raw.datePosted)} • Tipo: ${draft.raw.trnType}${draft.raw.rawFitId.isNotEmpty ? " • FITID: ${draft.raw.rawFitId}" : ""}',
                style: TextStyle(fontSize: 11, color: colors.textSecondary),
              ),
              if (draft.raw.rawDescription.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text(
                  draft.raw.rawDescription,
                  style: TextStyle(fontSize: 11.5, color: colors.textMuted),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 14),

        Text(
          'Ação de Conciliação',
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: colors.textSecondary,
          ),
        ),
        const SizedBox(height: 6),
        SizedBox(
          width: double.infinity,
          child: SegmentedButton<OfxReconcileAction>(
            segments: [
              ButtonSegment<OfxReconcileAction>(
                value: OfxReconcileAction.reconcileExisting,
                enabled: candidates.isNotEmpty || draft.matchedTxId != null,
                label: const Text('Conciliar', style: TextStyle(fontSize: 12)),
                icon: const Icon(Icons.sync_alt, size: 16),
              ),
              const ButtonSegment<OfxReconcileAction>(
                value: OfxReconcileAction.createNew,
                label: Text('Criar Novo', style: TextStyle(fontSize: 12)),
                icon: Icon(Icons.add_circle_outline, size: 16),
              ),
              const ButtonSegment<OfxReconcileAction>(
                value: OfxReconcileAction.ignore,
                label: Text('Ignorar', style: TextStyle(fontSize: 12)),
                icon: Icon(Icons.block, size: 16),
              ),
            ],
            selected: {draft.action},
            onSelectionChanged: (sel) {
              final next = sel.first;
              refresh(() {
                draft.action = next;
                if (next == OfxReconcileAction.reconcileExisting &&
                    draft.matchedTxId == null &&
                    candidates.isNotEmpty) {
                  final firstCand = candidates.first;
                  draft.matchedTxId = firstCand.id;
                  draft.alreadyReconciledInDb = firstCand.rec;
                  draft.updateDateOnMatch =
                      firstCand.rec ? false : _defaultUpdateDateOnMatch;
                  draft.updateAmountOnMatch =
                      firstCand.amt != draft.effectiveAmountCents;
                }
              });
            },
          ),
        ),
        const SizedBox(height: 14),

        if (draft.action == OfxReconcileAction.reconcileExisting) ...[
          if (matchedTx != null)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: colors.income.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: colors.income.withValues(alpha: 0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    matchedTx.rec
                        ? 'Lançamento existente já conciliado (receberá FITID)'
                        : 'Lançamento pendente selecionado para conciliação',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: colors.income,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${matchedTx.payee} • ${formatCurrency(matchedTx.amt, currency)}',
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w700),
                  ),
                  Text(
                    'Data: ${fmtDate(matchedTx.date)} • Categoria: ${matchedTx.cat}',
                    style: TextStyle(
                        fontSize: 11.5, color: colors.textSecondary),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 10),
          DropdownButtonFormField<String>(
            initialValue:
                candidates.any((c) => c.id == draft.matchedTxId)
                    ? draft.matchedTxId
                    : null,
            isExpanded: true,
            decoration: const InputDecoration(
              labelText: 'Lançamento Vinculado no OpenMoney',
              isDense: true,
              border: OutlineInputBorder(),
            ),
            items: candidates
                .map(
                  (c) => DropdownMenuItem<String>(
                    value: c.id,
                    child: Text(
                      '${fmtDate(c.date)} • ${c.payee} (${formatCurrency(c.amt, currency)})${c.rec ? " [Conc.]" : " [Pend.]"}',
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                )
                .toList(),
            onChanged: (newTxId) {
              if (newTxId == null) return;
              final chosen = _txById(newTxId);
              refresh(() {
                draft.matchedTxId = newTxId;
                if (chosen != null) {
                  draft.alreadyReconciledInDb = chosen.rec;
                  draft.updateDateOnMatch =
                      chosen.rec ? false : _defaultUpdateDateOnMatch;
                  draft.updateAmountOnMatch =
                      chosen.amt != draft.effectiveAmountCents;
                }
              });
            },
          ),
          const SizedBox(height: 8),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            value: draft.updateDateOnMatch,
            title: Text(
              'Atualizar data para ${fmtDate(draft.date)} (data do banco)',
              style: const TextStyle(fontSize: 12.5),
            ),
            onChanged: (v) =>
                refresh(() => draft.updateDateOnMatch = v ?? false),
          ),
          if (matchedTx != null &&
              matchedTx.auto != true &&
              matchedTx.amt != draft.effectiveAmountCents)
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              value: draft.updateAmountOnMatch,
              title: Text(
                'Atualizar valor de ${formatCurrency(matchedTx.amt, currency)} para ${formatCurrency(draft.effectiveAmountCents, currency)}',
                style: const TextStyle(fontSize: 12.5),
              ),
              onChanged: (v) =>
                  refresh(() => draft.updateAmountOnMatch = v ?? false),
            ),
        ] else if (draft.action == OfxReconcileAction.createNew) ...[
          Row(
            children: [
              Expanded(
                flex: 2,
                child: InkWell(
                  onTap: () => _pickDraftDate(draft),
                  child: InputDecorator(
                    decoration: const InputDecoration(
                      labelText: 'Data',
                      isDense: true,
                      border: OutlineInputBorder(),
                      suffixIcon: Icon(Icons.calendar_today, size: 16),
                    ),
                    child: Text(
                      fmtDate(draft.date),
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 3,
                child: CategorySelectFormField(
                  store: widget.store,
                  categoryType: isExpense ? 'Despesa' : 'Receita',
                  currentSelection: draft.categorySelection,
                  excludeAccountId: _targetAccountId,
                  onChanged: (val) =>
                      refresh(() => draft.categorySelection = val),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          TextFormField(
            key: ValueKey('payee_${draft.id}'),
            initialValue: draft.payee,
            decoration: const InputDecoration(
              labelText: 'Favorecido / Descrição',
              isDense: true,
              border: OutlineInputBorder(),
            ),
            onChanged: (val) {
              draft.payee = val;
              setState(() {});
            },
          ),
          const SizedBox(height: 10),
          TextFormField(
            key: ValueKey('memo_${draft.id}'),
            initialValue: draft.memo,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'Nota / Memo',
              isDense: true,
              border: OutlineInputBorder(),
            ),
            onChanged: (val) => draft.memo = val,
          ),
          const SizedBox(height: 10),
          TagInputField(
            tags: draft.tags,
            onChanged: (list) => refresh(() => draft.tags = list),
            availableTags: widget.store.allTags,
            colors: colors,
          ),
          if (_isCreditCardAccount && draft.canProjectInstallments) ...[
            const SizedBox(height: 8),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              dense: true,
              value: draft.projectFutureInstallments,
              title: Text(
                'Projetar parcelas futuras (${draft.raw.installmentCurrent! + 1}/${draft.raw.installmentTotal!} até ${draft.raw.installmentTotal!}/${draft.raw.installmentTotal!})',
                style: const TextStyle(fontSize: 12.5),
              ),
              onChanged: (v) =>
                  refresh(() => draft.projectFutureInstallments = v ?? false),
            ),
          ],
        ] else ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: colors.bgPrimary,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: colors.borderGlass),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Este item será ignorado',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: colors.textPrimary,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  draft.matchReason.isNotEmpty
                      ? draft.matchReason
                      : 'Nenhuma transação será criada ou alterada para este registro.',
                  style: TextStyle(fontSize: 12, color: colors.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}
