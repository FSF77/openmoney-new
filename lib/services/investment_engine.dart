import 'dart:math';
import '../models/openmoney_models.dart';

class AssetPositionSummary {
  final InvestAsset asset;
  final double currentQty;
  final double totalBoughtQty;
  final int totalBoughtCostCents;
  final int currentCostBasisCents;
  final int avgBuyPriceCents;
  final double totalSoldQty;
  final int totalSoldNetCents;
  final int avgSellPriceCents;
  final int realizedPnlCents;
  final int currentUnitPriceCents;
  final int currentGrossValueCents;
  final int estimatedTaxCents;
  final int currentNetValueCents;
  final int unrealizedPnlCents;
  final double unrealizedPnlPct;
  final int totalDividendsCents;
  final double yieldOnCostPct;
  final int totalReturnCents;
  final int daysHeld;
  final double irRatePct;

  const AssetPositionSummary({
    required this.asset,
    required this.currentQty,
    required this.totalBoughtQty,
    required this.totalBoughtCostCents,
    required this.currentCostBasisCents,
    required this.avgBuyPriceCents,
    required this.totalSoldQty,
    required this.totalSoldNetCents,
    required this.avgSellPriceCents,
    required this.realizedPnlCents,
    required this.currentUnitPriceCents,
    required this.currentGrossValueCents,
    required this.estimatedTaxCents,
    required this.currentNetValueCents,
    required this.unrealizedPnlCents,
    required this.unrealizedPnlPct,
    required this.totalDividendsCents,
    required this.yieldOnCostPct,
    required this.totalReturnCents,
    required this.daysHeld,
    required this.irRatePct,
  });

  bool get hasOpenPosition => currentQty > 1e-8;
}

class PortfolioSummary {
  final List<AssetPositionSummary> positions;
  final int totalCostBasisCents;
  final int totalMarketValueGrossCents;
  final int totalEstimatedTaxCents;
  final int totalMarketValueNetCents;
  final int totalUnrealizedPnlCents;
  final double totalUnrealizedPnlPct;
  final int totalRealizedPnlCents;
  final int totalDividendsCents;
  final Map<InvestAssetClass, int> byClass;

  const PortfolioSummary({
    required this.positions,
    required this.totalCostBasisCents,
    required this.totalMarketValueGrossCents,
    required this.totalEstimatedTaxCents,
    required this.totalMarketValueNetCents,
    required this.totalUnrealizedPnlCents,
    required this.totalUnrealizedPnlPct,
    required this.totalRealizedPnlCents,
    required this.totalDividendsCents,
    required this.byClass,
  });

  int get totalReturnCents =>
      totalUnrealizedPnlCents + totalRealizedPnlCents + totalDividendsCents;
}

class InvestmentEngine {
  static final Map<int, Set<String>> _anbimaHolidaysCache = {};

  static String _isoDate(DateTime d) {
    final m = d.month.toString().padLeft(2, '0');
    final day = d.day.toString().padLeft(2, '0');
    return '${d.year}-$m-$day';
  }

  /// Domingo de Páscoa pelo algoritmo gregoriano (Meeus/Jones/Butcher).
  static DateTime easterSunday(int year) {
    final a = year % 19;
    final b = year ~/ 100;
    final c = year % 100;
    final d = b ~/ 4;
    final e = b % 4;
    final f = (b + 8) ~/ 25;
    final g = (b - f + 1) ~/ 3;
    final h = (19 * a + b - d - g + 15) % 30;
    final i = c ~/ 4;
    final k = c % 4;
    final l = (32 + 2 * e + 2 * i - h - k) % 7;
    final m = (a + 11 * h + 22 * l) ~/ 451;
    final month = (h + l - 7 * m + 114) ~/ 31;
    final day = ((h + l - 7 * m + 114) % 31) + 1;
    return DateTime(year, month, day);
  }

