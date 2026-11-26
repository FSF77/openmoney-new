import 'dart:math';

enum InvestAssetClass {
  stock,
  fii,
  etf,
  bdr,
  fixedIncome,
  tesouro,
  crypto,
  other;

  String get label {
    switch (this) {
      case InvestAssetClass.stock:
        return 'Ações';
      case InvestAssetClass.fii:
        return 'FIIs';
      case InvestAssetClass.etf:
        return 'ETFs';
      case InvestAssetClass.bdr:
        return 'BDRs';
      case InvestAssetClass.fixedIncome:
        return 'Renda Fixa';
      case InvestAssetClass.tesouro:
        return 'Tesouro Direto';
      case InvestAssetClass.crypto:
        return 'Criptomoedas';
      case InvestAssetClass.other:
        return 'Outros';
    }
  }

  String get shortLabel {
    switch (this) {
      case InvestAssetClass.stock:
        return 'Ação';
      case InvestAssetClass.fii:
        return 'FII';
      case InvestAssetClass.etf:
        return 'ETF';
      case InvestAssetClass.bdr:
        return 'BDR';
      case InvestAssetClass.fixedIncome:
        return 'RF';
      case InvestAssetClass.tesouro:
        return 'Tesouro';
      case InvestAssetClass.crypto:
        return 'Cripto';
      case InvestAssetClass.other:
        return 'Outro';
    }
  }

  bool get isVariableIncome =>
      this == stock ||
      this == fii ||
      this == etf ||
      this == bdr ||
      this == crypto;

  bool get isFixedIncome => this == fixedIncome || this == tesouro;

  int get maxQtyDecimals {
    switch (this) {
      case InvestAssetClass.crypto:
        return 8;
      case InvestAssetClass.tesouro:
      case InvestAssetClass.other:
        return 4;
      case InvestAssetClass.fixedIncome:
        return 2;
      case InvestAssetClass.stock:
      case InvestAssetClass.fii:
      case InvestAssetClass.etf:
      case InvestAssetClass.bdr:
        return 2;
    }
  }

  static InvestAssetClass fromString(String? raw) {
    final s = (raw ?? '').trim().toLowerCase();
    for (final v in InvestAssetClass.values) {
      if (v.name.toLowerCase() == s) return v;
    }
    if (s.contains('acao') || s.contains('ações') || s == 'stock') {
      return InvestAssetClass.stock;
    }
    if (s.contains('fii') || s.contains('imobili')) return InvestAssetClass.fii;
    if (s.contains('etf')) return InvestAssetClass.etf;
    if (s.contains('bdr')) return InvestAssetClass.bdr;
    if (s.contains('tesouro')) return InvestAssetClass.tesouro;
    if (s.contains('renda fixa') ||
        s.contains('cdb') ||
        s.contains('lci') ||
        s.contains('lca') ||
        s == 'rf') {
      return InvestAssetClass.fixedIncome;
    }
    if (s.contains('cripto') || s.contains('crypto')) {
      return InvestAssetClass.crypto;
    }
    return InvestAssetClass.other;
  }
}

enum InvestFixedIncomeIndexer {
  cdi,
  selic,
  ipca,
  prefixado,
  other;

  String get label {
    switch (this) {
      case InvestFixedIncomeIndexer.cdi:
        return '% do CDI';
      case InvestFixedIncomeIndexer.selic:
        return 'Selic +';
      case InvestFixedIncomeIndexer.ipca:
        return 'IPCA +';
      case InvestFixedIncomeIndexer.prefixado:
        return 'Prefixado';
      case InvestFixedIncomeIndexer.other:
        return 'Outro';
    }
  }

