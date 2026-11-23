class AgendaQuickParsedItem {
  final String title;
  final int amountCents; // Positivo para receita, negativo para despesa
  final String date; // YYYY-MM-DD
  final bool isIncome;

  const AgendaQuickParsedItem({
    required this.title,
    required this.amountCents,
    required this.date,
    required this.isIncome,
  });
}

class AgendaQuickParser {
  static const _incomeKeywords = [
    'receber',
    'recebimento',
    'salario',
    'salário',
    'rendimento',
    'rendimentos',
    'pro-labore',
    'pró-labore',
    'dividendo',
    'dividendos',
    'cliente',
    'venda',
    'reembolso',
    'lucro',
    'comissao',
    'comissão',
    'honorarios',
    'honorários',
    'freela',
    'freelance',
    'consultoria',
    'aluguel recebido',
  ];

  static const _weekdaysPt = {
    'domingo': 7,
    'dom': 7,
    'segunda': 1,
    'seg': 1,
    'segunda-feira': 1,
    'terça': 2,
    'terca': 2,
    'ter': 2,
    'terça-feira': 2,
    'terca-feira': 2,
    'quarta': 3,
    'qua': 3,
    'quarta-feira': 3,
    'quinta': 4,
    'qui': 4,
    'quinta-feira': 4,
    'sexta': 5,
    'sex': 5,
    'sexta-feira': 5,
    'sábado': 6,
    'sabado': 6,
    'sab': 6,
  };

