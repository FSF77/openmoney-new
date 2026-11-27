import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../models/openmoney_models.dart';
import '../models/prediction_models.dart';
import '../store/money_store.dart';
import 'ofx_reconciliation_service.dart';
import 'investment_engine.dart';
import 'investment_insights_engine.dart';
import 'wallet_import_service.dart';

class PayeeSpikeDriver {
  final String payee;
  final int currentMonthCents;
  final int averagePrev3MonthsCents;
  final int deltaCents;
  final int txCount;
  final List<String> transactionIds;

  const PayeeSpikeDriver({
    required this.payee,
    required this.currentMonthCents,
    required this.averagePrev3MonthsCents,
    required this.deltaCents,
    required this.txCount,
    required this.transactionIds,
  });

  Map<String, dynamic> toJson({String currency = 'BRL'}) => {
        'payee': payee,
        'currentMonth': formatCurrency(currentMonthCents, currency),
        'averagePrev3Months': formatCurrency(averagePrev3MonthsCents, currency),
        'delta': formatCurrency(deltaCents, currency),
        'txCount': txCount,
      };
}

class CategorySpikeInsight {
  final String categoryPath;
  final int currentCents;
  final int previousMonthCents;
  final int average3MonthsCents;
  final int deltaVsAverageCents;
  final int deltaVsPrevMonthCents;
  final double percentVsAverage;
  final double percentVsPrevMonth;
  final int? budgetLimitCents;
  final int? predictionBaseCents;
  final bool isPredictionExhausted;
  final String currency;
  final List<PayeeSpikeDriver> topDrivers;

  const CategorySpikeInsight({
    required this.categoryPath,
    required this.currentCents,
    required this.previousMonthCents,
    required this.average3MonthsCents,
    required this.deltaVsAverageCents,
    required this.deltaVsPrevMonthCents,
    required this.percentVsAverage,
    required this.percentVsPrevMonth,
    this.budgetLimitCents,
    this.predictionBaseCents,
    this.isPredictionExhausted = false,
    required this.currency,
    required this.topDrivers,
  });

  bool get isOverBudget =>
      budgetLimitCents != null &&
      budgetLimitCents! > 0 &&
      currentCents > budgetLimitCents!;

  String buildSummarySentence() {
    String fmtCur(int c) => formatCurrency(c, currency);
    final sign = deltaVsAverageCents >= 0 ? '+' : '';
    final pct = percentVsAverage.round();
    final driversText = topDrivers.take(2).map((d) {
      return '${d.payee} (${fmtCur(d.currentMonthCents)})';
    }).join(' e ');
    if (driversText.isNotEmpty) {
      return '$categoryPath: ${fmtCur(currentCents)} ($sign$pct% vs média de 3 meses, $sign${fmtCur(deltaVsAverageCents)}), impulsionado por $driversText.';
    }
    return '$categoryPath: ${fmtCur(currentCents)} ($sign$pct% vs média de 3 meses).';
  }

  Map<String, dynamic> toJson() => {
        'categoryPath': categoryPath,
        'current': formatCurrency(currentCents, currency),
        'previousMonth': formatCurrency(previousMonthCents, currency),
        'average3Months': formatCurrency(average3MonthsCents, currency),
        'deltaVsAverage': formatCurrency(deltaVsAverageCents, currency),
        'percentVsAverage': double.parse(percentVsAverage.toStringAsFixed(1)),
        if (budgetLimitCents != null)
          'budgetLimit': formatCurrency(budgetLimitCents!, currency),
        if (predictionBaseCents != null)
          'predictionBase': formatCurrency(predictionBaseCents!, currency),
        if (isPredictionExhausted) 'isPredictionExhausted': true,
        'topDrivers': topDrivers
            .take(4)
            .map((d) => d.toJson(currency: currency))
            .toList(),
      };
}

class CardInvoiceAnalysis {
  final String cardId;
  final String cardName;
  final String invoiceKey;
  final String currency;
  final int totalInvoiceCents;
  final int spotPurchasesCents;
  final int installmentPurchasesCents;
  final int recurringPurchasesCents;
  final int previous3InvoicesAverageCents;
  final int deltaVsAverageCents;
  final double percentVsAverage;
  final Map<String, int> next3InvoicesCommittedCents;
  final List<({String payee, int amountCents, int count})> topPayees;
  final List<({String category, int amountCents})> topCategories;
  final String closeDateIso;
  final String dueDateIso;
  final bool isSettled;

  const CardInvoiceAnalysis({
    required this.cardId,
    required this.cardName,
    required this.invoiceKey,
    required this.currency,
    required this.totalInvoiceCents,
    required this.spotPurchasesCents,
    required this.installmentPurchasesCents,
    required this.recurringPurchasesCents,
    required this.previous3InvoicesAverageCents,
    required this.deltaVsAverageCents,
    required this.percentVsAverage,
    required this.next3InvoicesCommittedCents,
    required this.topPayees,
    required this.topCategories,
    required this.closeDateIso,
    required this.dueDateIso,
    required this.isSettled,
  });

  double get installmentSharePercent => totalInvoiceCents > 0
      ? (installmentPurchasesCents / totalInvoiceCents) * 100.0
      : 0.0;

  Map<String, dynamic> toJson() => {
        'cardId': cardId,
        'cardName': cardName,
        'invoiceKey': invoiceKey,
        'currency': currency,
        'totalInvoice': formatCurrency(totalInvoiceCents, currency),
        'spotPurchases': formatCurrency(spotPurchasesCents, currency),
        'installmentPurchases':
            formatCurrency(installmentPurchasesCents, currency),
        'recurringPurchases':
            formatCurrency(recurringPurchasesCents, currency),
        'installmentSharePercent':
            double.parse(installmentSharePercent.toStringAsFixed(1)),
        'previous3InvoicesAverage':
            formatCurrency(previous3InvoicesAverageCents, currency),
        'deltaVsAverage': formatCurrency(deltaVsAverageCents, currency),
        'percentVsAverage': double.parse(percentVsAverage.toStringAsFixed(1)),
        'next3InvoicesCommitted': {
          for (final entry in next3InvoicesCommittedCents.entries)
            entry.key: formatCurrency(entry.value, currency),
        },
        'closeDateIso': closeDateIso,
        'dueDateIso': dueDateIso,
        'isSettled': isSettled,
        'topPayees': topPayees
            .take(5)
            .map((e) => {
                  'payee': e.payee,
                  'amount': formatCurrency(e.amountCents, currency),
                  'count': e.count
                })
            .toList(),
        'topCategories': topCategories
            .take(5)
            .map((e) => {
                  'category': e.category,
                  'amount': formatCurrency(e.amountCents, currency),
                })
            .toList(),
      };
}

class RecurringCandidate {
  final String normalizedKey;
  final String displayPayee;
  final String accountId;
  final String accountName;
  final String category;
  final String currency;
  final String detectedFrequency; // 'weekly', 'biweekly', 'monthly', 'yearly'
  final int latestAmountCents; // signed cents
  final int previousAverageAmountCents; // signed cents
  final int priceChangeCents; // > 0 means expense became more expensive
  final double priceChangePercent;
  final int occurrencesCount;
  final String lastDateIso;
  final String predictedNextDateIso;
  final double confidence; // 0.0 .. 1.0
  final List<String> sampleTransactionIds;

  const RecurringCandidate({
    required this.normalizedKey,
    required this.displayPayee,
    required this.accountId,
    required this.accountName,
    required this.category,
    required this.currency,
    required this.detectedFrequency,
    required this.latestAmountCents,
    required this.previousAverageAmountCents,
    required this.priceChangeCents,
    required this.priceChangePercent,
    required this.occurrencesCount,
    required this.lastDateIso,
    required this.predictedNextDateIso,
    required this.confidence,
    required this.sampleTransactionIds,
  });

  bool get hasPriceIncrease => priceChangeCents > 50 && priceChangePercent >= 3.0;

  Map<String, dynamic> toJson() => {
        'payee': displayPayee,
        'accountId': accountId,
        'accountName': accountName,
        'category': category,
        'currency': currency,
        'freq': detectedFrequency,
        'latestAmount': formatCurrency(latestAmountCents.abs(), currency),
        'previousAverageAmount':
            formatCurrency(previousAverageAmountCents.abs(), currency),
        'priceChange': formatCurrency(priceChangeCents, currency),
        'priceChangePercent':
            double.parse(priceChangePercent.toStringAsFixed(1)),
        'occurrencesCount': occurrencesCount,
        'lastDateIso': lastDateIso,
        'predictedNextDateIso': predictedNextDateIso,
        'confidence': double.parse(confidence.toStringAsFixed(2)),
      };
}

