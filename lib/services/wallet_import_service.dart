import 'dart:typed_data';
import '../models/openmoney_models.dart';
import '../store/money_store.dart';
import 'importers_exporters.dart';

class WalletDraftItem {
  final String id;
  String date;
  String rawAccountName;
  String accountId;
  String payee;
  String memo;
  int amountCents;
  bool isExpense;
  String category;
  bool isSelected;
  bool isDuplicate;
  bool isAccountAutoMatched;

  WalletDraftItem({
    String? id,
    required this.date,
    required this.rawAccountName,
    required this.accountId,
    required this.payee,
    required this.memo,
    required this.amountCents,
    this.isExpense = true,
    this.category = 'Outros',
    this.isSelected = true,
    this.isDuplicate = false,
    this.isAccountAutoMatched = false,
  }) : id = id ?? uid();
}

class WalletImportService {
  static String normalize(String text) {
    return removeDiacritics(text.trim()).toLowerCase();
  }

  /// Resolve a conta no OpenMoney a partir do nome exportado pelo app Carteira (Apple Wallet).
  /// Prioridade:
  /// 1) Match exato em `walletAliases` da conta
  /// 2) Match exato no `name` da conta
  /// 3) Match por substring (ex: "Nubank Mastercard Ultravioleta" -> conta "Nubank")
  /// 4) Match por palavras-chave significativas
  static ({String accountId, bool autoMatched}) resolveAccount(
    String rawName,
    List<Account> accounts,
  ) {
    final trimmed = rawName.trim();
    if (trimmed.isEmpty) {
      final fallback = accounts.where((a) => a.isActive).firstOrNull?.id ??
          accounts.firstOrNull?.id ??
          '';
      return (accountId: fallback, autoMatched: false);
    }

    final normRaw = normalize(trimmed);

    // 1. Verifica walletAliases salvo nas contas
    for (final acc in accounts) {
      final aliases = acc.walletAliases;
      if (aliases != null) {
        for (final alias in aliases) {
          if (normalize(alias) == normRaw) {
            return (accountId: acc.id, autoMatched: true);
          }
        }
      }
    }

    // 2. Verifica nome exato da conta
    for (final acc in accounts) {
      if (normalize(acc.name) == normRaw) {
        return (accountId: acc.id, autoMatched: true);
      }
    }

    // 3. Verifica correspondência parcial (priorizando contas ativas e nomes mais longos)
    final sortedAccs = List<Account>.from(accounts)
      ..sort((a, b) {
        if (a.isActive != b.isActive) return a.isActive ? -1 : 1;
        return b.name.length.compareTo(a.name.length);
      });

    for (final acc in sortedAccs) {
      final normAcc = normalize(acc.name);
      if (normAcc.length < 3) continue;
      if (normRaw.contains(normAcc) || normAcc.contains(normRaw)) {
        return (accountId: acc.id, autoMatched: true);
      }
    }

    // 4. Palavras individuais significativas (>= 3 letras, ignorando termos genéricos de bandeira)
    const stopWords = <String>{
      'cartao',
      'card',
      'credito',
      'debito',
      'mastercard',
      'visa',
      'elo',
      'gold',
      'platinum',
      'black',
      'infinite',
      'ultravioleta',
      'banco',
      'bank',
    };
    final rawTokens = normRaw
        .split(RegExp(r'\s+'))
        .where((t) => t.length >= 3 && !stopWords.contains(t))
        .toList();

    for (final acc in sortedAccs) {
      final accTokens = normalize(acc.name)
          .split(RegExp(r'\s+'))
          .where((t) => t.length >= 3 && !stopWords.contains(t))
          .toList();
      if (rawTokens.any((t) => accTokens.contains(t))) {
        return (accountId: acc.id, autoMatched: true);
      }
    }

    final fallbackId = accounts
            .where((a) => a.isActive && a.type == kCardType)
            .firstOrNull
            ?.id ??
        accounts.where((a) => a.isActive).firstOrNull?.id ??
        accounts.firstOrNull?.id ??
        '';
    return (accountId: fallbackId, autoMatched: false);
  }

  static List<WalletDraftItem> parseWalletBytes(
    Uint8List bytes,
    MoneyStore store,
  ) {
    final content = readTextBytesWithEncoding(bytes);
    return parseWalletCSV(content, store);
  }