  /// Converte uma frase em linguagem natural em um lançamento financeiro estruturado.
  static AgendaQuickParsedItem? parse(
    String input, {
    DateTime? referenceDate,
    String? fallbackMonth, // "YYYY-MM"
  }) {
    final raw = input.trim();
    if (raw.isEmpty) return null;

    final ref = referenceDate ?? DateTime.now();
    final today = DateTime(ref.year, ref.month, ref.day);

    String working = raw;

    // 1. Detectar se é receita ou despesa
    bool isIncome = false;
    final lower = working.toLowerCase();
    for (final kw in _incomeKeywords) {
      if (lower.contains(kw)) {
        isIncome = true;
        break;
      }
    }
    // Prefixos explícitos como "+" ou "receita:" ou "ganho:"
    if (working.startsWith('+') || lower.startsWith('receita:')) {
      isIncome = true;
      working = working.replaceFirst(RegExp(r'^\+\s*|^receita:\s*', caseSensitive: false), '');
    } else if (working.startsWith('-') || lower.startsWith('despesa:')) {
      isIncome = false;
      working = working.replaceFirst(RegExp(r'^\-\s*|^despesa:\s*', caseSensitive: false), '');
    }

    // 2. Extrair data
    DateTime? targetDate;

    // 2.1 "hoje"
    final hojeRegex = RegExp(r'(?:\b|\s)hoje(?:\b|\s|$)', caseSensitive: false);
    if (hojeRegex.hasMatch(working)) {
      targetDate = today;
      working = working.replaceAll(hojeRegex, ' ');
    }

    // 2.2 "depois de amanhã"
    final depoisAmanhaRegex = RegExp(r'(?:\b|\s)depois\s+de\s+amanh[aã](?:\b|\s|$)', caseSensitive: false);
    if (targetDate == null && depoisAmanhaRegex.hasMatch(working)) {
      targetDate = today.add(const Duration(days: 2));
      working = working.replaceAll(depoisAmanhaRegex, ' ');
    }

    // 2.3 "amanhã" / "amanha"
    final amanhaRegex = RegExp(r'(?:\b|\s)amanh[aã](?:\b|\s|$)', caseSensitive: false);
    if (targetDate == null && amanhaRegex.hasMatch(working)) {
      targetDate = today.add(const Duration(days: 1));
      working = working.replaceAll(amanhaRegex, ' ');
    }

    // 2.4 DD/MM/AAAA ou DD/MM
    final dateSlashRegex = RegExp(r'\b(\d{1,2})/(\d{1,2})(?:/(\d{2,4}))?\b');
    final slashMatch = dateSlashRegex.firstMatch(working);
    if (targetDate == null && slashMatch != null) {
      final d = int.tryParse(slashMatch.group(1)!) ?? 1;
      final m = int.tryParse(slashMatch.group(2)!) ?? 1;
      int y = today.year;
      if (slashMatch.group(3) != null) {
        final rawY = int.tryParse(slashMatch.group(3)!) ?? today.year;
        y = rawY < 100 ? 2000 + rawY : rawY;
      } else {
        // Se a data já passou neste ano, considera próximo ano caso seja muito retroativa (> 60 dias)
        final candidate = DateTime(y, m, d);
        if (candidate.isBefore(today.subtract(const Duration(days: 60)))) {
          y += 1;
        }
      }
      targetDate = DateTime(y, m, d);
      working = working.replaceFirst(slashMatch.group(0)!, ' ');
    }

    // 2.5 "dia DD" ou "vencimento DD"
    final diaRegex = RegExp(r'\b(?:dia|vencimento|vence(?:\s+no\s+dia)?)\s+(\d{1,2})\b', caseSensitive: false);
    final diaMatch = diaRegex.firstMatch(working);
    if (targetDate == null && diaMatch != null) {
      final dayNum = int.tryParse(diaMatch.group(1)!) ?? 1;
      int year = today.year;
      int month = today.month;

      if (fallbackMonth != null && fallbackMonth.length == 7 && fallbackMonth.contains('-')) {
        final parts = fallbackMonth.split('-');
        year = int.tryParse(parts[0]) ?? today.year;
        month = int.tryParse(parts[1]) ?? today.month;
      } else {
        // Se o dia já passou no mês atual, aponta para o próximo mês
        if (dayNum < today.day) {
          month += 1;
          if (month > 12) {
            month = 1;
            year += 1;
          }
        }
      }
      final maxDays = DateTime(year, month + 1, 0).day;
      final safeDay = dayNum.clamp(1, maxDays);
      targetDate = DateTime(year, month, safeDay);
      working = working.replaceFirst(diaMatch.group(0)!, ' ');
    }

    // 2.6 Dia da semana ("segunda", "sexta", etc.)
    if (targetDate == null) {
      for (final entry in _weekdaysPt.entries) {
        final escaped = RegExp.escape(entry.key);
        final wdRegex = RegExp('(^|\\s+)$escaped(\\s+|\$)', caseSensitive: false);
        if (wdRegex.hasMatch(working)) {
          final targetWd = entry.value; // 1 = seg, 7 = dom
          int diff = targetWd - today.weekday;
          if (diff <= 0) diff += 7; // Próxima ocorrência do dia da semana
          targetDate = today.add(Duration(days: diff));
          working = working.replaceAll(wdRegex, ' ');
          break;
        }
      }
    }

    // Se nenhuma data foi encontrada, usa hoje (ou fallbackMonth no dia 1)
    if (targetDate == null) {
      if (fallbackMonth != null && fallbackMonth.length == 7 && fallbackMonth.contains('-')) {
        final parts = fallbackMonth.split('-');
        final y = int.tryParse(parts[0]) ?? today.year;
        final m = int.tryParse(parts[1]) ?? today.month;
        targetDate = (y == today.year && m == today.month) ? today : DateTime(y, m, 1);
      } else {
        targetDate = today;
      }
    }

    // 3. Extrair valor monetário
    // Suporta: R$ 1.250,50, R$120, 1500,00, 350.00, 180, 50k (opcional)
    int? amountCents;
    final moneyRegex = RegExp(
      r'(?:R\$\s*)?(\d{1,3}(?:\.\d{3})*|\d+)(?:[,\.](\d{2}))?\b',
      caseSensitive: false,
    );

    // Procuramos o valor que faça mais sentido
    for (final match in moneyRegex.allMatches(working)) {
      final intPartStr = match.group(1)!.replaceAll('.', '');
      final decPartStr = match.group(2);
      final intPart = int.tryParse(intPartStr);
      if (intPart != null) {
        final decPart = decPartStr != null ? (int.tryParse(decPartStr) ?? 0) : 0;
        amountCents = (intPart * 100) + decPart;
        working = working.replaceFirst(match.group(0)!, ' ');
        break;
      }
    }

    // Se nenhum valor foi informado, assume 0
    amountCents ??= 0;

    // 4. Limpar o título restante
    String cleanTitle = working
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll(RegExp(r'^\s*[-+–—]\s*'), '')
        .trim();

    if (cleanTitle.isEmpty) {
      cleanTitle = isIncome ? 'Receita Prevista' : 'Conta a Pagar';
    }

    // Formatar data em ISO YYYY-MM-DD
    final yStr = targetDate.year.toString().padLeft(4, '0');
    final mStr = targetDate.month.toString().padLeft(2, '0');
    final dStr = targetDate.day.toString().padLeft(2, '0');
    final isoDate = '$yStr-$mStr-$dStr';

    final signedAmt = isIncome ? amountCents.abs() : -amountCents.abs();

    return AgendaQuickParsedItem(
      title: cleanTitle,
      amountCents: signedAmt,
      date: isoDate,
      isIncome: isIncome,
    );
  }
}
