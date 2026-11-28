import '../models/agenda_models.dart';
import '../models/openmoney_models.dart';
import '../store/money_store.dart';

class AgendaGridDay {
  final String date; // "YYYY-MM-DD"
  final int dayNumber;
  final bool isCurrentMonth;
  final bool isToday;
  final List<AgendaEntry> entries;

  const AgendaGridDay({
    required this.date,
    required this.dayNumber,
    required this.isCurrentMonth,
    required this.isToday,
    required this.entries,
  });
}

class AgendaEngine {
  /// Gera o intervalo de datas (início e fim ISO) visíveis na grade de 7 colunas (Dom a Sáb).
  static ({String startDate, String endDate}) getMonthGridRange(String month) {
    final parts = month.split('-');
    final y = int.tryParse(parts[0]) ?? DateTime.now().year;
    final m = int.tryParse(parts[1]) ?? DateTime.now().month;

    final firstDay = DateTime(y, m, 1);
    // 7 = Domingo, 1 = Segunda ... 6 = Sábado
    // No grid onde Domingo é coluna 0:
    final leadingDays = firstDay.weekday % 7;
    final gridStart = firstDay.subtract(Duration(days: leadingDays));

    final lastDay = DateTime(y, m + 1, 0);
    final trailingDays = (6 - (lastDay.weekday % 7));
    final gridEnd = lastDay.add(Duration(days: trailingDays));

    return (
      startDate: _formatIso(gridStart),
      endDate: _formatIso(gridEnd),
    );
  }

