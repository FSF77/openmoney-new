import 'package:flutter/foundation.dart';
import '../models/openmoney_models.dart';
import '../store/money_store.dart';
import 'importers_exporters.dart';
import 'platform_io.dart';
import 'wallet_import_service.dart';

class ShortcutReceiptDraft {
  final String? rawDate;
  final String? rawAccount;
  final String? rawPayee;
  final String? rawAmount;
  final String? rawCategory;
  final String? rawMemo;
  final String? rawType;

  const ShortcutReceiptDraft({
    this.rawDate,
    this.rawAccount,
    this.rawPayee,
    this.rawAmount,
    this.rawCategory,
    this.rawMemo,
    this.rawType,
  });

  bool get hasAnyData =>
      (rawDate != null && rawDate!.trim().isNotEmpty) ||
      (rawAccount != null && rawAccount!.trim().isNotEmpty) ||
      (rawPayee != null && rawPayee!.trim().isNotEmpty) ||
      (rawAmount != null && rawAmount!.trim().isNotEmpty) ||
      (rawCategory != null && rawCategory!.trim().isNotEmpty) ||
      (rawMemo != null && rawMemo!.trim().isNotEmpty);
}

class ResolvedShortcutReceipt {
  final String accountId;
  final String dateIso;
  final String payee;
  final int amountCents;
  final String category;
  final String memo;
  final bool isExpense;
  final String? rawAccountName;

  const ResolvedShortcutReceipt({
    required this.accountId,
    required this.dateIso,
    required this.payee,
    required this.amountCents,
    required this.category,
    required this.memo,
    required this.isExpense,
    this.rawAccountName,
  });
}

class ShortcutUrlService extends ChangeNotifier {
  ShortcutUrlService._();
  static final ShortcutUrlService instance = ShortcutUrlService._();

  ShortcutReceiptDraft? _pendingDraft;
  bool _isModalOpen = false;

  bool get hasPendingDraft => _pendingDraft != null;
  bool get isModalOpen => _isModalOpen;

  void setModalOpen(bool value) {
    _isModalOpen = value;
  }

  ShortcutReceiptDraft? consumePendingDraft() {
    final d = _pendingDraft;
    _pendingDraft = null;
    return d;
  }

  /// Verifica a URL atual do navegador em busca de `?recibo=...` ou parâmetros individuais
  /// (`?data=...&conta=...&favorecido=...&valor=...`).
  /// Se encontrar, armazena o rascunho pendente e limpa a barra de endereços.
  bool captureFromCurrentUrl() {
    if (!kIsWeb) return false;

    final search = webWindowSearch();
    final hash = webWindowHash();

    ShortcutReceiptDraft? parsed;
    if (search.isNotEmpty) {
      parsed = parseQueryString(search);
    }
    if (parsed == null && hash.contains('?')) {
      final qIdx = hash.indexOf('?');
      parsed = parseQueryString(hash.substring(qIdx));
    }
    if (parsed == null) {
      final baseParams = Uri.base.queryParameters;
      if (baseParams.isNotEmpty) {
        parsed = parseQueryParametersMap(baseParams);
      }
    }

    if (parsed != null && parsed.hasAnyData) {
      _pendingDraft = parsed;
      webClearUrlQueryParams();
      notifyListeners();
      return true;
    }
    return false;
  }

  /// Analisa uma query string bruta (ex: `?recibo=Data:07/11/2026;Conta: Nubank;Favorecido:Posto;Valor:100.99;`)
  static ShortcutReceiptDraft? parseQueryString(String rawQuery) {
    final trimmed = rawQuery.trim();
    if (trimmed.isEmpty) return null;
    final clean = trimmed.startsWith('?') ? trimmed.substring(1) : trimmed;
    if (clean.isEmpty) return null;

    // Extrai manualmente o parâmetro recibo caso contenha caracteres não codificados (; ou :)
    final reciboMatch = RegExp(
      r'(?:^|&)(?:recibo|receipt|lancamento|tx)=([^&]+)',
      caseSensitive: false,
    ).firstMatch(clean);

    if (reciboMatch != null) {
      final rawVal = reciboMatch.group(1) ?? '';
      final decoded = _safeDecodeUriComponent(rawVal);
      final draft = parseReciboBlock(decoded);
      if (draft != null && draft.hasAnyData) {
        return draft;
      }
    }

    try {
      final map = Uri.splitQueryString(clean);
      return parseQueryParametersMap(map);
    } catch (_) {
      // Fallback manual se houver algum % malformado
      final map = <String, String>{};
      for (final part in clean.split('&')) {
        final eq = part.indexOf('=');
        if (eq > 0) {
          final k = _safeDecodeUriComponent(part.substring(0, eq));
          final v = _safeDecodeUriComponent(part.substring(eq + 1));
          map[k] = v;
        }
      }
      return parseQueryParametersMap(map);
    }
  }