class OrganizationOpportunity {
  final String kind; // 'uncategorized', 'duplicate', 'suggested_budget'
  final String title;
  final String subtitle;
  final List<String> transactionIds;
  final String? suggestedCategory;
  final String? suggestedPayee;
  final List<String>? suggestedTags;
  final int? suggestedBudgetCents;

  const OrganizationOpportunity({
    required this.kind,
    required this.title,
    required this.subtitle,
    required this.transactionIds,
    this.suggestedCategory,
    this.suggestedPayee,
    this.suggestedTags,
    this.suggestedBudgetCents,
  });

  Map<String, dynamic> toJson({String currency = 'BRL'}) => {
        'kind': kind,
        'title': title,
        'subtitle': subtitle,
        'txCount': transactionIds.length,
        'transactionIds': transactionIds.take(25).toList(),
        if (suggestedCategory != null) 'suggestedCategory': suggestedCategory,
        if (suggestedPayee != null) 'suggestedPayee': suggestedPayee,
        if (suggestedTags != null) 'suggestedTags': suggestedTags,
        if (suggestedBudgetCents != null)
          'suggestedBudget': formatCurrency(suggestedBudgetCents!, currency),
      };
}

class DocumentExtractedItem {
  final String dateIso;
  final String payee;
  final int signedAmountCents;
  final String category;
  final String accountId;
  final String memo;
  final int? installmentCurrent;
  final int? installmentTotal;
  final List<String> tags;
  final String? matchedExistingTxId;
  final bool isAlreadyReconciled;

  const DocumentExtractedItem({
    required this.dateIso,
    required this.payee,
    required this.signedAmountCents,
    required this.category,
    required this.accountId,
    this.memo = '',
    this.installmentCurrent,
    this.installmentTotal,
    this.tags = const [],
    this.matchedExistingTxId,
    this.isAlreadyReconciled = false,
  });

  bool get hasExistingMatch =>
      matchedExistingTxId != null && matchedExistingTxId!.isNotEmpty;
}

class AIQueryFilter {
  final String? startDate;
  final String? endDate;
  final String? accountId;
  final String? category;
  final String? tag;
  final String? searchText;
  final int limit;

  const AIQueryFilter({
    this.startDate,
    this.endDate,
    this.accountId,
    this.category,
    this.tag,
    this.searchText,
    this.limit = 35,
  });

  factory AIQueryFilter.fromJson(Map<String, dynamic> json) {
    return AIQueryFilter(
      startDate: json['startDate']?.toString(),
      endDate: json['endDate']?.toString(),
      accountId: json['accountId']?.toString(),
      category: json['category']?.toString(),
      tag: json['tag']?.toString(),
      searchText: json['searchText']?.toString(),
      limit: ((json['limit'] as num?)?.toInt() ?? 35).clamp(1, 80),
    );
  }
}

class FinancialInsightsEngine {
  FinancialInsightsEngine._();

  static final Map<String, String> _normPayeeCache = <String, String>{};
  static final RegExp _kParenInstallmentSuffix =
      RegExp(r'\s*\(\d{1,3}\s*/\s*\d{1,3}\)\s*$');
  static final RegExp _kSpaceInstallmentSuffix =
      RegExp(r'\s+\d{1,2}\s*/\s*\d{1,2}\s*$');
  static final RegExp _kTrailingDigitsSuffix = RegExp(r'\s+\d{4,}$');
  static final RegExp _kInstallmentOrAnticipatedRegex = RegExp(
    r'\(\d{1,3}\s*/\s*\d{1,3}\)|\b\d{1,2}\s*/\s*\d{1,2}\b|\bparc(?:ela)?\b|\bantecip',
    caseSensitive: false,
  );

  static String? _cachedSpikesSig;
  static List<CategorySpikeInsight>? _cachedSpikes;
  static String? _cachedRecsSig;
  static List<RecurringCandidate>? _cachedRecs;
  static String? _cachedOppsSig;
  static List<OrganizationOpportunity>? _cachedOpps;

  static String _buildStoreSignature(MoneyStore store, String ym) {
    // Invalidação O(1) baseada no contador de revisões do MoneyStore
    // (incrementado a cada save()/markIndexesDirty()/alteração remota).
    return '${identityHashCode(store)}_${identityHashCode(store.db)}_${ym}_${store.baseCurrency}_${store.dataRevision}_${store.db.txs.length}';
  }

  /// Verifica se um lançamento faz parte de parcelamento ou antecipação de parcelas.
  static bool isInstallmentOrAnticipated(Transaction t) {
    if (t.plan != null && t.plan!.trim().isNotEmpty) return true;
    if (t.pn != null || (t.pt != null && t.pt! > 1)) return true;
    if (_kInstallmentOrAnticipatedRegex.hasMatch(t.payee)) return true;
    if (t.memo.isNotEmpty && _kInstallmentOrAnticipatedRegex.hasMatch(t.memo)) {
      return true;
    }
    return false;
  }

  /// Normaliza o nome de um estabelecimento removendo sufixos de parcela "(1/10)",
  /// códigos finais numéricos e acentuação para agrupamento analítico.
  static String normalizePayeeForGrouping(String rawPayee) {
    final cached = _normPayeeCache[rawPayee];
    if (cached != null) return cached;
    var clean = rawPayee.trim();
    clean = clean.replaceAll(_kParenInstallmentSuffix, '');
    clean = clean.replaceAll(_kSpaceInstallmentSuffix, '');
    clean = OfxReconciliationService.normalizeText(clean);
    clean = clean.replaceAll(_kTrailingDigitsSuffix, '').trim();
    if (_normPayeeCache.length > 5000) {
      _normPayeeCache.clear();
    }
    _normPayeeCache[rawPayee] = clean;
    return clean;
  }

  static bool _shouldIncludeExpenseInAnalytics(
    Transaction tx,
    MoneyStore store, {
    Set<String>? accountFilterIds,
    String tagFilter = 'all',
  }) {
    if (tx.amt >= 0) return false;
    if (tx.auto == true) return false;
    if ((tx.xfer != null && tx.xfer!.isNotEmpty) ||
        (tx.peer != null && tx.peer!.isNotEmpty)) {
      return false;
    }
    if (isPredictionPayee(tx.payee)) return false;
    if (!store.isCategoryIncludedInReports(tx.cat)) return false;
    if (accountFilterIds != null &&
        accountFilterIds.isNotEmpty &&
        !accountFilterIds.contains(tx.acc)) {
      return false;
    }
    if (tagFilter != 'all') {
      final txTags = tx.tags ?? const <String>[];
      if (tagFilter == '__untagged__') {
        if (txTags.isNotEmpty) return false;
      } else {
        final normTarget = tagFilter.trim().toLowerCase();
        if (!txTags.any((t) => t.trim().toLowerCase() == normTarget)) {
          return false;
        }
      }
    }
    return true;
  }

  /// Retorna a competência mensal efetiva da transação (considerando `ik` para cartões de crédito).
  static String effectiveMonthForTx(Transaction tx, MoneyStore store) {
    final acc = store.accById(tx.acc);
    if (acc != null && acc.type == kCardType && acc.card != null) {
      if (tx.ik != null && tx.ik!.length >= 7) {
        return tx.ik!.substring(0, 7);
      }
      return invKeyFor(acc.card!, tx.date);
    }
    return tx.date.length >= 7 ? tx.date.substring(0, 7) : store.month;
  }