  /// Feriados bancários nacionais oficiais da ANBIMA para o ano informado.
  static Set<String> anbimaHolidaysForYear(int year) {
    return _anbimaHolidaysCache.putIfAbsent(year, () {
      final easter = easterSunday(year);
      final holidays = <String>{
        '$year-01-01', // Confraternização Universal
        '$year-04-21', // Tiradentes
        '$year-05-01', // Dia do Trabalho
        '$year-09-07', // Independência do Brasil
        '$year-10-12', // Nossa Senhora Aparecida
        '$year-11-02', // Finados
        '$year-11-15', // Proclamação da República
        if (year >= 2024) '$year-11-20', // Consciência Negra (Lei 14.759/2023)
        '$year-12-25', // Natal
        _isoDate(easter.subtract(const Duration(days: 48))), // Segunda Carnaval
        _isoDate(easter.subtract(const Duration(days: 47))), // Terça Carnaval
        _isoDate(easter.subtract(const Duration(days: 2))), // Sexta-feira Santa
        _isoDate(easter.add(const Duration(days: 60))), // Corpus Christi
      };
      return holidays;
    });
  }

  /// Retorna true se a data for dia útil bancário segundo o calendário ANBIMA.
  static bool isAnbimaBusinessDay(DateTime date) {
    if (date.weekday == DateTime.saturday || date.weekday == DateTime.sunday) {
      return false;
    }
    return !anbimaHolidaysForYear(date.year).contains(_isoDate(date));
  }

  /// Conta os dias úteis bancários ANBIMA no intervalo [start, end).
  static int businessDaysAnbima(DateTime start, DateTime end) {
    var cur = DateTime(start.year, start.month, start.day);
    final endNorm = DateTime(end.year, end.month, end.day);
    if (!cur.isBefore(endNorm)) return 0;
    int count = 0;
    while (cur.isBefore(endNorm)) {
      if (isAnbimaBusinessDay(cur)) count++;
      cur = cur.add(const Duration(days: 1));
    }
    return count;
  }

  static double _compoundFixedIncomeLot({
    required InvestAsset asset,
    required DateTime lotDate,
    required DateTime asOf,
    required MarketIndicators indicators,
  }) {
    final start = DateTime(lotDate.year, lotDate.month, lotDate.day);
    final end = DateTime(asOf.year, asOf.month, asOf.day);
    if (!start.isBefore(end)) return 1.0;

    final annualRate = _annualRateForFixedIncome(asset, indicators);
    if ((asset.indexer ?? InvestFixedIncomeIndexer.cdi) ==
            InvestFixedIncomeIndexer.cdi &&
        indicators.cdiDailySeries.isNotEmpty) {
      final pct = (asset.ratePct ?? 100.0) / 100.0;
      final dailyFallback = pow(1.0 + max(-0.99, annualRate), 1.0 / 252.0);
      double factor = 1.0;
      var cur = start;
      while (cur.isBefore(end)) {
        final dailyRatePct = indicators.cdiDailySeries[_isoDate(cur)];
        if (dailyRatePct != null) {
          factor *= 1.0 + (dailyRatePct / 100.0) * pct;
        } else if (isAnbimaBusinessDay(cur)) {
          factor *= dailyFallback;
        }
        cur = cur.add(const Duration(days: 1));
      }
      return factor;
    }

    final bizDays = businessDaysAnbima(start, end);
    return pow(1.0 + max(-0.99, annualRate), bizDays / 252.0).toDouble();
  }

  static double regressiveIrRate(int daysHeld, {bool taxExempt = false}) {
    if (taxExempt) return 0.0;
    if (daysHeld <= 180) return 22.5;
    if (daysHeld <= 360) return 20.0;
    if (daysHeld <= 720) return 17.5;
    return 15.0;
  }

