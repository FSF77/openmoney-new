import 'package:flutter/material.dart';
import '../../models/openmoney_models.dart';
import '../../services/b3_import_service.dart';
import '../../services/investment_engine.dart';
import '../../services/native_file_picker.dart';
import '../../services/platform_io.dart';
import '../../store/money_store.dart';
import '../theme/liquid_glass.dart';
import '../widgets/category_select_form_field.dart';
import '../widgets/date_input_formatter.dart';

/// Modal de cadastro/edição de Ativo de Investimento.
Future<InvestAsset?> showInvestmentAssetModal(
  BuildContext context,
  MoneyStore store, {
  InvestAsset? existing,
  String? defaultAccountId,
}) async {
  return showDialog<InvestAsset>(
    context: context,
    builder: (ctx) => _InvestAssetDialog(
      store: store,
      existing: existing,
      defaultAccountId: defaultAccountId,
    ),
  );
}

class _InvestAssetDialog extends StatefulWidget {
  final MoneyStore store;
  final InvestAsset? existing;
  final String? defaultAccountId;

  const _InvestAssetDialog({
    required this.store,
    this.existing,
    this.defaultAccountId,
  });

  @override
  State<_InvestAssetDialog> createState() => _InvestAssetDialogState();
}

class _InvestAssetDialogState extends State<_InvestAssetDialog> {
  late InvestAssetClass _assetClass;
  late String _accountId;
  late String _currency;
  late InvestFixedIncomeIndexer _indexer;
  late bool _taxExempt;
  late bool _manualPrice;
  late bool _inactive;
  late String _liquidity;

  final _tickerCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _subTypeCtrl = TextEditingController();
  final _rateCtrl = TextEditingController();
  final _maturityCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  final _memoCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    final investAccounts = widget.store.db.accounts
        .where((a) => a.isActive && a.type == 'Investimento')
        .toList();
    final fallbackAcc = investAccounts.isNotEmpty
        ? investAccounts.first.id
        : (widget.store.db.accounts.isNotEmpty
            ? widget.store.db.accounts.first.id
            : 'a1');

    _assetClass = e?.assetClass ?? InvestAssetClass.stock;
    _accountId = e?.accountId ?? widget.defaultAccountId ?? fallbackAcc;
    _currency = e?.currency ?? 'BRL';
    _indexer = e?.indexer ?? InvestFixedIncomeIndexer.cdi;
    _taxExempt = e?.taxExempt ?? false;
    _manualPrice = e?.manualPrice ?? false;
    _inactive = e?.inactive ?? false;
    _liquidity = e?.liquidity ?? 'daily';