  /// 1. Explica aumentos em categorias (Spikes) no mês alvo comparado ao mês anterior e à média de 3 meses,
  /// detalhando quais favorecidos específicos puxaram a alta.
  static List<CategorySpikeInsight> explainCategorySpikes(
    MoneyStore store, {
    String? targetMonth,
    Set<String>? accountFilterIds,
    String tagFilter = 'all',
    double minIncreasePercent = 12.0,
    int minDeltaCents = 3000,
  }) {
    final ym = (targetMonth != null && targetMonth.length >= 7)
        ? targetMonth.substring(0, 7)
        : store.month;
    final isDefaultQuery = (accountFilterIds == null || accountFilterIds.isEmpty) &&
        tagFilter == 'all' &&
        minIncreasePercent == 12.0 &&
        minDeltaCents == 3000;
    final sig = isDefaultQuery ? _buildStoreSignature(store, ym) : null;
    if (sig != null && sig == _cachedSpikesSig && _cachedSpikes != null) {
      return _cachedSpikes!;
    }
    final prev1 = addMonthsYM(ym, -1);
    final prev2 = addMonthsYM(ym, -2);
    final prev3 = addMonthsYM(ym, -3);
    final prevMonths = <String>{prev1, prev2, prev3};
    final baseCur = store.baseCurrency;

    // Mapa: categoryPath -> month -> totalCents
    final catMonthTotals = <String, Map<String, int>>{};
    // Mapa: categoryPath -> normPayee -> {display, currentCents, prevTotalCents, txIds}
    final catPayeeMap = <String,
        Map<
            String,
            ({
              String display,
              int currentCents,
              int prev3TotalCents,
              List<String> txIds,
            })>>{};

    for (final tx in store.db.txs) {
      if (!_shouldIncludeExpenseInAnalytics(
        tx,
        store,
        accountFilterIds: accountFilterIds,
        tagFilter: tagFilter,
      )) {
        continue;
      }
      final txYm = effectiveMonthForTx(tx, store);
      if (txYm != ym && !prevMonths.contains(txYm)) continue;

      final cat = tx.cat.trim().isEmpty ? 'Sem Categoria' : tx.cat.trim();
      final valBase = store.convertTxToCurrency(tx, baseCur).abs();

      final mMap = catMonthTotals.putIfAbsent(cat, () => <String, int>{});
      mMap[txYm] = (mMap[txYm] ?? 0) + valBase;

      final pMap = catPayeeMap.putIfAbsent(cat, () => {});
      final normP = normalizePayeeForGrouping(tx.payee);
      final key = normP.isEmpty ? 'outros' : normP;
      final existing = pMap[key];
      final cleanDisplay = tx.payee
          .replaceAll(RegExp(r'\s*\(\d{1,3}\s*/\s*\d{1,3}\)\s*$'), '')
          .trim();

      if (existing == null) {
        pMap[key] = (
          display: cleanDisplay.isEmpty ? 'Sem Favorecido' : cleanDisplay,
          currentCents: txYm == ym ? valBase : 0,
          prev3TotalCents: prevMonths.contains(txYm) ? valBase : 0,
          txIds: txYm == ym ? <String>[tx.id] : <String>[],
        );
      } else {
        pMap[key] = (
          display: existing.display,
          currentCents: existing.currentCents + (txYm == ym ? valBase : 0),
          prev3TotalCents: existing.prev3TotalCents +
              (prevMonths.contains(txYm) ? valBase : 0),
          txIds: txYm == ym
              ? (<String>[...existing.txIds, tx.id])
              : existing.txIds,
        );
      }
    }

    final predReport = store.getPredictionsReport(ym);
    final predByCat = <String, PredictionCategoryGroup>{
      for (final g in predReport.groups) g.category: g,
    };

    final insights = <CategorySpikeInsight>[];

    catMonthTotals.forEach((cat, mMap) {
      final cur = mMap[ym] ?? 0;
      if (cur <= 0) return;

      final p1 = mMap[prev1] ?? 0;
      final p2 = mMap[prev2] ?? 0;
      final p3 = mMap[prev3] ?? 0;

      // Calcula a média dos últimos 3 meses (considerando meses ativos ou divisor 3)
      final activePrevCount =
          (p1 > 0 ? 1 : 0) + (p2 > 0 ? 1 : 0) + (p3 > 0 ? 1 : 0);
      final avg3 =
          activePrevCount > 0 ? ((p1 + p2 + p3) / activePrevCount).round() : 0;

      final deltaAvg = cur - avg3;
      final deltaPrev = cur - p1;
      final pctAvg = avg3 > 0 ? ((cur - avg3) / avg3) * 100.0 : 100.0;
      final pctPrev = p1 > 0 ? ((cur - p1) / p1) * 100.0 : 100.0;

      int? budget = store.db.budgets[cat];
      if ((budget == null || budget <= 0) && cat.contains(kCategorySep)) {
        final parent = cat.split(kCategorySep).first;
        budget = store.db.budgets[parent];
      }

      final predGroup = predByCat[cat];
      final isOverBudget = budget != null && budget > 0 && cur > budget;
      final isPredExhausted = predGroup != null &&
          predGroup.predictions.any((p) => p.isExhausted);

      final hasSignificantSpike =
          (avg3 > 0 && pctAvg >= minIncreasePercent && deltaAvg >= minDeltaCents) ||
              (p1 > 0 &&
                  pctPrev >= minIncreasePercent &&
                  deltaPrev >= minDeltaCents) ||
              (avg3 == 0 && cur >= minDeltaCents * 2);

      if (!hasSignificantSpike && !isOverBudget && !isPredExhausted) {
        return;
      }

      final pMap = catPayeeMap[cat] ?? {};
      final drivers = <PayeeSpikeDriver>[];
      pMap.forEach((_, info) {
        if (info.currentCents <= 0) return;
        final pAvg = activePrevCount > 0
            ? (info.prev3TotalCents / activePrevCount).round()
            : 0;
        drivers.add(
          PayeeSpikeDriver(
            payee: info.display,
            currentMonthCents: info.currentCents,
            averagePrev3MonthsCents: pAvg,
            deltaCents: info.currentCents - pAvg,
            txCount: info.txIds.length,
            transactionIds: info.txIds,
          ),
        );
      });

      drivers.sort((a, b) {
        final cmp = b.deltaCents.compareTo(a.deltaCents);
        if (cmp != 0) return cmp;
        return b.currentMonthCents.compareTo(a.currentMonthCents);
      });

      insights.add(
        CategorySpikeInsight(
          categoryPath: cat,
          currentCents: cur,
          previousMonthCents: p1,
          average3MonthsCents: avg3,
          deltaVsAverageCents: deltaAvg,
          deltaVsPrevMonthCents: deltaPrev,
          percentVsAverage: pctAvg,
          percentVsPrevMonth: pctPrev,
          budgetLimitCents: (budget != null && budget > 0) ? budget : null,
          predictionBaseCents: predGroup?.totalBaseCents,
          isPredictionExhausted: isPredExhausted,
          currency: baseCur,
          topDrivers: drivers,
        ),
      );
    });

    insights.sort((a, b) => b.deltaVsAverageCents.compareTo(a.deltaVsAverageCents));
    if (sig != null) {
      _cachedSpikesSig = sig;
      _cachedSpikes = insights;
    }
    return insights;
  }

