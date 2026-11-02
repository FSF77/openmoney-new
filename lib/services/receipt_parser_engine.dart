import '../models/openmoney_models.dart';
import '../store/money_store.dart';

class ParsedReceiptDraft {
  final String filePath;
  final String fileName;
  String date;
  String payee;
  int amountCents;
  bool isExpense;
  String accountId;
  String category;
  String rawOcrText;
  bool isSelected;
  bool hasError;
  String errorMessage;

  ParsedReceiptDraft({
    required this.filePath,
    required this.fileName,
    required this.date,
    required this.payee,
    required this.amountCents,
    required this.isExpense,
    required this.accountId,
    required this.category,
    required this.rawOcrText,
    this.isSelected = true,
    this.hasError = false,
    this.errorMessage = '',
  });
}

class ReceiptParserEngine {
  /// Analisa o texto OCR extraído do documento e sugere os campos do lançamento
  static ParsedReceiptDraft parse({
    required String filePath,
    required String fileName,
    required String text,
    required MoneyStore store,
  }) {
    final cleanText = text.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final lines = cleanText
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .toList();

    // 1. Extração de Data
    final detectedDate = _detectDate(cleanText) ?? todayISO();

    // 2. Extração de Valor
    final detectedAmount = _detectAmount(lines);

    // 3. Detecção de Favorecido / Estabelecimento
    final detectedPayee = _detectPayee(lines, store);

    // 4. Detecção de Conta Emissora / Pagadora
    final detectedAccount = _detectAccount(cleanText, store);

    // 5. Sugestão Inteligente de Categoria via Histórico
    var suggestedCategory = 'Outros';
    var isExpense = true;

    final historyMatch = store.lastCategoryAndType(detectedPayee);
    if (historyMatch != null) {
      suggestedCategory = historyMatch.category;
      isExpense = historyMatch.isExpense;
      if (detectedAccount.isEmpty && historyMatch.accountId.isNotEmpty) {
        // Se não achou a conta pelo texto, usa a conta habitual do favorecido
      }
    }

    final finalAccountId = detectedAccount.isNotEmpty
        ? detectedAccount
        : (store.db.accounts.isNotEmpty ? store.db.accounts.first.id : '');

    return ParsedReceiptDraft(
      filePath: filePath,
      fileName: fileName,
      date: detectedDate,
      payee: detectedPayee,
      amountCents: detectedAmount,
      isExpense: isExpense,
      accountId: finalAccountId,
      category: suggestedCategory,
      rawOcrText: cleanText,
      hasError: detectedAmount == 0 || detectedPayee.isEmpty,
      errorMessage: detectedAmount == 0
          ? 'Valor não identificado'
          : (detectedPayee.isEmpty ? 'Favorecido não identificado' : ''),
    );
  }

  /// Detecta data no formato DD/MM/AAAA ou AAAA-MM-DD
  static String? _detectDate(String text) {
    // DD/MM/YYYY ou DD-MM-YYYY
    final dmyRegex = RegExp(r'\b(0[1-9]|[12][0-9]|3[01])[/\-\.](0[1-9]|1[0-2])[/\-\.](20\d\d)\b');
    final dmyMatch = dmyRegex.firstMatch(text);
    if (dmyMatch != null) {
      final day = dmyMatch.group(1)!;
      final month = dmyMatch.group(2)!;
      final year = dmyMatch.group(3)!;
      return '$year-$month-$day';
    }

    // YYYY-MM-DD
    final ymdRegex = RegExp(r'\b(20\d\d)[/\-\.](0[1-9]|1[0-2])[/\-\.](0[1-9]|[12][0-9]|3[01])\b');
    final ymdMatch = ymdRegex.firstMatch(text);
    if (ymdMatch != null) {
      final year = ymdMatch.group(1)!;
      final month = ymdMatch.group(2)!;
      final day = ymdMatch.group(3)!;
      return '$year-$month-$day';
    }

    return null;
  }

