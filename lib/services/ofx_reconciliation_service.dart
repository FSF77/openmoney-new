import 'dart:convert';
import 'dart:typed_data';

import '../models/openmoney_models.dart';
import '../store/money_store.dart';
import 'importers_exporters.dart';

enum OfxReconcileAction {
  reconcileExisting,
  createNew,
  ignore,
}

class OfxRawTransaction {
  final String rawFitId;
  final String compositeFitId;
  final String trnType;
  final String datePosted; // YYYY-MM-DD
  final int rawAmountCents;
  final String name;
  final String memo;
  final String checkNum;
  final String cleanPayee;
  final String cleanMemo;
  final int? installmentCurrent;
  final int? installmentTotal;
  final bool isExplicitInstallment;
  final String? peerBankCode;
  final String? peerAgency;
  final String? peerAccountNumber;

  const OfxRawTransaction({
    required this.rawFitId,
    required this.compositeFitId,
    required this.trnType,
    required this.datePosted,
    required this.rawAmountCents,
    required this.name,
    required this.memo,
    required this.checkNum,
    required this.cleanPayee,
    required this.cleanMemo,
    this.installmentCurrent,
    this.installmentTotal,
    this.isExplicitInstallment = false,
    this.peerBankCode,
    this.peerAgency,
    this.peerAccountNumber,
  });

  String get rawDescription {
    if (name.isNotEmpty && memo.isNotEmpty) {
      final nNorm = OfxReconciliationService.normalizeText(name);
      final mNorm = OfxReconciliationService.normalizeText(memo);
      if (nNorm != mNorm && !mNorm.contains(nNorm)) {
        return '$name - $memo';
      }
      return memo.length >= name.length ? memo : name;
    }
    return memo.isNotEmpty ? memo : name;
  }
}

class OfxStatement {
  final bool isCreditCard;
  final String orgName;
  final String fid;
  final String bankId;
  final String branchId;
  final String accountId;
  final String accountType;
  final String currency;
  final String startDate;
  final String endDate;
  final int? ledgerBalanceCents;
  final String? ledgerBalanceDate;
  final List<OfxRawTransaction> transactions;

  const OfxStatement({
    required this.isCreditCard,
    required this.orgName,
    required this.fid,
    required this.bankId,
    required this.branchId,
    required this.accountId,
    required this.accountType,
    required this.currency,
    required this.startDate,
    required this.endDate,
    this.ledgerBalanceCents,
    this.ledgerBalanceDate,
    required this.transactions,
  });

  String get effectiveBankCode {
    final fromBankId = OfxReconciliationService.normalizeBankCode(bankId);
    if (fromBankId.isNotEmpty) return fromBankId;
    return OfxReconciliationService.normalizeBankCode(fid);
  }

  String get ofxAccountAliasKey {
    final b = effectiveBankCode;
    final a = OfxReconciliationService.normalizeAccountNumber(accountId);
    if (b.isEmpty && a.isEmpty) return '';
    return 'ofx:${b.isEmpty ? (isCreditCard ? "cc" : "bank") : b}:$a';
  }

  String get displayLabel {
    final kind = isCreditCard ? 'Fatura Cartão' : 'Extrato Bancário';
    final inst = orgName.isNotEmpty
        ? orgName
        : (effectiveBankCode.isNotEmpty ? 'Banco $effectiveBankCode' : kind);
    final acct = accountId.isNotEmpty
        ? (accountId.length > 14 ? '${accountId.substring(0, 12)}…' : accountId)
        : '';
    final period = (startDate.isNotEmpty && endDate.isNotEmpty)
        ? ' • ${fmtDate(startDate)} a ${fmtDate(endDate)}'
        : '';
    return acct.isNotEmpty ? '$kind • $inst ($acct)$period' : '$kind • $inst$period';
  }
}

class OfxReconcileDraftItem {
  final String id;
  final OfxRawTransaction raw;
  OfxReconcileAction action;
  String? matchedTxId;
  bool alreadyReconciledInDb;
  bool updateDateOnMatch;
  bool updateAmountOnMatch;
  String date;
  String payee;
  String memo;
  String categorySelection; // Category path or "xfer:<peerAccountId>"
  List<String> tags;
  bool invertSign;
  bool isInvoicePaymentCredit;
  bool isFitIdAlreadyImported;
  bool projectFutureInstallments;
  String matchReason;

  OfxReconcileDraftItem({
    required this.id,
    required this.raw,
    required this.action,
    this.matchedTxId,
    this.alreadyReconciledInDb = false,
    this.updateDateOnMatch = false,
    this.updateAmountOnMatch = false,
    required this.date,
    required this.payee,
    required this.memo,
    required this.categorySelection,
    this.tags = const [],
    this.invertSign = false,
    this.isInvoicePaymentCredit = false,
    this.isFitIdAlreadyImported = false,
    this.projectFutureInstallments = false,
    this.matchReason = '',
  });

  int get effectiveAmountCents =>
      invertSign ? -raw.rawAmountCents : raw.rawAmountCents;

  bool get canProjectInstallments =>
      raw.isExplicitInstallment &&
      raw.installmentCurrent != null &&
      raw.installmentTotal != null &&
      raw.installmentCurrent! < raw.installmentTotal! &&
      !categorySelection.startsWith('xfer:');
}

class OfxBalanceComparison {
  final bool hasLedgerBalance;
  final int ofxLedgerCents;
  final String referenceDate;
  final int currentReconciledCents;
  final int deltaReconcileCents;
  final int deltaNewCents;
  final int projectedReconciledCents;
  final int differenceCents;
  final bool isCreditCardMode;

  const OfxBalanceComparison({
    required this.hasLedgerBalance,
    required this.ofxLedgerCents,
    required this.referenceDate,
    required this.currentReconciledCents,
    required this.deltaReconcileCents,
    required this.deltaNewCents,
    required this.projectedReconciledCents,
    required this.differenceCents,
    required this.isCreditCardMode,
  });
}

class OfxReconciliationService {
  static final RegExp _brPixBankRegex = RegExp(
    r'\((0?\d{3})\)\s*Ag[êe]ncia:\s*([0-9A-Za-z-]+)\s*Conta:\s*([0-9A-Za-z-]+)',
    caseSensitive: false,
  );