  /// 2. Análise completa de fatura de cartão de crédito (composição à vista vs parcelado vs recorrente,
  /// comparação com as 3 faturas anteriores e projeção das próximas 3 faturas).
  static CardInvoiceAnalysis? analyzeCardInvoice(
    MoneyStore store, {
    required String cardId,
    String? invoiceKey,
  }) {
    final acc = store.accById(cardId);
    if (acc == null || acc.type != kCardType || acc.card == null) return null;

    final targetIk = (invoiceKey != null && invoiceKey.length >= 7)
        ? invoiceKey.substring(0, 7)
        : store.month;
    final summary = store.invoiceSummary(cardId, targetIk);
    final txs = store.invoiceTransactions(cardId, targetIk);
    final cur = acc.effectiveCurrency;

    int totalCents = 0;
    int spotCents = 0;
    int installmentCents = 0;
    int recurringCents = 0;

    final payeeTotals = <String, ({String display, int cents, int count})>{};
    final catTotals = <String, int>{};

    for (final tx in txs) {
      if (tx.auto == true || tx.amt >= 0) continue;
      if (isPredictionPayee(tx.payee)) continue;
      final absAmt = tx.amt.abs();
      totalCents += absAmt;

      if ((tx.pt ?? 1) > 1) {
        installmentCents += absAmt;
      } else if (tx.recId != null && tx.recId!.isNotEmpty) {
        recurringCents += absAmt;
      } else {
        spotCents += absAmt;
      }

      final normP = normalizePayeeForGrouping(tx.payee);
      final key = normP.isEmpty ? 'outros' : normP;
      final cleanName = tx.payee
          .replaceAll(RegExp(r'\s*\(\d{1,3}\s*/\s*\d{1,3}\)\s*$'), '')
          .trim();
      final prevP = payeeTotals[key];
      payeeTotals[key] = (
        display: prevP?.display ?? (cleanName.isEmpty ? tx.payee : cleanName),
        cents: (prevP?.cents ?? 0) + absAmt,
        count: (prevP?.count ?? 0) + 1,
      );

      final cat = tx.cat.trim().isEmpty ? 'Sem Categoria' : tx.cat.trim();
      catTotals[cat] = (catTotals[cat] ?? 0) + absAmt;
    }

    // Média das 3 faturas anteriores
    int prevSum = 0;
    int prevCount = 0;
    for (int i = 1; i <= 3; i++) {
      final pIk = addMonthsYM(targetIk, -i);
      final pTxs = store.invoiceTransactions(cardId, pIk);
      int pTotal = 0;
      for (final t in pTxs) {
        if (t.auto == true || t.amt >= 0 || isPredictionPayee(t.payee)) continue;
        pTotal += t.amt.abs();
      }
      if (pTotal > 0) {
        prevSum += pTotal;
        prevCount++;
      }
    }
    final avgPrev3 = prevCount > 0 ? (prevSum / prevCount).round() : 0;
    final deltaAvg = totalCents - avgPrev3;
    final pctAvg = avgPrev3 > 0 ? ((totalCents - avgPrev3) / avgPrev3) * 100.0 : 0.0;

    // Comprometimento contratado nas próximas 3 faturas
    final next3Committed = <String, int>{};
    for (int i = 1; i <= 3; i++) {
      final fIk = addMonthsYM(targetIk, i);
      final fTxs = store.invoiceTransactions(cardId, fIk);
      int fTotal = 0;
      for (final t in fTxs) {
        if (t.auto == true || t.amt >= 0 || isPredictionPayee(t.payee)) continue;
        fTotal += t.amt.abs();
      }
      next3Committed[fIk] = fTotal;
    }

    final sortedPayees = payeeTotals.values
        .map((e) => (payee: e.display, amountCents: e.cents, count: e.count))
        .toList()
      ..sort((a, b) => b.amountCents.compareTo(a.amountCents));

    final sortedCats = catTotals.entries
        .map((e) => (category: e.key, amountCents: e.value))
        .toList()
      ..sort((a, b) => b.amountCents.compareTo(a.amountCents));

    return CardInvoiceAnalysis(
      cardId: cardId,
      cardName: acc.name,
      invoiceKey: targetIk,
      currency: cur,
      totalInvoiceCents: totalCents,
      spotPurchasesCents: spotCents,
      installmentPurchasesCents: installmentCents,
      recurringPurchasesCents: recurringCents,
      previous3InvoicesAverageCents: avgPrev3,
      deltaVsAverageCents: deltaAvg,
      percentVsAverage: pctAvg,
      next3InvoicesCommittedCents: next3Committed,
      topPayees: sortedPayees,
      topCategories: sortedCats,
      closeDateIso: summary?.closeDate ?? '',
      dueDateIso: summary?.dueDate ?? '',
      isSettled: summary?.isFullyPaid ?? false,
    );
  }

  /// 3. Identifica recorrências/assinaturas implícitas em `db.txs` que ainda não possuem `RecurrenceRule`
  /// e detecta eventuais reajustes de preço na cobrança mais recente.
  static List<RecurringCandidate> detectImplicitRecurrences(
    MoneyStore store, {
    int lookbackDays = 370,
  }) {
    final sig = lookbackDays == 370
        ? _buildStoreSignature(store, store.month)
        : null;
    if (sig != null && sig == _cachedRecsSig && _cachedRecs != null) {
      return _cachedRecs!;
    }
    final now = DateTime.now();
    final cutoff = now.subtract(Duration(days: lookbackDays));
    final cutoffIso =
        '${cutoff.year.toString().padLeft(4, '0')}-${cutoff.month.toString().padLeft(2, '0')}-${cutoff.day.toString().padLeft(2, '0')}';

    // Conjunto de favorecidos que já possuem regra explícita em db.recs
    final existingRecPayees = store.db.recs
        .map((r) => normalizePayeeForGrouping(r.payee))
        .where((s) => s.isNotEmpty)
        .toSet();

    // Agrupa lançamentos elegíveis por favorecido normalizado
    final groups = <String, List<Transaction>>{};
    for (final tx in store.db.txs) {
      if (tx.date.compareTo(cutoffIso) < 0) continue;
      if (tx.auto == true) continue;
      if (tx.recId != null && tx.recId!.isNotEmpty) continue;
      if ((tx.xfer != null && tx.xfer!.isNotEmpty) ||
          (tx.peer != null && tx.peer!.isNotEmpty)) {
        continue;
      }
      if ((tx.pt ?? 1) > 1 || (tx.plan != null && tx.plan!.isNotEmpty)) {
        // Exclui compras parceladas para nunca confundir parcela com assinatura
        continue;
      }
      if (isPredictionPayee(tx.payee)) continue;
      if (tx.amt == 0) continue;

      final norm = normalizePayeeForGrouping(tx.payee);
      if (norm.length < 3) continue;
      if (existingRecPayees.contains(norm)) continue;

      groups.putIfAbsent(norm, () => <Transaction>[]).add(tx);
    }

    final candidates = <RecurringCandidate>[];

    groups.forEach((normKey, list) {
      if (list.length < 2) return;

      // Ordena cronologicamente
      list.sort((a, b) => a.date.compareTo(b.date));

      // Colapsa lançamentos no mesmo dia e filtra apenas o mesmo sinal (despesa ou receita predominante)
      final expenses = list.where((t) => t.amt < 0).toList();
      final incomes = list.where((t) => t.amt > 0).toList();
      final working = expenses.length >= incomes.length ? expenses : incomes;
      if (working.length < 2) return;

      final dates = <DateTime>[];
      final dedupTxs = <Transaction>[];
      for (final tx in working) {
        final dt = DateTime.tryParse(tx.date);
        if (dt == null) continue;
        if (dates.isNotEmpty &&
            dates.last.difference(dt).inDays.abs() <= 2) {
          continue;
        }
        dates.add(dt);
        dedupTxs.add(tx);
      }

      if (dedupTxs.length < 2) return;

      final intervals = <int>[];
      for (int i = 1; i < dates.length; i++) {
        intervals.add(dates[i].difference(dates[i - 1]).inDays);
      }
      final avgInterval =
          intervals.reduce((a, b) => a + b) / intervals.length.toDouble();

      // Verifica desvio padrão dos intervalos
      double variance = 0;
      for (final iv in intervals) {
        variance += (iv - avgInterval) * (iv - avgInterval);
      }
      final stdDev = sqrt(variance / intervals.length);

      String? detectedFreq;
      int stepDays = 30;
      if (avgInterval >= 5 && avgInterval <= 9 && stdDev <= 3.0) {
        detectedFreq = 'weekly';
        stepDays = 7;
      } else if (avgInterval >= 12 && avgInterval <= 18 && stdDev <= 4.0) {
        detectedFreq = 'biweekly';
        stepDays = 15;
      } else if (avgInterval >= 25 && avgInterval <= 36 && stdDev <= 6.5) {
        detectedFreq = 'monthly';
        stepDays = 30;
      } else if (avgInterval >= 345 && avgInterval <= 385 && stdDev <= 15.0) {
        detectedFreq = 'yearly';
        stepDays = 365;
      }

      if (detectedFreq == null) return;

      // Verifica consistência de valor (evita agrupar supermercado aleatório como assinatura fixa se variar mais de 65%)
      final absAmounts = dedupTxs.map((t) => t.amt.abs()).toList();
      final avgAbs =
          absAmounts.reduce((a, b) => a + b) / absAmounts.length.toDouble();
      final maxDiff =
          absAmounts.map((a) => (a - avgAbs).abs()).reduce(max).toDouble();
      if (avgAbs > 0 && (maxDiff / avgAbs) > 0.55) {
        return;
      }

      final latestTx = dedupTxs.last;
      final prevTxs = dedupTxs.sublist(0, dedupTxs.length - 1);
      final prevAvgAbs = (prevTxs
                  .map((t) => t.amt.abs())
                  .reduce((a, b) => a + b) /
              prevTxs.length)
          .round();
      final latestAbs = latestTx.amt.abs();
      final priceChangeCents = latestAbs - prevAvgAbs;
      final priceChangePct =
          prevAvgAbs > 0 ? ((latestAbs - prevAvgAbs) / prevAvgAbs) * 100.0 : 0.0;

      final acc = store.accById(latestTx.acc);
      final nextDate = detectedFreq == 'monthly'
          ? addMonthsDate(latestTx.date, 1)
          : detectedFreq == 'yearly'
              ? addMonthsDate(latestTx.date, 12)
              : () {
                  final dt = DateTime.tryParse(latestTx.date) ?? now;
                  final nxt = dt.add(Duration(days: stepDays));
                  return '${nxt.year.toString().padLeft(4, '0')}-${nxt.month.toString().padLeft(2, '0')}-${nxt.day.toString().padLeft(2, '0')}';
                }();

      final conf = min(
        0.98,
        0.60 +
            (dedupTxs.length >= 3 ? 0.22 : 0.08) +
            (stdDev <= 2.5 ? 0.12 : 0.04),
      );

      candidates.add(
        RecurringCandidate(
          normalizedKey: normKey,
          displayPayee: latestTx.payee.trim(),
          accountId: latestTx.acc,
          accountName: acc?.name ?? 'Conta',
          category: latestTx.cat,
          currency: acc?.effectiveCurrency ?? store.baseCurrency,
          detectedFrequency: detectedFreq,
          latestAmountCents: latestTx.amt,
          previousAverageAmountCents:
              latestTx.amt < 0 ? -prevAvgAbs : prevAvgAbs,
          priceChangeCents: priceChangeCents,
          priceChangePercent: priceChangePct,
          occurrencesCount: dedupTxs.length,
          lastDateIso: latestTx.date,
          predictedNextDateIso: nextDate,
          confidence: conf,
          sampleTransactionIds: dedupTxs.map((t) => t.id).toList(),
        ),
      );
    });

    candidates.sort((a, b) {
      if (a.hasPriceIncrease != b.hasPriceIncrease) {
        return a.hasPriceIncrease ? -1 : 1;
      }
      final cmp = b.occurrencesCount.compareTo(a.occurrencesCount);
      if (cmp != 0) return cmp;
      return b.latestAmountCents.abs().compareTo(a.latestAmountCents.abs());
    });

    if (sig != null) {
      _cachedRecsSig = sig;
      _cachedRecs = candidates;
    }
    return candidates;
  }