  /// Detecta o valor monetário procurando prioritariamente por termos de fechamento/total
  static int _detectAmount(List<String> lines) {
    final totalKeywords = [
      'valor a pagar',
      'total a pagar',
      'valor total',
      'total r\$',
      'total:',
      'valor pago',
      'valor da transação',
      'valor líquido',
      'total liquido',
    ];

    final ignoreKeywords = [
      'tributo',
      'imposto',
      'troco',
      'desconto',
      'aproximado',
      'federal',
      'estadual',
      'icms',
    ];

    // 1. De baixo para cima com palavras-chave de Total
    for (var i = lines.length - 1; i >= 0; i--) {
      final line = lines[i].toLowerCase();
      if (ignoreKeywords.any((kw) => line.contains(kw))) continue;

      for (final kw in totalKeywords) {
        if (line.contains(kw)) {
          final amt = _extractCentsFromLine(lines[i]);
          if (amt > 0) return amt;

          // Se a linha tem apenas o rótulo "TOTAL R$", procura nas 3 linhas seguintes
          for (var j = i + 1; j < lines.length && j <= i + 3; j++) {
            final nextLine = lines[j].toLowerCase();
            if (ignoreKeywords.any((ik) => nextLine.contains(ik))) continue;
            final nextAmt = _extractCentsFromLine(lines[j]);
            if (nextAmt > 0) return nextAmt;
          }
        }
      }
    }

    // 2. Fallback: Procura qualquer linha com "total" que não seja tributo/troco
    for (var i = lines.length - 1; i >= 0; i--) {
      final line = lines[i].toLowerCase();
      if (ignoreKeywords.any((kw) => line.contains(kw))) continue;
      if (line.contains('total')) {
        final amt = _extractCentsFromLine(lines[i]);
        if (amt > 0) return amt;
      }
    }

    // 3. Fallback geral: maior valor monetário encontrado fora de linhas de tributo/troco
    var maxCents = 0;
    for (final line in lines) {
      final lineLower = line.toLowerCase();
      if (ignoreKeywords.any((kw) => lineLower.contains(kw))) continue;
      final amt = _extractCentsFromLine(line);
      if (amt > maxCents) {
        maxCents = amt;
      }
    }

    return maxCents;
  }

  static int _extractCentsFromLine(String line) {
    // Padrões monetários brasileiros: R$ 1.250,50 ou 1.250,50 ou R$ 50,00
    final valRegex = RegExp(r'(?:r\$\s*)?(\d{1,3}(?:\.\d{3})*|\d+)[,\.](\d{2})\b', caseSensitive: false);
    final matches = valRegex.allMatches(line);
    for (final m in matches) {
      final intPart = m.group(1)!.replaceAll('.', '');
      final decPart = m.group(2)!;
      final fullStr = '$intPart$decPart';
      final cents = int.tryParse(fullStr);
      if (cents != null && cents > 0) {
        return cents;
      }
    }
    return 0;
  }