  static InvestFixedIncomeIndexer fromString(String? raw) {
    final s = (raw ?? '').trim().toLowerCase();
    for (final v in InvestFixedIncomeIndexer.values) {
      if (v.name.toLowerCase() == s) return v;
    }
    if (s.contains('cdi')) return InvestFixedIncomeIndexer.cdi;
    if (s.contains('selic')) return InvestFixedIncomeIndexer.selic;
    if (s.contains('ipca')) return InvestFixedIncomeIndexer.ipca;
    if (s.contains('pre')) return InvestFixedIncomeIndexer.prefixado;
    return InvestFixedIncomeIndexer.other;
  }
}

enum InvestOpType {
  buy,
  sell,
  dividend,
  jcp,
  fiiYield,
  amortization,
  split,
  inplit,
  bonus,
  initialPosition;

  String get label {
    switch (this) {
      case InvestOpType.buy:
        return 'Compra';
      case InvestOpType.sell:
        return 'Venda';
      case InvestOpType.dividend:
        return 'Dividendo';
      case InvestOpType.jcp:
        return 'JCP';
      case InvestOpType.fiiYield:
        return 'Rendimento';
      case InvestOpType.amortization:
        return 'Amortização';
      case InvestOpType.split:
        return 'Desdobramento';
      case InvestOpType.inplit:
        return 'Grupamento';
      case InvestOpType.bonus:
        return 'Bonificação';
      case InvestOpType.initialPosition:
        return 'Posição Inicial';
    }
  }

  bool get isCashOut => this == buy;

  bool get isCashIn =>
      this == sell ||
      this == dividend ||
      this == jcp ||
      this == fiiYield ||
      this == amortization;

  bool get isIncome =>
      this == dividend || this == jcp || this == fiiYield;

  static InvestOpType fromString(String? raw) {
    final s = (raw ?? '').trim().toLowerCase();
    for (final v in InvestOpType.values) {
      if (v.name.toLowerCase() == s) return v;
    }
    if (s.contains('compra')) return InvestOpType.buy;
    if (s.contains('venda')) return InvestOpType.sell;
    if (s.contains('dividendo')) return InvestOpType.dividend;
    if (s.contains('jcp')) return InvestOpType.jcp;
    if (s.contains('rendimento')) return InvestOpType.fiiYield;
    if (s.contains('amortiza')) return InvestOpType.amortization;
    if (s.contains('desdobramento') || s == 'split') return InvestOpType.split;
    if (s.contains('grupamento') || s == 'inplit') return InvestOpType.inplit;
    if (s.contains('bonifica')) return InvestOpType.bonus;
    if (s.contains('inicial')) return InvestOpType.initialPosition;
    return InvestOpType.buy;
  }
}

String _genInvestUid() {
  final ts = DateTime.now().microsecondsSinceEpoch.toRadixString(36);
  final r = Random().nextInt(0xFFFFFF).toRadixString(36);
  return 'inv_${ts}_$r';
}

/// Formata quantidade respeitando precisão do tipo de ativo (até 8 casas para cripto).
String formatInvestQty(double qty, InvestAssetClass cls) {
  final decimals = cls.maxQtyDecimals;
  if ((qty - qty.roundToDouble()).abs() < 1e-9) {
    return qty.round().toString();
  }
  final fixed = qty.toStringAsFixed(decimals);
  var trimmed = fixed.replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
  return trimmed.replaceAll('.', ',');
}

class InvestAsset {
  String id;
  String ticker;
  String name;
  InvestAssetClass assetClass;
  String? subType;
  String accountId;
  String currency;

  // Renda Fixa & Tesouro
  InvestFixedIncomeIndexer? indexer;
  double? ratePct;
  String? maturityDate; // YYYY-MM-DD
  String? liquidity; // 'daily' | 'maturity'
  bool taxExempt;

  // Cotação Atualizada (em centavos inteiros)
  int? currentPriceCents;
  String? priceUpdatedAt;
  bool manualPrice;
  String? priceSource;
  String? memo;
  bool inactive;