  static ShortcutReceiptDraft? parseQueryParametersMap(
    Map<String, String> params,
  ) {
    if (params.isEmpty) return null;

    final lowerMap = <String, String>{};
    params.forEach((k, v) {
      lowerMap[WalletImportService.normalize(k)] = v.trim();
    });

    final reciboRaw = lowerMap['recibo'] ??
        lowerMap['receipt'] ??
        lowerMap['lancamento'] ??
        lowerMap['tx'];

    if (reciboRaw != null && reciboRaw.isNotEmpty) {
      final fromBlock = parseReciboBlock(reciboRaw);
      if (fromBlock != null && fromBlock.hasAnyData) {
        return fromBlock;
      }
    }

    final rawDate = lowerMap['data'] ?? lowerMap['date'] ?? lowerMap['dt'];
    final rawAccount = lowerMap['conta'] ??
        lowerMap['cartao'] ??
        lowerMap['card'] ??
        lowerMap['account'] ??
        lowerMap['acc'];
    final rawPayee = lowerMap['favorecido'] ??
        lowerMap['estabelecimento'] ??
        lowerMap['descricao'] ??
        lowerMap['payee'] ??
        lowerMap['merchant'] ??
        lowerMap['loja'] ??
        lowerMap['nome'];
    final rawAmount = lowerMap['valor'] ??
        lowerMap['amount'] ??
        lowerMap['total'] ??
        lowerMap['vlr'] ??
        lowerMap['amt'];
    final rawCategory =
        lowerMap['categoria'] ?? lowerMap['category'] ?? lowerMap['cat'];
    final rawMemo = lowerMap['nota'] ??
        lowerMap['obs'] ??
        lowerMap['observacao'] ??
        lowerMap['memo'] ??
        lowerMap['note'];
    final rawType = lowerMap['tipo'] ?? lowerMap['type'];

    final draft = ShortcutReceiptDraft(
      rawDate: rawDate,
      rawAccount: rawAccount,
      rawPayee: rawPayee,
      rawAmount: rawAmount,
      rawCategory: rawCategory,
      rawMemo: rawMemo,
      rawType: rawType,
    );

    return draft.hasAnyData ? draft : null;
  }