  static double _annualRateForFixedIncome(
    InvestAsset asset,
    MarketIndicators indicators,
  ) {
    final idx = asset.indexer ?? InvestFixedIncomeIndexer.cdi;
    final rate = asset.ratePct;
    switch (idx) {
      case InvestFixedIncomeIndexer.cdi:
        return (indicators.cdiAnnual / 100.0) * ((rate ?? 100.0) / 100.0);
      case InvestFixedIncomeIndexer.selic:
        return (indicators.selicAnnual + (rate ?? 0.0)) / 100.0;
      case InvestFixedIncomeIndexer.ipca:
        return ((1.0 + indicators.ipca12m / 100.0) *
                (1.0 + (rate ?? 0.0) / 100.0)) -
            1.0;
      case InvestFixedIncomeIndexer.prefixado:
        return (rate ?? 10.0) / 100.0;
      case InvestFixedIncomeIndexer.other:
        return (rate ?? 0.0) / 100.0;
    }
  }

  static DateTime _parseDateSafe(String iso) {
    try {
      return dateFromISO(iso);
    } catch (_) {
      return DateTime.now();
    }
  }

  /// Calcula o resumo completo de um ativo a partir de suas operações ordenadas.
  static AssetPositionSummary computeAssetPosition(
    InvestAsset asset,
    List<InvestOperation> ops, {
    MarketIndicators? indicators,
    String? asOfDateIso,
  }) {
    final effIndicators = indicators ?? MarketIndicators();
    final asOf = _parseDateSafe(asOfDateIso ?? todayISO());

    final sortedOps = List<InvestOperation>.from(ops)
      ..sort((a, b) {
        final dc = a.date.compareTo(b.date);
        if (dc != 0) return dc;
        return a.createdAt.compareTo(b.createdAt);
      });

    double currentQty = 0.0;
    double totalBoughtQty = 0.0;
    int totalBoughtCostCents = 0;
    int currentCostBasisCents = 0;
    int avgBuyPriceCents = 0;
    double totalSoldQty = 0.0;
    int totalSoldNetCents = 0;
    int avgSellPriceCents = 0;
    int realizedPnlCents = 0;
    int totalDividendsCents = 0;

    // Lotes abertos para cálculo preciso de dias corridos e juros compostos em Renda Fixa
    final List<({String date, int costCents})> rfLots = [];

    for (final op in sortedOps) {
      switch (op.type) {
        case InvestOpType.buy:
        case InvestOpType.initialPosition:
          if (op.quantity <= 0) break;
          final opCost = op.totalCents > 0
              ? op.totalCents
              : ((op.quantity * op.unitPriceCents).round() + op.feesCents);
          currentQty += op.quantity;
          currentCostBasisCents += opCost;
          totalBoughtQty += op.quantity;
          totalBoughtCostCents += opCost;
          if (currentQty > 1e-8) {
            avgBuyPriceCents = (currentCostBasisCents / currentQty).round();
          }
          if (asset.isFixedIncome) {
            rfLots.add((date: op.date, costCents: opCost));
          }
          break;

        case InvestOpType.sell:
          if (op.quantity <= 0) break;
          final netProceeds = op.totalCents > 0
              ? op.totalCents
              : max(0, (op.quantity * op.unitPriceCents).round() - op.feesCents);
          final soldQty = min(op.quantity, currentQty);
          final costBasisSold = (soldQty * avgBuyPriceCents).round();
          realizedPnlCents += (netProceeds - op.taxCents - costBasisSold);

          totalSoldQty += op.quantity;
          totalSoldNetCents += netProceeds;
          if (totalSoldQty > 1e-8) {
            avgSellPriceCents = (totalSoldNetCents / totalSoldQty).round();
          }

          currentQty -= op.quantity;
          currentCostBasisCents -= costBasisSold;
          if (currentQty <= 1e-8) {
            currentQty = 0.0;
            currentCostBasisCents = 0;
            rfLots.clear();
          } else if (asset.isFixedIncome && rfLots.isNotEmpty) {
            var remainingToDeduct = costBasisSold;
            while (remainingToDeduct > 0 && rfLots.isNotEmpty) {
              final first = rfLots.first;
              if (first.costCents <= remainingToDeduct) {
                remainingToDeduct -= first.costCents;
                rfLots.removeAt(0);
              } else {
                rfLots[0] = (
                  date: first.date,
                  costCents: first.costCents - remainingToDeduct,
                );
                remainingToDeduct = 0;
              }
            }
          }
          break;

        case InvestOpType.amortization:
          currentCostBasisCents = max(0, currentCostBasisCents - op.totalCents);
          if (currentQty > 1e-8) {
            avgBuyPriceCents = (currentCostBasisCents / currentQty).round();
          }
          break;

        case InvestOpType.dividend:
        case InvestOpType.jcp:
        case InvestOpType.fiiYield:
          totalDividendsCents += op.totalCents;
          break;

        case InvestOpType.split:
          if (op.quantity > 0 && currentQty > 1e-8) {
            currentQty *= op.quantity;
            avgBuyPriceCents = (currentCostBasisCents / currentQty).round();
          }
          break;

        case InvestOpType.inplit:
          if (op.quantity > 0 && currentQty > 1e-8) {
            currentQty /= op.quantity;
            avgBuyPriceCents = (currentCostBasisCents / currentQty).round();
          }
          break;

        case InvestOpType.bonus:
          if (op.quantity > 0) {
            currentQty += op.quantity;
            currentCostBasisCents += op.totalCents;
            if (currentQty > 1e-8) {
              avgBuyPriceCents = (currentCostBasisCents / currentQty).round();
            }
          }
          break;
      }
    }

    int currentUnitPriceCents = asset.currentPriceCents ?? avgBuyPriceCents;
    int currentGrossValueCents = 0;
    int estimatedTaxCents = 0;
    int daysHeld = 0;
    double irRatePct = 0.0;

    if (currentQty > 1e-8) {
      if (asset.isFixedIncome) {
        final oldestDate = rfLots.isNotEmpty
            ? _parseDateSafe(rfLots.first.date)
            : (sortedOps.isNotEmpty
                ? _parseDateSafe(sortedOps.first.date)
                : asOf);
        daysHeld = max(0, asOf.difference(oldestDate).inDays);
        irRatePct = regressiveIrRate(daysHeld, taxExempt: asset.taxExempt);

        if (asset.manualPrice && asset.currentPriceCents != null) {
          currentUnitPriceCents = asset.currentPriceCents!;
          currentGrossValueCents = (currentQty * currentUnitPriceCents).round();
        } else if (asset.currentPriceCents != null &&
            !asset.manualPrice &&
            asset.assetClass == InvestAssetClass.tesouro) {
          currentUnitPriceCents = asset.currentPriceCents!;
          currentGrossValueCents = (currentQty * currentUnitPriceCents).round();
        } else {
          double grossSum = 0.0;
          if (rfLots.isNotEmpty) {
            for (final lot in rfLots) {
              final lotDate = _parseDateSafe(lot.date);
              final factor = _compoundFixedIncomeLot(
                asset: asset,
                lotDate: lotDate,
                asOf: asOf,
                indicators: effIndicators,
              );
              grossSum += lot.costCents * factor;
            }
          } else {
            final factor = _compoundFixedIncomeLot(
              asset: asset,
              lotDate: oldestDate,
              asOf: asOf,
              indicators: effIndicators,
            );
            grossSum = currentCostBasisCents * factor;
          }
          currentGrossValueCents = grossSum.round();
          currentUnitPriceCents = (currentGrossValueCents / currentQty).round();
        }

        final grossProfit = currentGrossValueCents - currentCostBasisCents;
        if (grossProfit > 0 && irRatePct > 0) {
          estimatedTaxCents = (grossProfit * (irRatePct / 100.0)).round();
        }
      } else {
        currentGrossValueCents = (currentQty * currentUnitPriceCents).round();
      }
    }

    final currentNetValueCents = currentGrossValueCents - estimatedTaxCents;
    final unrealizedPnlCents = currentQty > 1e-8
        ? (currentGrossValueCents - currentCostBasisCents)
        : 0;
    final unrealizedPnlPct = currentCostBasisCents > 0
        ? (unrealizedPnlCents / currentCostBasisCents) * 100.0
        : 0.0;
    final yieldOnCostPct = currentCostBasisCents > 0
        ? (totalDividendsCents / currentCostBasisCents) * 100.0
        : 0.0;
    final totalReturnCents =
        realizedPnlCents + unrealizedPnlCents + totalDividendsCents;

    return AssetPositionSummary(
      asset: asset,
      currentQty: currentQty,
      totalBoughtQty: totalBoughtQty,
      totalBoughtCostCents: totalBoughtCostCents,
      currentCostBasisCents: currentCostBasisCents,
      avgBuyPriceCents: avgBuyPriceCents,
      totalSoldQty: totalSoldQty,
      totalSoldNetCents: totalSoldNetCents,
      avgSellPriceCents: avgSellPriceCents,
      realizedPnlCents: realizedPnlCents,
      currentUnitPriceCents: currentUnitPriceCents,
      currentGrossValueCents: currentGrossValueCents,
      estimatedTaxCents: estimatedTaxCents,
      currentNetValueCents: currentNetValueCents,
      unrealizedPnlCents: unrealizedPnlCents,
      unrealizedPnlPct: unrealizedPnlPct,
      totalDividendsCents: totalDividendsCents,
      yieldOnCostPct: yieldOnCostPct,
      totalReturnCents: totalReturnCents,
      daysHeld: daysHeld,
      irRatePct: irRatePct,
    );
  }