  static final RegExp _isoDateInFileRegex = RegExp(r'(20\d{2})[-_](\d{2})[-_](\d{2})');

  static final RegExp _acquirerPrefixRegex = RegExp(
    r'^(?:Pg\s*\*|Dl\s*\*|Ebn\s*\*|Ec\s*\*Mp\s*\*|Ec\s*\*|Mp\s*\*|Ifd\s*\*|Pag\s*\*|Mercadopago\s*\*)\s*',
    caseSensitive: false,
  );

  static String normalizeText(String raw) {
    return removeDiacritics(raw)
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  static String normalizeBankCode(String? raw) {
    if (raw == null) return '';
    final digits = raw.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.isEmpty) return '';
    return digits.replaceFirst(RegExp(r'^0+'), '');
  }

  static String normalizeAccountNumber(String? raw) {
    if (raw == null) return '';
    final clean = raw.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    if (clean.isEmpty) return '';
    return clean.replaceFirst(RegExp(r'^0+'), '');
  }

  /// Decodifica bytes OFX priorizando UTF-8 estrito (para corrigir arquivos que declaram CHARSET:1252 mas usam UTF-8).
  static String decodeOfxBytes(Uint8List bytes) {
    try {
      return utf8.decode(bytes, allowMalformed: false);
    } catch (_) {
      return readTextBytesWithEncoding(bytes);
    }
  }

  static String decodeEntities(String input) {
    var out = input
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&apos;', "'")
        .replaceAll('&#39;', "'");
    out = out.replaceAllMapped(RegExp(r'&#(\d+);'), (m) {
      final code = int.tryParse(m.group(1) ?? '');
      return code != null ? String.fromCharCode(code) : m.group(0)!;
    });
    out = out.replaceAllMapped(RegExp(r'&#x([0-9a-fA-F]+);'), (m) {
      final code = int.tryParse(m.group(1) ?? '', radix: 16);
      return code != null ? String.fromCharCode(code) : m.group(0)!;
    });
    return out;
  }

  static String? parseOfxDate(String? raw) {
    if (raw == null) return null;
    final match = RegExp(r'(\d{4})(\d{2})(\d{2})').firstMatch(raw.trim());
    if (match == null) return null;
    final y = int.tryParse(match.group(1)!) ?? 0;
    final m = int.tryParse(match.group(2)!) ?? 0;
    final d = int.tryParse(match.group(3)!) ?? 0;
    if (y < 1970 || y > 2099 || m < 1 || m > 12 || d < 1 || d > 31) {
      return null;
    }
    return '${y.toString().padLeft(4, '0')}-${pad2(m)}-${pad2(d)}';
  }

  static int? parseOfxAmountCents(String? raw) {
    if (raw == null) return null;
    final clean = raw.trim();
    if (clean.isEmpty) return null;
    return parseAmountCents(clean);
  }

  static String _extractTagValue(String block, String tagName) {
    final re = RegExp(
      '<$tagName>\\s*([^<\\r\\n]*)',
      caseSensitive: false,
    );
    final m = re.firstMatch(block);
    if (m == null) return '';
    return decodeEntities((m.group(1) ?? '').trim());
  }

  static String _extractSubBlock(String block, String tagName) {
    final openRe = RegExp('<$tagName>', caseSensitive: false);
    final openMatch = openRe.firstMatch(block);
    if (openMatch == null) return '';
    final start = openMatch.end;
    final closeRe = RegExp('</$tagName>', caseSensitive: false);
    final closeMatch = closeRe.firstMatch(block.substring(start));
    if (closeMatch != null) {
      return block.substring(start, start + closeMatch.start);
    }
    return block.substring(start);
  }

  static List<({bool isCard, String body})> _extractStatementBlocks(String content) {
    final tagRe = RegExp(r'<(CC)?STMTRS>', caseSensitive: false);
    final matches = tagRe.allMatches(content).toList();
    final results = <({bool isCard, String body})>[];

    for (int i = 0; i < matches.length; i++) {
      final m = matches[i];
      final isCard = (m.group(1) ?? '').isNotEmpty;
      final closeTag = isCard ? '</CCSTMTRS>' : '</STMTRS>';
      final searchStart = m.end;
      final nextStart = (i + 1 < matches.length) ? matches[i + 1].start : content.length;
      final window = content.substring(searchStart, nextStart);
      final closeRe = RegExp(closeTag, caseSensitive: false);
      final closeMatch = closeRe.firstMatch(window);
      final body = closeMatch != null ? window.substring(0, closeMatch.start) : window;
      results.add((isCard: isCard, body: body));
    }
    return results;
  }

  static List<String> _extractStmTrnBlocks(String block) {
    final trnRe = RegExp(r'<STMTTRN>', caseSensitive: false);
    final matches = trnRe.allMatches(block).toList();
    final items = <String>[];

    for (int i = 0; i < matches.length; i++) {
      final start = matches[i].end;
      final nextStart = (i + 1 < matches.length) ? matches[i + 1].start : block.length;
      var slice = block.substring(start, nextStart);
      final endMatch = RegExp(r'</STMTTRN>|</BANKTRANLIST>|</STMTRS>|</CCSTMTRS>', caseSensitive: false)
          .firstMatch(slice);
      if (endMatch != null) {
        slice = slice.substring(0, endMatch.start);
      }
      items.add(slice);
    }
    return items;
  }