  /// Analisa o bloco estruturado do Atalho iOS:
  /// Ex: `Data:07/11/2026;Conta: Nubank;Favorecido:Posto;Valor:100.99;`
  static ShortcutReceiptDraft? parseReciboBlock(String rawBlock) {
    final text = rawBlock.trim();
    if (text.isEmpty) return null;

    String? rawDate;
    String? rawAccount;
    String? rawPayee;
    String? rawAmount;
    String? rawCategory;
    String? rawMemo;
    String? rawType;

    final pairs = text
        .split(RegExp(r'[;|\n\r]+'))
        .map((s) => s.trim())
        .where((s) => s.isNotEmpty);

    for (final pair in pairs) {
      final colonIdx = pair.indexOf(':');
      final eqIdx = pair.indexOf('=');
      int sepIdx = -1;
      if (colonIdx > 0 && (eqIdx == -1 || colonIdx < eqIdx)) {
        sepIdx = colonIdx;
      } else if (eqIdx > 0) {
        sepIdx = eqIdx;
      }
      if (sepIdx <= 0) continue;

      final key = WalletImportService.normalize(pair.substring(0, sepIdx));
      final val = pair.substring(sepIdx + 1).trim();
      if (val.isEmpty) continue;

      if (key == 'data' || key == 'date' || key == 'dt') {
        rawDate = val;
      } else if (key == 'conta' ||
          key == 'cartao' ||
          key == 'card' ||
          key == 'account' ||
          key == 'banco' ||
          key == 'carteira') {
        rawAccount = val;
      } else if (key == 'favorecido' ||
          key == 'estabelecimento' ||
          key == 'descricao' ||
          key == 'payee' ||
          key == 'merchant' ||
          key == 'loja' ||
          key == 'local' ||
          key == 'nome') {
        rawPayee = val;
      } else if (key == 'valor' ||
          key == 'amount' ||
          key == 'total' ||
          key == 'vlr' ||
          key == 'preco') {
        rawAmount = val;
      } else if (key == 'categoria' || key == 'cat' || key == 'category') {
        rawCategory = val;
      } else if (key == 'nota' ||
          key == 'notas' ||
          key == 'obs' ||
          key == 'observacao' ||
          key == 'memo' ||
          key == 'note') {
        if (WalletImportService.normalize(val) != 'notas') {
          rawMemo = val;
        }
      } else if (key == 'tipo' || key == 'type') {
        rawType = val;
      }
    }

    final draft = ShortcutReceiptDraft(
      rawDate: rawDate,
      rawAccount: rawAccount,
      rawPayee: rawPayee,
      rawAmount: rawAmount,
      rawCategory: rawCategory,
      rawMemo: rawMemo,
      rawType: rawType,
    );
    return draft.hasAnyData ? draft : null;
  }

  /// Resolve todos os campos do rascunho contra a base de dados real carregada no `MoneyStore`.
  static ResolvedShortcutReceipt resolveDraft(
    ShortcutReceiptDraft draft,
    MoneyStore store,
  ) {
    store.rebuildIndexesIfNeeded();

    // 1. Data (DD/MM/YYYY, DD/MM/YY ou YYYY-MM-DD -> YYYY-MM-DD)
    final dateIso = parseDateString(draft.rawDate ?? '') ?? todayISO();

    // 2. Valor (100.99 ou 100,99 -> 10099 centavos)
    final rawParsedCents = parseAmountCents(draft.rawAmount ?? '');
    final amountCents = (rawParsedCents ?? 0).abs();

    // 3. Tipo inicial (Despesa por padrão, a menos que especificado ou valor explicitamente positivo/receita)
    bool isExpense = true;
    if (draft.rawType != null && draft.rawType!.trim().isNotEmpty) {
      final normType = WalletImportService.normalize(draft.rawType!);
      if (normType.startsWith('rec') ||
          normType.startsWith('cred') ||
          normType.startsWith('ent') ||
          normType == '+') {
        isExpense = false;
      }
    }

    // 4. Favorecido e Histórico do Favorecido no MoneyStore
    String payee = (draft.rawPayee ?? '').trim();
    String? historyCategory;
    String? historyAccountId;

    if (payee.isNotEmpty) {
      // Se existe no histórico com grafia canônica exata (case-insensitive), preserva a grafia
      final suggestions = store.payeeSuggestions(payee, limit: 8);
      final normPayee = WalletImportService.normalize(payee);
      for (final s in suggestions) {
        if (WalletImportService.normalize(s.name) == normPayee) {
          payee = s.name;
          break;
        }
      }

      final match = store.lastCategoryAndType(payee);
      if (match != null) {
        historyCategory = match.category;
        historyAccountId = match.accountId;
        if (draft.rawType == null || draft.rawType!.trim().isEmpty) {
          isExpense = match.isExpense;
        }
      }
    }

    // 5. Conta — Motor Inteligente de 4 Camadas (4-Tier Smart Account Matcher)
    final accountId = _resolveAccountSmart(
      rawAccount: draft.rawAccount,
      historyAccountId: historyAccountId,
      store: store,
    );

    // 6. Categoria (Explícita -> Histórico do Favorecido -> Palavras-chave -> Padrão)
    final catType = isExpense ? 'Despesa' : 'Receita';
    final availablePaths = store.allCategoryPaths(catType);
    String category = '';

    if (draft.rawCategory != null && draft.rawCategory!.trim().isNotEmpty) {
      category = _matchCategoryPath(draft.rawCategory!, availablePaths) ?? '';
    }
    if (category.isEmpty &&
        historyCategory != null &&
        historyCategory.isNotEmpty) {
      category = _matchCategoryPath(historyCategory, availablePaths) ??
          historyCategory;
    }
    if (category.isEmpty && payee.isNotEmpty) {
      category = _guessCategoryByKeywords(payee, availablePaths) ?? '';
    }
    if (category.isEmpty && availablePaths.isNotEmpty) {
      category = availablePaths.first;
    }

    final memo = (draft.rawMemo ?? '').trim();
    final cleanRawAccount =
        (draft.rawAccount != null && draft.rawAccount!.trim().isNotEmpty)
            ? draft.rawAccount!.trim()
            : null;

    return ResolvedShortcutReceipt(
      accountId: accountId,
      dateIso: dateIso,
      payee: payee,
      amountCents: amountCents,
      category: category,
      memo: memo,
      isExpense: isExpense,
      rawAccountName: cleanRawAccount,
    );
  }