  /// 4. Encontra oportunidades de organização da base (sem categoria, duplicatas prováveis, etc.).
  static List<OrganizationOpportunity> findOrganizationOpportunities(
    MoneyStore store, {
    String? targetMonth,
  }) {
    final ym = targetMonth ?? store.month;
    final sig = _buildStoreSignature(store, ym);
    if (sig == _cachedOppsSig && _cachedOpps != null) {
      return _cachedOpps!;
    }
    final opportunities = <OrganizationOpportunity>[];

    // A) Lançamentos sem categoria agrupados por favorecido
    final uncatByPayee = <String, List<Transaction>>{};
    for (final tx in store.db.txs) {
      if (tx.auto == true ||
          tx.xfer != null ||
          tx.peer != null ||
          isPredictionPayee(tx.payee)) {
        continue;
      }
      if (tx.cat.trim().isEmpty ||
          tx.cat.trim().toLowerCase() == 'sem categoria') {
        final norm = normalizePayeeForGrouping(tx.payee);
        if (norm.isEmpty) continue;
        uncatByPayee.putIfAbsent(norm, () => <Transaction>[]).add(tx);
      }
    }

    uncatByPayee.forEach((_, list) {
      final samplePayee = list.first.payee.trim();
      final suggestion = store.lastCategoryAndType(samplePayee);
      final suggestedCat = (suggestion != null &&
              suggestion.category.trim().isNotEmpty &&
              suggestion.category.toLowerCase() != 'sem categoria')
          ? suggestion.category
          : null;
      opportunities.add(
        OrganizationOpportunity(
          kind: 'uncategorized',
          title:
              'Classificar ${list.length} lançamento(s) de "$samplePayee"',
          subtitle: suggestedCat != null
              ? 'Sugestão pelo histórico: $suggestedCat'
              : 'Lançamentos estão sem categoria definida.',
          transactionIds: list.map((t) => t.id).toList(),
          suggestedCategory: suggestedCat,
          suggestedPayee: samplePayee,
        ),
      );
    });

    // B) Possíveis duplicidades reais no mês selecionado:
    // Ignora obrigatoriamente lançamentos já conciliados (t.rec == true),
    // lançamentos importados via OFX (fitid), transferências, automáticos,
    // compras parceladas e antecipações de parcelas.
    final monthTxs = store.db.txs
        .where((t) =>
            t.auto != true &&
            !t.rec &&
            t.xfer == null &&
            t.peer == null &&
            (t.fitid == null || t.fitid!.isEmpty) &&
            !isInstallmentOrAnticipated(t) &&
            !isPredictionPayee(t.payee) &&
            effectiveMonthForTx(t, store) == ym)
        .toList();

    final visitedIds = <String>{};
    for (int i = 0; i < monthTxs.length; i++) {
      final a = monthTxs[i];
      if (visitedIds.contains(a.id)) continue;
      final rawPayeeA = a.payee.trim().toLowerCase();
      if (rawPayeeA.isEmpty) continue;

      final dupGroup = <Transaction>[a];
      for (int j = i + 1; j < monthTxs.length; j++) {
        final b = monthTxs[j];
        if (visitedIds.contains(b.id)) continue;
        if (a.acc != b.acc || a.amt != b.amt || a.date != b.date) continue;
        if (b.payee.trim().toLowerCase() != rawPayeeA) continue;
        dupGroup.add(b);
        visitedIds.add(b.id);
      }

      if (dupGroup.length > 1) {
        visitedIds.add(a.id);
        final acc = store.accById(a.acc);
        final fmtAmt = formatCurrency(
          a.amt.abs(),
          acc?.effectiveCurrency ?? store.baseCurrency,
        );
        opportunities.add(
          OrganizationOpportunity(
            kind: 'duplicate',
            title:
                'Possível duplicidade não conciliada: ${a.payee} ($fmtAmt em ${fmtDate(a.date)})',
            subtitle:
                '${dupGroup.length} lançamentos idênticos em aberto na mesma data na conta ${acc?.name ?? a.acc}.',
            transactionIds: dupGroup.map((t) => t.id).toList(),
          ),
        );
      }
    }

    _cachedOppsSig = sig;
    _cachedOpps = opportunities;
    return opportunities;
  }