  static ({
    String cleanPayee,
    String cleanMemo,
    int? installmentCurrent,
    int? installmentTotal,
    bool isExplicitInstallment,
    String? peerBankCode,
    String? peerAgency,
    String? peerAccountNumber,
  }) _extractMetadata({
    required String rawName,
    required String rawMemo,
    required bool isCreditCard,
  }) {
    final trimmedName = rawName.trim();
    final trimmedMemo = rawMemo.trim();
    final sourceForPayee = (trimmedName.isNotEmpty &&
            !const {'pix', 'ted', 'doc', 'debito', 'credito', 'compra'}
                .contains(normalizeText(trimmedName)))
        ? trimmedName
        : (trimmedMemo.isNotEmpty ? trimmedMemo : trimmedName);

    String working = sourceForPayee;

    // 1. Extrair coordenadas bancárias da contraparte no memo (PIX / TED)
    String? peerBank;
    String? peerAg;
    String? peerAcc;
    final fullText = '$trimmedName $trimmedMemo';
    final bankMatch = _brPixBankRegex.firstMatch(fullText);
    if (bankMatch != null) {
      peerBank = normalizeBankCode(bankMatch.group(1));
      peerAg = bankMatch.group(2)?.trim();
      peerAcc = bankMatch.group(3)?.trim();
    }

    // 2. Remover prefixos padrão de extratos brasileiros (Nubank, Itaú, Inter, BB, etc.)
    const prefixes = [
      'transferencia recebida pelo pix via open banking - ',
      'transferencia enviada pelo pix via open banking - ',
      'transferencia recebida pelo pix - ',
      'transferencia enviada pelo pix - ',
      'transferencia recebida - ',
      'transferencia enviada - ',
      'pagamento de boleto efetuado - ',
      'pagamento de boleto - ',
      'compra no debito - ',
      'pix enviado - ',
      'pix recebido - ',
    ];
    final normWorking = removeDiacritics(working).toLowerCase();
    for (final p in prefixes) {
      if (normWorking.startsWith(p)) {
        working = working.substring(p.length).trim();
        break;
      }
    }

    // 3. Limpar sufixo explicativo em parênteses quando contém dados bancários/CPF/CNPJ/transferência
    final parenIdx = working.indexOf(' (');
    if (parenIdx > 2) {
      final tail = working.substring(parenIdx);
      final tailLower = removeDiacritics(tail).toLowerCase();
      if (tailLower.contains('transferencia') ||
          tailLower.contains('agencia:') ||
          tailLower.contains('conta:') ||
          tailLower.contains('•••') ||
          RegExp(r'\d{2}\.\d{3}\.\d{3}/\d{4}').hasMatch(tail)) {
        working = working.substring(0, parenIdx).trim();
      }
    }

    // 4. Remover segmentos de CPF/CNPJ/Banco após " - "
    final segments = working.split(' - ');
    if (segments.length >= 2) {
      final second = segments[1].trim();
      final looksLikeDocOrBank = second.contains('•••') ||
          RegExp(r'^\d{2,3}\.\d{3}\.').hasMatch(second) ||
          RegExp(r'\(\d{4}\)$').hasMatch(second);
      if (looksLikeDocOrBank && segments[0].trim().isNotEmpty) {
        working = segments[0].trim();
      }
    }

    // 5. Em cartão de crédito, limpar prefixo de adquirente preservando original em memo
    if (isCreditCard) {
      final stripped = working.replaceFirst(_acquirerPrefixRegex, '').trim();
      if (stripped.isNotEmpty) {
        working = stripped;
      }
    }

    if (working.isEmpty) {
      working = trimmedMemo.isNotEmpty ? trimmedMemo : (trimmedName.isNotEmpty ? trimmedName : 'Lançamento OFX');
    }

    // 6. Detectar indicador de parcela (ex: "Parcela 3/12" ou "4/5")
    int? pn;
    int? pt;
    bool isExplicit = false;
    final explicitParcelMatch = RegExp(
      r'(?:parcela|parc\.?)\s*(\d{1,2})\s*/\s*(\d{1,2})',
      caseSensitive: false,
    ).firstMatch(fullText);
    if (explicitParcelMatch != null) {
      final c = int.tryParse(explicitParcelMatch.group(1)!);
      final t = int.tryParse(explicitParcelMatch.group(2)!);
      if (c != null && t != null && c >= 1 && t >= 2 && c <= t && t <= 60) {
        pn = c;
        pt = t;
        isExplicit = true;
      }
    } else {
      final genericMatch = RegExp(
        r'(?<![/\-\d])(\d{1,2})\s*/\s*(\d{1,2})(?![/\-\d])',
      ).firstMatch(working);
      if (genericMatch != null) {
        final c = int.tryParse(genericMatch.group(1)!);
        final t = int.tryParse(genericMatch.group(2)!);
        if (c != null && t != null && c >= 1 && t >= 2 && c <= t && t <= 36) {
          pn = c;
          pt = t;
        }
      }
    }

    // Preservar texto integral original no memo quando trouxer informação adicional útil
    String cleanMemo = '';
    if (trimmedMemo.isNotEmpty && trimmedMemo != working) {
      cleanMemo = trimmedMemo;
    } else if (trimmedName.isNotEmpty && trimmedName != working) {
      cleanMemo = trimmedName;
    }

    return (
      cleanPayee: working,
      cleanMemo: cleanMemo,
      installmentCurrent: pn,
      installmentTotal: pt,
      isExplicitInstallment: isExplicit,
      peerBankCode: peerBank,
      peerAgency: peerAg,
      peerAccountNumber: peerAcc,
    );
  }

  static List<OfxStatement> parseBytes(Uint8List bytes) {
    return parseContent(decodeOfxBytes(bytes));
  }