  InvestAsset({
    String? id,
    required this.ticker,
    required this.name,
    required this.assetClass,
    this.subType,
    required this.accountId,
    String? currency,
    this.indexer,
    this.ratePct,
    this.maturityDate,
    this.liquidity,
    this.taxExempt = false,
    this.currentPriceCents,
    this.priceUpdatedAt,
    this.manualPrice = false,
    this.priceSource,
    this.memo,
    this.inactive = false,
  }) : id = (id != null && id.trim().isNotEmpty) ? id.trim() : _genInvestUid(),
        currency = (currency != null && currency.trim().isNotEmpty)
            ? currency.trim().toUpperCase()
            : 'BRL';

  bool get isFixedIncome => assetClass.isFixedIncome;

  String get displayCode =>
      ticker.trim().isNotEmpty ? ticker.trim().toUpperCase() : name.trim();

  String get indexerSummary {
    if (!isFixedIncome || indexer == null) return '';
    final r = ratePct;
    switch (indexer!) {
      case InvestFixedIncomeIndexer.cdi:
        return '${r != null ? _fmtPctNum(r) : "100"}% CDI';
      case InvestFixedIncomeIndexer.selic:
        return r != null && r != 0 ? 'Selic + ${_fmtPctNum(r)}%' : 'Selic';
      case InvestFixedIncomeIndexer.ipca:
        return r != null ? 'IPCA + ${_fmtPctNum(r)}%' : 'IPCA';
      case InvestFixedIncomeIndexer.prefixado:
        return r != null ? '${_fmtPctNum(r)}% a.a.' : 'Prefixado';
      case InvestFixedIncomeIndexer.other:
        return subType ?? 'Renda Fixa';
    }
  }