  static List<WalletDraftItem> parseWalletCSV(
    String content,
    MoneyStore store,
  ) {
    final rawLines = content
        .replaceAll('\uFEFF', '')
        .split(RegExp(r'\r?\n|\r'))
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();

    if (rawLines.isEmpty) return [];

    final delimiter = _detectDelimiter(rawLines.first);
    final records =
        rawLines.map((line) => _parseCSVLine(line, delimiter)).toList();
    if (records.isEmpty) return [];

    int dateIdx = 0;
    int accIdx = 1;
    int descIdx = 2;
    int? noteIdx = 3;
    int valIdx = 4;
    int startRow = 0;

    final firstRow = records.first;
    final firstRowNorm = firstRow.map(normalize).toList();
    final looksLikeHeader = firstRowNorm.any((c) =>
            c.contains('data') ||
            c.contains('date') ||
            c.contains('conta') ||
            c.contains('valor') ||
            c.contains('descri')) ||
        (firstRow.length >= 2 &&
            parseAmountCents(firstRow.last) == null &&
            parseDateString(firstRow.first) == null);

    if (looksLikeHeader) {
      startRow = 1;
      int? foundDate;
      int? foundAcc;
      int? foundDesc;
      int? foundNote;
      int? foundVal;

      for (int i = 0; i < firstRowNorm.length; i++) {
        final col = firstRowNorm[i];
        if (foundDate == null &&
            (col.contains('data') || col.contains('date') || col == 'dt')) {
          foundDate = i;
        } else if (foundAcc == null &&
            (col.contains('conta') ||
                col.contains('cartao') ||
                col.contains('card') ||
                col.contains('carteira') ||
                col.contains('account'))) {
          foundAcc = i;
        } else if (foundDesc == null &&
            (col.contains('desc') ||
                col.contains('estabelecimento') ||
                col.contains('favorecido') ||
                col.contains('payee') ||
                col.contains('merchant') ||
                col.contains('loja') ||
                col.contains('nome'))) {
          foundDesc = i;
        } else if (foundNote == null &&
            (col.contains('nota') ||
                col.contains('obs') ||
                col.contains('memo') ||
                col.contains('note'))) {
          foundNote = i;
        } else if (foundVal == null &&
            (col.contains('valor') ||
                col.contains('amount') ||
                col.contains('total') ||
                col.contains('preco') ||
                col == 'vlr')) {
          foundVal = i;
        }
      }

      if (foundDate != null) dateIdx = foundDate;
      if (foundAcc != null) accIdx = foundAcc;
      if (foundDesc != null) descIdx = foundDesc;
      noteIdx = foundNote;
      if (foundVal != null) valIdx = foundVal;
    } else if (firstRow.length == 4) {
      dateIdx = 0;
      accIdx = 1;
      descIdx = 2;
      noteIdx = null;
      valIdx = 3;
    }

    final drafts = <WalletDraftItem>[];

    for (int rIdx = startRow; rIdx < records.length; rIdx++) {
      final row = records[rIdx];
      if (row.length < 3) continue;

      final rawDate = dateIdx < row.length ? row[dateIdx] : '';
      final parsedDate = parseDateString(rawDate) ?? todayISO();

      final rawAcc = accIdx < row.length ? row[accIdx].trim() : '';
      final rawPayee = descIdx < row.length ? row[descIdx].trim() : '';
      final rawNote =
          (noteIdx != null && noteIdx < row.length) ? row[noteIdx].trim() : '';

      final effectiveValIdx = valIdx < row.length ? valIdx : (row.length - 1);
      final rawVal = effectiveValIdx < row.length ? row[effectiveValIdx] : '0';
      final rawCents = parseAmountCents(rawVal);
      if (rawCents == null || rawCents == 0) continue;

      final amountCents = rawCents.abs();
      bool isExpense = true;
      String suggestedCategory = 'Outros';

      if (rawPayee.isNotEmpty) {
        final match = store.lastCategoryAndType(rawPayee);
        if (match != null) {
          suggestedCategory = match.category;
          isExpense = match.isExpense;
        }
      }

      final accResolution = resolveAccount(rawAcc, store.db.accounts);

      final isDup = store.db.txs.any((tx) =>
          tx.acc == accResolution.accountId &&
          tx.date == parsedDate &&
          tx.amt.abs() == amountCents &&
          normalize(tx.payee) == normalize(rawPayee));

      drafts.add(
        WalletDraftItem(
          date: parsedDate,
          rawAccountName: rawAcc,
          accountId: accResolution.accountId,
          payee: rawPayee,
          memo: rawNote,
          amountCents: amountCents,
          isExpense: isExpense,
          category: suggestedCategory,
          isSelected: !isDup,
          isDuplicate: isDup,
          isAccountAutoMatched: accResolution.autoMatched,
        ),
      );
    }

    return drafts;
  }

  static String _detectDelimiter(String firstLine) {
    final semi = ';'.allMatches(firstLine).length;
    final comma = ','.allMatches(firstLine).length;
    final tab = '\t'.allMatches(firstLine).length;
    if (tab > semi && tab > comma) return '\t';
    if (semi >= comma) return ';';
    return ',';
  }

  static List<String> _parseCSVLine(String line, String delimiter) {
    final fields = <String>[];
    final current = StringBuffer();
    bool inQuotes = false;

    for (int i = 0; i < line.length; i++) {
      final ch = line[i];
      if (ch == '"') {
        inQuotes = !inQuotes;
      } else if (ch == delimiter && !inQuotes) {
        fields.add(current.toString().trim());
        current.clear();
      } else {
        current.write(ch);
      }
    }
    fields.add(current.toString().trim());
    return fields;
  }
}