  static List<OfxStatement> parseContent(String content) {
    final cleanContent = content.replaceAll('\uFEFF', '');
    if (cleanContent.trim().isEmpty) return [];

    final fiBlock = _extractSubBlock(cleanContent, 'FI');
    final orgName = _extractTagValue(fiBlock.isNotEmpty ? fiBlock : cleanContent, 'ORG');
    final fid = _extractTagValue(fiBlock.isNotEmpty ? fiBlock : cleanContent, 'FID');

    final stmtBlocks = _extractStatementBlocks(cleanContent);
    if (stmtBlocks.isEmpty) return [];

    final statements = <OfxStatement>[];

    for (final blk in stmtBlocks) {
      final body = blk.body;
      final isCard = blk.isCard;
      final curRaw = _extractTagValue(body, 'CURDEF').toUpperCase();
      final currency = curRaw.length == 3 ? curRaw : 'BRL';

      final acctBlock = isCard
          ? _extractSubBlock(body, 'CCACCTFROM')
          : _extractSubBlock(body, 'BANKACCTFROM');
      final acctSrc = acctBlock.isNotEmpty ? acctBlock : body;

      final bankId = _extractTagValue(acctSrc, 'BANKID');
      final branchId = _extractTagValue(acctSrc, 'BRANCHID');
      final accountId = _extractTagValue(acctSrc, 'ACCTID');
      final acctType = _extractTagValue(acctSrc, 'ACCTTYPE');

      final tranListBlock = _extractSubBlock(body, 'BANKTRANLIST');
      final tranListSrc = tranListBlock.isNotEmpty ? tranListBlock : body;
      final dtStart = parseOfxDate(_extractTagValue(tranListSrc, 'DTSTART')) ?? '';
      final dtEnd = parseOfxDate(_extractTagValue(tranListSrc, 'DTEND')) ?? '';

      final ledgerBlock = _extractSubBlock(body, 'LEDGERBAL');
      final balAmtRaw = ledgerBlock.isNotEmpty
          ? _extractTagValue(ledgerBlock, 'BALAMT')
          : '';
      final ledgerCents = parseOfxAmountCents(balAmtRaw);
      final ledgerDate = ledgerBlock.isNotEmpty
          ? parseOfxDate(_extractTagValue(ledgerBlock, 'DTASOF'))
          : null;

      final trnBlocks = _extractStmTrnBlocks(tranListSrc);
      final rawTxs = <OfxRawTransaction>[];
      final seenCompositeCounts = <String, int>{};

      for (final trn in trnBlocks) {
        final trnType = _extractTagValue(trn, 'TRNTYPE').toUpperCase();
        final dtPosted = parseOfxDate(_extractTagValue(trn, 'DTPOSTED'));
        final amtCents = parseOfxAmountCents(_extractTagValue(trn, 'TRNAMT'));
        if (dtPosted == null || amtCents == null || amtCents == 0) continue;

        final rawFitId = _extractTagValue(trn, 'FITID');
        final rawName = _extractTagValue(trn, 'NAME');
        final rawMemo = _extractTagValue(trn, 'MEMO');
        final checkNum = _extractTagValue(trn, 'CHECKNUM').isNotEmpty
            ? _extractTagValue(trn, 'CHECKNUM')
            : _extractTagValue(trn, 'REFNUM');

        final meta = _extractMetadata(
          rawName: rawName,
          rawMemo: rawMemo,
          isCreditCard: isCard,
        );

        final baseKey = rawFitId.isNotEmpty
            ? '$rawFitId|$dtPosted|$amtCents'
            : 'ofx|$dtPosted|$amtCents|${normalizeText(meta.cleanPayee)}';
        final occ = (seenCompositeCounts[baseKey] ?? 0) + 1;
        seenCompositeCounts[baseKey] = occ;
        final compositeFitId = occ == 1 ? baseKey : '$baseKey|#$occ';

        rawTxs.add(
          OfxRawTransaction(
            rawFitId: rawFitId,
            compositeFitId: compositeFitId,
            trnType: trnType,
            datePosted: dtPosted,
            rawAmountCents: amtCents,
            name: rawName,
            memo: rawMemo,
            checkNum: checkNum,
            cleanPayee: meta.cleanPayee,
            cleanMemo: meta.cleanMemo,
            installmentCurrent: meta.installmentCurrent,
            installmentTotal: meta.installmentTotal,
            isExplicitInstallment: meta.isExplicitInstallment,
            peerBankCode: meta.peerBankCode,
            peerAgency: meta.peerAgency,
            peerAccountNumber: meta.peerAccountNumber,
          ),
        );
      }

      statements.add(
        OfxStatement(
          isCreditCard: isCard,
          orgName: orgName,
          fid: fid,
          bankId: bankId,
          branchId: branchId,
          accountId: accountId,
          accountType: acctType,
          currency: currency,
          startDate: dtStart,
          endDate: dtEnd,
          ledgerBalanceCents: ledgerCents,
          ledgerBalanceDate: ledgerDate,
          transactions: rawTxs,
        ),
      );
    }

    return statements;
  }

  static ({String accountId, bool autoMatched}) detectTargetAccount({
    required OfxStatement statement,
    required List<Account> accounts,
    String? preferredAccountId,
    String? fileName,
  }) {
    if (accounts.isEmpty) return (accountId: '', autoMatched: false);

    final compatible = accounts
        .where((a) => statement.isCreditCard ? a.type == kCardType : a.type != kCardType)
        .toList();
    final pool = compatible.isNotEmpty ? compatible : accounts;

    // 1. Se foi aberto diretamente na tela da conta compatível, prioriza-a
    if (preferredAccountId != null && preferredAccountId.isNotEmpty) {
      for (final a in compatible) {
        if (a.id == preferredAccountId) {
          return (accountId: a.id, autoMatched: true);
        }
      }
    }

    // 2. Match exato por walletAliases (ex: "ofx:260:5284864" ou ACCTID salvo)
    final aliasKey = statement.ofxAccountAliasKey.toLowerCase();
    final rawAcctNorm = normalizeAccountNumber(statement.accountId);
    for (final a in pool) {
      final aliases = a.walletAliases ?? const [];
      for (final al in aliases) {
        final normAl = al.trim().toLowerCase();
        if (aliasKey.isNotEmpty && normAl == aliasKey) {
          return (accountId: a.id, autoMatched: true);
        }
        if (rawAcctNorm.isNotEmpty && normalizeAccountNumber(al) == rawAcctNorm) {
          return (accountId: a.id, autoMatched: true);
        }
      }
    }

    // 3. Match por bankCode + accountNumber normalizados no cadastro da conta
    final stmtBank = statement.effectiveBankCode;
    if (rawAcctNorm.isNotEmpty) {
      for (final a in pool) {
        final accNum = normalizeAccountNumber(a.accountNumber);
        if (accNum.isEmpty || accNum != rawAcctNorm) continue;
        final accBank = normalizeBankCode(a.bankCode);
        if (stmtBank.isEmpty || accBank.isEmpty || accBank == stmtBank) {
          return (accountId: a.id, autoMatched: true);
        }
      }
    }

    // 4. Match por código do banco + instituição (ORG/nome do arquivo) entre contas ativas
    final activePool = pool.where((a) => a.isActive).toList();
    final searchPool = activePool.isNotEmpty ? activePool : pool;

    if (stmtBank.isNotEmpty) {
      final bankMatches = searchPool
          .where((a) => normalizeBankCode(a.bankCode) == stmtBank)
          .toList();
      if (bankMatches.length == 1) {
        return (accountId: bankMatches.first.id, autoMatched: true);
      }
    }

    final hints = normalizeText('${statement.orgName} ${fileName ?? ""}');
    if (hints.isNotEmpty) {
      final hintTokens = hints
          .split(' ')
          .where((w) =>
              w.length >= 3 &&
              !const {'cartao', 'conta', 'banco', 'pagamentos', 'ofx', 'fatura', 'extrato', 'ltda'}
                  .contains(w))
          .toList();
      if (hints.contains('nu pagamentos') || hints.contains('nubank') || RegExp(r'\bnu\b').hasMatch(hints)) {
        hintTokens.add('nubank');
      }
      for (final a in searchPool) {
        final normAcc = normalizeText('${a.name} ${a.logo ?? ""}');
        if (hintTokens.any((t) => normAcc.contains(t))) {
          return (accountId: a.id, autoMatched: true);
        }
      }
    }

    // Fallback
    if (preferredAccountId != null &&
        preferredAccountId.isNotEmpty &&
        accounts.any((a) => a.id == preferredAccountId)) {
      return (accountId: preferredAccountId, autoMatched: false);
    }
    return (accountId: searchPool.first.id, autoMatched: false);
  }