  /// Identifica o favorecido com base nas linhas iniciais e histórico
  static String _detectPayee(List<String> lines, MoneyStore store) {
    store.rebuildIndexesIfNeeded();
    final cachedPayees = store.payeeSuggestions('', limit: 100).map((p) => p.name).toList();

    final ignorePrefixes = [
      'cnpj', 'cpf', 'ie ', 'im ', 'via ', 'laranjinha', 'cielo', 'stone', 'getnet', 'safrapay', 'bin',
      'rede', 'pagbank', 'pagseguro', 'mercado pago', 'debito', 'credito', 'mastercard', 'visa', 'elo',
      'auto :', 'aid:', 'autorizacao', 'protocolo', 'documento auxiliar', 'danfe', 'nfc-e', 'nf-e',
      'chave:', 'chave de acesso', 'consumidor', 'tributos', 'totais', 'total', 'troco', 'icms', 'simples',
      'caixa:', 'op caixa', 'atend:', 'extrato', 'comprovante', 'codigo', 'descricao', 'item'
    ];

    // 1. Tenta correspondência com histórico existente (exata ou por token/palavra)
    for (final line in lines) {
      final cleanLine = line.trim();
      if (cleanLine.length < 3) continue;
      final lower = cleanLine.toLowerCase();
      if (ignorePrefixes.any((pfx) => lower.startsWith(pfx))) continue;

      for (final p in cachedPayees) {
        if (p.length >= 3) {
          if (cleanLine.toLowerCase().contains(p.toLowerCase()) ||
              p.toLowerCase().contains(cleanLine.toLowerCase())) {
            return p;
          }
          final wordsP = p.toLowerCase().split(' ').where((w) => w.length >= 4).toList();
          final wordsLine = lower.split(' ').where((w) => w.length >= 4).toList();
          if (wordsP.any((w) => wordsLine.contains(w))) {
            return p;
          }
        }
      }
    }

    // 2. Procura linhas vizinhas ao CNPJ
    for (var i = 0; i < lines.length; i++) {
      final lineLower = lines[i].toLowerCase();
      if (lineLower.contains('cnpj')) {
        // Linha anterior
        if (i > 0) {
          final prev = lines[i - 1].trim();
          final prevLower = prev.toLowerCase();
          if (prev.length >= 3 && !ignorePrefixes.any((pfx) => prevLower.startsWith(pfx))) {
            return _cleanPayeeName(prev);
          }
        }
        // Linha posterior
        if (i + 1 < lines.length) {
          final next = lines[i + 1].trim();
          final nextLower = next.toLowerCase();
          if (next.length >= 3 && !ignorePrefixes.any((pfx) => nextLower.startsWith(pfx))) {
            return _cleanPayeeName(next);
          }
        }
      }
    }

    // 3. Procura termos indicativos de estabelecimento / recebedor
    final payeeKeywords = [
      'recebedor',
      'destinatário',
      'beneficiário',
      'favorecido',
      'estabelecimento',
      'razão social',
      'nome fantasia',
      'n.estab'
    ];

    for (var i = 0; i < lines.length; i++) {
      final lineLower = lines[i].toLowerCase();
      for (final kw in payeeKeywords) {
        if (lineLower.startsWith(kw) || lineLower.contains('$kw:')) {
          var payeeCandidate = lines[i]
              .replaceAll(RegExp('$kw:?', caseSensitive: false), '')
              .replaceAll(RegExp(r'cnpj:?.*', caseSensitive: false), '')
              .trim();
          if (payeeCandidate.length > 2 && !ignorePrefixes.any((pfx) => payeeCandidate.toLowerCase().startsWith(pfx))) {
            return _cleanPayeeName(payeeCandidate);
          }
          if (i + 1 < lines.length) {
            final next = lines[i + 1].trim();
            if (next.length > 2 && !ignorePrefixes.any((pfx) => next.toLowerCase().startsWith(pfx))) {
              return _cleanPayeeName(next);
            }
          }
        }
      }
    }

    // 4. Fallback: primeiras linhas ignorando endereços, números e cabeçalhos
    for (final line in lines) {
      final l = line.trim();
      final lower = l.toLowerCase();
      if (l.length >= 3 &&
          !RegExp(r'^\d').hasMatch(l) &&
          !ignorePrefixes.any((pfx) => lower.startsWith(pfx)) &&
          !lower.contains('avenida') && !lower.contains(' rua ') && !lower.contains('av.') &&
          !lower.contains('sao paulo') && !lower.contains('sp')) {
        return _cleanPayeeName(l);
      }
    }

    return 'Não Identificado';
  }

  static String _cleanPayeeName(String raw) {
    var p = raw.replaceAll(RegExp(r'[#\*\_]+'), ' ').trim();
    p = p.replaceAll(RegExp(r'\s+'), ' ');
    return p;
  }

  /// Identifica a conta bancária pelo nome do banco ou instituição no documento
  static String _detectAccount(String text, MoneyStore store) {
    final lower = text.toLowerCase();

    // Mapeamento de termos para encontrar a conta correspondente
    final bankKeywords = {
      'nubank': ['nubank', 'nu pagamentos', 'nu finance'],
      'itaú': ['itau', 'itaú', 'unibanco'],
      'bradesco': ['bradesco', 'next'],
      'santander': ['santander'],
      'inter': ['banco inter', 'intermedium'],
      'caixa': ['caixa econômica', 'cef'],
      'banco do brasil': ['banco do brasil', 'bb sa'],
      'c6': ['c6 bank', 'c6'],
      'pagbank': ['pagbank', 'pagseguro'],
      'mercado pago': ['mercado pago', 'mercadopago'],
      'btg': ['btg pactual', 'btg'],
      'sicredi': ['sicredi'],
      'sicoob': ['sicoob'],
    };

    for (final entry in bankKeywords.entries) {
      final found = entry.value.any((kw) => lower.contains(kw));
      if (found) {
        // Tenta achar conta do usuário cujo nome contenha o banco
        for (final acc in store.db.accounts) {
          final accName = acc.name.toLowerCase();
          if (accName.contains(entry.key) ||
              entry.value.any((kw) => accName.contains(kw))) {
            return acc.id;
          }
        }
      }
    }

    return '';
  }
}