  static String _resolveAccountSmart({
    required String? rawAccount,
    required String? historyAccountId,
    required MoneyStore store,
  }) {
    final activeAccs = store.activeAccounts;
    final allAccs = activeAccs.isNotEmpty ? activeAccs : store.db.accounts;
    if (allAccs.isEmpty) return 'a1';

    final cleanRaw = (rawAccount ?? '').trim();

    // Camadas 1 e 2: Match direto/alias/sinônimos bancários a partir do parâmetro `Conta:`
    if (cleanRaw.isNotEmpty) {
      final walletMatch = WalletImportService.resolveAccount(cleanRaw, allAccs);
      if (walletMatch.autoMatched && walletMatch.accountId.isNotEmpty) {
        return walletMatch.accountId;
      }

      // Scorer avançado com sinônimos bancários (Apple Pay / Carteira / Notificações)
      final synonymMatch = _matchAccountWithBankingSynonyms(cleanRaw, allAccs);
      if (synonymMatch != null && synonymMatch.isNotEmpty) {
        return synonymMatch;
      }
    }

    // Camada 3: Conta habitual do favorecido no histórico
    if (historyAccountId != null && historyAccountId.isNotEmpty) {
      final histAcc = store.accById(historyAccountId);
      if (histAcc != null && !histAcc.isInactive) {
        return histAcc.id;
      }
    }

    // Camada 4: Conta favorita, última conta usada ou primeira conta ativa
    if (store.favoriteAccounts.isNotEmpty) {
      return store.favoriteAccounts.first.id;
    }
    final lastUsed = store.lastUsedAccountId;
    if (lastUsed.isNotEmpty && store.accById(lastUsed)?.isInactive == false) {
      return lastUsed;
    }
    return allAccs.first.id;
  }

  static const List<List<String>> _bankSynonyms = [
    ['nubank', 'nu', 'nu pagamentos', 'roxinho'],
    ['ultravioleta', 'uv'],
    ['itau', 'itaú', 'uniclass', 'personnalite', 'personnalité', 'ion'],
    ['bradesco', 'next', 'prime', 'bradescard'],
    ['santander', 'select', 'unique', 'sx', 'van gogh', 'aadv'],
    ['banco do brasil', 'bb', 'ourocard', 'brasil'],
    ['caixa', 'cef', 'caixa economica'],
    ['inter', 'banco inter', 'intermedium'],
    ['c6', 'c6 bank', 'c6bank', 'carbon'],
    ['btg', 'btg pactual'],
    ['xp', 'xp investimentos', 'rico'],
    ['sicoob', 'sipag'],
    ['sicredi'],
    ['picpay', 'pic pay'],
    ['mercado pago', 'mercadopago', 'mp'],
    ['pagbank', 'pagseguro'],
    ['amex', 'american express'],
    ['nomad'],
    ['wise'],
  ];