  /// 5. Reconcilia itens extraídos de documento (PDF, imagem, fatura, extrato) contra `store.db.txs`,
  /// reutilizando as regras determinísticas da ADR 027 (evitando duplicar itens já lançados).
  static List<DocumentExtractedItem> reconcileExtractedDocumentItems(
    MoneyStore store, {
    required List<Map<String, dynamic>> rawItems,
    String? defaultAccountId,
  }) {
    final usedTxIds = <String>{};
    final result = <DocumentExtractedItem>[];

    for (final raw in rawItems) {
      final rawPayee = (raw['payee'] ?? raw['description'] ?? '').toString().trim();
      if (rawPayee.isEmpty) continue;

      // Ignora linha de pagamento da própria fatura anterior (ADR 027)
      final normPayee = OfxReconciliationService.normalizeText(rawPayee);
      if (normPayee.contains('pagamento recebido') ||
          normPayee.contains('pagamento de fatura') ||
          normPayee.contains('debito automatico fatura')) {
        continue;
      }

      final dateIso = (raw['date'] ?? todayISO()).toString().trim();
      final isExpense = raw['is_expense'] as bool? ??
          raw['isExpense'] as bool? ??
          ((raw['amount_cents'] as num? ?? raw['amountCents'] as num? ?? 0) <= 0);
      final rawCents =
          ((raw['amount_cents'] ?? raw['amountCents'] ?? 0) as num).toInt().abs();
      if (rawCents <= 0) continue;
      final signedCents = isExpense ? -rawCents : rawCents;

      // Resolve conta (4-tier ou defaultAccountId)
      final rawAccHint =
          (raw['detected_bank'] ?? raw['account'] ?? raw['accountId'] ?? '')
              .toString()
              .trim();
      String resolvedAccId = defaultAccountId ?? '';
      if (resolvedAccId.isEmpty ||
          store.accById(resolvedAccId) == null) {
        if (rawAccHint.isNotEmpty) {
          final byId = store.accById(rawAccHint);
          if (byId != null) {
            resolvedAccId = byId.id;
          } else {
            final resolvedAcc =
                WalletImportService.resolveAccount(rawAccHint, store.db.accounts);
            final matched = resolvedAcc.autoMatched
                ? resolvedAcc.accountId
                : store.lastCategoryAndType(rawPayee)?.accountId;
            if (matched != null && matched.isNotEmpty) {
              resolvedAccId = matched;
            }
          }
        }
        if (resolvedAccId.isEmpty) {
          resolvedAccId = store.selectedAccountId.isNotEmpty
              ? store.selectedAccountId
              : (store.activeAccounts.isNotEmpty
                  ? store.activeAccounts.first.id
                  : (store.db.accounts.isNotEmpty
                      ? store.db.accounts.first.id
                      : 'a1'));
        }
      }

      // Resolve categoria (sugerida pela IA ou pelo histórico local)
      String category = (raw['category'] ?? '').toString().trim();
      final hist = store.lastCategoryAndType(rawPayee);
      if (category.isEmpty && hist != null && hist.category.isNotEmpty) {
        category = hist.category;
      }
      if (category.isEmpty) {
        final fallbackCats =
            store.allCategoryPaths(isExpense ? 'Despesa' : 'Receita');
        category = fallbackCats.isNotEmpty ? fallbackCats.first : 'Outros';
      }

      final pn = (raw['pn'] ?? raw['installmentCurrent'] as num?)?.toInt();
      final pt = (raw['pt'] ?? raw['installmentTotal'] as num?)?.toInt();
      final tags = <String>[
        if (raw['tags'] is List)
          ...(raw['tags'] as List).map((e) => e.toString().trim()).where((e) => e.isNotEmpty),
      ];

      // Pareamento 1-para-1 determinístico contra lançamentos existentes na conta
      String? matchedId;
      bool alreadyReconciled = false;
      final itemDate = DateTime.tryParse(dateIso);
      final acc = store.accById(resolvedAccId);
      final isCard = acc?.type == kCardType && acc?.card != null;
      final targetIk =
          (isCard && dateIso.length == 10) ? invKeyFor(acc!.card!, dateIso) : null;

      int bestScore = -1;
      for (final tx in store.accountTransactions(resolvedAccId)) {
        if (usedTxIds.contains(tx.id)) continue;
        if (tx.auto == true || isPredictionPayee(tx.payee)) continue;
        if (tx.amt != signedCents) continue;

        int score = 0;
        final txDate = DateTime.tryParse(tx.date);
        int daysDiff = 999;
        if (itemDate != null && txDate != null) {
          daysDiff = itemDate.difference(txDate).inDays.abs();
        }

        if (daysDiff <= 4) {
          score += 50 - (daysDiff * 8);
        } else if (isCard &&
            targetIk != null &&
            effectiveMonthForTx(tx, store) == targetIk) {
          score += 25;
        } else {
          continue;
        }

        if (pn != null && pt != null && tx.pn == pn && tx.pt == pt) {
          score += 35;
        }

        final txNorm = normalizePayeeForGrouping(tx.payee);
        if (txNorm.isNotEmpty &&
            normPayee.isNotEmpty &&
            (txNorm.contains(normPayee) || normPayee.contains(txNorm))) {
          score += 30;
        }

        if (score > bestScore && score >= 35) {
          bestScore = score;
          matchedId = tx.id;
          alreadyReconciled = tx.rec;
        }
      }

      if (matchedId != null) {
        usedTxIds.add(matchedId);
      }

      result.add(
        DocumentExtractedItem(
          dateIso: dateIso,
          payee: rawPayee,
          signedAmountCents: signedCents,
          category: category,
          accountId: resolvedAccId,
          memo: (raw['memo'] ?? '').toString().trim(),
          installmentCurrent: pn,
          installmentTotal: pt,
          tags: tags,
          matchedExistingTxId: matchedId,
          isAlreadyReconciled: alreadyReconciled,
        ),
      );
    }

    return result;
  }

  /// 6. Constrói o snapshot compacto (< 4 KB) para contextualizar os modelos de IA sem expor a base bruta.
  static Map<String, dynamic> buildCompactContextSnapshot(
    MoneyStore store, {
    String? focusMonth,
    String? focusAccountId,
    String? focusCategory,
  }) {
    final ym = focusMonth ?? store.month;
    final baseCur = store.baseCurrency;
    final report = store.buildMonthlyReport(ym);
    final spikes = explainCategorySpikes(store, targetMonth: ym);
    final recurrences = detectImplicitRecurrences(store);
    final dueSummary = store.dueBillsSummary(withinDays: 14);
    final predReport = store.getPredictionsReport(ym);

    final activeAccs = store.db.accounts
        .where((a) => !a.isInactive)
        .map((a) {
          final cur = a.effectiveCurrency;
          return {
            'id': a.id,
            'name': a.name,
            'type': a.type,
            'currency': cur,
            'realBalance': formatCurrency(store.balance(a, predicted: false), cur),
            'predictedBalance':
                formatCurrency(store.balance(a, predicted: true), cur),
            if (a.type == kCardType && a.card != null)
              'currentInvoiceKey': invKeyFor(a.card!, todayISO()),
          };
        })
        .toList();

    final cardAnalyses = <Map<String, dynamic>>[];
    for (final a in store.db.accounts) {
      if (a.isInactive || a.type != kCardType || a.card == null) continue;
      final invAnalysis = analyzeCardInvoice(
        store,
        cardId: a.id,
        invoiceKey: ym,
      );
      if (invAnalysis != null && invAnalysis.totalInvoiceCents > 0) {
        cardAnalyses.add(invAnalysis.toJson());
      }
    }

    // Resumo dos últimos 7 dias (para perguntas sobre "esta semana" / "últimos dias")
    final nowDt = DateTime.now();
    final weekStartDt = nowDt.subtract(const Duration(days: 7));
    final todayIso = todayISO();
    final weekStartIso =
        '${weekStartDt.year.toString().padLeft(4, '0')}-${weekStartDt.month.toString().padLeft(2, '0')}-${weekStartDt.day.toString().padLeft(2, '0')}';
    int weekIncomeCents = 0;
    int weekExpenseCents = 0;
    final weekCatExpenseCents = <String, int>{};
    for (final tx in store.db.txs) {
      if (tx.auto == true ||
          tx.xfer != null ||
          tx.peer != null ||
          isPredictionPayee(tx.payee)) {
        continue;
      }
      if (tx.date.compareTo(weekStartIso) < 0 ||
          tx.date.compareTo(todayIso) > 0) {
        continue;
      }
      if (!store.isCategoryIncludedInReports(tx.cat)) continue;
      final valBase = store.convertTxToCurrency(tx, baseCur);
      if (valBase >= 0) {
        weekIncomeCents += valBase;
      } else {
        final absVal = valBase.abs();
        weekExpenseCents += absVal;
        final topCat = tx.cat.trim().isEmpty
            ? 'Sem Categoria'
            : tx.cat.split(kCategorySep).first.trim();
        weekCatExpenseCents[topCat] =
            (weekCatExpenseCents[topCat] ?? 0) + absVal;
      }
    }
    final weekTopCats = weekCatExpenseCents.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final realCash = store.totalBalance(predicted: false);
    final hasInvestments = store.db.investAssets.isNotEmpty;
    PortfolioSummary? invSummary;
    InvestmentInsightsReport? invReport;
    int invCash = 0;
    if (hasInvestments) {
      invSummary = store.portfolioSummary();
      invCash = store.investmentCashBalance();
      invReport = InvestmentInsightsEngine.analyze(
        summary: invSummary,
        cashBalanceCents: invCash,
        baseCurrency: baseCur,
      );
    }

    return {
      'todayIso': todayIso,
      'referenceMonth': ym,
      'baseCurrency': baseCur,
      'focusAccountId': ?focusAccountId,
      'focusCategory': ?focusCategory,
      'patrimony': {
        'totalReal': formatCurrency(realCash, baseCur),
        if (invSummary != null)
          'investmentsGross':
              formatCurrency(invSummary.totalMarketValueGrossCents, baseCur),
        if (invSummary != null)
          'consolidatedTotal': formatCurrency(
              realCash + invSummary.totalMarketValueGrossCents, baseCur),
        'totalPredictedMonth':
            formatCurrency(store.totalBalance(predicted: true), baseCur),
        'totalPredictedYear':
            formatCurrency(store.totalBalancePredictedYear(), baseCur),
      },
      if (invSummary != null && invReport != null)
        'investments': invReport.toAiContextJson(
          summary: invSummary,
          cashBalanceCents: invCash,
          baseCurrency: baseCur,
        ),
      'accounts': activeAccs,
      'availableCategories': {
        'Despesa': store.allCategoryPaths('Despesa'),
        'Receita': store.allCategoryPaths('Receita'),
      },
      'availableTags': store.db.tags,
      'monthlySummary': {
        'month': ym,
        'income': formatCurrency(report.totalIncome, baseCur),
        'expense': formatCurrency(report.totalExpense, baseCur),
        'net': formatCurrency(report.netTotal, baseCur),
        'savingsRatePercent': report.savingsRate,
        'topExpenseCategories': report.expenseGroups
            .take(8)
            .map((c) => {
                  'category': c.name,
                  'amount': formatCurrency(c.total, baseCur),
                  'sharePercent': c.percentage,
                })
            .toList(),
      },
      'last7DaysSummary': {
        'startDate': weekStartIso,
        'endDate': todayIso,
        'income': formatCurrency(weekIncomeCents, baseCur),
        'expense': formatCurrency(weekExpenseCents, baseCur),
        'net': formatCurrency(weekIncomeCents - weekExpenseCents, baseCur),
        'topExpenseCategories': weekTopCats
            .take(6)
            .map((e) => {
                  'category': e.key,
                  'amount': formatCurrency(e.value, baseCur),
                  'sharePercent': weekExpenseCents > 0
                      ? ((e.value / weekExpenseCents) * 100).round()
                      : 0,
                })
            .toList(),
      },
      'categorySpikes': spikes.take(6).map((s) => s.toJson()).toList(),
      'cardInvoices': cardAnalyses,
      'implicitRecurrences':
          recurrences.take(8).map((r) => r.toJson()).toList(),
      'organizationOpportunities': findOrganizationOpportunities(
        store,
        targetMonth: ym,
      ).take(8).map((o) => o.toJson(currency: baseCur)).toList(),
      'predictionsSummary': {
        'totalPlannedBase':
            formatCurrency(predReport.totalPlannedBaseCents, baseCur),
        'totalSpent': formatCurrency(predReport.totalSpentCents, baseCur),
        'totalRemaining':
            formatCurrency(predReport.totalRemainingCents, baseCur),
        'exhaustedCategories': predReport.groups
            .where((g) => g.predictions.any((p) => p.isExhausted))
            .map((g) => g.category)
            .toList(),
      },
      'dueBillsNext14Days': {
        'overdueCount': dueSummary.overdueCount,
        'dueSoonCount': dueSummary.totalCount,
        'totalPayable': formatCurrency(dueSummary.payTotal, baseCur),
        'totalReceivable': formatCurrency(dueSummary.receiveTotal, baseCur),
      },
    };
  }