  /// Retorna todas as entradas da Agenda visíveis para o mês especificado.
  static List<AgendaEntry> generateMonthEntries({
    required MoneyStore store,
    required String month,
    bool includeDone = false,
    Set<String>? accountIds,
  }) {
    final range = getMonthGridRange(month);
    final today = todayISO();
    final entries = <AgendaEntry>[];

    // Mapear contas e cartões
    final cardAccounts = <String, Account>{};
    final regularAccounts = <String, Account>{};
    for (final a in store.db.accounts) {
      if (a.type == kCardType && a.card != null) {
        cardAccounts[a.id] = a;
      } else {
        regularAccounts[a.id] = a;
      }
    }

    // 1. Processar Lançamentos de Contas Correntes / Dinheiro / Outras (não-cartão)
    for (final tx in store.db.txs) {
      if (cardAccounts.containsKey(tx.acc)) continue; // Lançamentos individuais de cartão não entram aqui

      // Filtrar por contas se selecionado
      if (accountIds != null && accountIds.isNotEmpty && !accountIds.contains(tx.acc)) {
        continue;
      }

      // Transferências internas neutras não são contas a pagar nem receitas
      if (tx.xfer != null && !tx.xfer!.startsWith('invpay:')) {
        continue;
      }

      // Filtrar concluídos se o usuário não quiser
      if (tx.rec && !includeDone) {
        continue;
      }

      // Se a data está fora da grade visível, ignorar
      if (tx.date.compareTo(range.startDate) < 0 || tx.date.compareTo(range.endDate) > 0) {
        continue;
      }

      final acc = store.accById(tx.acc);
      final accName = acc?.name ?? 'Conta';
      final currency = acc?.effectiveCurrency ?? store.baseCurrency;

      final isOverdue = !tx.rec && tx.date.compareTo(today) < 0;

      if (tx.amt < 0) {
        // Conta a pagar
        entries.add(
          AgendaEntry(
            id: tx.id,
            kind: AgendaEntryKind.bill,
            date: tx.date,
            title: tx.payee.isNotEmpty ? tx.payee : 'Conta a Pagar',
            category: tx.cat.isNotEmpty ? tx.cat : 'Despesas',
            accountName: accName,
            amountCents: tx.amt.abs(),
            currency: currency,
            isDone: tx.rec,
            isOverdue: isOverdue,
            tx: tx,
          ),
        );
      } else if (tx.amt > 0) {
        // Receita prevista
        entries.add(
          AgendaEntry(
            id: tx.id,
            kind: AgendaEntryKind.income,
            date: tx.date,
            title: tx.payee.isNotEmpty ? tx.payee : 'Receita Prevista',
            category: tx.cat.isNotEmpty ? tx.cat : 'Receitas',
            accountName: accName,
            amountCents: tx.amt,
            currency: currency,
            isDone: tx.rec,
            isOverdue: isOverdue,
            tx: tx,
          ),
        );
      }
    }

    // 2. Processar Faturas de Cartão de Crédito
    for (final card in cardAccounts.values) {
      if (accountIds != null && accountIds.isNotEmpty && !accountIds.contains(card.id)) {
        continue;
      }
      final cardCfg = card.card!;
      final invoices = card.invoices ?? {};
      final allInvoiceKeys = <String>{...invoices.keys};

      // Adicionar chave do ciclo atual e do mês visualizado para garantir cobertura
      allInvoiceKeys.add(invKeyFor(cardCfg, today));
      allInvoiceKeys.add(invKeyFor(cardCfg, '$month-01'));
      allInvoiceKeys.add(invKeyFor(cardCfg, '$month-15'));
      allInvoiceKeys.add(invKeyFor(cardCfg, range.startDate));
      allInvoiceKeys.add(invKeyFor(cardCfg, range.endDate));

      for (final ik in allInvoiceKeys) {
        final summary = store.invoiceSummary(card.id, ik);
        if (summary == null || summary.chargesCents == 0) continue;

        final dueDate = summary.dueDate;
        // Verificar se a data de vencimento da fatura cai dentro da grade do mês
        if (dueDate.compareTo(range.startDate) < 0 || dueDate.compareTo(range.endDate) > 0) {
          continue;
        }

        final isFullyPaid = summary.isFullyPaid || summary.remainingCents == 0;
        if (isFullyPaid && !includeDone) {
          continue;
        }

        final isVigente = isVigenteInvoice(
          cardCfg: cardCfg,
          invoiceKey: ik,
          account: card,
          today: today,
        );
        final isOverdue = !isFullyPaid && dueDate.compareTo(today) < 0 && isVigente;

        final amountCents = isFullyPaid ? summary.chargesCents : summary.remainingCents;

        entries.add(
          AgendaEntry(
            id: 'inv:${card.id}:$ik',
            kind: AgendaEntryKind.invoice,
            date: dueDate,
            title: 'Fatura ${card.name}',
            category: 'Cartão de Crédito',
            accountName: card.name,
            amountCents: amountCents,
            currency: card.effectiveCurrency,
            isDone: isFullyPaid,
            isOverdue: isOverdue,
            cardId: card.id,
            invoiceKey: ik,
            invoiceCloseDate: summary.closeDate,
            invoiceDueDate: dueDate,
            invoiceChargesCents: summary.chargesCents,
            invoicePaymentsCents: summary.paymentsCents,
            invoiceRemainingCents: summary.remainingCents,
          ),
        );
      }
    }

    // 3. Vencimentos de Renda Fixa e Tesouro Direto
    final investSummary = store.portfolioSummary();
    for (final p in investSummary.positions) {
      if (!p.hasOpenPosition || !p.asset.isFixedIncome) continue;
      final md = p.asset.maturityDate?.trim() ?? '';
      if (md.length < 10) continue;
      if (accountIds != null &&
          accountIds.isNotEmpty &&
          !accountIds.contains(p.asset.accountId)) {
        continue;
      }
      if (md.compareTo(range.startDate) < 0 ||
          md.compareTo(range.endDate) > 0) {
        continue;
      }
      final accName = store.accById(p.asset.accountId)?.name ?? 'Corretora';
      entries.add(
        AgendaEntry(
          id: 'invmat_${p.asset.id}',
          kind: AgendaEntryKind.income,
          date: md,
          title: 'Vencimento ${p.asset.displayCode}',
          category: 'Investimentos · ${p.asset.assetClass.label}',
          accountName: accName,
          amountCents: p.currentGrossValueCents,
          currency: p.asset.currency,
          isDone: false,
          isOverdue: md.compareTo(today) < 0,
          investAsset: p.asset,
        ),
      );
    }

    // Ordenar entradas: primeiro por data, depois pendentes antes de concluídos, faturas/contas antes de receitas
    entries.sort((a, b) {
      final dateComp = a.date.compareTo(b.date);
      if (dateComp != 0) return dateComp;
      if (a.isDone != b.isDone) return a.isDone ? 1 : -1;
      if (a.isPayable != b.isPayable) return a.isPayable ? -1 : 1;
      return b.amountCents.compareTo(a.amountCents);
    });

    return entries;
  }