  static String? _matchAccountWithBankingSynonyms(
    String rawInput,
    List<Account> accounts,
  ) {
    final normInput = WalletImportService.normalize(rawInput);
    final mentionsCard = RegExp(
      r'\b(cartao|card|credito|mastercard|visa|elo|amex|ultravioleta|uv|black|infinite|platinum|carbon|ourocard)\b',
    ).hasMatch(normInput);

    final expandedTerms = <String>{normInput};
    for (final group in _bankSynonyms) {
      final normGroup = group.map(WalletImportService.normalize).toList();
      if (normGroup.any((term) =>
          RegExp('(^|\\s)${RegExp.escape(term)}(\\s|\$)').hasMatch(normInput))) {
        expandedTerms.addAll(normGroup);
      }
    }

    Account? bestAcc;
    int bestScore = 0;

    for (final acc in accounts) {
      final normName = WalletImportService.normalize(acc.name);
      int score = 0;

      for (final term in expandedTerms) {
        if (term.length >= 2 &&
            RegExp('(^|\\s)${RegExp.escape(term)}(\\s|\$)')
                .hasMatch(normName)) {
          score += 35;
        } else if (term.length >= 3 && normName.contains(term)) {
          score += 20;
        }
      }

      if (score > 0) {
        if (mentionsCard && acc.type == kCardType) {
          score += 15;
        }
        if (acc.isFavorite) {
          score += 5;
        }
        if (score > bestScore) {
          bestScore = score;
          bestAcc = acc;
        }
      }
    }

    return bestScore >= 20 ? bestAcc?.id : null;
  }

  static String? _matchCategoryPath(
    String rawCat,
    List<String> availablePaths,
  ) {
    final normRaw = WalletImportService.normalize(rawCat);
    if (normRaw.isEmpty) return null;

    for (final path in availablePaths) {
      if (WalletImportService.normalize(path) == normRaw) {
        return path;
      }
    }
    for (final path in availablePaths) {
      final normPath = WalletImportService.normalize(path);
      if (normPath.endsWith(':$normRaw') || normPath.contains(normRaw)) {
        return path;
      }
    }
    return null;
  }

  static String? _guessCategoryByKeywords(
    String payee,
    List<String> availablePaths,
  ) {
    final norm = WalletImportService.normalize(payee);
    const rules = <({List<String> payeeKeywords, List<String> catKeywords})>[
      (
        payeeKeywords: [
          'posto',
          'ipiranga',
          'shell',
          'petrobras',
          'br mania',
          'combustivel',
          'gasolina',
          'etanol',
          'auto posto',
        ],
        catKeywords: ['combustivel', 'auto', 'transporte', 'veiculo'],
      ),
      (
        payeeKeywords: [
          'drogasil',
          'droga raia',
          'drogaria',
          'farmacia',
          'panvel',
          'pague menos',
          'ultrafarma',
        ],
        catKeywords: ['farmacia', 'medicamento', 'saude'],
      ),
      (
        payeeKeywords: [
          'uber',
          '99app',
          '99 pop',
          'taxi',
          'estacionamento',
          'sem parar',
          'veloe',
          'conectcar',
          'pedagio',
        ],
        catKeywords: ['uber', 'transporte', 'estacionamento', 'pedagio'],
      ),
      (
        payeeKeywords: [
          'ifood',
          'rappi',
          'restaurante',
          'lanchonete',
          'padaria',
          'panificadora',
          'burger',
          'mcdonalds',
          'bk ',
          'outback',
          'starbucks',
          'cafe',
          'pizzaria',
        ],
        catKeywords: ['restaurante', 'lanche', 'alimentacao', 'delivery'],
      ),
      (
        payeeKeywords: [
          'supermercado',
          'mercado',
          'atacadao',
          'assai',
          'carrefour',
          'pao de acucar',
          'extra',
          'hortifruti',
          'sacolao',
          'zaffari',
          'angeloni',
          'muffato',
        ],
        catKeywords: ['supermercado', 'mercado', 'alimentacao'],
      ),
    ];

    for (final rule in rules) {
      if (rule.payeeKeywords.any((kw) => norm.contains(kw))) {
        for (final catKw in rule.catKeywords) {
          final found = _matchCategoryPath(catKw, availablePaths);
          if (found != null) return found;
        }
      }
    }
    return null;
  }

  static String _safeDecodeUriComponent(String input) {
    final plusFixed = input.replaceAll('+', ' ');
    try {
      return Uri.decodeComponent(plusFixed);
    } catch (_) {
      return plusFixed;
    }
  }
}
