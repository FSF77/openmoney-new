import 'dart:math';

const String kCardType = 'Cartão de crédito';
const String kCategorySep = ' › ';
const List<String> kAccountTypes = [
  'Corrente',
  'Poupança',
  'Cartão de crédito',
  'Investimento',
  'Dinheiro',
];

class CardConfig {
  int closeDay;
  int dueDay;
  String pay;

  CardConfig({
    required this.closeDay,
    required this.dueDay,
    required this.pay,
  });

  factory CardConfig.fromJson(Map<String, dynamic> json) {
    return CardConfig(
      closeDay: (json['closeDay'] as num?)?.toInt() ?? 1,
      dueDay: (json['dueDay'] as num?)?.toInt() ?? 10,
      pay: json['pay'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {
        'closeDay': closeDay,
        'dueDay': dueDay,
        'pay': pay,
      };

  CardConfig copyWith({int? closeDay, int? dueDay, String? pay}) {
    return CardConfig(
      closeDay: closeDay ?? this.closeDay,
      dueDay: dueDay ?? this.dueDay,
      pay: pay ?? this.pay,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CardConfig &&
          closeDay == other.closeDay &&
          dueDay == other.dueDay &&
          pay == other.pay;

  @override
  int get hashCode => Object.hash(closeDay, dueDay, pay);
}

class InvoiceInfo {
  String close;
  String due;
  String pay;
  bool? manual;

  InvoiceInfo({
    required this.close,
    required this.due,
    required this.pay,
    this.manual,
  });

  factory InvoiceInfo.fromJson(Map<String, dynamic> json) {
    return InvoiceInfo(
      close: json['close'] as String? ?? '',
      due: json['due'] as String? ?? '',
      pay: json['pay'] as String? ?? '',
      manual: json['manual'] as bool?,
    );
  }

  Map<String, dynamic> toJson() => {
        'close': close,
        'due': due,
        'pay': pay,
        if (manual != null) 'manual': manual,
      };

  InvoiceInfo copyWith({
    String? close,
    String? due,
    String? pay,
    bool? manual,
  }) {
    return InvoiceInfo(
      close: close ?? this.close,
      due: due ?? this.due,
      pay: pay ?? this.pay,
      manual: manual ?? this.manual,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is InvoiceInfo &&
          close == other.close &&
          due == other.due &&
          pay == other.pay &&
          manual == other.manual;

  @override
  int get hashCode => Object.hash(close, due, pay, manual);
}

class Account {
  String id;
  String name;
  String type;
  int opening;
  CardConfig? card;
  Map<String, InvoiceInfo>? invoices;
  bool? inactive;
  bool? favorite;

  Account({
    required this.id,
    required this.name,
    required this.type,
    required this.opening,
    this.card,
    this.invoices,
    this.inactive,
    this.favorite,
  });

  bool get isInactive => inactive == true;
  bool get isActive => !isInactive;
  bool get isFavorite => favorite == true;

  factory Account.fromJson(Map<String, dynamic> json) {
    Map<String, InvoiceInfo>? parsedInvoices;
    if (json['invoices'] is Map) {
      parsedInvoices = {};
      (json['invoices'] as Map).forEach((k, v) {
        if (v is Map<String, dynamic>) {
          parsedInvoices![k.toString()] = InvoiceInfo.fromJson(v);
        } else if (v is Map) {
          parsedInvoices![k.toString()] =
              InvoiceInfo.fromJson(Map<String, dynamic>.from(v));
        }
      });
    }

    CardConfig? parsedCard;
    if (json['card'] is Map<String, dynamic>) {
      parsedCard = CardConfig.fromJson(json['card'] as Map<String, dynamic>);
    } else if (json['card'] is Map) {
      parsedCard =
          CardConfig.fromJson(Map<String, dynamic>.from(json['card'] as Map));
    }

    return Account(
      id: json['id'] as String? ?? uid(),
      name: json['name'] as String? ?? 'Conta',
      type: json['type'] as String? ?? 'Corrente',
      opening: (json['opening'] as num?)?.toInt() ?? 0,
      card: parsedCard,
      invoices: parsedInvoices,
      inactive: json['inactive'] as bool?,
      favorite: json['favorite'] as bool?,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'type': type,
        'opening': opening,
        if (card != null) 'card': card!.toJson(),
        if (invoices != null)
          'invoices': invoices!.map((k, v) => MapEntry(k, v.toJson())),
        if (inactive != null) 'inactive': inactive,
        if (favorite != null) 'favorite': favorite,
      };

  Account copyWith({
    String? id,
    String? name,
    String? type,
    int? opening,
    CardConfig? card,
    Map<String, InvoiceInfo>? invoices,
    bool? inactive,
    bool? favorite,
  }) {
    return Account(
      id: id ?? this.id,
      name: name ?? this.name,
      type: type ?? this.type,
      opening: opening ?? this.opening,
      card: card ?? this.card?.copyWith(),
      invoices: invoices ??
          this.invoices?.map((k, v) => MapEntry(k, v.copyWith())),
      inactive: inactive ?? this.inactive,
      favorite: favorite ?? this.favorite,
    );
  }
}

class PayeeSuggestion {
  final String name;
  final String category;
  final bool isExpense;
  final int count;
  final String lastDate;

  String get id => name.toLowerCase();

  const PayeeSuggestion({
    required this.name,
    required this.category,
    required this.isExpense,
    this.count = 1,
    this.lastDate = '',
  });
}

class CategoryItem {
  String name;
  String? parent;
  String type;
  bool? includeInReports;

  CategoryItem({
    required this.name,
    String? parent,
    this.type = 'Despesa',
    this.includeInReports,
  }) : parent = (parent != null && parent.isEmpty) ? null : parent;

  String get id => path;

  String get path {
    if (parent != null && parent!.isNotEmpty) {
      return '$parent$kCategorySep$name';
    }
    return name;
  }

  bool get effectiveIncludeInReports {
    if (includeInReports != null) {
      return includeInReports!;
    }
    final norm = removeDiacritics(path).toLowerCase();
    if (norm.contains('transferencia') ||
        norm.contains('transferencias') ||
        isHiddenFromPlanning(path)) {
      return false;
    }
    return true;
  }

  factory CategoryItem.fromJson(dynamic json) {
    if (json is String) {
      final lower = json.toLowerCase();
      return CategoryItem(
        name: json,
        parent: null,
        type: (lower == 'salário' || lower == 'salario') ? 'Receita' : 'Despesa',
        includeInReports: null,
      );
    }
    if (json is Map) {
      final map = Map<String, dynamic>.from(json);
      final p = map['parent'] as String?;
      return CategoryItem(
        name: map['name'] as String? ?? '',
        parent: (p != null && p.isEmpty) ? null : p,
        type: map['type'] as String? ?? 'Despesa',
        includeInReports: map['includeInReports'] as bool?,
      );
    }
    return CategoryItem(name: 'Outros');
  }

  Map<String, dynamic> toJson() => {
        'name': name,
        if (parent != null) 'parent': parent,
        'type': type,
        if (includeInReports != null) 'includeInReports': includeInReports,
      };

  CategoryItem copyWith({
    String? name,
    String? parent,
    String? type,
    bool? includeInReports,
  }) {
    return CategoryItem(
      name: name ?? this.name,
      parent: parent ?? this.parent,
      type: type ?? this.type,
      includeInReports: includeInReports ?? this.includeInReports,
    );
  }
}

class Transaction {
  String id;
  String acc;
  String? peer;
  String date; // ISO "YYYY-MM-DD"
  String payee;
  String cat;
  String memo;
  int amt; // In cents (negative = expense, positive = income)
  bool rec;
  String? xfer;
  bool? auto;
  String? card;
  String? ik;
  String? inv;
  String? plan;
  int? pn;
  int? pt;
  String? recId;
  String? recFreq;
  int? recSeq;
  double? createdAt;

  Transaction({
    String? id,
    required this.acc,
    this.peer,
    required this.date,
    required this.payee,
    required this.cat,
    this.memo = '',
    required this.amt,
    this.rec = false,
    this.xfer,
    this.auto,
    this.card,
    this.ik,
    this.inv,
    this.plan,
    this.pn,
    this.pt,
    this.recId,
    this.recFreq,
    this.recSeq,
    double? createdAt,
  })  : id = id ?? uid(),
        createdAt =
            createdAt ?? (DateTime.now().millisecondsSinceEpoch / 1000.0);

  factory Transaction.fromJson(Map<String, dynamic> json) {
    final dateStr = json['date'] as String? ?? todayISO();
    final autoVal = json['auto'] as bool?;
    final recVal = json['rec'] as bool? ??
        (!(autoVal ?? false) && dateStr.compareTo(todayISO()) <= 0);

    return Transaction(
      id: json['id'] as String? ?? uid(),
      acc: json['acc'] as String? ?? '',
      peer: json['peer'] as String?,
      date: dateStr,
      payee: json['payee'] as String? ?? '',
      cat: json['cat'] as String? ?? '',
      memo: json['memo'] as String? ?? '',
      amt: (json['amt'] as num?)?.toInt() ?? 0,
      rec: recVal,
      xfer: json['xfer'] as String?,
      auto: autoVal,
      card: json['card'] as String?,
      ik: json['ik'] as String?,
      inv: json['inv'] as String?,
      plan: json['plan'] as String?,
      pn: (json['pn'] as num?)?.toInt(),
      pt: (json['pt'] as num?)?.toInt(),
      recId: json['recId'] as String?,
      recFreq: json['recFreq'] as String?,
      recSeq: (json['recSeq'] as num?)?.toInt(),
      createdAt: (json['createdAt'] as num?)?.toDouble(),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'acc': acc,
        if (peer != null) 'peer': peer,
        'date': date,
        'payee': payee,
        'cat': cat,
        'memo': memo,
        'amt': amt,
        'rec': rec,
        if (xfer != null) 'xfer': xfer,
        if (auto != null) 'auto': auto,
        if (card != null) 'card': card,
        if (ik != null) 'ik': ik,
        if (inv != null) 'inv': inv,
        if (plan != null) 'plan': plan,
        if (pn != null) 'pn': pn,
        if (pt != null) 'pt': pt,
        if (recId != null) 'recId': recId,
        if (recFreq != null) 'recFreq': recFreq,
        if (recSeq != null) 'recSeq': recSeq,
        if (createdAt != null) 'createdAt': createdAt,
      };

  Transaction copyWith({
    String? id,
    String? acc,
    String? peer,
    String? date,
    String? payee,
    String? cat,
    String? memo,
    int? amt,
    bool? rec,
    String? xfer,
    bool? auto,
    String? card,
    String? ik,
    String? inv,
    String? plan,
    int? pn,
    int? pt,
    String? recId,
    String? recFreq,
    int? recSeq,
    double? createdAt,
  }) {
    return Transaction(
      id: id ?? this.id,
      acc: acc ?? this.acc,
      peer: peer ?? this.peer,
      date: date ?? this.date,
      payee: payee ?? this.payee,
      cat: cat ?? this.cat,
      memo: memo ?? this.memo,
      amt: amt ?? this.amt,
      rec: rec ?? this.rec,
      xfer: xfer ?? this.xfer,
      auto: auto ?? this.auto,
      card: card ?? this.card,
      ik: ik ?? this.ik,
      inv: inv ?? this.inv,
      plan: plan ?? this.plan,
      pn: pn ?? this.pn,
      pt: pt ?? this.pt,
      recId: recId ?? this.recId,
      recFreq: recFreq ?? this.recFreq,
      recSeq: recSeq ?? this.recSeq,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}

class RecurrenceRule {
  String id;
  String acc;
  String? peer;
  String start;
  String freq; // "daily", "weekly", "biweekly", "monthly", "bimonthly", "quarterly", "semiannual", "yearly"
  String payee;
  String cat;
  String memo;
  int amt;
  int nextSeq;
  String? end;

  RecurrenceRule({
    required this.id,
    required this.acc,
    this.peer,
    required this.start,
    required this.freq,
    required this.payee,
    required this.cat,
    required this.memo,
    required this.amt,
    this.nextSeq = 1,
    this.end,
  });

  factory RecurrenceRule.fromJson(Map<String, dynamic> json) {
    return RecurrenceRule(
      id: json['id'] as String? ?? uid(),
      acc: json['acc'] as String? ?? '',
      peer: json['peer'] as String?,
      start: json['start'] as String? ?? todayISO(),
      freq: json['freq'] as String? ?? 'monthly',
      payee: json['payee'] as String? ?? '',
      cat: json['cat'] as String? ?? '',
      memo: json['memo'] as String? ?? '',
      amt: (json['amt'] as num?)?.toInt() ?? 0,
      nextSeq: (json['nextSeq'] as num?)?.toInt() ?? 1,
      end: json['end'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'acc': acc,
        if (peer != null) 'peer': peer,
        'start': start,
        'freq': freq,
        'payee': payee,
        'cat': cat,
        'memo': memo,
        'amt': amt,
        'nextSeq': nextSeq,
        if (end != null) 'end': end,
      };

  RecurrenceRule copyWith({
    String? id,
    String? acc,
    String? peer,
    String? start,
    String? freq,
    String? payee,
    String? cat,
    String? memo,
    int? amt,
    int? nextSeq,
    String? end,
  }) {
    return RecurrenceRule(
      id: id ?? this.id,
      acc: acc ?? this.acc,
      peer: peer ?? this.peer,
      start: start ?? this.start,
      freq: freq ?? this.freq,
      payee: payee ?? this.payee,
      cat: cat ?? this.cat,
      memo: memo ?? this.memo,
      amt: amt ?? this.amt,
      nextSeq: nextSeq ?? this.nextSeq,
      end: end ?? this.end,
    );
  }
}

class Database {
  List<Account> accounts;
  List<CategoryItem> cats;
  List<Transaction> txs;
  List<RecurrenceRule> recs;
  Map<String, int> budgets;
  int v;

  Database({
    List<Account>? accounts,
    List<CategoryItem>? cats,
    List<Transaction>? txs,
    List<RecurrenceRule>? recs,
    Map<String, int>? budgets,
    this.v = 6,
  })  : accounts = accounts ??
            [
              Account(
                id: 'a1',
                name: 'Conta Corrente',
                type: 'Corrente',
                opening: 0,
              )
            ],
        cats = cats ?? List<CategoryItem>.from(kDefaultCats),
        txs = txs ?? [],
        recs = recs ?? [],
        budgets = budgets ?? {};

  factory Database.fromJson(Map<String, dynamic> json) {
    List<Account>? parsedAccounts;
    if (json['accounts'] is List) {
      parsedAccounts = (json['accounts'] as List)
          .whereType<Map>()
          .map((m) => Account.fromJson(Map<String, dynamic>.from(m)))
          .toList();
    }

    List<CategoryItem>? parsedCats;
    if (json['cats'] is List) {
      parsedCats =
          (json['cats'] as List).map((c) => CategoryItem.fromJson(c)).toList();
    }

    List<Transaction>? parsedTxs;
    if (json['txs'] is List) {
      parsedTxs = (json['txs'] as List)
          .whereType<Map>()
          .map((m) => Transaction.fromJson(Map<String, dynamic>.from(m)))
          .toList();
    }

    List<RecurrenceRule>? parsedRecs;
    if (json['recs'] is List) {
      parsedRecs = (json['recs'] as List)
          .whereType<Map>()
          .map((m) => RecurrenceRule.fromJson(Map<String, dynamic>.from(m)))
          .toList();
    }

    Map<String, int> parsedBudgets = {};
    if (json['budgets'] is Map) {
      (json['budgets'] as Map).forEach((k, v) {
        if (v is num) {
          parsedBudgets[k.toString()] = v.toInt();
        }
      });
    }

    return Database(
      accounts: (parsedAccounts != null && parsedAccounts.isNotEmpty)
          ? parsedAccounts
          : [
              Account(
                id: 'a1',
                name: 'Conta Corrente',
                type: 'Corrente',
                opening: 0,
              )
            ],
      cats: parsedCats ?? List<CategoryItem>.from(kDefaultCats),
      txs: parsedTxs ?? [],
      recs: parsedRecs ?? [],
      budgets: parsedBudgets,
      v: (json['v'] as num?)?.toInt() ?? 6,
    );
  }

  Map<String, dynamic> toJson() => {
        'accounts': accounts.map((a) => a.toJson()).toList(),
        'cats': cats.map((c) => c.toJson()).toList(),
        'txs': txs.map((t) => t.toJson()).toList(),
        'recs': recs.map((r) => r.toJson()).toList(),
        'budgets': budgets,
        'v': v,
      };
}

final List<CategoryItem> kDefaultCats = [
  CategoryItem(name: 'Alimentação', parent: null, type: 'Despesa'),
  CategoryItem(
      name: 'Bares e Restaurantes', parent: 'Alimentação', type: 'Despesa'),
  CategoryItem(name: 'Mercado', parent: 'Alimentação', type: 'Despesa'),
  CategoryItem(name: 'Assinaturas e Serviços', parent: null, type: 'Despesa'),
  CategoryItem(
      name: 'Apple', parent: 'Assinaturas e Serviços', type: 'Despesa'),
  CategoryItem(
      name: 'Games', parent: 'Assinaturas e Serviços', type: 'Despesa'),
  CategoryItem(
      name: 'Google', parent: 'Assinaturas e Serviços', type: 'Despesa'),
  CategoryItem(name: 'IA', parent: 'Assinaturas e Serviços', type: 'Despesa'),
  CategoryItem(
      name: 'Microsoft', parent: 'Assinaturas e Serviços', type: 'Despesa'),
  CategoryItem(
      name: 'Nintendo', parent: 'Assinaturas e Serviços', type: 'Despesa'),
  CategoryItem(
      name: 'Sites e Domínios',
      parent: 'Assinaturas e Serviços',
      type: 'Despesa'),
  CategoryItem(
      name: 'Streaming', parent: 'Assinaturas e Serviços', type: 'Despesa'),
  CategoryItem(name: 'Casa', parent: null, type: 'Despesa'),
  CategoryItem(name: 'Água, Esgoto', parent: 'Casa', type: 'Despesa'),
  CategoryItem(name: 'Condomínio', parent: 'Casa', type: 'Despesa'),
  CategoryItem(name: 'Despesas da casa', parent: 'Casa', type: 'Despesa'),
  CategoryItem(name: 'Eletricidade', parent: 'Casa', type: 'Despesa'),
  CategoryItem(name: 'Gás', parent: 'Casa', type: 'Despesa'),
  CategoryItem(name: 'Internet', parent: 'Casa', type: 'Despesa'),
  CategoryItem(name: 'IPTU', parent: 'Casa', type: 'Despesa'),
  CategoryItem(name: 'Telefonia', parent: 'Casa', type: 'Despesa'),
  CategoryItem(name: 'TV', parent: 'Casa', type: 'Despesa'),
  CategoryItem(name: 'Compras', parent: null, type: 'Despesa'),
  CategoryItem(name: 'Automóveis', parent: 'Compras', type: 'Despesa'),
  CategoryItem(name: 'Eletrodomésticos', parent: 'Compras', type: 'Despesa'),
  CategoryItem(
      name: 'Eletrônicos e Informática', parent: 'Compras', type: 'Despesa'),
  CategoryItem(name: 'Móveis', parent: 'Compras', type: 'Despesa'),
  CategoryItem(name: 'Músicas & Filmes', parent: 'Compras', type: 'Despesa'),
  CategoryItem(name: 'Softwares', parent: 'Compras', type: 'Despesa'),
  CategoryItem(name: 'Videogames', parent: 'Compras', type: 'Despesa'),
  CategoryItem(name: 'Cuidados pessoais', parent: null, type: 'Despesa'),
  CategoryItem(name: 'Educação', parent: null, type: 'Despesa'),
  CategoryItem(name: 'Família', parent: null, type: 'Despesa'),
  CategoryItem(name: 'Festas', parent: null, type: 'Despesa'),
  CategoryItem(name: 'Impostos e Taxas', parent: null, type: 'Despesa'),
  CategoryItem(name: 'IRRF', parent: 'Impostos e Taxas', type: 'Despesa'),
  CategoryItem(
      name: 'Simples Nacional', parent: 'Impostos e Taxas', type: 'Despesa'),
  CategoryItem(
      name: 'Taxas bancárias', parent: 'Impostos e Taxas', type: 'Despesa'),
  CategoryItem(name: 'Investimentos (D)', parent: null, type: 'Despesa'),
  CategoryItem(name: 'Lazer e hobbies', parent: null, type: 'Despesa'),
  CategoryItem(name: 'Academia', parent: 'Lazer e hobbies', type: 'Despesa'),
  CategoryItem(
      name: 'Cinema, Teatro', parent: 'Lazer e hobbies', type: 'Despesa'),
  CategoryItem(name: 'Diversão', parent: 'Lazer e hobbies', type: 'Despesa'),
  CategoryItem(name: 'Saúde', parent: null, type: 'Despesa'),
  CategoryItem(name: 'Medicamentos', parent: 'Saúde', type: 'Despesa'),
  CategoryItem(name: 'Médicos', parent: 'Saúde', type: 'Despesa'),
  CategoryItem(name: 'Plano de saúde', parent: 'Saúde', type: 'Despesa'),
  CategoryItem(name: 'Seguro de Vida', parent: 'Saúde', type: 'Despesa'),
  CategoryItem(name: 'Terapeutas', parent: 'Saúde', type: 'Despesa'),
  CategoryItem(name: 'Transporte', parent: null, type: 'Despesa'),
  CategoryItem(name: 'Combustível', parent: 'Transporte', type: 'Despesa'),
  CategoryItem(name: 'Documentação', parent: 'Transporte', type: 'Despesa'),
  CategoryItem(
      name: 'Estacionamento, Pedágio', parent: 'Transporte', type: 'Despesa'),
  CategoryItem(
      name: 'Manutenção, Serviços', parent: 'Transporte', type: 'Despesa'),
  CategoryItem(
      name: 'Metro, Ônibus, Taxi', parent: 'Transporte', type: 'Despesa'),
  CategoryItem(name: 'Multas', parent: 'Transporte', type: 'Despesa'),
  CategoryItem(name: 'Seguro Auto', parent: 'Transporte', type: 'Despesa'),
  CategoryItem(name: 'Viagem', parent: null, type: 'Despesa'),
  CategoryItem(name: 'ZZZ (D)', parent: null, type: 'Despesa'),
  CategoryItem(name: 'Cashback', parent: null, type: 'Receita'),
  CategoryItem(name: 'Investimentos (C)', parent: null, type: 'Receita'),
  CategoryItem(name: 'Renda', parent: null, type: 'Receita'),
  CategoryItem(
      name: 'Distribuição de Lucros', parent: 'Renda', type: 'Receita'),
  CategoryItem(name: 'Pró-labore', parent: 'Renda', type: 'Receita'),
  CategoryItem(name: 'Outras Rendas', parent: null, type: 'Receita'),
  CategoryItem(name: 'Benefícios', parent: 'Outras Rendas', type: 'Receita'),
  CategoryItem(
      name: 'Devolução de impostos', parent: 'Outras Rendas', type: 'Receita'),
  CategoryItem(
      name: 'Prestação de Serviços', parent: 'Outras Rendas', type: 'Receita'),
  CategoryItem(name: 'Reembolso', parent: 'Outras Rendas', type: 'Receita'),
  CategoryItem(name: 'Rendimentos', parent: null, type: 'Receita'),
  CategoryItem(name: 'Vendas', parent: null, type: 'Receita'),
  CategoryItem(name: 'Automóveis', parent: 'Vendas', type: 'Receita'),
  CategoryItem(name: 'Eletrodomésticos', parent: 'Vendas', type: 'Receita'),
  CategoryItem(
      name: 'Eletrônicos e Informática', parent: 'Vendas', type: 'Receita'),
  CategoryItem(name: 'Móveis', parent: 'Vendas', type: 'Receita'),
  CategoryItem(name: 'ZZZ (C)', parent: null, type: 'Receita'),
];

// MARK: - Auxiliary Models

enum PredictionAdjustStatus {
  adjusted,
  exhausted,
  unchanged;

  String get label {
    switch (this) {
      case PredictionAdjustStatus.adjusted:
        return 'Ajustada';
      case PredictionAdjustStatus.exhausted:
        return 'Esgotada';
      case PredictionAdjustStatus.unchanged:
        return 'Mantida';
    }
  }
}

class PredictionAdjustItem {
  final String payee;
  final String accountName;
  final String category;
  final int baseCents;
  final int spentCents;
  final int remainingCents;
  final PredictionAdjustStatus status;

  const PredictionAdjustItem({
    required this.payee,
    required this.accountName,
    required this.category,
    required this.baseCents,
    required this.spentCents,
    required this.remainingCents,
    required this.status,
  });
}

class PredictionsAdjustResult {
  final String title;
  final String message;
  final bool hasExhausted;
  final List<PredictionAdjustItem> items;
  final String month;
  final int totalDeductedCents;

  const PredictionsAdjustResult({
    required this.title,
    this.message = '',
    this.hasExhausted = false,
    this.items = const [],
    this.month = '',
    this.totalDeductedCents = 0,
  });
}

class RecentFileItem {
  final String path;
  final DateTime lastOpened;

  const RecentFileItem({
    required this.path,
    required this.lastOpened,
  });

  String get displayName {
    final normalized = path.replaceAll('\\', '/');
    final parts = normalized.split('/');
    return parts.isNotEmpty ? parts.last : path;
  }

  factory RecentFileItem.fromJson(Map<String, dynamic> json) {
    return RecentFileItem(
      path: json['path'] as String? ?? '',
      lastOpened: DateTime.tryParse(json['lastOpened'] as String? ?? '') ??
          DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
        'path': path,
        'lastOpened': lastOpened.toIso8601String(),
      };
}

class InvoiceSummary {
  final String key;
  final String closeDate;
  final String dueDate;
  final String payAccountId;
  final String payAccountName;
  final int chargesCents;
  final int paymentsCents;
  final int remainingCents;
  final bool isFullyPaid;

  const InvoiceSummary({
    required this.key,
    required this.closeDate,
    required this.dueDate,
    required this.payAccountId,
    required this.payAccountName,
    required this.chargesCents,
    required this.paymentsCents,
    required this.remainingCents,
    required this.isFullyPaid,
  });
}

class DueBillItem {
  final Transaction tx;
  final String accountName;
  final int daysUntilDue; // < 0: overdue, 0: today, > 0: upcoming
  final String? dueDate;

  const DueBillItem({
    required this.tx,
    required this.accountName,
    required this.daysUntilDue,
    this.dueDate,
  });

  String get id => tx.id;
  String get effectiveDueDate => dueDate ?? tx.date;
  bool get isOverdue => daysUntilDue < 0;
  bool get isDueToday => daysUntilDue == 0;
  bool get isPayable => tx.amt < 0;
  bool get isReceivable => tx.amt > 0;

  String get statusDescription {
    if (daysUntilDue < 0) {
      final absDays = daysUntilDue.abs();
      return absDays == 1 ? 'Atrasado há 1 dia' : 'Atrasado há $absDays dias';
    } else if (daysUntilDue == 0) {
      return 'Vence Hoje';
    } else if (daysUntilDue == 1) {
      return 'Vence Amanhã';
    } else {
      return 'Vence em $daysUntilDue dias';
    }
  }
}

class SubCategoryStat {
  final String name;
  final int amount;
  final int percentage;

  const SubCategoryStat({
    required this.name,
    required this.amount,
    required this.percentage,
  });
}

class CategoryGroupStat {
  final String name;
  final int total;
  final int percentage;
  final List<SubCategoryStat> subs;

  const CategoryGroupStat({
    required this.name,
    required this.total,
    required this.percentage,
    required this.subs,
  });
}

class MonthlyReportData {
  final String monthYM;
  final List<CategoryGroupStat> incomeGroups;
  final List<CategoryGroupStat> expenseGroups;
  final int totalIncome;
  final int totalExpense;
  final int netTotal;
  final int savingsRate;

  const MonthlyReportData({
    required this.monthYM,
    required this.incomeGroups,
    required this.expenseGroups,
    required this.totalIncome,
    required this.totalExpense,
    required this.netTotal,
    required this.savingsRate,
  });
}

class RecurrenceFrequencyOption {
  final String id;
  final String label;
  const RecurrenceFrequencyOption(this.id, this.label);
}

const List<RecurrenceFrequencyOption> kRecurrenceFrequencyOptions = [
  RecurrenceFrequencyOption('daily', 'Diário'),
  RecurrenceFrequencyOption('weekly', 'Semanal'),
  RecurrenceFrequencyOption('biweekly', 'Quinzenal'),
  RecurrenceFrequencyOption('monthly', 'Mensal'),
  RecurrenceFrequencyOption('bimonthly', 'Bimestral'),
  RecurrenceFrequencyOption('quarterly', 'Trimestral'),
  RecurrenceFrequencyOption('semiannual', 'Semestral'),
  RecurrenceFrequencyOption('yearly', 'Anual'),
];

String recurrenceFrequencyLabel(String? freq) {
  switch (freq) {
    case 'daily':
    case 'diario':
    case 'diário':
      return 'Diário';
    case 'weekly':
    case 'semanal':
      return 'Semanal';
    case 'biweekly':
    case 'quinzenal':
      return 'Quinzenal';
    case 'monthly':
    case 'mensal':
      return 'Mensal';
    case 'bimonthly':
    case 'bimestral':
      return 'Bimestral';
    case 'quarterly':
    case 'trimestral':
      return 'Trimestral';
    case 'semiannual':
    case 'semestral':
      return 'Semestral';
    case 'yearly':
    case 'anual':
      return 'Anual';
    default:
      return 'Mensal';
  }
}

// MARK: - Formatting, Dates & Pure Business Functions

final Random _rng = Random();
const String _uidChars = '0123456789abcdefghijklmnopqrstuvwxyz';

String uid() {
  return String.fromCharCodes(
    Iterable.generate(
      7,
      (_) => _uidChars.codeUnitAt(_rng.nextInt(_uidChars.length)),
    ),
  );
}

String pad2(int n) => n.toString().padLeft(2, '0');

String todayISO() {
  final now = DateTime.now();
  return '${now.year.toString().padLeft(4, '0')}-${pad2(now.month)}-${pad2(now.day)}';
}

DateTime dateFromISO(String s) {
  final parts = s.split('-');
  if (parts.length == 3) {
    final y = int.tryParse(parts[0]) ?? DateTime.now().year;
    final m = int.tryParse(parts[1]) ?? 1;
    final d = int.tryParse(parts[2]) ?? 1;
    return DateTime(y, m, d);
  }
  return DateTime.now();
}

String isoFromDate(DateTime d) {
  return '${d.year.toString().padLeft(4, '0')}-${pad2(d.month)}-${pad2(d.day)}';
}

int daysBetween(String fromISO, String toISO) {
  final d1 = dateFromISO(fromISO);
  final d2 = dateFromISO(toISO);
  final utc1 = DateTime.utc(d1.year, d1.month, d1.day);
  final utc2 = DateTime.utc(d2.year, d2.month, d2.day);
  return utc2.difference(utc1).inDays;
}

String brl(int cents) {
  final isNegative = cents < 0;
  final absCents = cents.abs();
  final intPart = absCents ~/ 100;
  final decPart = (absCents % 100).toString().padLeft(2, '0');

  final intStr = intPart.toString();
  final buffer = StringBuffer();
  for (int i = 0; i < intStr.length; i++) {
    if (i > 0 && (intStr.length - i) % 3 == 0) {
      buffer.write('.');
    }
    buffer.write(intStr[i]);
  }
  final formatted = 'R\$ ${buffer.toString()},$decPart';
  return isNegative ? '-$formatted' : formatted;
}

String formatInputCents(int cents) {
  final absCents = cents.abs();
  final intPart = absCents ~/ 100;
  final decPart = (absCents % 100).toString().padLeft(2, '0');
  return '$intPart,$decPart';
}

int? parseCents(String s) {
  final trimmed = s.trim();
  if (trimmed.isEmpty) return null;
  String normalized;
  if (trimmed.contains(',')) {
    normalized = trimmed.replaceAll('.', '').replaceAll(',', '.');
  } else {
    normalized = trimmed;
  }
  normalized = normalized.replaceAll(RegExp(r'[^0-9.\-]'), '');
  final val = double.tryParse(normalized);
  if (val == null || val.isNaN) return null;
  return (val * 100.0).round();
}

String fmtDate(String iso) {
  final parts = iso.split('-');
  if (parts.length != 3) return iso;
  return '${parts[2]}/${parts[1]}/${parts[0]}';
}

const List<String> _ptMonthsFull = [
  'janeiro',
  'fevereiro',
  'março',
  'abril',
  'maio',
  'junho',
  'julho',
  'agosto',
  'setembro',
  'outubro',
  'novembro',
  'dezembro',
];

const List<String> _ptWeekdaysShort = [
  'seg',
  'ter',
  'qua',
  'qui',
  'sex',
  'sáb',
  'dom',
];

String fmtMonth(String ym) {
  final parts = ym.split('-');
  if (parts.length < 2) return ym;
  final y = int.tryParse(parts[0]);
  final m = int.tryParse(parts[1]);
  if (y == null || m == null || m < 1 || m > 12) return ym;
  final mName = _ptMonthsFull[m - 1];
  return '${mName[0].toUpperCase()}${mName.substring(1)} de $y';
}

String formatInvoiceKeyForDisplay(String ik) {
  final clean = ik.trim();
  final parts = clean.split('-');
  if (parts.length == 2) {
    final y = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (y != null && m != null) {
      return '${pad2(m)}/${y.toString().padLeft(4, '0')}';
    }
  }
  return clean;
}

String weekdayShort(String iso) {
  final d = dateFromISO(iso);
  return _ptWeekdaysShort[d.weekday - 1];
}

String removeDiacritics(String str) {
  const withDia =
      'ÀÁÂÃÄÅàáâãäåÒÓÔÕÕÖØòóôõöøÈÉÊËèéêëðÇçÐÌÍÎÏìíîïÙÚÛÜùúûüÑñŠšŸÿýŽž';
  const withoutDia =
      'AAAAAAaaaaaaOOOOOOOooooooEEEEeeeeeCcDIIIIiiiiUUUUuuuuNnSsYyyZz';
  var result = str;
  for (int i = 0; i < withDia.length; i++) {
    result = result.replaceAll(withDia[i], withoutDia[i]);
  }
  return result;
}

int cmpPt(String a, String b) {
  final na = removeDiacritics(a).toLowerCase();
  final nb = removeDiacritics(b).toLowerCase();
  return na.compareTo(nb);
}

int cmpPath(String a, String b) {
  final pa = a.split(kCategorySep);
  final pb = b.split(kCategorySep);
  final topCmp = cmpPt(pa[0], pb[0]);
  if (topCmp != 0) return topCmp;
  final sa = pa.length > 1 ? pa[1] : '';
  final sb = pb.length > 1 ? pb[1] : '';
  return cmpPt(sa, sb);
}

int byCatSort(CategoryItem a, CategoryItem b) {
  final tc = cmpPt(a.type, b.type);
  if (tc != 0) return tc;
  return cmpPath(a.path, b.path);
}

bool isHiddenFromPlanning(String catPath) {
  final parts = catPath.split(kCategorySep);
  for (final part in parts) {
    final norm = part.trim().toUpperCase();
    if (norm == 'ZZZ (D)' ||
        norm == 'ZZZ (C)' ||
        norm == 'ZZZ(D)' ||
        norm == 'ZZZ(C)') {
      return true;
    }
  }
  return false;
}

bool isPredictionPayee(String payee) {
  final norm = removeDiacritics(payee).trim().toLowerCase();
  return norm.startsWith('previsao');
}

int? parseBaseFromMemo(String memo) {
  final regex = RegExp(
    r'\[(?:Previsão base|Previsao base|Base):\s*(?:R\$\s*)?([0-9.,]+)\]',
    caseSensitive: false,
  );
  final match = regex.firstMatch(memo);
  if (match == null) return null;
  final raw = match.group(1);
  if (raw == null) return null;
  return parseCents(raw);
}

String memoWithBaseTag(String memo, int baseCents) {
  final cleanVal = brl(baseCents).replaceAll('\u00A0', ' ');
  final tag = '[Previsão base: $cleanVal]';
  final regex = RegExp(
    r'\s*\[(?:Previsão base|Previsao base|Base):[^\]]+\]',
    caseSensitive: false,
  );
  final stripped = memo.replaceAll(regex, '').trim();
  return stripped.isEmpty ? tag : '$tag $stripped';
}

int daysInMonth(int year, int month) {
  return DateTime(year, month + 1, 0).day;
}

String dayIn(int year, int month, int day) {
  final maxDay = daysInMonth(year, month);
  return pad2(day < maxDay ? day : maxDay);
}

String addMonthsYM(String key, int n) {
  final parts = key.split('-');
  if (parts.length < 2) return key;
  int y = int.tryParse(parts[0]) ?? DateTime.now().year;
  int m = (int.tryParse(parts[1]) ?? 1) + n - 1;
  y += (m / 12).floor();
  m = ((m % 12) + 12) % 12 + 1;
  return '${y.toString().padLeft(4, '0')}-${pad2(m)}';
}

String addDaysDate(String iso, int n) {
  final d = dateFromISO(iso);
  final next = DateTime(d.year, d.month, d.day + n);
  return isoFromDate(next);
}

String addMonthsDate(String iso, int n) {
  final parts = iso.split('-');
  if (parts.length != 3) return iso;
  final y = int.tryParse(parts[0]) ?? DateTime.now().year;
  final m = int.tryParse(parts[1]) ?? 1;
  final d = int.tryParse(parts[2]) ?? 1;
  final ym = addMonthsYM('${y.toString().padLeft(4, '0')}-${pad2(m)}', n);
  final ymParts = ym.split('-');
  final ny = int.tryParse(ymParts[0]) ?? y;
  final nm = int.tryParse(ymParts[1]) ?? m;
  return '$ym-${dayIn(ny, nm, d)}';
}

String addYearsDate(String iso, int n) {
  final parts = iso.split('-');
  if (parts.length != 3) return iso;
  final y = int.tryParse(parts[0]) ?? DateTime.now().year;
  final m = int.tryParse(parts[1]) ?? 1;
  final d = int.tryParse(parts[2]) ?? 1;
  final ny = y + n;
  return '${ny.toString().padLeft(4, '0')}-${pad2(m)}-${dayIn(ny, m, d)}';
}

String addFreqDate(String iso, String freq, int n) {
  switch (freq) {
    case 'daily':
    case 'diario':
    case 'diário':
      return addDaysDate(iso, n);
    case 'weekly':
    case 'semanal':
      return addDaysDate(iso, n * 7);
    case 'biweekly':
    case 'quinzenal':
      return addDaysDate(iso, n * 15);
    case 'monthly':
    case 'mensal':
      return addMonthsDate(iso, n);
    case 'bimonthly':
    case 'bimestral':
      return addMonthsDate(iso, n * 2);
    case 'quarterly':
    case 'trimestral':
      return addMonthsDate(iso, n * 3);
    case 'semiannual':
    case 'semestral':
      return addMonthsDate(iso, n * 6);
    case 'yearly':
    case 'anual':
      return addYearsDate(iso, n);
    default:
      return addMonthsDate(iso, n);
  }
}

String invKeyFor(CardConfig card, String date) {
  final parts = date.split('-');
  if (parts.length != 3) {
    return date.length >= 7 ? date.substring(0, 7) : date;
  }
  final y = int.tryParse(parts[0]) ?? DateTime.now().year;
  final m = int.tryParse(parts[1]) ?? 1;
  final d = int.tryParse(parts[2]) ?? 1;
  final k = '${y.toString().padLeft(4, '0')}-${pad2(m)}';
  final closeMonth = d > card.closeDay ? addMonthsYM(k, 1) : k;
  return card.dueDay <= card.closeDay ? addMonthsYM(closeMonth, 1) : closeMonth;
}

({String close, String due}) invDates(CardConfig card, String key) {
  final parts = key.split('-');
  if (parts.length != 2) {
    return (close: '$key-01', due: '$key-10');
  }
  final y = int.tryParse(parts[0]) ?? DateTime.now().year;
  final m = int.tryParse(parts[1]) ?? 1;
  final closeKey = card.dueDay <= card.closeDay ? addMonthsYM(key, -1) : key;
  final cParts = closeKey.split('-');
  final cy = int.tryParse(cParts[0]) ?? y;
  final cm = int.tryParse(cParts[1]) ?? m;
  return (
    close: '$closeKey-${dayIn(cy, cm, card.closeDay)}',
    due: '$key-${dayIn(y, m, card.dueDay)}',
  );
}

List<({String key, String label})> invoiceOptions({
  required CardConfig card,
  String? aroundDate,
  List<String> existingKeys = const [],
}) {
  final baseDate = aroundDate ?? todayISO();
  final baseKey = invKeyFor(card, baseDate);
  final keys = <String>{};
  for (int i = -6; i <= 12; i++) {
    keys.add(addMonthsYM(baseKey, i));
  }
  keys.addAll(existingKeys);
  final sorted = keys.toList()..sort();
  return sorted.map((k) {
    final d = invDates(card, k);
    final mLabel = fmtMonth(k);
    return (key: k, label: '$mLabel (Vence ${fmtDate(d.due)})');
  }).toList();
}

List<int> splitAmt(int total, int count) {
  if (count <= 0) return [total];
  final b = total ~/ count;
  final r = total - b * count;
  final g = total >= 0 ? 1 : -1;
  return List<int>.generate(count, (i) => b + (i < r.abs() ? g : 0));
}