  /// Consolida toda a carteira (ou filtrada por conta/classe), convertendo para a moeda alvo se informado.
  static PortfolioSummary computePortfolio(
    Database db, {
    String? accountId,
    String? targetCurrency,
    String? asOfDateIso,
  }) {
    final opsByAsset = <String, List<InvestOperation>>{};
    final assetsWithAnyOp = <String>{};
    for (final op in db.investOps) {
      assetsWithAnyOp.add(op.assetId);
      if (accountId != null && op.accountId != accountId) continue;
      opsByAsset.putIfAbsent(op.assetId, () => []).add(op);
    }

    final positions = <AssetPositionSummary>[];
    int totalCost = 0;
    int totalGross = 0;
    int totalTax = 0;
    int totalNet = 0;
    int totalRealized = 0;
    int totalDivs = 0;
    final byClass = <InvestAssetClass, int>{};

    final toCur = targetCurrency ?? db.effectiveBaseCurrency;

    int conv(int cents, String fromCur) {
      if (fromCur == toCur) return cents;
      return convertCents(
        cents,
        fromCurrency: fromCur,
        toCurrency: toCur,
        rates: db.rates,
      );
    }

    for (final asset in db.investAssets) {
      final ops = opsByAsset[asset.id] ?? const [];
      if (accountId != null) {
        final hasOpsInAcc = ops.isNotEmpty;
        final isEmptyAssetOwnedByAcc =
            !assetsWithAnyOp.contains(asset.id) && asset.accountId == accountId;
        if (!hasOpsInAcc && !isEmptyAssetOwnedByAcc) continue;
      }
      final summary = computeAssetPosition(
        asset,
        ops,
        indicators: db.investIndicators,
        asOfDateIso: asOfDateIso,
      );
      positions.add(summary);

      totalCost += conv(summary.currentCostBasisCents, asset.currency);
      final grossConv = conv(summary.currentGrossValueCents, asset.currency);
      totalGross += grossConv;
      totalTax += conv(summary.estimatedTaxCents, asset.currency);
      totalNet += conv(summary.currentNetValueCents, asset.currency);
      totalRealized += conv(summary.realizedPnlCents, asset.currency);
      totalDivs += conv(summary.totalDividendsCents, asset.currency);

      if (summary.hasOpenPosition) {
        byClass[asset.assetClass] = (byClass[asset.assetClass] ?? 0) + grossConv;
      }
    }

    positions.sort((a, b) {
      if (a.hasOpenPosition != b.hasOpenPosition) {
        return a.hasOpenPosition ? -1 : 1;
      }
      return b.currentGrossValueCents.compareTo(a.currentGrossValueCents);
    });

    final totalUnrealized = totalGross - totalCost;
    final totalUnrealizedPct =
        totalCost > 0 ? (totalUnrealized / totalCost) * 100.0 : 0.0;

    return PortfolioSummary(
      positions: positions,
      totalCostBasisCents: totalCost,
      totalMarketValueGrossCents: totalGross,
      totalEstimatedTaxCents: totalTax,
      totalMarketValueNetCents: totalNet,
      totalUnrealizedPnlCents: totalUnrealized,
      totalUnrealizedPnlPct: totalUnrealizedPct,
      totalRealizedPnlCents: totalRealized,
      totalDividendsCents: totalDivs,
      byClass: byClass,
    );
  }