  static String detectTargetInvoiceKey({
    required OfxStatement statement,
    required Account? cardAccount,
    String? preferredInvoiceKey,
    String? fileName,
    required String currentStoreMonth,
  }) {
    // 1. Data de vencimento explícita no nome do arquivo (ex: Cartao_Nubank_2026-12-05.ofx)
    if (fileName != null && fileName.isNotEmpty) {
      final m = _isoDateInFileRegex.firstMatch(fileName);
      if (m != null) {
        final y = m.group(1)!;
        final mo = int.tryParse(m.group(2)!) ?? 0;
        if (mo >= 1 && mo <= 12) {
          return '$y-${pad2(mo)}';
        }
      }
    }

    // 2. Competência inferida pela data de fechamento do arquivo (DTEND) com CardConfig
    if (cardAccount?.card != null && statement.endDate.isNotEmpty) {
      return invKeyFor(cardAccount!.card!, statement.endDate);
    }

    if (preferredInvoiceKey != null && preferredInvoiceKey.isNotEmpty) {
      return preferredInvoiceKey;
    }

    if (cardAccount?.card != null && statement.transactions.isNotEmpty) {
      return invKeyFor(cardAccount!.card!, statement.transactions.first.datePosted);
    }

    return currentStoreMonth;
  }

  static bool isCreditCardInvoicePaymentMemo(String rawDescription) {
    final norm = normalizeText(rawDescription);
    if (norm.isEmpty) return false;
    if (norm.contains('estorno') ||
        norm.contains('reembolso') ||
        norm.contains('confianca') ||
        norm.contains('iof de volta')) {
      return false;
    }
    return norm == 'pagamento recebido' ||
        norm.contains('pagamento recebido') ||
        norm.contains('pagamento de fatura') ||
        norm.contains('pagamento fatura') ||
        norm.contains('pgto fatura') ||
        norm.contains('debito automatico fatura');
  }

  static bool isBankInvoicePaymentMemo(String rawDescription) {
    final norm = normalizeText(rawDescription);
    return norm.contains('pagamento de fatura') ||
        norm.contains('pagamento fatura') ||
        norm.contains('pgto fatura');
  }

  static String? _detectPeerAccountId({
    required OfxRawTransaction raw,
    required String targetAccountId,
    required List<Account> accounts,
    required bool isCreditCard,
    required int effectiveAmtCents,
  }) {
    if (isCreditCard) return null;

    // 1. Match por Banco + Agência + Conta nos dados do PIX/TED
    final peerAcctNorm = normalizeAccountNumber(raw.peerAccountNumber);
    final peerBankNorm = normalizeBankCode(raw.peerBankCode);
    if (peerAcctNorm.isNotEmpty) {
      for (final a in accounts) {
        if (a.id == targetAccountId || a.type == kCardType) continue;
        final accNum = normalizeAccountNumber(a.accountNumber);
        if (accNum.isEmpty || accNum != peerAcctNorm) continue;
        final accBank = normalizeBankCode(a.bankCode);
        if (peerBankNorm.isEmpty || accBank.isEmpty || accBank == peerBankNorm) {
          return a.id;
        }
      }
    }

    // 2. Pagamento de fatura no extrato bancário -> sugerir transferência para cartão vinculado
    if (effectiveAmtCents < 0 && isBankInvoicePaymentMemo(raw.rawDescription)) {
      final cardsPayingHere = accounts
          .where((a) =>
              a.type == kCardType &&
              a.card?.pay == targetAccountId &&
              a.isActive)
          .toList();
      if (cardsPayingHere.length == 1) {
        return cardsPayingHere.first.id;
      }
    }

    return null;
  }

  static String _suggestCategorySelection({
    required OfxRawTransaction raw,
    required int effectiveAmtCents,
    required String targetAccountId,
    required bool isCreditCard,
    required MoneyStore store,
  }) {
    final peerAccId = _detectPeerAccountId(
      raw: raw,
      targetAccountId: targetAccountId,
      accounts: store.db.accounts,
      isCreditCard: isCreditCard,
      effectiveAmtCents: effectiveAmtCents,
    );
    if (peerAccId != null && peerAccId.isNotEmpty) {
      return 'xfer:$peerAccId';
    }

    final isExpense = effectiveAmtCents < 0;
    final candidatesToLookup = <String>[
      raw.cleanPayee,
      if (raw.memo.isNotEmpty && raw.memo != raw.cleanPayee) raw.memo,
    ];
    for (final q in candidatesToLookup) {
      final match = store.lastCategoryAndType(q);
      if (match != null && match.category.isNotEmpty) {
        if (match.isExpense == isExpense ||
            match.category.startsWith('Transferência:')) {
          return match.category;
        }
      }
    }

    final catType = isExpense ? 'Despesa' : 'Receita';
    final paths = store.allCategoryPaths(catType);
    if (paths.contains('Outros')) return 'Outros';
    return paths.isNotEmpty ? paths.first : (isExpense ? 'Outros' : 'Outras Rendas');
  }