  /// Calcula o resumo do mês com precisão (contas a pagar, a receber, atrasados e próxima receita).
  static AgendaMonthSummary calculateMonthSummary({
    required MoneyStore store,
    required String month,
    Set<String>? accountIds,
  }) {
    final today = todayISO();
    final baseCur = store.baseCurrency;

    int pendingPayCount = 0;
    int pendingPayTotalCents = 0;
    int pendingReceiveCount = 0;
    int pendingReceiveTotalCents = 0;

    // Próxima receita
    String? nextIncomeTitle;
    String? nextIncomeDate;
    int? nextIncomeAmountCents;

    // Atrasados gerais
    int overdueCount = 0;
    int overdueTotalCents = 0;

    // Usamos as entradas do mês alvo (sem filtrar concluídos inicialmente para saber tudo)
    final monthEntries = generateMonthEntries(
      store: store,
      month: month,
      includeDone: false,
      accountIds: accountIds,
    );

    // Identificar itens pertencentes ao mês estrito YYYY-MM
    final targetMonthPrefix = '$month-';

    AgendaEntry? nearestUpcomingIncome;

    for (final entry in monthEntries) {
      if (entry.isDone) continue;

      final valBase = store.convertToBase(
        entry.amountCents,
        entry.currency,
        txRateToBrl: entry.tx?.rate,
      );

      // Itens estritos do mês
      if (entry.date.startsWith(targetMonthPrefix)) {
        if (entry.isPayable) {
          pendingPayCount++;
          pendingPayTotalCents += valBase;
        } else if (entry.isIncome) {
          pendingReceiveCount++;
          pendingReceiveTotalCents += valBase;

          // Próxima receita
          if (entry.date.compareTo(today) >= 0) {
            if (nearestUpcomingIncome == null ||
                entry.date.compareTo(nearestUpcomingIncome.date) < 0) {
              nearestUpcomingIncome = entry;
            }
          }
        }
      }
    }

    if (nearestUpcomingIncome != null) {
      nextIncomeTitle = nearestUpcomingIncome.title;
      nextIncomeDate = nearestUpcomingIncome.date;
      nextIncomeAmountCents = nearestUpcomingIncome.amountCents;
    } else {
      // Se não há receita futura no mês, pega a última ou qualquer receita aberta do mês
      final anyIncome = monthEntries.where((e) => e.isIncome && !e.isDone).firstOrNull;
      if (anyIncome != null) {
        nextIncomeTitle = anyIncome.title;
        nextIncomeDate = anyIncome.date;
        nextIncomeAmountCents = anyIncome.amountCents;
      }
    }

    // Calcular atrasados consolidados usando dueBillsSummary do store (que já audita tudo até hoje)
    final dueSummary = store.dueBillsSummary(accountIds: accountIds);
    overdueCount = dueSummary.overdueCount;

    // Somar o total dos itens atrasados
    final overdueItems = store.dueBillItems(accountIds: accountIds).where((i) => i.isOverdue);
    for (final item in overdueItems) {
      if (item.isPayable) {
        overdueTotalCents += store.convertToBase(
          item.tx.amt.abs(),
          store.accById(item.tx.acc)?.effectiveCurrency ?? baseCur,
          txRateToBrl: item.tx.rate,
        );
      }
    }

    return AgendaMonthSummary(
      pendingPayCount: pendingPayCount,
      pendingPayTotalCents: pendingPayTotalCents,
      pendingReceiveCount: pendingReceiveCount,
      pendingReceiveTotalCents: pendingReceiveTotalCents,
      overdueCount: overdueCount,
      overdueTotalCents: overdueTotalCents,
      nextIncomeTitle: nextIncomeTitle,
      nextIncomeDate: nextIncomeDate,
      nextIncomeAmountCents: nextIncomeAmountCents,
      currency: baseCur,
    );
  }

  /// Constrói os blocos de dias da grade para renderização do calendário
  static List<AgendaGridDay> buildGridDays({
    required String month,
    required List<AgendaEntry> entries,
  }) {
    final range = getMonthGridRange(month);
    final today = todayISO();
    final targetMonthPrefix = '$month-';

    final entriesByDate = <String, List<AgendaEntry>>{};
    for (final e in entries) {
      entriesByDate.putIfAbsent(e.date, () => []).add(e);
    }

    final startDt = DateTime.parse(range.startDate);
    final endDt = DateTime.parse(range.endDate);

    final days = <AgendaGridDay>[];
    DateTime current = startDt;

    while (!current.isAfter(endDt)) {
      final iso = _formatIso(current);
      final isCurrentMonth = iso.startsWith(targetMonthPrefix);
      final isToday = iso == today;

      days.add(
        AgendaGridDay(
          date: iso,
          dayNumber: current.day,
          isCurrentMonth: isCurrentMonth,
          isToday: isToday,
          entries: entriesByDate[iso] ?? const [],
        ),
      );

      current = current.add(const Duration(days: 1));
    }

    return days;
  }

  static String _formatIso(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }
}
