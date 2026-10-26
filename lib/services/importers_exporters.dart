import 'dart:convert';
import 'dart:typed_data';
import '../models/openmoney_models.dart';

class ImportSummary {
  final String title;
  final int importedCount;
  final int skippedCount;
  final int newCategoriesCount;
  final int newAccountsCount;
  final String details;
  final String? customMessage;

  const ImportSummary({
    this.title = 'Importação Concluída',
    this.importedCount = 0,
    this.skippedCount = 0,
    this.newCategoriesCount = 0,
    this.newAccountsCount = 0,
    this.details = '',
    this.customMessage,
  });

  String get formattedMessage {
    if (customMessage != null && customMessage!.isNotEmpty) {
      return customMessage!;
    }
    final lines = <String>[];
    if (title.contains('Categoria')) {
      lines.add('✓ $importedCount categoria(s) importada(s) com sucesso.');
      if (skippedCount > 0) {
        lines.add('• $skippedCount categoria(s) já existiam e foram mantidas.');
      }
    } else {
      lines.add('✓ $importedCount lançamento(s) importado(s) com sucesso.');
      if (skippedCount > 0) {
        lines.add('• $skippedCount lançamento(s) duplicado(s) foram ignorados.');
      }
      if (newCategoriesCount > 0) {
        lines.add('• $newCategoriesCount nova(s) categoria(s) cadastrada(s).');
      }
      if (newAccountsCount > 0) {
        lines.add('• $newAccountsCount nova(s) conta(s) criada(s).');
      }
    }
    if (details.isNotEmpty) {
      lines.add('\n$details');
    }
    return lines.join('\n');
  }
}

/// Decodifica bytes com suporte a UTF-8 e fallback para Windows CP1252 / Latin-1 (Microsoft Money 99).
String readTextBytesWithEncoding(Uint8List bytes) {
  try {
    return utf8.decode(bytes);
  } catch (_) {
    // Fallback para Windows-1252 / Latin-1 preservando acentuação brasileira
    final codes = List<int>.generate(bytes.length, (i) {
      final b = bytes[i];
      return _cp1252Map[b] ?? b;
    });
    return String.fromCharCodes(codes);
  }
}

const Map<int, int> _cp1252Map = {
  0x80: 0x20AC,
  0x82: 0x201A,
  0x83: 0x0192,
  0x84: 0x201E,
  0x85: 0x2026,
  0x86: 0x2020,
  0x87: 0x2021,
  0x88: 0x02C6,
  0x89: 0x2030,
  0x8A: 0x0160,
  0x8B: 0x2039,
  0x8C: 0x0152,
  0x8E: 0x017D,
  0x91: 0x2018,
  0x92: 0x2019,
  0x93: 0x201C,
  0x94: 0x201D,
  0x95: 0x2022,
  0x96: 0x2013,
  0x97: 0x2014,
  0x98: 0x02DC,
  0x99: 0x2122,
  0x9A: 0x0161,
  0x9B: 0x203A,
  0x9C: 0x0153,
  0x9E: 0x017E,
  0x9F: 0x0178,
};

String? parseDateString(String raw) {
  final clean = raw.trim();
  if (clean.isEmpty) return null;

  if (RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(clean)) {
    return clean;
  }

  final parts = clean
      .split(RegExp(r"[\/\-'`. ]+"))
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();

  if (parts.length != 3) return null;

  final p0 = int.tryParse(parts[0]) ?? 0;
  final p1 = int.tryParse(parts[1]) ?? 0;
  final p2 = int.tryParse(parts[2]) ?? 0;

  int day = 0;
  int month = 0;
  int year = 0;

  if (parts[0].length == 4) {
    year = p0;
    month = p1;
    day = p2;
  } else {
    year = p2;
    if (year < 100) {
      year = year >= 70 ? (1900 + year) : (2000 + year);
    }
    if (p0 > 12) {
      day = p0;
      month = p1;
    } else if (p1 > 12) {
      month = p0;
      day = p1;
    } else {
      day = p0;
      month = p1;
    }
  }

  if (year < 1970 || year > 2099 || month < 1 || month > 12 || day < 1 || day > 31) {
    return null;
  }

  return '${year.toString().padLeft(4, '0')}-${pad2(month)}-${pad2(day)}';
}

int? parseAmountCents(String raw) {
  var s = raw.trim();
  if (s.isEmpty) return null;

  var isNeg = false;
  if (s.startsWith('(') && s.endsWith(')')) {
    isNeg = true;
    s = s.substring(1, s.length - 1);
  } else if (s.startsWith('-')) {
    isNeg = true;
    s = s.substring(1);
  } else if (s.endsWith('-')) {
    isNeg = true;
    s = s.substring(0, s.length - 1);
  }

  s = s
      .replaceAll('R\$', '')
      .replaceAll('\$', '')
      .replaceAll('BRL', '')
      .trim();

  final hasComma = s.contains(',');
  final hasDot = s.contains('.');

  if (hasComma && hasDot) {
    final lastComma = s.lastIndexOf(',');
    final lastDot = s.lastIndexOf('.');
    if (lastComma > lastDot) {
      s = s.replaceAll('.', '').replaceAll(',', '.');
    } else {
      s = s.replaceAll(',', '');
    }
  } else if (hasComma) {
    s = s.replaceAll(',', '.');
  }

  s = s.replaceAll(RegExp(r'[^0-9.]'), '');
  final val = double.tryParse(s);
  if (val == null || val.isNaN) return null;
  final cents = (val * 100.0).round();
  return isNeg ? -cents : cents;
}