  static int _daysDiff(String isoA, String isoB) {
    final dA = dateFromISO(isoA);
    final dB = dateFromISO(isoB);
    return dA.difference(dB).inDays.abs();
  }

  static String _effectiveTxIk(Transaction tx, CardConfig? cardCfg) {
    if (tx.ik != null && tx.ik!.isNotEmpty) return tx.ik!;
    if (tx.inv != null && tx.inv!.isNotEmpty) return tx.inv!;
    if (cardCfg != null) return invKeyFor(cardCfg, tx.date);
    return tx.date.length >= 7 ? tx.date.substring(0, 7) : '';
  }

  static int _tokenSimilarityScore(String ofxText, String txText) {
    final a = normalizeText(ofxText);
    final b = normalizeText(txText);
    if (a.isEmpty || b.isEmpty) return 0;
    if (a == b) return 45;
    if (a.contains(b) || b.contains(a)) return 36;

    const stop = {
      'de',
      'da',
      'do',
      'dos',
      'das',
      'em',
      'para',
      'com',
      'ltda',
      'parcela',
      'pagamento',
      'transferencia',
      'pix',
    };
    final tokensA = a
        .split(' ')
        .where((t) => t.length >= 3 && !stop.contains(t))
        .toSet();
    final tokensB = b
        .split(' ')
        .where((t) => t.length >= 3 && !stop.contains(t))
        .toSet();
    if (tokensA.isEmpty || tokensB.isEmpty) return 0;

    int shared = 0;
    for (final t in tokensA) {
      if (tokensB.contains(t)) {
        shared++;
      }
    }
    if (shared == 0) return 0;
    return (shared * 15).clamp(0, 42);
  }