  /// Estima o IR Retido na Fonte (Tabela Regressiva de Renda Fixa) para uma venda,
  /// usando contagem de dias corridos por lote em ordem FIFO a partir de cada aporte.
  static ({int irCents, double effectiveRatePct, int oldestDaysHeld}) estimateSellIr({
    required InvestAsset asset,
    required List<InvestOperation> priorOps,
    required String sellDateIso,
    required double sellQty,
    required int grossSellCents,
    int feesCents = 0,
  }) {
    if (!asset.isFixedIncome ||
        asset.taxExempt ||
        sellQty <= 1e-8 ||
        grossSellCents <= 0) {
      return (irCents: 0, effectiveRatePct: 0.0, oldestDaysHeld: 0);
    }

    final sorted = List<InvestOperation>.from(priorOps)
      ..sort((a, b) {
        final dc = a.date.compareTo(b.date);
        if (dc != 0) return dc;
        return a.createdAt.compareTo(b.createdAt);
      });

    final lots = <({String date, double qty, int costCents})>[];
    for (final op in sorted) {
      if (op.date.compareTo(sellDateIso) > 0) continue;
      if (op.type == InvestOpType.buy || op.type == InvestOpType.initialPosition) {
        if (op.quantity <= 0) continue;
        final opCost = op.totalCents > 0
            ? op.totalCents
            : ((op.quantity * op.unitPriceCents).round() + op.feesCents);
        lots.add((date: op.date, qty: op.quantity, costCents: opCost));
      } else if (op.type == InvestOpType.sell) {
        var rem = op.quantity;
        while (rem > 1e-8 && lots.isNotEmpty) {
          final first = lots.first;
          if (first.qty <= rem + 1e-8) {
            rem -= first.qty;
            lots.removeAt(0);
          } else {
            final ratio = (first.qty - rem) / first.qty;
            lots[0] = (
              date: first.date,
              qty: first.qty - rem,
              costCents: (first.costCents * ratio).round(),
            );
            rem = 0;
          }
        }
      }
    }

    if (lots.isEmpty) {
      return (irCents: 0, effectiveRatePct: 0.0, oldestDaysHeld: 0);
    }

    final sellDt = _parseDateSafe(sellDateIso);
    final netBeforeTax = max(0, grossSellCents - feesCents);
    double remToSell = sellQty;
    double totalIr = 0.0;
    int totalProfit = 0;
    int oldestDays = 0;

    for (final lot in lots) {
      if (remToSell <= 1e-8) break;
      final usedQty = min(remToSell, lot.qty);
      final usedCost = lot.qty > 0
          ? (lot.costCents * (usedQty / lot.qty)).round()
          : 0;
      final lotProceeds = (netBeforeTax * (usedQty / sellQty)).round();
      final lotProfit = max(0, lotProceeds - usedCost);

      final lotDt = _parseDateSafe(lot.date);
      final days = max(0, sellDt.difference(lotDt).inDays);
      if (days > oldestDays) oldestDays = days;
      final rate = regressiveIrRate(days, taxExempt: false);

      totalProfit += lotProfit;
      totalIr += lotProfit * (rate / 100.0);
      remToSell -= usedQty;
    }

    final irCents = totalIr.round();
    final effRate = totalProfit > 0 ? (irCents / totalProfit) * 100.0 : 0.0;
    return (
      irCents: irCents,
      effectiveRatePct: effRate,
      oldestDaysHeld: oldestDays,
    );
  }
}