  /// 7. Executa busca local filtrada sob demanda quando a IA solicita mais detalhes de transações.
  static List<Map<String, dynamic>> executeLocalQuery(
    MoneyStore store,
    AIQueryFilter filter,
  ) {
    final results = <Transaction>[];
    final qNorm = filter.searchText != null
        ? OfxReconciliationService.normalizeText(filter.searchText!)
        : '';
    final catNorm = filter.category != null
        ? OfxReconciliationService.normalizeText(filter.category!)
        : '';
    final tagNorm = filter.tag?.trim().toLowerCase() ?? '';

    for (final tx in store.db.txs) {
      if (tx.auto == true) continue;
      if (filter.startDate != null &&
          filter.startDate!.isNotEmpty &&
          tx.date.compareTo(filter.startDate!) < 0) {
        continue;
      }
      if (filter.endDate != null &&
          filter.endDate!.isNotEmpty &&
          tx.date.compareTo(filter.endDate!) > 0) {
        continue;
      }
      if (filter.accountId != null &&
          filter.accountId!.isNotEmpty &&
          tx.acc != filter.accountId) {
        continue;
      }
      if (catNorm.isNotEmpty &&
          !OfxReconciliationService.normalizeText(tx.cat).contains(catNorm)) {
        continue;
      }
      if (tagNorm.isNotEmpty) {
        final tags = tx.tags ?? const <String>[];
        if (!tags.any((t) => t.toLowerCase() == tagNorm)) continue;
      }
      if (qNorm.isNotEmpty) {
        final hay = OfxReconciliationService.normalizeText(
          '${tx.payee} ${tx.cat} ${tx.memo} ${(tx.tags ?? const []).join(" ")}',
        );
        if (!hay.contains(qNorm)) continue;
      }
      results.add(tx);
    }

    results.sort((a, b) => b.date.compareTo(a.date));

    return results.take(filter.limit).map((t) {
      final acc = store.accById(t.acc);
      final cur = acc?.effectiveCurrency ?? store.baseCurrency;
      return {
        'id': t.id,
        'date': t.date,
        'account': acc?.name ?? t.acc,
        'accountId': t.acc,
        'payee': t.payee,
        'category': t.cat,
        'amount': formatCurrency(t.amt, cur),
        'type': t.amt < 0 ? 'Despesa' : 'Receita',
        'currency': cur,
        'reconciled': t.rec,
        if (isInstallmentOrAnticipated(t)) 'isInstallment': true,
        if (t.pn != null) 'installmentCurrent': t.pn,
        if (t.pt != null) 'installmentTotal': t.pt,
        if (t.memo.isNotEmpty) 'memo': t.memo,
        if (t.tags != null && t.tags!.isNotEmpty) 'tags': t.tags,
        if (t.ik != null) 'invoiceKey': t.ik,
      };
    }).toList();
  }