String? parseInvoiceKey(String raw) {
  final clean = raw.trim();
  if (clean.isEmpty) return null;

  if (RegExp(r'^\d{4}-\d{2}$').hasMatch(clean)) {
    return clean;
  }

  final parts = clean
      .split(RegExp(r'[\/\-. ]+'))
      .map((s) => s.trim())
      .where((s) => s.isNotEmpty)
      .toList();

  if (parts.length == 2) {
    final p0 = int.tryParse(parts[0]) ?? 0;
    final p1 = int.tryParse(parts[1]) ?? 0;
    if (parts[0].length == 4 && p1 >= 1 && p1 <= 12) {
      return '${p0.toString().padLeft(4, '0')}-${pad2(p1)}';
    } else if (parts[1].length == 4 && p0 >= 1 && p0 <= 12) {
      return '${p1.toString().padLeft(4, '0')}-${pad2(p0)}';
    } else if (parts[1].length == 2 && p0 >= 1 && p0 <= 12) {
      final year = 2000 + p1;
      return '${year.toString().padLeft(4, '0')}-${pad2(p0)}';
    }
  }

  const months = {
    'jan': 1,
    'fev': 2,
    'mar': 3,
    'abr': 4,
    'mai': 5,
    'jun': 6,
    'jul': 7,
    'ago': 8,
    'set': 9,
    'out': 10,
    'nov': 11,
    'dez': 12,
  };
  final lower = removeDiacritics(clean).toLowerCase();
  for (final entry in months.entries) {
    if (lower.contains(entry.key)) {
      final digits = RegExp(r'\d+').allMatches(lower).map((m) => m.group(0)!);
      for (final d in digits) {
        if (d.length == 4) {
          final y = int.tryParse(d);
          if (y != null) {
            return '${y.toString().padLeft(4, '0')}-${pad2(entry.value)}';
          }
        } else if (d.length == 2) {
          final y = int.tryParse(d);
          if (y != null) {
            return '${(2000 + y).toString().padLeft(4, '0')}-${pad2(entry.value)}';
          }
        }
      }
    }
  }
  return null;
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

String _detectCsvDelimiter(String firstLine) {
  final semi = ';'.allMatches(firstLine).length;
  final comma = ','.allMatches(firstLine).length;
  final tab = '\t'.allMatches(firstLine).length;
  if (tab > semi && tab > comma) return '\t';
  if (semi >= comma) return ';';
  return ',';
}

List<String> _parseCsvLine(String line, String delimiter) {
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

String _escapeCSV(String value) => value.replaceAll('"', '""');

class CSVExporter {
  static String generateCSV({
    required List<Transaction> transactions,
    required List<Account> accounts,
    String? accountFilterId,
  }) {
    final accMap = {for (final a in accounts) a.id: a};
    final filtered = (accountFilterId != null && accountFilterId.isNotEmpty)
        ? transactions.where((t) => t.acc == accountFilterId).toList()
        : List<Transaction>.from(transactions);

    filtered.sort((a, b) {
      final dc = a.date.compareTo(b.date);
      if (dc != 0) return dc;
      final tA = a.createdAt ?? 0.0;
      final tB = b.createdAt ?? 0.0;
      if (tA != tB) return tA.compareTo(tB);
      return a.id.compareTo(b.id);
    });

    final lines = <String>[
      '"Data";"Conta";"Status da Conta";"Favorita";"Descrição";"Categoria";"Nota";"Valor";"Conciliado";"Fatura"',
    ];

    for (final tx in filtered) {
      final acc = accMap[tx.acc];
      final accName = _escapeCSV(acc?.name ?? 'Conta');
      final accStatus = (acc?.isInactive == true) ? 'Desabilitada' : 'Habilitada';
      final accFav = (acc?.isFavorite == true) ? 'Sim' : 'Não';
      final dateStr = tx.date;
      final payeeStr = _escapeCSV(tx.payee);
      
      // Ao exportar uma categoria que seja transferência entre contas,
      // não use "Transferência › nome da conta" e sim "Transferência: nome da conta"
      var exportedCat = tx.cat;
      final xferChevronRegex = RegExp(
        r'^\s*transfer[eê]ncia\s*[›>]\s*(.*)$',
        caseSensitive: false,
      );
      final xferMatch = xferChevronRegex.firstMatch(exportedCat);
      if (xferMatch != null) {
        final targetAccName = xferMatch.group(1)?.trim() ?? '';
        exportedCat = 'Transferência: $targetAccName';
      } else if (tx.xfer != null && !exportedCat.startsWith('Transferência:')) {
        exportedCat = exportedCat
            .replaceAll(' › ', ': ')
            .replaceAll(' ›', ': ')
            .replaceAll('› ', ': ')
            .replaceAll('›', ': ');
      }
      final catStr = _escapeCSV(exportedCat);
      final memoStr = _escapeCSV(tx.memo);
      final isNeg = tx.amt < 0;
      final absCents = tx.amt.abs();
      final amtStr =
          '${isNeg ? "-" : ""}${absCents ~/ 100},${(absCents % 100).toString().padLeft(2, "0")}';
      final recStr = tx.rec ? 'Sim' : 'Não';

      var invoiceStr = '';
      if (acc != null && acc.type == kCardType) {
        if (tx.ik != null && tx.ik!.isNotEmpty) {
          invoiceStr = formatInvoiceKeyForDisplay(tx.ik!);
        } else if (acc.card != null) {
          final ik = invKeyFor(acc.card!, tx.date);
          invoiceStr = formatInvoiceKeyForDisplay(ik);
        }
      }

      lines.add(
        '"$dateStr";"$accName";"$accStatus";"$accFav";"$payeeStr";"$catStr";"$memoStr";"$amtStr";"$recStr";"${_escapeCSV(invoiceStr)}"',
      );
    }

    return '\uFEFF${lines.join('\r\n')}';
  }
}

class _ColumnMapping {
  int? date;
  int? account;
  int? accountStatus;
  int? accountFavorite;
  int? payee;
  int? category;
  int? memo;
  int? amount;
  int? reconciled;
  int? invoice;

  _ColumnMapping({
    this.date,
    this.account,
    this.accountStatus,
    this.accountFavorite,
    this.payee,
    this.category,
    this.memo,
    this.amount,
    this.reconciled,
    this.invoice,
  });

  int get score {
    int s = 0;
    if (date != null) s += 4;
    if (amount != null) s += 4;
    if (account != null) s += 2;
    if (payee != null) s += 2;
    if (category != null) s += 1;
    if (memo != null) s += 1;
    if (reconciled != null) s += 1;
    if (invoice != null) s += 1;
    return s;
  }
}

class CSVImporter {
  static ({
    List<Transaction> newTxs,
    List<Account> newAccounts,
    List<CategoryItem> newCats,
    int skippedCount,
  }) parse({
    required String content,
    String? targetAccountId,
    required List<Account> existingAccounts,
    required List<CategoryItem> existingCats,
    required List<Transaction> existingTxs,
    bool allowDuplicates = false,
  }) {
    final rawLines = content
        .replaceAll('\uFEFF', '')
        .split(RegExp(r'\r?\n'))
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();

    if (rawLines.isEmpty) {
      return (newTxs: [], newAccounts: [], newCats: [], skippedCount: 0);
    }

    final delimiter = _detectCsvDelimiter(rawLines[0]);
    final records =
        rawLines.map((line) => _parseCsvLine(line, delimiter)).toList();

    if (records.isEmpty) {
      return (newTxs: [], newAccounts: [], newCats: [], skippedCount: 0);
    }

    int bestHeaderIndex = 0;
    var bestColMap = _detectColumnMapping(records[0]);
    int bestScore = bestColMap.score;

    final scanLimit = records.length < 8 ? records.length : 8;
    for (int rIdx = 0; rIdx < scanLimit; rIdx++) {
      final map = _detectColumnMapping(records[rIdx]);
      if (map.score > bestScore) {
        bestScore = map.score;
        bestHeaderIndex = rIdx;
        bestColMap = map;
      }
    }

    var colMap = bestColMap;
    int dataStartIndex = 0;

    if (bestScore >= 3) {
      dataStartIndex = bestHeaderIndex + 1;
    } else {
      dataStartIndex = 0;
      final sampleRow = records[0];
      if (sampleRow.length >= 8) {
        colMap = _ColumnMapping(
          date: 0,
          account: 1,
          accountStatus: 2,
          accountFavorite: 3,
          payee: 4,
          category: 5,
          memo: 6,
          amount: 7,
          reconciled: sampleRow.length > 8 ? 8 : null,
          invoice: sampleRow.length > 9 ? 9 : null,
        );
      } else if (sampleRow.length >= 6) {
        colMap = _ColumnMapping(
          date: 0,
          account: 1,
          payee: 2,
          category: 3,
          memo: 4,
          amount: 5,
          reconciled: 6,
        );
      } else if (sampleRow.length >= 3) {
        colMap = _ColumnMapping(date: 0, payee: 1, amount: 2);
      } else {
        colMap = _ColumnMapping(date: 0, amount: 1);
      }
      if (colMap.amount != null && colMap.amount! < sampleRow.length) {
        if (parseAmountCents(sampleRow[colMap.amount!]) == null) {
          dataStartIndex = 1;
        }
      }
    }

    final newTxs = <Transaction>[];
    final newAccounts = <Account>[];
    final newCats = <CategoryItem>[];
    int skipped = 0;
    final allAccounts = List<Account>.from(existingAccounts);
    final allCats = List<CategoryItem>.from(existingCats);

    final seenKeys = existingTxs
        .map((t) => '${t.acc}|${t.date}|${t.amt}|${t.payee.toLowerCase()}')
        .toSet();
    final knownCatPaths = existingCats.map((c) => c.path).toSet();

    const invalidAccountNames = {
      'conta',
      'contas',
      'account',
      'accounts',
      'nome da conta',
      'nome da conta bancaria',
      'conta bancaria',
      'banco',
      'bank',
      'tipo de conta',
      'tipo',
      'cartao',
      'cartao de credito',
      'categoria',
      'valor',
      'data',
      'data lancamento',
      'historico',
      'descricao',
    };

    if (targetAccountId == null && colMap.account != null) {
      final aIdx = colMap.account!;
      for (int rowIdx = dataStartIndex; rowIdx < records.length; rowIdx++) {
        final row = records[rowIdx];
        if (aIdx >= row.length) continue;
        final accName = row[aIdx].trim();
        final lower = removeDiacritics(accName).toLowerCase();
        if (accName.isEmpty || invalidAccountNames.contains(lower)) continue;

        if (!allAccounts.any((a) => cmpPt(a.name, accName) == 0)) {
          String accType;
          if (lower.contains('cartao') ||
              lower.contains('card') ||
              lower.contains('credito')) {
            accType = kCardType;
          } else if (lower.contains('poupanca') || lower.contains('savings')) {
            accType = 'Poupança';
          } else if (lower.contains('invest')) {
            accType = 'Investimento';
          } else if (lower.contains('dinheiro') || lower.contains('cash')) {
            accType = 'Dinheiro';
          } else {
            accType = 'Corrente';
          }

          bool? isInactive;
          if (colMap.accountStatus != null && colMap.accountStatus! < row.length) {
            final st = removeDiacritics(row[colMap.accountStatus!].trim()).toLowerCase();
            if (st.contains('desabilit') || st.contains('inativ') || st == 'false' || st == '0') {
              isInactive = true;
            } else if (st.contains('habilit') || st.contains('ativ') || st == 'true' || st == '1') {
              isInactive = null;
            }
          }

          bool? isFavorite;
          if (colMap.accountFavorite != null && colMap.accountFavorite! < row.length) {
            final fv = removeDiacritics(row[colMap.accountFavorite!].trim()).toLowerCase();
            if (fv == 'sim' || fv == 'yes' || fv == 'true' || fv == '1' || fv.contains('favorit')) {
              isFavorite = true;
            }
          }

          final newAcc = Account(
            id: uid(),
            name: accName,
            type: accType,
            opening: 0,
            inactive: isInactive,
            favorite: isFavorite,
          );
          newAccounts.add(newAcc);
          allAccounts.add(newAcc);
        } else {
          // Atualiza status e favorita se a conta já existe e ainda não foi alterada nesta importação
          final existingAcc = allAccounts.firstWhere((a) => cmpPt(a.name, accName) == 0);
          if (colMap.accountStatus != null && colMap.accountStatus! < row.length) {
            final st = removeDiacritics(row[colMap.accountStatus!].trim()).toLowerCase();
            if (st.contains('desabilit') || st.contains('inativ')) {
              existingAcc.inactive = true;
            } else if (st.contains('habilit') || st.contains('ativ')) {
              existingAcc.inactive = null;
            }
          }
          if (colMap.accountFavorite != null && colMap.accountFavorite! < row.length) {
            final fv = removeDiacritics(row[colMap.accountFavorite!].trim()).toLowerCase();
            if (fv == 'sim' || fv == 'yes' || fv == 'true' || fv == '1') {
              existingAcc.favorite = true;
            }
          }
        }
      }
    }

    if (allAccounts.isEmpty) {
      final defaultAcc = Account(
        id: targetAccountId ?? uid(),
        name: 'Conta Corrente',
        type: 'Corrente',
        opening: 0,
      );
      newAccounts.add(defaultAcc);
      allAccounts.add(defaultAcc);
    }

    final fallbackAccId = (targetAccountId != null &&
            allAccounts.any((a) => a.id == targetAccountId))
        ? targetAccountId
        : (allAccounts.isNotEmpty ? allAccounts.first.id : uid());

    for (int rowIdx = dataStartIndex; rowIdx < records.length; rowIdx++) {
      final row = records[rowIdx];
      if (row.length <= 1) continue;

      final dateIdx = colMap.date;
      if (dateIdx == null || dateIdx >= row.length) continue;
      final parsedDate = parseDateString(row[dateIdx]);
      if (parsedDate == null) continue;

      final amtIdx = colMap.amount;
      if (amtIdx == null || amtIdx >= row.length) continue;
      final parsedAmt = parseAmountCents(row[amtIdx]);
      if (parsedAmt == null) continue;

      final payee = (colMap.payee != null && colMap.payee! < row.length)
          ? row[colMap.payee!].trim()
          : 'Lançamento';

      var accId = fallbackAccId;
      if (targetAccountId != null &&
          allAccounts.any((a) => a.id == targetAccountId)) {
        accId = targetAccountId;
      } else if (colMap.account != null && colMap.account! < row.length) {
        final accName = row[colMap.account!].trim();
        final lower = removeDiacritics(accName).toLowerCase();
        if (accName.isNotEmpty && !invalidAccountNames.contains(lower)) {
          for (final a in allAccounts) {
            if (cmpPt(a.name, accName) == 0) {
              accId = a.id;
              break;
            }
          }
        }
      }

      var cat = (colMap.category != null && colMap.category! < row.length)
          ? row[colMap.category!].trim()
          : '';

      // Normaliza categorias de transferência com chevron para "Transferência: nome da conta"
      final xferChevronRegex = RegExp(
        r'^\s*transfer[eê]ncia\s*[›>]\s*(.*)$',
        caseSensitive: false,
      );
      final xferMatch = xferChevronRegex.firstMatch(cat);
      if (xferMatch != null) {
        final targetAccName = xferMatch.group(1)?.trim() ?? '';
        cat = 'Transferência: $targetAccName';
      }

      if (cat.isEmpty) {
        cat = parsedAmt < 0 ? 'Outros' : 'Outras Rendas';
      }
      if (!cat.startsWith('Transferência:')) {
        cat = cat
            .replaceAll(' : ', kCategorySep)
            .replaceAll(':', kCategorySep)
            .replaceAll(' / ', kCategorySep)
            .replaceAll('/', kCategorySep);
      }

      if (!knownCatPaths.contains(cat)) {
        knownCatPaths.add(cat);
        final catType = parsedAmt < 0 ? 'Despesa' : 'Receita';
        final parts = cat.split(kCategorySep);
        final CategoryItem newCatItem;
        if (parts.length > 1) {
          newCatItem = CategoryItem(
            name: parts.last.trim(),
            parent: parts.first.trim(),
            type: catType,
          );
        } else {
          newCatItem = CategoryItem(name: cat, parent: null, type: catType);
        }
        newCats.add(newCatItem);
        allCats.add(newCatItem);
      }

      final memo = (colMap.memo != null && colMap.memo! < row.length)
          ? row[colMap.memo!].trim()
          : '';

      bool rec = false;
      if (colMap.reconciled != null && colMap.reconciled! < row.length) {
        final rStr = row[colMap.reconciled!].trim().toLowerCase();
        rec = rStr == 'sim' ||
            rStr == 'yes' ||
            rStr == 'true' ||
            rStr == '1' ||
            rStr == 'x' ||
            rStr == 'c';
      } else {
        rec = parsedDate.compareTo(todayISO()) <= 0;
      }

      final dupKey = '$accId|$parsedDate|$parsedAmt|${payee.toLowerCase()}';
      if (!allowDuplicates && seenKeys.contains(dupKey)) {
        skipped++;
        continue;
      }
      seenKeys.add(dupKey);

      String? parsedIk;
      Account? accItem;
      for (final a in allAccounts) {
        if (a.id == accId) {
          accItem = a;
          break;
        }
      }
      if (accItem?.type == kCardType) {
        if (colMap.invoice != null && colMap.invoice! < row.length) {
          final rawInv = row[colMap.invoice!].trim();
          if (rawInv.isNotEmpty) {
            parsedIk = parseInvoiceKey(rawInv);
          }
        }
        if (parsedIk == null && accItem?.card != null) {
          parsedIk = invKeyFor(accItem!.card!, parsedDate);
        }
      }

      newTxs.add(
        Transaction(
          id: uid(),
          acc: accId,
          date: parsedDate,
          payee: payee.isEmpty ? 'Lançamento' : payee,
          cat: cat,
          memo: memo,
          amt: parsedAmt,
          rec: rec,
          ik: parsedIk,
        ),
      );
    }

    return (
      newTxs: newTxs,
      newAccounts: newAccounts,
      newCats: newCats,
      skippedCount: skipped,
    );
  }

  static _ColumnMapping _detectColumnMapping(List<String> header) {
    final map = _ColumnMapping();
    for (int idx = 0; idx < header.length; idx++) {
      final col = removeDiacritics(header[idx]).toLowerCase();
      if (map.date == null &&
          (col.contains('data') ||
              col.contains('date') ||
              col == 'dt' ||
              col.contains('dia') ||
              col.contains('lancamento') ||
              col.contains('movimento'))) {
        map.date = idx;
      } else if (map.account == null &&
          (col.contains('conta') ||
              col.contains('account') ||
              col.contains('banco') ||
              col.contains('bank') ||
              col.contains('carteira'))) {
        if (col.contains('status') || col.contains('habilit') || col.contains('ativ')) {
          map.accountStatus ??= idx;
        } else if (col.contains('favorit') || col.contains('fav')) {
          map.accountFavorite ??= idx;
        } else {
          map.account = idx;
        }
      } else if (map.accountStatus == null &&
          (col.contains('status') ||
              col.contains('habilitad') ||
              col.contains('desabilitad') ||
              col.contains('inativ'))) {
        map.accountStatus = idx;
      } else if (map.accountFavorite == null &&
          (col.contains('favorit') || col == 'fav' || col.contains('star'))) {
        map.accountFavorite = idx;
      } else if (map.payee == null &&
          (col.contains('desc') ||
              col.contains('benef') ||
              col.contains('payee') ||
              col.contains('historico') ||
              col.contains('nome') ||
              col.contains('estabelecimento') ||
              col.contains('transacao') ||
              col.contains('favorecido'))) {
        map.payee = idx;
      } else if (map.category == null &&
          (col.contains('cat') ||
              col.contains('categoria') ||
              col.contains('category') ||
              col.contains('subcategoria') ||
              col.contains('classificacao'))) {
        map.category = idx;
      } else if (map.memo == null &&
          (col.contains('nota') ||
              col.contains('memo') ||
              col.contains('obs') ||
              col.contains('detalhe') ||
              col.contains('observacao') ||
              col.contains('info'))) {
        map.memo = idx;
      } else if (map.amount == null &&
          (col.contains('valor') ||
              col.contains('amount') ||
              col.contains('quantia') ||
              col == 'vlr' ||
              col.contains('total') ||
              col.contains('debito') ||
              col.contains('credito') ||
              col.contains('saida') ||
              col.contains('entrada') ||
              col.contains('preco'))) {
        map.amount = idx;
      } else if (map.reconciled == null &&
          (col.contains('conc') ||
              col.contains('status') ||
              col.contains('cleared') ||
              col.contains('rec'))) {
        map.reconciled = idx;
      } else if (map.invoice == null &&
          (col.contains('fatura') ||
              col.contains('invoice') ||
              col.contains('competencia') ||
              col.contains('ciclo'))) {
        map.invoice = idx;
      }
    }
    return map;
  }
}

class CategoryCSVExporter {
  static String generateCSV(List<CategoryItem> categories) {
    final lines = <String>[
      '"Tipo";"Categoria Principal";"Subcategoria";"Categoria Completa"',
    ];

    final extraTypes = categories
        .map((c) => c.type)
        .where((t) => t != 'Despesa' && t != 'Receita')
        .toSet()
        .toList()
      ..sort();
    final distinctTypes = ['Despesa', 'Receita', ...extraTypes];
    final processedPaths = <String>{};

    for (final type in distinctTypes) {
      final typeCats = categories.where((c) => c.type == type).toList();
      final topCats = typeCats
          .where((c) => c.parent == null || c.parent!.isEmpty)
          .toList()
        ..sort((a, b) => cmpPt(a.name, b.name));

      for (final top in topCats) {
        final topEsc = _escapeCSV(top.name);
        final typeEsc = _escapeCSV(type);
        lines.add('"$typeEsc";"$topEsc";"";"$topEsc"');
        processedPaths.add(top.path);

        final subCats = typeCats.where((c) => c.parent == top.name).toList()
          ..sort((a, b) => cmpPt(a.name, b.name));
        for (final sub in subCats) {
          final subEsc = _escapeCSV(sub.name);
          final fullEsc = _escapeCSV(sub.path);
          lines.add('"$typeEsc";"$topEsc";"$subEsc";"$fullEsc"');
          processedPaths.add(sub.path);
        }
      }

      for (final rem in typeCats.where((c) => !processedPaths.contains(c.path))) {
        final typeEsc = _escapeCSV(rem.type);
        if (rem.parent != null && rem.parent!.isNotEmpty) {
          lines.add(
            '"$typeEsc";"${_escapeCSV(rem.parent!)}";"${_escapeCSV(rem.name)}";"${_escapeCSV(rem.path)}"',
          );
        } else {
          lines.add(
            '"$typeEsc";"${_escapeCSV(rem.name)}";"";"${_escapeCSV(rem.path)}"',
          );
        }
        processedPaths.add(rem.path);
      }
    }

    return '\uFEFF${lines.join('\r\n')}';
  }
}

class CategoryCSVImporter {
  static ({List<CategoryItem> newCats, int skippedCount}) parse({
    required String content,
    required List<CategoryItem> existingCats,
  }) {
    final rawLines = content
        .replaceAll('\uFEFF', '')
        .split(RegExp(r'\r?\n'))
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();

    if (rawLines.isEmpty) {
      return (newCats: [], skippedCount: 0);
    }

    final delimiter = _detectCsvDelimiter(rawLines[0]);
    final records =
        rawLines.map((line) => _parseCsvLine(line, delimiter)).toList();

    if (records.isEmpty) {
      return (newCats: [], skippedCount: 0);
    }

    int? colType;
    int? colParent;
    int? colSub;
    int? colFull;

    final firstRow = records[0];
    for (int idx = 0; idx < firstRow.length; idx++) {
      final col = removeDiacritics(firstRow[idx]).toLowerCase();
      if (colType == null && (col == 'tipo' || col == 'type' || col.contains('tipo'))) {
        colType = idx;
      } else if (colFull == null &&
          (col.contains('completa') ||
              col.contains('caminho') ||
              col.contains('path'))) {
        colFull = idx;
      } else if (colParent == null &&
          (col.contains('principal') ||
              col.contains('parent') ||
              col.contains('pai'))) {
        colParent = idx;
      } else if (colSub == null &&
          (col.contains('sub') ||
              col.contains('subcategoria') ||
              col.contains('subcategory'))) {
        colSub = idx;
      } else if (colParent == null &&
          (col == 'categoria' || col == 'category')) {
        colParent = idx;
      }
    }

    final hasHeader = colType != null ||
        colParent != null ||
        colSub != null ||
        colFull != null;
    final dataStartIndex = hasHeader ? 1 : 0;

    final newCats = <CategoryItem>[];
    final existingPaths =
        existingCats.map((c) => c.path.toLowerCase()).toSet();
    int skippedCount = 0;

    for (int rIdx = dataStartIndex; rIdx < records.length; rIdx++) {
      final row = records[rIdx];
      if (row.isEmpty || (row.length == 1 && row[0].isEmpty)) continue;

      String catType = 'Despesa';
      String rawParent = '';
      String rawSub = '';
      String rawFull = '';

      if (hasHeader) {
        if (colType != null && colType < row.length) {
          catType = _parseCatType(row[colType]);
        }
        if (colParent != null && colParent < row.length) {
          rawParent = row[colParent].trim();
        }
        if (colSub != null && colSub < row.length) {
          rawSub = row[colSub].trim();
        }
        if (colFull != null && colFull < row.length) {
          rawFull = row[colFull].trim();
        }
      } else {
        if (row.length >= 4) {
          catType = _parseCatType(row[0]);
          rawParent = row[1];
          rawSub = row[2];
          rawFull = row[3];
        } else if (row.length == 3) {
          if (_isCatType(row[0])) {
            catType = _parseCatType(row[0]);
            rawParent = row[1];
            rawSub = row[2];
          } else {
            rawParent = row[0];
            rawSub = row[1];
            rawFull = row[2];
          }
        } else if (row.length == 2) {
          if (_isCatType(row[0])) {
            catType = _parseCatType(row[0]);
            rawFull = row[1];
          } else {
            rawParent = row[0];
            rawSub = row[1];
          }
        } else if (row.length == 1) {
          rawFull = row[0];
        }
      }

      String? parentName;
      String subcategoryName = '';

      if (rawParent.isNotEmpty && rawSub.isNotEmpty) {
        parentName = rawParent;
        subcategoryName = rawSub;
      } else if (rawParent.isNotEmpty && rawSub.isEmpty) {
        final split = _splitCategoryPath(rawParent);
        if (split != null) {
          parentName = split.parent;
          subcategoryName = split.sub;
        } else {
          subcategoryName = rawParent;
        }
      } else if (rawParent.isEmpty && rawSub.isNotEmpty) {
        final split = _splitCategoryPath(rawSub);
        if (split != null) {
          parentName = split.parent;
          subcategoryName = split.sub;
        } else {
          subcategoryName = rawSub;
        }
      } else if (rawFull.isNotEmpty) {
        final split = _splitCategoryPath(rawFull);
        if (split != null) {
          parentName = split.parent;
          subcategoryName = split.sub;
        } else {
          subcategoryName = rawFull;
        }
      }

      final cleanSub = subcategoryName.replaceAll('"', '').trim();
      final cleanParent = parentName?.replaceAll('"', '').trim();
      if (cleanSub.isEmpty) continue;

      if (cleanParent != null && cleanParent.isNotEmpty) {
        final parentLower = cleanParent.toLowerCase();
        if (!existingPaths.contains(parentLower)) {
          newCats.add(CategoryItem(name: cleanParent, parent: null, type: catType));
          existingPaths.add(parentLower);
        }
        final subItem =
            CategoryItem(name: cleanSub, parent: cleanParent, type: catType);
        final subLower = subItem.path.toLowerCase();
        if (!existingPaths.contains(subLower)) {
          newCats.add(subItem);
          existingPaths.add(subLower);
        } else {
          skippedCount++;
        }
      } else {
        final topItem =
            CategoryItem(name: cleanSub, parent: null, type: catType);
        final topLower = topItem.path.toLowerCase();
        if (!existingPaths.contains(topLower)) {
          newCats.add(topItem);
          existingPaths.add(topLower);
        } else {
          skippedCount++;
        }
      }
    }

    return (newCats: newCats, skippedCount: skippedCount);
  }

  static ({String parent, String sub})? _splitCategoryPath(String text) {
    const seps = [kCategorySep, ' › ', ' > ', ' / ', ' : ', ':', '/', '>'];
    for (final sep in seps) {
      if (text.contains(sep)) {
        final parts = text.split(sep);
        if (parts.length >= 2) {
          final p = parts.first.trim();
          final s = parts.sublist(1).join(kCategorySep).trim();
          if (p.isNotEmpty && s.isNotEmpty) {
            return (parent: p, sub: s);
          }
        }
      }
    }
    return null;
  }

  static String _parseCatType(String text) {
    final lower = removeDiacritics(text.trim()).toLowerCase();
    if (lower.contains('rec') ||
        lower.contains('inc') ||
        lower.contains('cred') ||
        lower == 'c' ||
        lower == 'r' ||
        lower == '+') {
      return 'Receita';
    }
    return 'Despesa';
  }

  static bool _isCatType(String text) {
    final lower = removeDiacritics(text.trim()).toLowerCase();
    return lower == 'despesa' ||
        lower == 'receita' ||
        lower == 'expense' ||
        lower == 'income' ||
        lower == 'd' ||
        lower == 'r';
  }
}

class QIFImporter {
  static ({
    List<Transaction> newTxs,
    List<Account> newAccounts,
    List<CategoryItem> newCats,
    int skippedCount,
  }) parse({
    required String content,
    String? targetAccountId,
    required List<Account> existingAccounts,
    required List<CategoryItem> existingCats,
    required List<Transaction> existingTxs,
  }) {
    final lines = content.split(RegExp(r'\r?\n'));
    final newTxs = <Transaction>[];
    final newAccounts = <Account>[];
    final newCats = <CategoryItem>[];
    final allAccounts = List<Account>.from(existingAccounts);
    final allCats = List<CategoryItem>.from(existingCats);
    int skipped = 0;

    final seenKeys = existingTxs
        .map((t) => '${t.acc}|${t.date}|${t.amt}|${t.payee.toLowerCase()}')
        .toSet();
    final knownCatPaths = existingCats.map((c) => c.path).toSet();

    var preScanSection = '';
    var preAccName = '';
    var preAccType = 'Corrente';
    var detectedQIFType = '';

    for (final rawLine in lines) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;
      if (line.startsWith('!')) {
        preScanSection = line;
        final uSec = line.toUpperCase();
        if (uSec.startsWith('!TYPE:')) {
          detectedQIFType = uSec.substring(6).trim();
        }
        continue;
      }
      final prefix = line[0];
      final value = line.substring(1).trim();
      if (prefix == '^') {
        if (preScanSection.toUpperCase().startsWith('!ACCOUNT') &&
            preAccName.isNotEmpty) {
          if (!allAccounts.any((a) => cmpPt(a.name, preAccName) == 0)) {
            final newAcc = Account(
              id: uid(),
              name: preAccName,
              type: preAccType,
              opening: 0,
            );
            newAccounts.add(newAcc);
            allAccounts.add(newAcc);
          }
        }
        preAccName = '';
        preAccType = 'Corrente';
      } else if (preScanSection.toUpperCase().startsWith('!ACCOUNT')) {
        if (prefix == 'N') {
          preAccName = value;
        } else if (prefix == 'T') {
          final uType = value.toUpperCase();
          if (uType.contains('CCARD')) {
            preAccType = kCardType;
          } else if (uType.contains('CASH')) {
            preAccType = 'Dinheiro';
          } else if (uType.contains('INVST')) {
            preAccType = 'Investimento';
          } else {
            preAccType = 'Corrente';
          }
        }
      } else if (prefix == 'L') {
        if (value.startsWith('[') && value.endsWith(']')) {
          final peerName = value.substring(1, value.length - 1).trim();
          if (peerName.isNotEmpty &&
              !allAccounts.any((a) => cmpPt(a.name, peerName) == 0)) {
            final lower = removeDiacritics(peerName).toLowerCase();
            String accType = 'Corrente';
            if (lower.contains('cartao') ||
                lower.contains('card') ||
                lower.contains('credito')) {
              accType = kCardType;
            } else if (lower.contains('poupanca')) {
              accType = 'Poupança';
            } else if (lower.contains('invest')) {
              accType = 'Investimento';
            } else if (lower.contains('dinheiro')) {
              accType = 'Dinheiro';
            }
            final newAcc = Account(
              id: uid(),
              name: peerName,
              type: accType,
              opening: 0,
            );
            newAccounts.add(newAcc);
            allAccounts.add(newAcc);
          }
        }
      }
    }

    if (allAccounts.isEmpty) {
      String defaultName = 'Conta Corrente';
      String defaultType = 'Corrente';
      if (detectedQIFType.contains('CCARD')) {
        defaultName = 'Cartão de Crédito';
        defaultType = kCardType;
      } else if (detectedQIFType.contains('CASH')) {
        defaultName = 'Dinheiro';
        defaultType = 'Dinheiro';
      }
      final defaultAcc = Account(
        id: targetAccountId ?? uid(),
        name: defaultName,
        type: defaultType,
        opening: 0,
      );
      newAccounts.add(defaultAcc);
      allAccounts.add(defaultAcc);
    }

    var currentAccId = (targetAccountId != null &&
            allAccounts.any((a) => a.id == targetAccountId))
        ? targetAccountId
        : (allAccounts.isNotEmpty ? allAccounts.first.id : uid());

    var currentSection = '';
    var qDate = '';
    var qAmt = 0;
    var qAmtSet = false;
    var qPayee = '';
    var qMemo = '';
    var qCat = '';
    var qRec = false;
    var qAccName = '';
    var qAccType = 'Corrente';

    for (final rawLine in lines) {
      final line = rawLine.trim();
      if (line.isEmpty) continue;
      if (line.startsWith('!')) {
        currentSection = line;
        continue;
      }
      final prefix = line[0];
      final value = line.substring(1).trim();

      if (prefix == '^') {
        if (currentSection.toUpperCase().startsWith('!ACCOUNT')) {
          if (qAccName.isNotEmpty) {
            Account? matched;
            for (final a in allAccounts) {
              if (cmpPt(a.name, qAccName) == 0) {
                matched = a;
                break;
              }
            }
            if (matched != null) {
              currentAccId = matched.id;
            } else {
              final newId = uid();
              final newAcc = Account(
                id: newId,
                name: qAccName,
                type: qAccType,
                opening: 0,
              );
              newAccounts.add(newAcc);
              allAccounts.add(newAcc);
              currentAccId = newId;
            }
          }
          qAccName = '';
          qAccType = 'Corrente';
        } else {
          if (qDate.isNotEmpty && qAmtSet) {
            final finalPayee = qPayee.isEmpty ? 'Lançamento QIF' : qPayee;
            var finalCat = qCat;

            bool isTransfer = false;
            String? transferPeerId;
            if (finalCat.startsWith('[') && finalCat.endsWith(']')) {
              final peerName =
                  finalCat.substring(1, finalCat.length - 1).trim();
              for (final a in allAccounts) {
                if (cmpPt(a.name, peerName) == 0) {
                  isTransfer = true;
                  transferPeerId = a.id;
                  finalCat = 'Transferência: ${a.name}';
                  break;
                }
              }
            }

            if (finalCat.isEmpty) {
              finalCat = qAmt < 0 ? 'Outros' : 'Outras Rendas';
            }

            if (!isTransfer && !knownCatPaths.contains(finalCat)) {
              knownCatPaths.add(finalCat);
              final catType = qAmt < 0 ? 'Despesa' : 'Receita';
              final parts = finalCat.split(kCategorySep);
              final CategoryItem newCatItem;
              if (parts.length > 1) {
                newCatItem = CategoryItem(
                  name: parts.last.trim(),
                  parent: parts.first.trim(),
                  type: catType,
                );
              } else {
                newCatItem = CategoryItem(
                  name: finalCat,
                  parent: null,
                  type: catType,
                );
              }
              newCats.add(newCatItem);
              allCats.add(newCatItem);
            }

            final dupKey =
                '$currentAccId|$qDate|$qAmt|${finalPayee.toLowerCase()}';
            if (seenKeys.contains(dupKey)) {
              skipped++;
            } else {
              seenKeys.add(dupKey);
              newTxs.add(
                Transaction(
                  id: uid(),
                  acc: currentAccId,
                  peer: transferPeerId,
                  date: qDate,
                  payee: finalPayee,
                  cat: finalCat,
                  memo: qMemo,
                  amt: qAmt,
                  rec: qRec,
                  xfer: isTransfer ? 'xfer' : null,
                ),
              );
            }
          }
          qDate = '';
          qAmt = 0;
          qAmtSet = false;
          qPayee = '';
          qMemo = '';
          qCat = '';
          qRec = false;
        }
        continue;
      }

      if (currentSection.toUpperCase().startsWith('!ACCOUNT')) {
        if (prefix == 'N') {
          qAccName = value;
        } else if (prefix == 'T') {
          final uType = value.toUpperCase();
          if (uType.contains('CCARD')) {
            qAccType = kCardType;
          } else if (uType.contains('CASH')) {
            qAccType = 'Dinheiro';
          } else if (uType.contains('INVST')) {
            qAccType = 'Investimento';
          } else {
            qAccType = 'Corrente';
          }
        }
      } else {
        switch (prefix) {
          case 'D':
            final parsed = parseDateString(value);
            if (parsed != null) qDate = parsed;
            break;
          case 'T':
          case 'U':
            final cents = parseAmountCents(value);
            if (cents != null) {
              qAmt = cents;
              qAmtSet = true;
            }
            break;
          case 'P':
            qPayee = value;
            break;
          case 'M':
            qMemo = value;
            break;
          case 'L':
            qCat = value.replaceAll(':', kCategorySep);
            break;
          case 'C':
            final uVal = value.toUpperCase();
            qRec = uVal == 'X' || uVal == 'C' || uVal == '*' || uVal == 'R';
            break;
        }
      }
    }

    return (
      newTxs: newTxs,
      newAccounts: newAccounts,
      newCats: newCats,
      skippedCount: skipped,
    );
  }
}

// MARK: - Mobile Inbox Importer (OpenMoney Coletor .json)

class MobileInboxImportItem {
  final String txId;
  final String accountName;
  final String date;
  final String payee;
  final String cat;
  final String memo;
  final int amt;
  final bool rec;

  const MobileInboxImportItem({
    required this.txId,
    required this.accountName,
    required this.date,
    required this.payee,
    required this.cat,
    required this.memo,
    required this.amt,
    required this.rec,
  });
}

class MobileInboxImportResult {
  final List<MobileInboxImportItem> items;
  final int skippedCount;
  final int newCatsCount;
  final String source;

  const MobileInboxImportResult({
    required this.items,
    this.skippedCount = 0,
    this.newCatsCount = 0,
    this.source = 'OpenMoney Coletor Mobile',
  });
}

class MobileInboxItem {
  final String? id;
  final String acc;
  final String? peer;
  final String date;
  final String payee;
  final String cat;
  final String? memo;
  final int amt;
  final bool? rec;
  final String? xfer;
  final String? receiptThumb;

  const MobileInboxItem({
    this.id,
    required this.acc,
    this.peer,
    required this.date,
    required this.payee,
    required this.cat,
    this.memo,
    required this.amt,
    this.rec,
    this.xfer,
    this.receiptThumb,
  });

  factory MobileInboxItem.fromJson(Map<String, dynamic> json) {
    int parsedAmt = 0;
    final rawAmt = json['amt'];
    if (rawAmt is int) {
      parsedAmt = rawAmt;
    } else if (rawAmt is num) {
      parsedAmt = rawAmt.round();
    } else if (rawAmt is String) {
      parsedAmt = int.tryParse(rawAmt) ?? (parseAmountCents(rawAmt) ?? 0);
    }

    return MobileInboxItem(
      id: json['id']?.toString(),
      acc: (json['acc'] ?? '').toString(),
      peer: json['peer']?.toString(),
      date: (json['date'] ?? todayISO()).toString(),
      payee: (json['payee'] ?? 'Lançamento').toString(),
      cat: (json['cat'] ?? '').toString(),
      memo: json['memo']?.toString(),
      amt: parsedAmt,
      rec: json['rec'] is bool ? json['rec'] as bool : null,
      xfer: json['xfer']?.toString(),
      receiptThumb: json['receiptThumb']?.toString(),
    );
  }
}

class MobileInboxImporter {
  static ({
    List<Transaction> newTxs,
    List<CategoryItem> newCats,
    int skippedCount,
  }) parse({
    required Uint8List bytes,
    required List<Account> existingAccounts,
    required List<CategoryItem> existingCats,
    required List<Transaction> existingTxs,
  }) {
    final content = readTextBytesWithEncoding(bytes).replaceAll('\uFEFF', '').trim();
    final items = <MobileInboxItem>[];

    try {
      final decoded = jsonDecode(content);
      if (decoded is Map<String, dynamic>) {
        final rawTxs = decoded['txs'];
        if (rawTxs is List) {
          for (final el in rawTxs) {
            if (el is Map<String, dynamic>) {
              items.add(MobileInboxItem.fromJson(el));
            }
          }
        }
      } else if (decoded is List) {
        for (final el in decoded) {
          if (el is Map<String, dynamic>) {
            items.add(MobileInboxItem.fromJson(el));
          }
        }
      }
    } catch (_) {
      return (newTxs: [], newCats: [], skippedCount: 0);
    }

    final newTxs = <Transaction>[];
    final newCats = <CategoryItem>[];
    final knownCatPaths = existingCats.map((c) => c.path.toLowerCase()).toSet();
    int skippedCount = 0;

    final existingIdSet = existingTxs.map((t) => t.id).toSet();

    for (final item in items) {
      final txId = (item.id != null && item.id!.isNotEmpty) ? item.id! : uid();

      if (existingIdSet.contains(txId)) {
        skippedCount++;
        continue;
      }

      final cleanPayeeLower = item.payee.trim().toLowerCase();
      final isDuplicate = existingTxs.any((existing) =>
          existing.acc == item.acc &&
          existing.date == item.date &&
          existing.payee.trim().toLowerCase() == cleanPayeeLower &&
          existing.amt == item.amt &&
          existing.cat == item.cat);
      if (isDuplicate) {
        skippedCount++;
        continue;
      }

      Account? targetAcc;
      for (final a in existingAccounts) {
        if (a.id == item.acc) {
          targetAcc = a;
          break;
        }
      }
      if (targetAcc == null) {
        for (final a in existingAccounts) {
          if (cmpPt(a.name, item.acc) == 0) {
            targetAcc = a;
            break;
          }
        }
      }
      if (targetAcc == null) {
        for (final a in existingAccounts) {
          if (!a.isInactive) {
            targetAcc = a;
            break;
          }
        }
      }

      final finalAccId = targetAcc?.id ?? item.acc;

      var catPath = item.cat.trim();
      if (catPath.contains(':') && !catPath.contains(kCategorySep)) {
        catPath = catPath
            .split(':')
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .join(kCategorySep);
      }

      if (catPath.isNotEmpty && !knownCatPaths.contains(catPath.toLowerCase())) {
        final catType = item.amt >= 0 ? 'Receita' : 'Despesa';
        final parts = catPath.split(kCategorySep);
        final CategoryItem createdCat;
        if (parts.length > 1) {
          final parent = parts.first.trim();
          final sub = parts.last.trim();
          if (!knownCatPaths.contains(parent.toLowerCase())) {
            final parentCat =
                CategoryItem(name: parent, parent: null, type: catType);
            newCats.add(parentCat);
            knownCatPaths.add(parent.toLowerCase());
          }
          createdCat = CategoryItem(name: sub, parent: parent, type: catType);
        } else {
          createdCat = CategoryItem(name: catPath, parent: null, type: catType);
        }
        newCats.add(createdCat);
        knownCatPaths.add(createdCat.path.toLowerCase());
      }

      String? ik;
      if (targetAcc != null &&
          targetAcc.type == kCardType &&
          targetAcc.card != null) {
        ik = invKeyFor(targetAcc.card!, item.date);
      }

      var memo = item.memo ?? '';
      if (item.receiptThumb != null && item.receiptThumb!.isNotEmpty) {
        if (!memo.contains('Comprovante')) {
          memo = memo.isEmpty
              ? '[Comprovante Digitalizado]'
              : '$memo [Comprovante Digitalizado]';
        }
      }

      final rec = item.rec ?? (item.date.compareTo(todayISO()) <= 0);

      final tx = Transaction(
        id: txId,
        acc: finalAccId,
        peer: item.peer,
        date: item.date,
        payee: item.payee,
        cat: catPath,
        memo: memo,
        amt: item.amt,
        rec: rec,
        xfer: item.xfer,
        ik: ik,
      );

      newTxs.add(tx);
      existingIdSet.add(txId);
    }

    return (
      newTxs: newTxs,
      newCats: newCats,
      skippedCount: skippedCount,
    );
  }
}