  static String _fmtPctNum(double v) {
    if ((v - v.roundToDouble()).abs() < 1e-6) {
      return v.round().toString();
    }
    return v.toStringAsFixed(2).replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '').replaceAll('.', ',');
  }

  factory InvestAsset.fromJson(Map<String, dynamic> json) {
    final cls = InvestAssetClass.fromString(json['assetClass'] as String?);
    final rawSub = (json['subType'] as String?)?.trim();
    final rawTaxExempt = json['taxExempt'] as bool?;
    final autoExempt = rawSub != null &&
        (rawSub.toUpperCase().contains('LCI') ||
            rawSub.toUpperCase().contains('LCA') ||
            rawSub.toUpperCase().contains('CRI') ||
            rawSub.toUpperCase().contains('CRA'));
    return InvestAsset(
      id: json['id'] as String?,
      ticker: (json['ticker'] as String? ?? '').trim(),
      name: (json['name'] as String? ?? '').trim(),
      assetClass: cls,
      subType: (rawSub != null && rawSub.isNotEmpty) ? rawSub : null,
      accountId: json['accountId'] as String? ?? '',
      currency: json['currency'] as String? ?? 'BRL',
      indexer: json['indexer'] != null
          ? InvestFixedIncomeIndexer.fromString(json['indexer'] as String?)
          : null,
      ratePct: (json['ratePct'] as num?)?.toDouble(),
      maturityDate: (json['maturityDate'] as String?)?.trim().isNotEmpty == true
          ? (json['maturityDate'] as String).trim()
          : null,
      liquidity: (json['liquidity'] as String?)?.trim().isNotEmpty == true
          ? (json['liquidity'] as String).trim()
          : null,
      taxExempt: rawTaxExempt ?? autoExempt,
      currentPriceCents: (json['currentPriceCents'] as num?)?.toInt(),
      priceUpdatedAt: json['priceUpdatedAt'] as String?,
      manualPrice: json['manualPrice'] as bool? ?? false,
      priceSource: json['priceSource'] as String?,
      memo: json['memo'] as String?,
      inactive: json['inactive'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'ticker': ticker,
        'name': name,
        'assetClass': assetClass.name,
        if (subType != null && subType!.trim().isNotEmpty) 'subType': subType,
        'accountId': accountId,
        if (currency != 'BRL') 'currency': currency,
        if (indexer != null) 'indexer': indexer!.name,
        if (ratePct != null) 'ratePct': ratePct,
        if (maturityDate != null) 'maturityDate': maturityDate,
        if (liquidity != null) 'liquidity': liquidity,
        if (taxExempt) 'taxExempt': taxExempt,
        if (currentPriceCents != null) 'currentPriceCents': currentPriceCents,
        if (priceUpdatedAt != null) 'priceUpdatedAt': priceUpdatedAt,
        if (manualPrice) 'manualPrice': manualPrice,
        if (priceSource != null) 'priceSource': priceSource,
        if (memo != null && memo!.trim().isNotEmpty) 'memo': memo,
        if (inactive) 'inactive': inactive,
      };

  InvestAsset copyWith({
    String? id,
    String? ticker,
    String? name,
    InvestAssetClass? assetClass,
    String? subType,
    String? accountId,
    String? currency,
    InvestFixedIncomeIndexer? indexer,
    double? ratePct,
    String? maturityDate,
    String? liquidity,
    bool? taxExempt,
    int? currentPriceCents,
    bool clearCurrentPrice = false,
    String? priceUpdatedAt,
    bool? manualPrice,
    String? priceSource,
    String? memo,
    bool? inactive,
  }) {
    return InvestAsset(
      id: id ?? this.id,
      ticker: ticker ?? this.ticker,
      name: name ?? this.name,
      assetClass: assetClass ?? this.assetClass,
      subType: subType ?? this.subType,
      accountId: accountId ?? this.accountId,
      currency: currency ?? this.currency,
      indexer: indexer ?? this.indexer,
      ratePct: ratePct ?? this.ratePct,
      maturityDate: maturityDate ?? this.maturityDate,
      liquidity: liquidity ?? this.liquidity,
      taxExempt: taxExempt ?? this.taxExempt,
      currentPriceCents:
          clearCurrentPrice ? null : (currentPriceCents ?? this.currentPriceCents),
      priceUpdatedAt:
          clearCurrentPrice ? null : (priceUpdatedAt ?? this.priceUpdatedAt),
      manualPrice: manualPrice ?? this.manualPrice,
      priceSource:
          clearCurrentPrice ? null : (priceSource ?? this.priceSource),
      memo: memo ?? this.memo,
      inactive: inactive ?? this.inactive,
    );
  }
}

class InvestOperation {
  String id;
  String assetId;
  String accountId;
  InvestOpType type;
  String date; // YYYY-MM-DD
  double quantity;
  int unitPriceCents;
  int feesCents;
  int taxCents;
  int totalCents;
  String? linkedTxId;
  String? linkedTaxTxId;
  String memo;
  double createdAt;

  InvestOperation({
    String? id,
    required this.assetId,
    required this.accountId,
    required this.type,
    required this.date,
    required this.quantity,
    required this.unitPriceCents,
    this.feesCents = 0,
    this.taxCents = 0,
    int? totalCents,
    this.linkedTxId,
    this.linkedTaxTxId,
    this.memo = '',
    double? createdAt,
  })  : id = (id != null && id.trim().isNotEmpty) ? id.trim() : _genInvestUid(),
        totalCents = totalCents ??
            ((type == InvestOpType.buy || type == InvestOpType.initialPosition)
                ? ((quantity * unitPriceCents).round() + feesCents)
                : (type == InvestOpType.sell
                    ? max(0, (quantity * unitPriceCents).round() - feesCents)
                    : (quantity * unitPriceCents).round())),
        createdAt =
            createdAt ?? (DateTime.now().millisecondsSinceEpoch / 1000.0);

  factory InvestOperation.fromJson(Map<String, dynamic> json) {
    return InvestOperation(
      id: json['id'] as String?,
      assetId: json['assetId'] as String? ?? '',
      accountId: json['accountId'] as String? ?? '',
      type: InvestOpType.fromString(json['type'] as String?),
      date: json['date'] as String? ?? '',
      quantity: (json['quantity'] as num?)?.toDouble() ?? 0.0,
      unitPriceCents: (json['unitPriceCents'] as num?)?.toInt() ?? 0,
      feesCents: (json['feesCents'] as num?)?.toInt() ?? 0,
      taxCents: (json['taxCents'] as num?)?.toInt() ?? 0,
      totalCents: (json['totalCents'] as num?)?.toInt(),
      linkedTxId: json['linkedTxId'] as String?,
      linkedTaxTxId: json['linkedTaxTxId'] as String?,
      memo: json['memo'] as String? ?? '',
      createdAt: (json['createdAt'] as num?)?.toDouble(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'assetId': assetId,
        'accountId': accountId,
        'type': type.name,
        'date': date,
        'quantity': quantity,
        'unitPriceCents': unitPriceCents,
        if (feesCents != 0) 'feesCents': feesCents,
        if (taxCents != 0) 'taxCents': taxCents,
        'totalCents': totalCents,
        if (linkedTxId != null) 'linkedTxId': linkedTxId,
        if (linkedTaxTxId != null) 'linkedTaxTxId': linkedTaxTxId,
        if (memo.isNotEmpty) 'memo': memo,
        'createdAt': createdAt,
      };

  InvestOperation copyWith({
    String? id,
    String? assetId,
    String? accountId,
    InvestOpType? type,
    String? date,
    double? quantity,
    int? unitPriceCents,
    int? feesCents,
    int? taxCents,
    int? totalCents,
    String? linkedTxId,
    bool clearLinkedTx = false,
    String? linkedTaxTxId,
    bool clearLinkedTaxTx = false,
    String? memo,
    double? createdAt,
  }) {
    return InvestOperation(
      id: id ?? this.id,
      assetId: assetId ?? this.assetId,
      accountId: accountId ?? this.accountId,
      type: type ?? this.type,
      date: date ?? this.date,
      quantity: quantity ?? this.quantity,
      unitPriceCents: unitPriceCents ?? this.unitPriceCents,
      feesCents: feesCents ?? this.feesCents,
      taxCents: taxCents ?? this.taxCents,
      totalCents: totalCents ?? this.totalCents,
      linkedTxId: clearLinkedTx ? null : (linkedTxId ?? this.linkedTxId),
      linkedTaxTxId:
          clearLinkedTaxTx ? null : (linkedTaxTxId ?? this.linkedTaxTxId),
      memo: memo ?? this.memo,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}

class MarketIndicators {
  double cdiAnnual;
  double selicAnnual;
  double ipca12m;
  String updatedAt;
  bool manual;

  MarketIndicators({
    this.cdiAnnual = 11.15,
    this.selicAnnual = 11.25,
    this.ipca12m = 4.50,
    this.updatedAt = '',
    this.manual = false,
  });

  factory MarketIndicators.fromJson(Map<String, dynamic> json) {
    return MarketIndicators(
      cdiAnnual: (json['cdiAnnual'] as num?)?.toDouble() ?? 11.15,
      selicAnnual: (json['selicAnnual'] as num?)?.toDouble() ?? 11.25,
      ipca12m: (json['ipca12m'] as num?)?.toDouble() ?? 4.50,
      updatedAt: json['updatedAt'] as String? ?? '',
      manual: json['manual'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
        'cdiAnnual': cdiAnnual,
        'selicAnnual': selicAnnual,
        'ipca12m': ipca12m,
        'updatedAt': updatedAt,
        if (manual) 'manual': manual,
      };

  MarketIndicators copyWith({
    double? cdiAnnual,
    double? selicAnnual,
    double? ipca12m,
    String? updatedAt,
    bool? manual,
  }) {
    return MarketIndicators(
      cdiAnnual: cdiAnnual ?? this.cdiAnnual,
      selicAnnual: selicAnnual ?? this.selicAnnual,
      ipca12m: ipca12m ?? this.ipca12m,
      updatedAt: updatedAt ?? this.updatedAt,
      manual: manual ?? this.manual,
    );
  }
}