    if (e != null) {
      _tickerCtrl.text = e.ticker;
      _nameCtrl.text = e.name;
      _subTypeCtrl.text = e.subType ?? '';
      if (e.ratePct != null) _rateCtrl.text = e.ratePct.toString().replaceAll('.', ',');
      if (e.maturityDate != null) _maturityCtrl.text = fmtDate(e.maturityDate!);
      if (e.currentPriceCents != null) {
        _priceCtrl.text = formatInputCents(e.currentPriceCents!);
      }
      _memoCtrl.text = e.memo ?? '';
    } else {
      _rateCtrl.text = '100';
    }
  }

  @override
  void dispose() {
    _tickerCtrl.dispose();
    _nameCtrl.dispose();
    _subTypeCtrl.dispose();
    _rateCtrl.dispose();
    _maturityCtrl.dispose();
    _priceCtrl.dispose();
    _memoCtrl.dispose();
    super.dispose();
  }

  void _save() {
    final ticker = _tickerCtrl.text.trim().toUpperCase();
    final name = _nameCtrl.text.trim();
    if (ticker.isEmpty && name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Informe o código/ticker ou nome do ativo.')),
      );
      return;
    }

    final parsedRate =
        double.tryParse(_rateCtrl.text.trim().replaceAll(',', '.'));
    final parsedPrice = parseCents(_priceCtrl.text);

    String? maturityIso;
    final matRaw = _maturityCtrl.text.trim();
    if (matRaw.isNotEmpty) {
      final parts = matRaw.split('/');
      if (parts.length == 3) {
        maturityIso = '${parts[2]}-${parts[1]}-${parts[0]}';
      } else if (RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(matRaw)) {
        maturityIso = matRaw;
      }
    }

    final asset = InvestAsset(
      id: widget.existing?.id,
      ticker: ticker.isNotEmpty ? ticker : name.toUpperCase(),
      name: name.isNotEmpty ? name : ticker,
      assetClass: _assetClass,
      subType: _subTypeCtrl.text.trim().isNotEmpty
          ? _subTypeCtrl.text.trim()
          : null,
      accountId: _accountId,
      currency: _currency,
      indexer: _assetClass.isFixedIncome ? _indexer : null,
      ratePct: _assetClass.isFixedIncome ? parsedRate : null,
      maturityDate: _assetClass.isFixedIncome ? maturityIso : null,
      liquidity: _assetClass.isFixedIncome ? _liquidity : null,
      taxExempt: _assetClass.isFixedIncome ? _taxExempt : false,
      currentPriceCents: parsedPrice ?? widget.existing?.currentPriceCents,
      priceUpdatedAt: parsedPrice != null
          ? DateTime.now().toIso8601String()
          : widget.existing?.priceUpdatedAt,
      manualPrice: _manualPrice || (parsedPrice != null && _assetClass.isFixedIncome),
      priceSource: _manualPrice ? 'Manual' : widget.existing?.priceSource,
      memo: _memoCtrl.text.trim().isNotEmpty ? _memoCtrl.text.trim() : null,
      inactive: _inactive,
    );

    widget.store.addOrUpdateInvestAsset(asset);
    Navigator.of(context).pop(asset);
  }

  Future<void> _confirmDeleteAsset() async {
    final existing = widget.existing;
    if (existing == null) return;
    bool deleteTxs = true;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSt) => AlertDialog(
          title: Text('Excluir ${existing.displayCode}?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Isso removerá o ativo e todo o histórico de operações dele na carteira.',
              ),
              const SizedBox(height: 10),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: const Text(
                  'Excluir também os lançamentos vinculados no caixa da conta',
                  style: TextStyle(fontSize: 12.5),
                ),
                value: deleteTxs,
                onChanged: (v) => setSt(() => deleteTxs = v ?? true),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancelar'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Excluir Ativo'),
            ),
          ],
        ),
      ),
    );
    if (confirmed == true && mounted) {
      widget.store.deleteInvestAsset(existing.id, deleteLinkedTxs: deleteTxs);
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colors = OpenMoneyColors(isDark);
    final accounts = widget.store.db.accounts.where((a) => a.isActive).toList();
    final investFirst = [
      ...accounts.where((a) => a.type == 'Investimento'),
      ...accounts.where((a) => a.type != 'Investimento'),
    ];

    return AlertDialog(
      backgroundColor: colors.bgSecondary,
      title: Text(
        widget.existing == null ? 'Novo Ativo' : 'Editar Ativo',
        style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.w800),
      ),
      content: SizedBox(
        width: 460,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DropdownButtonFormField<InvestAssetClass>(
                initialValue: _assetClass,
                decoration: const InputDecoration(
                  labelText: 'Classe do Ativo',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: InvestAssetClass.values
                    .map((c) => DropdownMenuItem(value: c, child: Text(c.label)))
                    .toList(),
                onChanged: (v) {
                  if (v == null) return;
                  setState(() {
                    _assetClass = v;
                    if (v == InvestAssetClass.tesouro) {
                      _subTypeCtrl.text = 'Tesouro Direto';
                    }
                  });
                },
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: TextField(
                      controller: _tickerCtrl,
                      textCapitalization: TextCapitalization.characters,
                      decoration: InputDecoration(
                        labelText: _assetClass.isFixedIncome
                            ? 'Código / Apelido'
                            : 'Ticker (ex: PETR4, HGLG11, BTC)',
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: _currency,
                      decoration: const InputDecoration(
                        labelText: 'Moeda',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: const [
                        DropdownMenuItem(value: 'BRL', child: Text('BRL')),
                        DropdownMenuItem(value: 'USD', child: Text('USD')),
                        DropdownMenuItem(value: 'EUR', child: Text('EUR')),
                      ],
                      onChanged: (v) {
                        if (v != null) setState(() => _currency = v);
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _nameCtrl,
                decoration: const InputDecoration(
                  labelText: 'Nome / Emissor (ex: Petrobras, CDB Banco Inter)',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String>(
                initialValue: investFirst.any((a) => a.id == _accountId)
                    ? _accountId
                    : (investFirst.isNotEmpty ? investFirst.first.id : null),
                decoration: const InputDecoration(
                  labelText: 'Conta / Corretora de Custódia',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: investFirst
                    .map((a) => DropdownMenuItem(
                          value: a.id,
                          child: Text('${a.name} (${a.type})'),
                        ))
                    .toList(),
                onChanged: (v) {
                  if (v != null) setState(() => _accountId = v);
                },
              ),
              if (_assetClass.isFixedIncome) ...[
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _subTypeCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Tipo (CDB, LCI, LCA, Selic...)',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        onChanged: (v) {
                          final u = v.toUpperCase();
                          if (u.contains('LCI') ||
                              u.contains('LCA') ||
                              u.contains('CRI') ||
                              u.contains('CRA')) {
                            setState(() => _taxExempt = true);
                          }
                        },
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: DropdownButtonFormField<InvestFixedIncomeIndexer>(
                        initialValue: _indexer,
                        decoration: const InputDecoration(
                          labelText: 'Indexador',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        items: InvestFixedIncomeIndexer.values
                            .map((i) =>
                                DropdownMenuItem(value: i, child: Text(i.label)))
                            .toList(),
                        onChanged: (v) {
                          if (v != null) setState(() => _indexer = v);
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _rateCtrl,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        decoration: InputDecoration(
                          labelText: _indexer == InvestFixedIncomeIndexer.cdi
                              ? 'Percentual (% do CDI)'
                              : 'Taxa (% a.a.)',
                          border: const OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: _maturityCtrl,
                        keyboardType: TextInputType.number,
                        inputFormatters: [DateInputFormatter()],
                        decoration: const InputDecoration(
                          labelText: 'Vencimento (DD/MM/AAAA)',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: const Text('Isento de IR (LCI, LCA, CRI, CRA)'),
                  value: _taxExempt,
                  onChanged: (v) => setState(() => _taxExempt = v),
                ),
              ],
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _priceCtrl,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'Preço Atualizado (opcional)',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Checkbox(
                        value: _manualPrice,
                        onChanged: (v) =>
                            setState(() => _manualPrice = v ?? false),
                      ),
                      const Text('Manual', style: TextStyle(fontSize: 12)),
                    ],
                  ),
                ],
              ),
              if (widget.existing != null) ...[
                const SizedBox(height: 6),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: const Text('Ativo inativo (arquivado)'),
                  subtitle: const Text(
                    'Oculta da lista principal e de novos lançamentos',
                    style: TextStyle(fontSize: 11),
                  ),
                  value: _inactive,
                  onChanged: (v) => setState(() => _inactive = v),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        if (widget.existing != null)
          TextButton(
            onPressed: _confirmDeleteAsset,
            style: TextButton.styleFrom(foregroundColor: colors.expense),
            child: const Text('Excluir Ativo'),
          ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _save,
          child: const Text('Salvar Ativo'),
        ),
      ],
    );
  }
}

/// Modal de lançamento de Operação na Carteira (Compra, Venda, Provento, Posição Inicial, etc.).
Future<bool?> showInvestmentOperationModal(
  BuildContext context,
  MoneyStore store, {
  InvestAsset? initialAsset,
  InvestOpType initialType = InvestOpType.buy,
  InvestOperation? existingOp,
}) async {
  return showDialog<bool>(
    context: context,
    builder: (ctx) => _InvestOperationDialog(
      store: store,
      initialAsset: initialAsset,
      initialType: initialType,
      existingOp: existingOp,
    ),
  );
}

class _InvestOperationDialog extends StatefulWidget {
  final MoneyStore store;
  final InvestAsset? initialAsset;
  final InvestOpType initialType;
  final InvestOperation? existingOp;

  const _InvestOperationDialog({
    required this.store,
    this.initialAsset,
    required this.initialType,
    this.existingOp,
  });

  @override
  State<_InvestOperationDialog> createState() => _InvestOperationDialogState();
}

class _InvestOperationDialogState extends State<_InvestOperationDialog> {
  late InvestOpType _opType;
  String? _assetId;
  late String _accountId;
  late bool _affectCash;
  late String _dividendCat;
  late String _irCat;
  bool _syncingFields = false;
  bool _taxEditedManually = false;

  final _dateCtrl = TextEditingController(text: fmtDate(todayISO()));
  final _qtyCtrl = TextEditingController();
  final _unitPriceCtrl = TextEditingController();
  final _feesCtrl = TextEditingController(text: '0,00');
  final _totalCtrl = TextEditingController();
  final _taxCtrl = TextEditingController(text: '0,00');
  final _memoCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    final ex = widget.existingOp;
    _opType = ex?.type ?? widget.initialType;
    _affectCash = ex != null
        ? (ex.linkedTxId != null)
        : (widget.initialType != InvestOpType.initialPosition &&
            widget.initialType != InvestOpType.split &&
            widget.initialType != InvestOpType.inplit &&
            widget.initialType != InvestOpType.bonus);
    _dividendCat = widget.store.investDividendCategory;
    _irCat = widget.store.investIrCategory;
    widget.store.ensureCategoryPath(_irCat, type: 'Despesa');

    if (ex != null) {
      _assetId = ex.assetId;
      _accountId = ex.accountId;
      _dateCtrl.text = fmtDate(ex.date);
      final asset = widget.store.investAssetById(ex.assetId);
      _qtyCtrl.text = formatInvestQty(
        ex.quantity,
        asset?.assetClass ?? InvestAssetClass.stock,
      );
      _feesCtrl.text = formatInputCents(ex.feesCents);
      _totalCtrl.text = formatInputCents(ex.totalCents);
      _taxCtrl.text = formatInputCents(ex.taxCents);
      _taxEditedManually = true;
      if (ex.quantity > 0 && ex.totalCents > 0) {
        final grossCents = ex.type == InvestOpType.sell
            ? (ex.totalCents + ex.feesCents)
            : (ex.totalCents - ex.feesCents);
        final unitVal = (grossCents / 100.0) / ex.quantity;
        _unitPriceCtrl.text = _formatUnitDouble(unitVal);
      } else {
        _unitPriceCtrl.text = formatInputCents(ex.unitPriceCents);
      }
      _memoCtrl.text = ex.memo;
      if (ex.linkedTxId != null && ex.type.isIncome) {
        final linkedTx = widget.store.db.txs
            .where((t) => t.id == ex.linkedTxId)
            .firstOrNull;
        if (linkedTx != null && linkedTx.cat.isNotEmpty) {
          _dividendCat = linkedTx.cat;
        }
      }
      if (ex.linkedTaxTxId != null) {
        final linkedTax = widget.store.db.txs
            .where((t) => t.id == ex.linkedTaxTxId)
            .firstOrNull;
        if (linkedTax != null && linkedTax.cat.isNotEmpty) {
          _irCat = linkedTax.cat;
        }
      }
    } else if (widget.initialAsset != null) {
      _assetId = widget.initialAsset!.id;
      _accountId = widget.initialAsset!.accountId;
    } else if (widget.store.db.investAssets.isNotEmpty) {
      _assetId = widget.store.db.investAssets.first.id;
      _accountId = widget.store.db.investAssets.first.accountId;
    } else {
      final invAcc = widget.store.db.accounts
          .where((a) => a.isActive && a.type == 'Investimento')
          .toList();
      _accountId = invAcc.isNotEmpty
          ? invAcc.first.id
          : (widget.store.db.accounts.isNotEmpty
              ? widget.store.db.accounts.first.id
              : 'a1');
    }

    _dateCtrl.addListener(_onDateOrIrInputsChanged);
    _qtyCtrl.addListener(_onQtyOrUnitChanged);
    _unitPriceCtrl.addListener(_onQtyOrUnitChanged);
    _feesCtrl.addListener(_onQtyOrUnitChanged);
    _totalCtrl.addListener(_onTotalChanged);

    if (ex == null && _opType == InvestOpType.sell) {
      _prefillAvailableQtyForSell();
    }
  }

  void _prefillAvailableQtyForSell() {
    if (widget.existingOp != null || _opType != InvestOpType.sell) return;
    final asset = widget.store.investAssetById(_assetId);
    if (asset == null) return;
    final ops = widget.store.db.investOps
        .where((o) => o.assetId == asset.id)
        .toList();
    final pos = InvestmentEngine.computeAssetPosition(asset, ops);
    if (pos.currentQty > 1e-8) {
      _qtyCtrl.text = formatInvestQty(pos.currentQty, asset.assetClass);
    }
  }

  @override
  void dispose() {
    _dateCtrl.dispose();
    _qtyCtrl.dispose();
    _unitPriceCtrl.dispose();
    _feesCtrl.dispose();
    _totalCtrl.dispose();
    _taxCtrl.dispose();
    _memoCtrl.dispose();
    super.dispose();
  }

  String _parseDateIso() {
    var dateIso = todayISO();
    final parts = _dateCtrl.text.trim().split('/');
    if (parts.length == 3 &&
        parts[0].length == 2 &&
        parts[1].length == 2 &&
        parts[2].length == 4) {
      dateIso = '${parts[2]}-${parts[1]}-${parts[0]}';
    }
    return dateIso;
  }

  ({int irCents, double effectiveRatePct, int oldestDaysHeld}) _estimateIr() {
    final asset = widget.store.investAssetById(_assetId);
    if (asset == null ||
        _opType != InvestOpType.sell ||
        !asset.isFixedIncome ||
        asset.taxExempt) {
      return (irCents: 0, effectiveRatePct: 0.0, oldestDaysHeld: 0);
    }
    final qty = _parseDoubleBr(_qtyCtrl.text);
    final total = _effectiveTotalCents();
    final fees = parseCents(_feesCtrl.text) ?? 0;
    final priorOps = widget.store.db.investOps
        .where((o) =>
            o.assetId == asset.id && o.id != widget.existingOp?.id)
        .toList();
    return InvestmentEngine.estimateSellIr(
      asset: asset,
      priorOps: priorOps,
      sellDateIso: _parseDateIso(),
      sellQty: qty,
      grossSellCents: total + fees,
      feesCents: fees,
    );
  }

  void _recalcSuggestedIrIfNeeded() {
    if (_taxEditedManually) return;
    final est = _estimateIr();
    _taxCtrl.text = formatInputCents(est.irCents);
  }

  void _onDateOrIrInputsChanged() {
    _recalcSuggestedIrIfNeeded();
    if (mounted) setState(() {});
  }

  double _parseDoubleBr(String raw) {
    var clean = raw.trim().replaceAll(' ', '');
    if (clean.isEmpty) return 0.0;
    if (clean.contains(',')) {
      clean = clean.replaceAll('.', '').replaceAll(',', '.');
    }
    clean = clean.replaceAll(RegExp(r'[^0-9.\-]'), '');
    return double.tryParse(clean) ?? 0.0;
  }

  String _formatUnitDouble(double val) {
    if (val <= 0) return '0,00';
    final s = val.toStringAsFixed(6);
    var trimmed = s.replaceAll(RegExp(r'0+$'), '');
    if (trimmed.endsWith('.')) {
      trimmed = '${trimmed}00';
    } else {
      final dotIdx = trimmed.indexOf('.');
      if (dotIdx >= 0 && trimmed.length - dotIdx - 1 < 2) {
        trimmed = trimmed.padRight(dotIdx + 3, '0');
      }
    }
    return trimmed.replaceAll('.', ',');
  }

  void _onQtyOrUnitChanged() {
    if (_syncingFields) return;
    _syncingFields = true;
    try {
      final qty = _parseDoubleBr(_qtyCtrl.text);
      final unitDouble = _parseDoubleBr(_unitPriceCtrl.text);
      final fees = parseCents(_feesCtrl.text) ?? 0;
      int totalCents;
      if (_opType.isIncome || _opType == InvestOpType.amortization) {
        totalCents = unitDouble > 0 && qty <= 0
            ? (unitDouble * 100.0).round()
            : (qty * unitDouble * 100.0).round();
      } else if (_opType == InvestOpType.sell) {
        final gross = (qty * unitDouble * 100.0).round();
        totalCents = gross > fees ? gross - fees : 0;
      } else {
        totalCents = (qty * unitDouble * 100.0).round() + fees;
      }
      _totalCtrl.text = formatInputCents(totalCents);
      _recalcSuggestedIrIfNeeded();
      setState(() {});
    } finally {
      _syncingFields = false;
    }
  }

  void _onTotalChanged() {
    if (_syncingFields) return;
    _syncingFields = true;
    try {
      final qty = _parseDoubleBr(_qtyCtrl.text);
      final totalCents = parseCents(_totalCtrl.text) ?? 0;
      final fees = parseCents(_feesCtrl.text) ?? 0;
      if (qty > 0 && totalCents >= 0) {
        final grossCents = _opType == InvestOpType.sell
            ? (totalCents + fees)
            : (_opType.isIncome || _opType == InvestOpType.amortization
                ? totalCents
                : (totalCents > fees ? totalCents - fees : 0));
        final unitVal = (grossCents / 100.0) / qty;
        _unitPriceCtrl.text = _formatUnitDouble(unitVal);
      }
      _recalcSuggestedIrIfNeeded();
      setState(() {});
    } finally {
      _syncingFields = false;
    }
  }

  int _effectiveTotalCents() {
    final parsed = parseCents(_totalCtrl.text);
    if (parsed != null && parsed >= 0) return parsed;
    final qty = _parseDoubleBr(_qtyCtrl.text);
    final unitDouble = _parseDoubleBr(_unitPriceCtrl.text);
    final fees = parseCents(_feesCtrl.text) ?? 0;
    if (_opType == InvestOpType.sell) {
      final gross = (qty * unitDouble * 100.0).round();
      return gross > fees ? gross - fees : 0;
    }
    return (qty * unitDouble * 100.0).round() + fees;
  }

  void _save() {
    if (_assetId == null || _assetId!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cadastre ou selecione um ativo primeiro.')),
      );
      return;
    }
    final qty = _parseDoubleBr(_qtyCtrl.text);
    final fees = parseCents(_feesCtrl.text) ?? 0;
    final totalCents = _effectiveTotalCents();

    if (!_opType.isIncome &&
        _opType != InvestOpType.amortization &&
        qty <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Informe uma quantidade válida.')),
      );
      return;
    }

    final effQty = (_opType.isIncome || _opType == InvestOpType.amortization) &&
            qty <= 0
        ? 1.0
        : qty;
    final grossCents = _opType == InvestOpType.sell
        ? (totalCents + fees)
        : (_opType.isIncome || _opType == InvestOpType.amortization
            ? totalCents
            : (totalCents > fees ? totalCents - fees : 0));
    final unitCents = effQty > 0
        ? (grossCents / effQty).round()
        : (parseCents(_unitPriceCtrl.text) ?? 0);

    var dateIso = _parseDateIso();
    final taxCents = _opType == InvestOpType.sell
        ? (parseCents(_taxCtrl.text) ?? 0)
        : 0;

    final op = InvestOperation(
      id: widget.existingOp?.id,
      assetId: _assetId!,
      accountId: _accountId,
      type: _opType,
      date: dateIso,
      quantity: effQty,
      unitPriceCents: unitCents,
      feesCents: fees,
      taxCents: taxCents,
      totalCents: totalCents,
      linkedTxId: widget.existingOp?.linkedTxId,
      linkedTaxTxId: widget.existingOp?.linkedTaxTxId,
      memo: _memoCtrl.text.trim(),
      createdAt: widget.existingOp?.createdAt,
    );

    if (_opType.isIncome && _dividendCat.isNotEmpty) {
      widget.store.setInvestDividendCategory(_dividendCat);
    }
    if (_opType == InvestOpType.sell && taxCents > 0 && _irCat.isNotEmpty) {
      widget.store.setInvestIrCategory(_irCat);
    }

    if (widget.existingOp != null) {
      widget.store.updateInvestOperation(
        op,
        affectAccountCash: _affectCash,
        dividendCategory: _dividendCat,
        irCategory: _irCat,
      );
    } else {
      widget.store.addInvestOperation(
        op,
        affectAccountCash: _affectCash,
        dividendCategory: _dividendCat,
        irCategory: _irCat,
      );
    }
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colors = OpenMoneyColors(isDark);
    final assets = widget.store.db.investAssets;
    final selectedAsset = widget.store.investAssetById(_assetId);
    final cur = selectedAsset?.currency ?? widget.store.baseCurrency;

    final qty = _parseDoubleBr(_qtyCtrl.text);
    final total = _effectiveTotalCents();

    // Preview de impacto no PM / Lucro Realizado
    AssetPositionSummary? currentPos;
    if (selectedAsset != null) {
      final ops = widget.store.db.investOps
          .where((o) =>
              o.assetId == selectedAsset.id && o.id != widget.existingOp?.id)
          .toList();
      currentPos = InvestmentEngine.computeAssetPosition(selectedAsset, ops);
    }

    String? previewText;
    if (currentPos != null && qty > 0 && total > 0) {
      if (_opType == InvestOpType.buy ||
          _opType == InvestOpType.initialPosition) {
        final newQty = currentPos.currentQty + qty;
        final newCost = currentPos.currentCostBasisCents + total;
        final newPm = newQty > 0 ? (newCost / newQty).round() : 0;
        previewText =
            'Novo Preço Médio estimado: ${formatCurrency(newPm, cur)}';
      } else if (_opType == InvestOpType.sell &&
          currentPos.avgBuyPriceCents > 0) {
        final costSold = (qty * currentPos.avgBuyPriceCents).round();
        final pnl = total - costSold;
        previewText =
            'Lucro/Prejuízo Realizado estimado: ${formatCurrency(pnl, cur)} (PM mantido em ${formatCurrency(currentPos.avgBuyPriceCents, cur)})';
      }
    }

    return AlertDialog(
      backgroundColor: colors.bgSecondary,
      title: Text(
        widget.existingOp != null
            ? 'Editar Operação na Carteira'
            : 'Nova Operação na Carteira',
        style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.w800),
      ),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DropdownButtonFormField<InvestOpType>(
                initialValue: _opType,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Tipo de Operação',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                items: InvestOpType.values
                    .map((t) => DropdownMenuItem(
                          value: t,
                          child: Text(
                            t.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ))
                    .toList(),
                onChanged: (v) {
                  if (v == null) return;
                  setState(() {
                    _opType = v;
                    if (v == InvestOpType.initialPosition ||
                        v == InvestOpType.split ||
                        v == InvestOpType.inplit ||
                        v == InvestOpType.bonus) {
                      _affectCash = false;
                    } else {
                      _affectCash = true;
                    }
                  });
                  if (v == InvestOpType.sell) {
                    _prefillAvailableQtyForSell();
                  }
                  _onQtyOrUnitChanged();
                },
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      initialValue: assets.any((a) => a.id == _assetId)
                          ? _assetId
                          : null,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Ativo',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: assets
                          .where((a) => !a.inactive || a.id == _assetId)
                          .map((a) => DropdownMenuItem(
                                value: a.id,
                                child: Text(
                                  '${a.displayCode} · ${a.assetClass.shortLabel}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ))
                          .toList(),
                      onChanged: (v) {
                        if (v == null) return;
                        final a = widget.store.investAssetById(v);
                        setState(() {
                          _assetId = v;
                          if (a != null) _accountId = a.accountId;
                        });
                        _prefillAvailableQtyForSell();
                        _onQtyOrUnitChanged();
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final created =
                          await showInvestmentAssetModal(context, widget.store);
                      if (created != null && mounted) {
                        setState(() {
                          _assetId = created.id;
                          _accountId = created.accountId;
                        });
                      }
                    },
                    icon: const Icon(Icons.add, size: 16),
                    label: const Text('Ativo'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _dateCtrl,
                      keyboardType: TextInputType.number,
                      inputFormatters: [DateInputFormatter()],
                      decoration: const InputDecoration(
                        labelText: 'Data (DD/MM/AAAA)',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _qtyCtrl,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                        labelText: _opType == InvestOpType.split ||
                                _opType == InvestOpType.inplit
                            ? 'Fator (ex: 10)'
                            : 'Quantidade',
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _unitPriceCtrl,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                        labelText: _opType.isIncome ||
                                _opType == InvestOpType.amortization
                            ? 'Valor / Unitário'
                            : 'Preço Unitário',
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _feesCtrl,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'Taxas / Corretagem',
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _totalCtrl,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(
                  labelText: _opType == InvestOpType.sell &&
                          selectedAsset != null &&
                          selectedAsset.isFixedIncome &&
                          !selectedAsset.taxExempt
                      ? 'Valor Bruto da Venda ($cur) — editável'
                      : 'Total da Operação ($cur) — editável',
                  helperText:
                      'Altere o total para recalcular o preço unitário automaticamente',
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              if (_opType == InvestOpType.sell &&
                  selectedAsset != null &&
                  selectedAsset.isFixedIncome &&
                  !selectedAsset.taxExempt) ...[
                const SizedBox(height: 12),
                Builder(builder: (context) {
                  final est = _estimateIr();
                  final taxCents = parseCents(_taxCtrl.text) ?? 0;
                  final netCents = total > taxCents ? total - taxCents : 0;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextField(
                        controller: _taxCtrl,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        onChanged: (_) {
                          _taxEditedManually = true;
                          setState(() {});
                        },
                        decoration: InputDecoration(
                          labelText: 'IR Retido na Fonte ($cur)',
                          helperText: est.oldestDaysHeld > 0
                              ? 'Tabela regressiva est.: ${est.effectiveRatePct.toStringAsFixed(1)}% (${est.oldestDaysHeld} dias) · Líquido: ${formatCurrency(netCents, cur)}'
                              : 'Valor líquido estimado: ${formatCurrency(netCents, cur)}',
                          border: const OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                      if (_affectCash && taxCents > 0) ...[
                        const SizedBox(height: 10),
                        CategorySelectFormField(
                          store: widget.store,
                          categoryType: 'Despesa',
                          currentSelection: _irCat,
                          allowTransfers: false,
                          labelText: 'Categoria do lançamento de IR',
                          onChanged: (v) => setState(() => _irCat = v),
                        ),
                      ],
                    ],
                  );
                }),
              ],
              if (previewText != null) ...[
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: colors.surfaceGlass,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: colors.borderGlass),
                  ),
                  child: Text(
                    previewText,
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: colors.accent,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 8),
              Builder(builder: (context) {
                final activeAccs = widget.store.db.accounts
                    .where((a) => a.isActive)
                    .toList();
                final orderedAccs = [
                  ...activeAccs.where((a) => a.type == 'Investimento'),
                  ...activeAccs.where((a) => a.type != 'Investimento'),
                ];
                final validAccId =
                    orderedAccs.any((a) => a.id == _accountId)
                        ? _accountId
                        : (orderedAccs.isNotEmpty
                            ? orderedAccs.first.id
                            : null);
                return DropdownButtonFormField<String>(
                  initialValue: validAccId,
                  isExpanded: true,
                  decoration: const InputDecoration(
                    labelText: 'Conta / Corretora de Custódia',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  items: orderedAccs
                      .map((a) => DropdownMenuItem(
                            value: a.id,
                            child: Text(
                              '${a.name} (${a.type})',
                              overflow: TextOverflow.ellipsis,
                            ),
                          ))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) setState(() => _accountId = v);
                  },
                );
              }),
              const SizedBox(height: 6),
              if (_opType != InvestOpType.split &&
                  _opType != InvestOpType.inplit &&
                  _opType != InvestOpType.bonus)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: Text(
                    _opType == InvestOpType.initialPosition
                        ? 'Converter saldo da conta Investimento (Transferência -)'
                        : 'Movimentar caixa da conta selecionada',
                    style: const TextStyle(fontSize: 13),
                  ),
                  subtitle: Text(
                    _opType.isIncome
                        ? 'Categoria: $_dividendCat'
                        : (_opType == InvestOpType.sell
                            ? 'Gera lançamento Transferência (+) na conta'
                            : 'Gera lançamento Transferência (-) sem afetar gastos/relatórios'),
                    style: TextStyle(fontSize: 11, color: colors.textSecondary),
                  ),
                  value: _affectCash,
                  onChanged: (v) => setState(() => _affectCash = v),
                ),
              if (_opType.isIncome && _affectCash) ...[
                const SizedBox(height: 6),
                TextFormField(
                  initialValue: _dividendCat,
                  decoration: const InputDecoration(
                    labelText: 'Categoria para Proventos',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  onChanged: (v) => _dividendCat = v,
                ),
              ],
              const SizedBox(height: 8),
              TextField(
                controller: _memoCtrl,
                decoration: const InputDecoration(
                  labelText: 'Observação (opcional)',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _save,
          child: Text(
            widget.existingOp != null
                ? 'Salvar Alterações'
                : 'Registrar Operação',
          ),
        ),
      ],
    );
  }
}

/// Modal de Importação de Planilha B3 (.xlsx / .csv).
Future<int?> showB3ImportModal(BuildContext context, MoneyStore store) async {
  return showDialog<int>(
    context: context,
    builder: (ctx) => _B3ImportDialog(store: store),
  );
}

class _B3ImportDialog extends StatefulWidget {
  final MoneyStore store;
  const _B3ImportDialog({required this.store});

  @override
  State<_B3ImportDialog> createState() => _B3ImportDialogState();
}

class _B3ImportDialogState extends State<_B3ImportDialog> {
  B3ParseResult? _result;
  String? _fileName;
  late String _accountId;
  bool _convertCashBalance = false;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    final invAcc = widget.store.db.accounts
        .where((a) => a.isActive && a.type == 'Investimento')
        .toList();
    _accountId = invAcc.isNotEmpty
        ? invAcc.first.id
        : (widget.store.db.accounts.isNotEmpty
            ? widget.store.db.accounts.first.id
            : 'a1');
  }

  Future<void> _pickFile() async {
    setState(() => _loading = true);
    try {
      final selected = await NativeFilePicker.pickFile(
        title: 'Selecionar Planilha B3 (.xlsx ou .csv)',
        allowedExtensions: ['xlsx', 'csv'],
      );
      if (selected != null && selected.isNotEmpty && mounted) {
        final bytes = File(selected).readAsBytesSync();
        final name = selected.split(RegExp(r'[/\\]')).last;
        final parsed = B3ImportService.parseBytes(
          bytes,
          name,
          existingOps: widget.store.db.investOps,
          existingAssets: widget.store.db.investAssets,
        );
        setState(() {
          _fileName = name;
          _result = parsed;
        });
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colors = OpenMoneyColors(isDark);
    final accounts = widget.store.db.accounts.where((a) => a.isActive).toList();

    return AlertDialog(
      backgroundColor: colors.bgSecondary,
      title: Text(
        'Importar Planilha B3 (.xlsx / .csv)',
        style: TextStyle(color: colors.textPrimary, fontWeight: FontWeight.w800),
      ),
      content: SizedBox(
        width: 580,
        height: 440,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    initialValue: accounts.any((a) => a.id == _accountId)
                        ? _accountId
                        : null,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Conta de Destino (Corretora)',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: accounts
                        .map((a) => DropdownMenuItem(
                              value: a.id,
                              child: Text(
                                '${a.name} (${a.type})',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ))
                        .toList(),
                    onChanged: (v) {
                      if (v != null) setState(() => _accountId = v);
                    },
                  ),
                ),
                const SizedBox(width: 10),
                FilledButton.icon(
                  onPressed: _loading ? null : _pickFile,
                  icon: const Icon(Icons.upload_file, size: 18),
                  label: Text(_fileName == null ? 'Escolher Arquivo' : 'Trocar'),
                ),
              ],
            ),
            if (_fileName != null) ...[
              const SizedBox(height: 8),
              Text(
                'Arquivo: $_fileName · Modo detectado: ${_result?.mode == "operations" ? "Negociação/Movimentação" : "Posição Inicial"}',
                style: TextStyle(fontSize: 12, color: colors.textSecondary),
              ),
            ],
            if (_result?.warning != null) ...[
              const SizedBox(height: 8),
              Text(
                _result!.warning!,
                style: TextStyle(fontSize: 12, color: colors.warning),
              ),
            ],
            const SizedBox(height: 10),
            Expanded(
              child: _result == null
                  ? Center(
                      child: Text(
                        'Exporte a planilha de "Posição" ou "Movimentação" na Área do Investidor B3 (.xlsx ou .csv) e selecione acima.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: colors.textSecondary),
                      ),
                    )
                  : ListView.builder(
                      itemCount: _result!.items.length,
                      itemBuilder: (ctx, i) {
                        final item = _result!.items[i];
                        return CheckboxListTile(
                          dense: true,
                          value: item.selected,
                          onChanged: (v) =>
                              setState(() => item.selected = v ?? false),
                          title: Text(
                            '${item.ticker} · ${item.assetClass.shortLabel} (${item.opType.label})',
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                          subtitle: Text(
                            'Qtde: ${formatInvestQty(item.quantity, item.assetClass)} · Unit: ${formatCurrency(item.unitPriceCents, "BRL")} · Total: ${formatCurrency(item.totalCents, "BRL")}${item.isDuplicate ? " [Duplicado]" : ""}',
                            style: TextStyle(
                              fontSize: 11.5,
                              color: item.isDuplicate
                                  ? colors.warning
                                  : colors.textSecondary,
                            ),
                          ),
                        );
                      },
                    ),
            ),
            if (_result != null && _result!.items.isNotEmpty)
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: const Text(
                  'Converter saldo atual da conta em Posição Inicial (Transferência -)',
                  style: TextStyle(fontSize: 12.5),
                ),
                value: _convertCashBalance,
                onChanged: (v) => setState(() => _convertCashBalance = v),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: _result == null ||
                  !_result!.items.any((i) => i.selected)
              ? null
              : () {
                  final count = widget.store.importB3Items(
                    _result!.items,
                    accountId: _accountId,
                    convertCashBalance: _convertCashBalance,
                  );
                  Navigator.of(context).pop(count);
                },
          child: const Text('Importar Selecionados'),
        ),
      ],
    );
  }
}

/// Modal de Detalhe de Operações / Movimentações de um Ativo específico.
Future<void> showAssetOperationsModal(
  BuildContext context,
  MoneyStore store,
  InvestAsset asset,
) async {
  await showDialog<void>(
    context: context,
    builder: (ctx) => _AssetOperationsDialog(store: store, assetId: asset.id),
  );
}

class _AssetOperationsDialog extends StatelessWidget {
  final MoneyStore store;
  final String assetId;

  const _AssetOperationsDialog({
    required this.store,
    required this.assetId,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colors = OpenMoneyColors(isDark);

    return AnimatedBuilder(
      animation: store,
      builder: (context, _) {
        final asset = store.investAssetById(assetId);
        if (asset == null) {
          return AlertDialog(
            backgroundColor: colors.bgSecondary,
            content: const Text('Ativo não encontrado.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Fechar'),
              ),
            ],
          );
        }

        final ops = store.db.investOps
            .where((o) => o.assetId == asset.id)
            .toList()
          ..sort((a, b) => b.date.compareTo(a.date));
        final pos = InvestmentEngine.computeAssetPosition(
          asset,
          ops,
          indicators: store.db.investIndicators,
        );
        final cur = asset.currency;
        final pnlColor =
            pos.unrealizedPnlCents >= 0 ? colors.income : colors.expense;

        return AlertDialog(
          backgroundColor: colors.bgSecondary,
          title: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${asset.displayCode} · ${asset.assetClass.label}',
                      style: TextStyle(
                        color: colors.textPrimary,
                        fontWeight: FontWeight.w800,
                        fontSize: 17,
                      ),
                    ),
                    Text(
                      asset.name,
                      style: TextStyle(
                        fontSize: 12,
                        color: colors.textSecondary,
                        fontWeight: FontWeight.normal,
                      ),
                    ),
                  ],
                ),
              ),
              OutlinedButton.icon(
                onPressed: () => showInvestmentAssetModal(
                  context,
                  store,
                  existing: asset,
                ),
                icon: const Icon(Icons.edit_outlined, size: 16),
                label: const Text('Ativo'),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: () => showInvestmentOperationModal(
                  context,
                  store,
                  initialAsset: asset,
                ),
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Operação'),
              ),
            ],
          ),
          content: SizedBox(
            width: 660,
            height: 440,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: colors.surfaceGlass,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: colors.borderGlass),
                  ),
                  child: Wrap(
                    spacing: 18,
                    runSpacing: 8,
                    children: [
                      _DetailStat(
                        label: 'Qtde',
                        value: formatInvestQty(pos.currentQty, asset.assetClass),
                      ),
                      _DetailStat(
                        label: 'PM Compra',
                        value: formatCurrency(pos.avgBuyPriceCents, cur),
                      ),
                      if (pos.avgSellPriceCents > 0)
                        _DetailStat(
                          label: 'PM Venda',
                          value: formatCurrency(pos.avgSellPriceCents, cur),
                        ),
                      _DetailStat(
                        label: 'Preço Atual',
                        value: formatCurrency(pos.currentUnitPriceCents, cur),
                      ),
                      _DetailStat(
                        label: pos.estimatedTaxCents > 0
                            ? 'Valor Atual (Bruto)'
                            : 'Valor Atual',
                        value: formatCurrency(pos.currentGrossValueCents, cur),
                      ),
                      if (pos.estimatedTaxCents > 0)
                        _DetailStat(
                          label: 'Líquido Est. (IR ${formatCurrency(pos.estimatedTaxCents, cur)})',
                          value: formatCurrency(pos.currentNetValueCents, cur),
                        ),
                      _DetailStat(
                        label: 'Rentabilidade',
                        value:
                            '${formatCurrency(pos.unrealizedPnlCents, cur)} (${pos.unrealizedPnlPct.toStringAsFixed(2)}%)',
                        valueColor: pnlColor,
                      ),
                      if (pos.realizedPnlCents != 0)
                        _DetailStat(
                          label: 'Realizado',
                          value: formatCurrency(pos.realizedPnlCents, cur),
                          valueColor: pos.realizedPnlCents >= 0
                              ? colors.income
                              : colors.expense,
                        ),
                      if (pos.totalDividendsCents > 0)
                        _DetailStat(
                          label: 'Proventos',
                          value: formatCurrency(pos.totalDividendsCents, cur),
                          valueColor: colors.income,
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Movimentações (${ops.length})',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    fontSize: 13,
                    color: colors.textSecondary,
                  ),
                ),
                const SizedBox(height: 6),
                Expanded(
                  child: ops.isEmpty
                      ? Center(
                          child: Text(
                            'Nenhuma movimentação registrada para este ativo.',
                            style: TextStyle(color: colors.textSecondary),
                          ),
                        )
                      : ListView.builder(
                          itemCount: ops.length,
                          itemBuilder: (ctx, i) {
                            final op = ops[i];
                            final accName =
                                store.accById(op.accountId)?.name ?? '';
                            return Container(
                              margin: const EdgeInsets.only(bottom: 6),
                              decoration: BoxDecoration(
                                color: colors.surfaceCard,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: colors.borderGlass),
                              ),
                              child: ListTile(
                                dense: true,
                                title: Text(
                                  '${op.type.label} · ${fmtDate(op.date)}${accName.isNotEmpty ? " · $accName" : ""}',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    fontSize: 13,
                                    color: colors.textPrimary,
                                  ),
                                ),
                                subtitle: Text(
                                  'Qtde: ${formatInvestQty(op.quantity, asset.assetClass)} · '
                                  'Unit: ${formatCurrency(op.unitPriceCents, cur)}'
                                  '${op.feesCents > 0 ? " · Taxas: ${formatCurrency(op.feesCents, cur)}" : ""}'
                                  '${op.taxCents > 0 ? " · IR: ${formatCurrency(op.taxCents, cur)}" : ""}'
                                  '${op.memo.isNotEmpty ? " · ${op.memo}" : ""}',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    color: colors.textSecondary,
                                  ),
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      formatCurrency(op.totalCents, cur),
                                      style: TextStyle(
                                        fontWeight: FontWeight.w800,
                                        fontSize: 13,
                                        color: op.type.isCashIn
                                            ? colors.income
                                            : colors.textPrimary,
                                      ),
                                    ),
                                    IconButton(
                                      tooltip: 'Editar operação',
                                      icon: const Icon(Icons.edit_outlined,
                                          size: 17),
                                      onPressed: () =>
                                          showInvestmentOperationModal(
                                        context,
                                        store,
                                        existingOp: op,
                                      ),
                                    ),
                                    IconButton(
                                      tooltip: 'Excluir operação',
                                      icon: Icon(Icons.delete_outline,
                                          size: 17, color: colors.expense),
                                      onPressed: () =>
                                          confirmDeleteInvestOperation(
                                        context,
                                        store,
                                        op,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Fechar'),
            ),
          ],
        );
      },
    );
  }
}

class _DetailStat extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;

  const _DetailStat({
    required this.label,
    required this.value,
    this.valueColor,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label,
            style: const TextStyle(fontSize: 10.5, color: Colors.grey)),
        Text(
          value,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w800,
            color: valueColor,
          ),
        ),
      ],
    );
  }
}