  static List<OfxReconcileDraftItem> buildReconciliationDrafts({
    required OfxStatement statement,
    required String targetAccountId,
    String? targetInvoiceKey,
    required bool invertSigns,
    required bool defaultUpdateDateOnMatch,
    required MoneyStore store,
  }) {
    final targetAcc = store.accById(targetAccountId);
    final isCard = targetAcc?.type == kCardType || statement.isCreditCard;
    final cardCfg = targetAcc?.card;

    final accTxs = store.db.txs
        .where((t) => t.acc == targetAccountId && !isPredictionPayee(t.payee))
        .toList();

    final drafts = List<OfxReconcileDraftItem?>.filled(statement.transactions.length, null);
    final claimedTxIds = <String>{};

    // Passo 1: Identificar FITIDs já gravados na conta (idempotência exata) e Pagamento Recebido no cartão
    for (int i = 0; i < statement.transactions.length; i++) {
      final raw = statement.transactions[i];
      final effectiveAmt = invertSigns ? -raw.rawAmountCents : raw.rawAmountCents;

      Transaction? fitMatch;
      for (final tx in accTxs) {
        if (claimedTxIds.contains(tx.id)) continue;
        if (tx.fitid == raw.compositeFitId ||
            (raw.rawFitId.isNotEmpty &&
                tx.fitid == raw.rawFitId &&
                tx.amt == effectiveAmt &&
                tx.date == raw.datePosted)) {
          fitMatch = tx;
          break;
        }
      }

      if (fitMatch != null) {
        claimedTxIds.add(fitMatch.id);
        drafts[i] = OfxReconcileDraftItem(
          id: 'ofx_${i}_${raw.compositeFitId}',
          raw: raw,
          action: OfxReconcileAction.ignore,
          matchedTxId: fitMatch.id,
          alreadyReconciledInDb: fitMatch.rec,
          updateDateOnMatch: false,
          date: raw.datePosted,
          payee: raw.cleanPayee,
          memo: raw.cleanMemo,
          categorySelection: fitMatch.cat,
          invertSign: invertSigns,
          isFitIdAlreadyImported: true,
          matchReason: 'Já importado e conciliado (FITID)',
        );
        continue;
      }

      if (isCard &&
          effectiveAmt > 0 &&
          isCreditCardInvoicePaymentMemo(raw.rawDescription)) {
        // Verifica se existe pagamento manual/auto pendente com mesmo valor ±7 dias
        Transaction? pendingPay;
        for (final tx in accTxs) {
          if (claimedTxIds.contains(tx.id) || tx.fitid != null) continue;
          if (tx.amt == effectiveAmt &&
              _daysDiff(tx.date, raw.datePosted) <= 7) {
            if (!tx.rec || pendingPay == null) {
              pendingPay = tx;
              if (!tx.rec) break;
            }
          }
        }

        if (pendingPay != null && !pendingPay.rec) {
          claimedTxIds.add(pendingPay.id);
          drafts[i] = OfxReconcileDraftItem(
            id: 'ofx_${i}_${raw.compositeFitId}',
            raw: raw,
            action: OfxReconcileAction.reconcileExisting,
            matchedTxId: pendingPay.id,
            alreadyReconciledInDb: false,
            updateDateOnMatch: defaultUpdateDateOnMatch,
            date: raw.datePosted,
            payee: raw.cleanPayee,
            memo: raw.cleanMemo,
            categorySelection: pendingPay.cat,
            invertSign: invertSigns,
            isInvoicePaymentCredit: true,
            matchReason: 'Quitação de fatura anterior pareada',
          );
        } else {
          if (pendingPay != null) claimedTxIds.add(pendingPay.id);
          drafts[i] = OfxReconcileDraftItem(
            id: 'ofx_${i}_${raw.compositeFitId}',
            raw: raw,
            action: OfxReconcileAction.ignore,
            matchedTxId: pendingPay?.id,
            alreadyReconciledInDb: pendingPay?.rec ?? true,
            updateDateOnMatch: false,
            date: raw.datePosted,
            payee: raw.cleanPayee,
            memo: raw.cleanMemo,
            categorySelection: pendingPay?.cat ?? '',
            invertSign: invertSigns,
            isInvoicePaymentCredit: true,
            matchReason: pendingPay != null
                ? 'Pagamento de fatura anterior já liquidado'
                : 'Pagamento de fatura anterior (ignorado para não distorcer a fatura)',
          );
        }
      }
    }

    // Passo 2: Pontuar pares 1-para-1 entre OFX restantes e transações da conta sem FITID
    final scoredPairs = <({int ofxIdx, String txId, int score, Transaction tx})>[];

    for (int i = 0; i < statement.transactions.length; i++) {
      if (drafts[i] != null) continue;
      final raw = statement.transactions[i];
      final effectiveAmt = invertSigns ? -raw.rawAmountCents : raw.rawAmountCents;
      final isBankInvPay = !isCard && effectiveAmt < 0 && isBankInvoicePaymentMemo(raw.rawDescription);

      for (final tx in accTxs) {
        if (claimedTxIds.contains(tx.id)) continue;
        if (tx.fitid != null && tx.fitid!.isNotEmpty) continue;
        if (tx.amt != effectiveAmt) continue;

        final days = _daysDiff(tx.date, raw.datePosted);
        final txIk = isCard ? _effectiveTxIk(tx, cardCfg) : '';
        final inSameInvoice = isCard &&
            targetInvoiceKey != null &&
            targetInvoiceKey.isNotEmpty &&
            txIk == targetInvoiceKey;

        final maxDays = isCard ? 5 : ((isBankInvPay || tx.auto == true || tx.card != null) ? 7 : 4);
        if (!inSameInvoice && days > maxDays) continue;

        // Se ambos informam parcela explícita e o número difere, não parear
        if (raw.installmentCurrent != null &&
            tx.pn != null &&
            raw.installmentCurrent != tx.pn) {
          continue;
        }

        int score = 0;
        score += tx.rec ? 15 : 60;

        if (days == 0) {
          score += 40;
        } else if (days == 1) {
          score += 32;
        } else if (days == 2) {
          score += 24;
        } else if (days <= 4) {
          score += 15;
        } else if (days <= 7) {
          score += 8;
        } else if (inSameInvoice) {
          score += 12;
        }

        if (raw.installmentCurrent != null && raw.installmentTotal != null) {
          final pn = raw.installmentCurrent!;
          final pt = raw.installmentTotal!;
          if ((tx.pn == pn && tx.pt == pt) ||
              tx.payee.contains('($pn/$pt)') ||
              tx.payee.contains('$pn/$pt')) {
            score += 50;
          }
        }

        if (isBankInvPay && (tx.auto == true || tx.card != null || normalizeText(tx.payee).contains('cartao'))) {
          score += 45;
        } else {
          score += _tokenSimilarityScore(
            '${raw.cleanPayee} ${raw.memo}',
            '${tx.payee} ${tx.memo}',
          );
        }

        if (score > 0) {
          scoredPairs.add((ofxIdx: i, txId: tx.id, score: score, tx: tx));
        }
      }
    }

    scoredPairs.sort((a, b) {
      final sc = b.score.compareTo(a.score);
      if (sc != 0) return sc;
      return a.ofxIdx.compareTo(b.ofxIdx);
    });

    final usedOfx = <int>{};
    for (final pair in scoredPairs) {
      if (usedOfx.contains(pair.ofxIdx) || claimedTxIds.contains(pair.txId)) {
        continue;
      }
      usedOfx.add(pair.ofxIdx);
      claimedTxIds.add(pair.txId);

      final raw = statement.transactions[pair.ofxIdx];
      final tx = pair.tx;
      final alreadyRec = tx.rec;
      final reason = alreadyRec
          ? 'Já existente e conciliado (${fmtDate(tx.date)}) — vincular FITID'
          : 'Lançamento pendente encontrado (${fmtDate(tx.date)})';

      drafts[pair.ofxIdx] = OfxReconcileDraftItem(
        id: 'ofx_${pair.ofxIdx}_${raw.compositeFitId}',
        raw: raw,
        action: OfxReconcileAction.reconcileExisting,
        matchedTxId: tx.id,
        alreadyReconciledInDb: alreadyRec,
        updateDateOnMatch: alreadyRec ? false : defaultUpdateDateOnMatch,
        date: raw.datePosted,
        payee: raw.cleanPayee,
        memo: raw.cleanMemo,
        categorySelection: tx.cat,
        invertSign: invertSigns,
        matchReason: reason,
      );
    }

    // Passo 3: Itens não pareados -> Criar Novo Conciliado
    for (int i = 0; i < statement.transactions.length; i++) {
      if (drafts[i] != null) continue;
      final raw = statement.transactions[i];
      final effectiveAmt = invertSigns ? -raw.rawAmountCents : raw.rawAmountCents;
      final suggestedCat = _suggestCategorySelection(
        raw: raw,
        effectiveAmtCents: effectiveAmt,
        targetAccountId: targetAccountId,
        isCreditCard: isCard,
        store: store,
      );

      final canProject = isCard &&
          raw.isExplicitInstallment &&
          raw.installmentCurrent != null &&
          raw.installmentTotal != null &&
          raw.installmentCurrent! < raw.installmentTotal! &&
          !suggestedCat.startsWith('xfer:');

      drafts[i] = OfxReconcileDraftItem(
        id: 'ofx_${i}_${raw.compositeFitId}',
        raw: raw,
        action: OfxReconcileAction.createNew,
        date: raw.datePosted,
        payee: raw.cleanPayee,
        memo: raw.cleanMemo,
        categorySelection: suggestedCat,
        invertSign: invertSigns,
        projectFutureInstallments: canProject,
        matchReason: suggestedCat.startsWith('xfer:')
            ? 'Transferência detectada pelos dados bancários'
            : 'Novo lançamento do extrato',
      );
    }

    return drafts.whereType<OfxReconcileDraftItem>().toList();
  }