  /// 8. Gera uma explicação analítica completa 100% offline em Markdown (para uso imediato sem gastar tokens).
  static String generateOfflineDiagnosticMarkdown(
    MoneyStore store, {
    String? topic, // 'spikes', 'invoices', 'recurrences', 'organize', 'overview'
    String? targetMonth,
    String? cardId,
  }) {
    final ym = targetMonth ?? store.month;
    final baseCur = store.baseCurrency;
    String fmt(int c, [String? cur]) =>
        formatCurrency(c, cur ?? baseCur);
    final buf = StringBuffer();

    if (topic == 'organize') {
      final opps = findOrganizationOpportunities(store, targetMonth: ym);
      buf.writeln('### 🗂️ Auditoria de Organização ($ym)');
      if (opps.isEmpty) {
        buf.writeln(
          '\n✅ Sua base está muito bem organizada! Não encontrei lançamentos sem categoria nem duplicidades não conciliadas neste mês.',
        );
      } else {
        buf.writeln(
          '\nEncontrei **${opps.length}** oportunidade(s) reais de organização (ignorando lançamentos já conciliados e compras parceladas/antecipadas):',
        );
        for (final o in opps.take(10)) {
          buf.writeln('- **${o.title}**: ${o.subtitle}');
        }
      }
      return buf.toString().trim();
    }

    if (topic == 'spikes') {
      final spikes = explainCategorySpikes(store, targetMonth: ym);
      buf.writeln('### 📈 Análise de Variações por Categoria ($ym)');
      if (spikes.isEmpty) {
        buf.writeln(
          '\nNenhuma categoria apresentou aumento atípico (>12%) ou estouro de limite em **$ym** comparado à média dos 3 meses anteriores.',
        );
      } else {
        for (final s in spikes.take(6)) {
          final sign = s.deltaVsAverageCents >= 0 ? '+' : '';
          buf.writeln(
            '\n- **${s.categoryPath}**: **${fmt(s.currentCents)}** '
            '($sign${s.percentVsAverage.round()}% vs média de ${fmt(s.average3MonthsCents)})',
          );
          if (s.isOverBudget) {
            buf.writeln(
              '  - ⚠️ Acima do limite mensal configurado de ${fmt(s.budgetLimitCents!)}.',
            );
          }
          if (s.isPredictionExhausted) {
            buf.writeln('  - ⚠️ Envelope de previsão orçamentária **ESGOTADO**.');
          }
          if (s.topDrivers.isNotEmpty) {
            final driversStr = s.topDrivers.take(3).map((d) {
              final dSign = d.deltaCents >= 0 ? '+' : '';
              return '**${d.payee}** (${fmt(d.currentMonthCents)}, $dSign${fmt(d.deltaCents)} vs média)';
            }).join(', ');
            buf.writeln('  - Principais causadores: $driversStr.');
          }
        }
      }
      return buf.toString().trim();
    }

    if (topic == 'invoices') {
      buf.writeln('### 💳 Raio-X das Faturas de Cartão ($ym)');
      final cards = store.db.accounts
          .where((a) =>
              !a.isInactive &&
              a.type == kCardType &&
              a.card != null &&
              (cardId == null || a.id == cardId))
          .toList();
      if (cards.isEmpty) {
        buf.writeln('\nNenhum cartão de crédito ativo encontrado.');
      } else {
        bool anyInvoice = false;
        for (final c in cards) {
          final analysis =
              analyzeCardInvoice(store, cardId: c.id, invoiceKey: ym);
          if (analysis == null || analysis.totalInvoiceCents == 0) continue;
          anyInvoice = true;
          final cur = analysis.currency;
          final sign = analysis.deltaVsAverageCents >= 0 ? '+' : '';
          buf.writeln(
            '\n#### ${analysis.cardName} — Total: **${fmt(analysis.totalInvoiceCents, cur)}**',
          );
          if (analysis.previous3InvoicesAverageCents > 0) {
            buf.writeln(
              '- Comparação com média (3M): **$sign${analysis.percentVsAverage.round()}%** (média: ${fmt(analysis.previous3InvoicesAverageCents, cur)})',
            );
          }
          buf.writeln(
            '- Composição: À vista **${fmt(analysis.spotPurchasesCents, cur)}** · Parcelados **${fmt(analysis.installmentPurchasesCents, cur)}** (${analysis.installmentSharePercent.round()}%) · Recorrentes **${fmt(analysis.recurringPurchasesCents, cur)}**',
          );
          if (analysis.topPayees.isNotEmpty) {
            final topP = analysis.topPayees
                .take(3)
                .map((p) => '${p.payee} (${fmt(p.amountCents, cur)})')
                .join(', ');
            buf.writeln('- Maiores gastos na fatura: $topP');
          }
          final nextEntries = analysis.next3InvoicesCommittedCents.entries
              .where((e) => e.value > 0)
              .map((e) => '${e.key}: ${fmt(e.value, cur)}')
              .join(' · ');
          if (nextEntries.isNotEmpty) {
            buf.writeln('- Já comprometido nas próximas faturas: $nextEntries');
          }
        }
        if (!anyInvoice) {
          buf.writeln('\nNenhuma fatura com lançamentos em **$ym**.');
        }
      }
      return buf.toString().trim();
    }

    if (topic == 'recurrences') {
      final recs = detectImplicitRecurrences(store);
      buf.writeln('### 🔁 Assinaturas e Recorrências Identificadas');
      if (recs.isEmpty) {
        buf.writeln(
          '\nTodas as cobranças periódicas identificadas já estão cadastradas como regras de recorrência.',
        );
      } else {
        buf.writeln(
          '\nEncontrei **${recs.length}** cobrança(s) periódica(s) no seu histórico que ainda não estão automatizadas:',
        );
        for (final r in recs.take(8)) {
          final freqLabel = recurrenceFrequencyLabel(r.detectedFrequency);
          final amtStr = fmt(r.latestAmountCents.abs(), r.currency);
          String alert = '';
          if (r.hasPriceIncrease) {
            alert =
                ' — ⚠️ **Subiu +${fmt(r.priceChangeCents, r.currency)} (+${r.priceChangePercent.round()}%)** na última cobrança!';
          }
          buf.writeln(
            '- **${r.displayPayee}** ($amtStr · $freqLabel · ${r.accountName} · *${r.category}*)$alert',
          );
        }
      }
      return buf.toString().trim();
    }

    // Overview geral
    final report = store.buildMonthlyReport(ym);
    final spikes = explainCategorySpikes(store, targetMonth: ym);
    final recs = detectImplicitRecurrences(store);
    buf.writeln('### ✨ Resumo Inteligente ($ym)');
    buf.writeln(
      '- **Patrimônio Real Consolidado:** ${fmt(store.totalBalance(predicted: false))} (Previsto mês: ${fmt(store.totalBalance(predicted: true))})',
    );
    buf.writeln(
      '- **Resultado de $ym:** Receitas ${fmt(report.totalIncome)} · Despesas ${fmt(report.totalExpense)} · Saldo ${fmt(report.netTotal)} (Taxa de poupança: **${report.savingsRate}%**)',
    );
    if (spikes.isNotEmpty) {
      buf.writeln(
        '- **Principal alerta de categoria:** ${spikes.first.buildSummarySentence()}',
      );
    }
    if (recs.isNotEmpty) {
      final priceUp = recs.where((r) => r.hasPriceIncrease).length;
      buf.writeln(
        '- **Recorrências detectadas:** ${recs.length} assinatura(s)/conta(s) periódica(s) sem regra automática${priceUp > 0 ? " ($priceUp com reajuste recente)" : ""}.',
      );
    }
    return buf.toString().trim();
  }
}

/// Cache reativo e com debounce dos insights da Assistente IA.
///
/// Evita que telas (Painel da Assistente, Dashboard) recalculem picos de
/// categorias, recorrências implícitas e oportunidades de organização dentro
/// do `build()` a cada `notifyListeners()` do [MoneyStore] — o que travava a UI
/// (rodinha colorida) ao incluir/editar/excluir lançamentos com o painel aberto.
///
/// O recálculo só ocorre após um período ocioso ([debounce]) desde a última
/// mutação, fora do frame de salvamento, e apenas quando há consumidores ativos.
class AiInsightsCache extends ChangeNotifier {
  AiInsightsCache._();
  static final AiInsightsCache instance = AiInsightsCache._();

  static const Duration debounce = Duration(milliseconds: 1500);

  MoneyStore? _store;
  int _consumers = 0;
  Timer? _timer;
  String? _computedKey;

  List<CategorySpikeInsight> spikes = const [];
  List<RecurringCandidate> recurrences = const [];
  List<OrganizationOpportunity> opportunities = const [];

  bool get hasData => _computedKey != null;

  String _keyFor(MoneyStore s) =>
      '${identityHashCode(s.db)}_${s.month}_${s.baseCurrency}_${s.dataRevision}';

  /// Registra um consumidor (ex.: painel aberto). Agenda o primeiro cálculo
  /// logo após o frame atual.
  void attach(MoneyStore store) {
    if (_store != store) {
      _store?.removeListener(_onStoreChanged);
      _store = store;
      store.addListener(_onStoreChanged);
      _computedKey = null;
    }
    _consumers++;
    if (_computedKey != _keyFor(store)) {
      _schedule(const Duration(milliseconds: 60));
    }
  }

  void detach(MoneyStore store) {
    if (_consumers > 0) _consumers--;
    if (_consumers == 0) {
      _timer?.cancel();
      _timer = null;
    }
  }

  void _onStoreChanged() {
    final s = _store;
    if (s == null || _consumers == 0) return;
    if (_computedKey == _keyFor(s)) return; // nada mudou nos dados
    _schedule(debounce);
  }

  void _schedule(Duration delay) {
    _timer?.cancel();
    _timer = Timer(delay, _recompute);
  }

  /// Força recálculo imediato (ex.: ao clicar em um atalho de análise).
  void refreshNow() => _recompute();

  void _recompute() {
    _timer = null;
    final s = _store;
    if (s == null) return;
    final key = _keyFor(s);
    if (key == _computedKey) return;
    try {
      spikes = FinancialInsightsEngine.explainCategorySpikes(s);
      recurrences = FinancialInsightsEngine.detectImplicitRecurrences(s);
      opportunities = FinancialInsightsEngine.findOrganizationOpportunities(s);
      _computedKey = key;
      notifyListeners();
    } catch (_) {
      // Nunca deixa uma falha analítica afetar o fluxo de salvamento.
    }
  }
}