/// Diálogo de confirmação antes de excluir qualquer operação da carteira.
Future<bool> confirmDeleteInvestOperation(
  BuildContext context,
  MoneyStore store,
  InvestOperation op,
) async {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  final colors = OpenMoneyColors(isDark);
  final asset = store.investAssetById(op.assetId);
  final cur = asset?.currency ?? store.baseCurrency;
  final hasLinked = op.linkedTxId != null || op.linkedTaxTxId != null;

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: colors.surfaceCard,
      title: Text(
        'Excluir Operação?',
        style: TextStyle(
          color: colors.textPrimary,
          fontWeight: FontWeight.w800,
        ),
      ),
      content: Text(
        'Tem certeza que deseja excluir ${op.type.label} de ${asset?.displayCode ?? "Ativo"} '
        'em ${fmtDate(op.date)} no valor de ${formatCurrency(op.totalCents, cur)}?'
        '${hasLinked ? "\n\nOs lançamentos vinculados no caixa da conta também serão removidos." : ""}',
        style: TextStyle(color: colors.textSecondary, fontSize: 13),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Cancelar'),
        ),
        ElevatedButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          style: ElevatedButton.styleFrom(
            backgroundColor: colors.expense,
            foregroundColor: Colors.white,
          ),
          child: const Text('Excluir'),
        ),
      ],
    ),
  );

  if (confirmed == true) {
    store.deleteInvestOperation(op.id);
    return true;
  }
  return false;
}