  static List<Transaction> candidateTransactionsForManualLink({
    required OfxReconcileDraftItem draft,
    required List<OfxReconcileDraftItem> allDrafts,
    required String targetAccountId,
    String? targetInvoiceKey,
    required MoneyStore store,
  }) {
    final acc = store.accById(targetAccountId);
    final isCard = acc?.type == kCardType;
    final cardCfg = acc?.card;
    final claimedElsewhere = <String>{
      for (final d in allDrafts)
        if (d.id != draft.id &&
            d.action == OfxReconcileAction.reconcileExisting &&
            d.matchedTxId != null)
          d.matchedTxId!,
    };

    final targetSign = draft.effectiveAmountCents < 0 ? -1 : 1;
    final candidates = store.db.txs.where((tx) {
      if (tx.acc != targetAccountId) return false;
      if (isPredictionPayee(tx.payee)) return false;
      if (claimedElsewhere.contains(tx.id)) return false;
      if (tx.id == draft.matchedTxId) return true;
      if (tx.fitid != null && tx.fitid!.isNotEmpty) return false;
      if ((tx.amt < 0 ? -1 : 1) != targetSign) return false;
      if (isCard && targetInvoiceKey != null && targetInvoiceKey.isNotEmpty) {
        if (_effectiveTxIk(tx, cardCfg) == targetInvoiceKey) return true;
      }
      return _daysDiff(tx.date, draft.date) <= 45;
    }).toList();

    candidates.sort((a, b) {
      if (a.id == draft.matchedTxId) return -1;
      if (b.id == draft.matchedTxId) return 1;
      final aExact = a.amt == draft.effectiveAmountCents ? 0 : 1;
      final bExact = b.amt == draft.effectiveAmountCents ? 0 : 1;
      if (aExact != bExact) return aExact.compareTo(bExact);
      final aPending = !a.rec ? 0 : 1;
      final bPending = !b.rec ? 0 : 1;
      if (aPending != bPending) return aPending.compareTo(bPending);
      return _daysDiff(a.date, draft.date).compareTo(_daysDiff(b.date, draft.date));
    });

    return candidates;
  }

  static OfxBalanceComparison computeBalanceComparison({
    required OfxStatement statement,
    required String targetAccountId,
    String? targetInvoiceKey,
    required List<OfxReconcileDraftItem> drafts,
    required MoneyStore store,
  }) {
    final ofxLedger = statement.ledgerBalanceCents;
    final refDate = statement.ledgerBalanceDate ??
        (statement.endDate.isNotEmpty ? statement.endDate : todayISO());
    final acc = store.accById(targetAccountId);
    final isCard = acc?.type == kCardType || statement.isCreditCard;

    if (ofxLedger == null || acc == null) {
      return OfxBalanceComparison(
        hasLedgerBalance: false,
        ofxLedgerCents: 0,
        referenceDate: refDate,
        currentReconciledCents: 0,
        deltaReconcileCents: 0,
        deltaNewCents: 0,
        projectedReconciledCents: 0,
        differenceCents: 0,
        isCreditCardMode: isCard,
      );
    }

    final txById = {
      for (final tx in store.db.txs)
        if (tx.acc == targetAccountId) tx.id: tx,
    };

    if (isCard) {
      final cardCfg = acc.card;
      final ikTarget = targetInvoiceKey ?? '';
      int currentNet = 0;
      for (final tx in txById.values) {
        if (tx.auto == true) continue;
        if (isPredictionPayee(tx.payee)) continue;
        if (ikTarget.isNotEmpty && _effectiveTxIk(tx, cardCfg) != ikTarget) {
          continue;
        }
        // Excluir créditos de pagamento da fatura atual para equivaler ao LEDGERBAL da fatura
        if (tx.amt > 0 && tx.xfer != null) continue;
        currentNet += tx.amt;
      }

      int deltaRec = 0;
      int deltaNew = 0;
      for (final d in drafts) {
        if (d.isInvoicePaymentCredit) continue;
        if (d.action == OfxReconcileAction.createNew) {
          deltaNew += d.effectiveAmountCents;
        } else if (d.action == OfxReconcileAction.reconcileExisting &&
            d.matchedTxId != null) {
          final existing = txById[d.matchedTxId!];
          if (existing != null && d.updateAmountOnMatch && existing.auto != true) {
            deltaRec += (d.effectiveAmountCents - existing.amt);
          }
        }
      }

      final projected = currentNet + deltaRec + deltaNew;
      return OfxBalanceComparison(
        hasLedgerBalance: true,
        ofxLedgerCents: ofxLedger,
        referenceDate: refDate,
        currentReconciledCents: currentNet,
        deltaReconcileCents: deltaRec,
        deltaNewCents: deltaNew,
        projectedReconciledCents: projected,
        differenceCents: ofxLedger - projected,
        isCreditCardMode: true,
      );
    }

    // Conta Bancária / Corrente / Poupança / Investimento / Dinheiro
    int currentRec = acc.opening;
    for (final tx in txById.values) {
      if (tx.rec && tx.date.compareTo(refDate) <= 0) {
        currentRec += tx.amt;
      }
    }

    int deltaRec = 0;
    int deltaNew = 0;
    for (final d in drafts) {
      if (d.action == OfxReconcileAction.createNew) {
        if (d.date.compareTo(refDate) <= 0) {
          deltaNew += d.effectiveAmountCents;
        }
      } else if (d.action == OfxReconcileAction.reconcileExisting &&
          d.matchedTxId != null) {
        final existing = txById[d.matchedTxId!];
        if (existing == null) continue;
        final finalDate = d.updateDateOnMatch ? d.date : existing.date;
        final finalAmt =
            (d.updateAmountOnMatch && existing.auto != true)
                ? d.effectiveAmountCents
                : existing.amt;
        final wasCounted = existing.rec && existing.date.compareTo(refDate) <= 0;
        final willCount = finalDate.compareTo(refDate) <= 0;
        if (!wasCounted && willCount) {
          deltaRec += finalAmt;
        } else if (wasCounted && !willCount) {
          deltaRec -= existing.amt;
        } else if (wasCounted && willCount && finalAmt != existing.amt) {
          deltaRec += (finalAmt - existing.amt);
        }
      }
    }

    final projected = currentRec + deltaRec + deltaNew;
    return OfxBalanceComparison(
      hasLedgerBalance: true,
      ofxLedgerCents: ofxLedger,
      referenceDate: refDate,
      currentReconciledCents: currentRec,
      deltaReconcileCents: deltaRec,
      deltaNewCents: deltaNew,
      projectedReconciledCents: projected,
      differenceCents: ofxLedger - projected,
      isCreditCardMode: false,
    );
  }
}
