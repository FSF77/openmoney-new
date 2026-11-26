import 'dart:math' as math;
import '../models/openmoney_models.dart';
import '../store/money_store.dart';
import 'cash_flow_engine.dart';
import 'financial_insights_engine.dart';

/// Filtro global do Dashboard de Gráficos. Meses no formato `YYYY-MM`.
class AnalyticsFilter {
  final String fromYM;
  final String toYM;
  final Set<String> accountIds; // vazio = todas
  final CashFlowStatusFilter statusFilter;
  final String? categoryTop; // filtro cruzado por categoria-pai
  final double savingsGoal; // 0..1 (ex.: 0.20)
  final double reserveGoalMonths;
  final bool isAllTime;

  const AnalyticsFilter({
    required this.fromYM,
    required this.toYM,
    this.accountIds = const <String>{},
    this.statusFilter = CashFlowStatusFilter.all,
    this.categoryTop,
    this.savingsGoal = 0.20,
    this.reserveGoalMonths = 6,
    this.isAllTime = false,
  });

  AnalyticsFilter copyWith({
    String? fromYM,
    String? toYM,
    Set<String>? accountIds,
    CashFlowStatusFilter? statusFilter,
    Object? categoryTop = _keep,
    double? savingsGoal,
    double? reserveGoalMonths,
    bool? isAllTime,
  }) {
    return AnalyticsFilter(
      fromYM: fromYM ?? this.fromYM,
      toYM: toYM ?? this.toYM,
      accountIds: accountIds ?? this.accountIds,
      statusFilter: statusFilter ?? this.statusFilter,
      categoryTop:
          identical(categoryTop, _keep) ? this.categoryTop : categoryTop as String?,
      savingsGoal: savingsGoal ?? this.savingsGoal,
      reserveGoalMonths: reserveGoalMonths ?? this.reserveGoalMonths,
      isAllTime: isAllTime ?? this.isAllTime,
    );
  }

  static const Object _keep = Object();
}

class MonthPoint {
  final String ym;
  final int income;
  final int expense; // positivo
  final int netWorth; // saldo patrimonial no fim do mês
  const MonthPoint(this.ym, this.income, this.expense, this.netWorth);
  int get net => income - expense;
}

class CategorySlice {
  final String name;
  final int cents; // positivo
  final Map<String, int> subs;
  const CategorySlice(this.name, this.cents, this.subs);
}

class BudgetProgress {
  final String category;
  final int budget;
  final int spent;
  const BudgetProgress(this.category, this.budget, this.spent);
  double get ratio => budget <= 0 ? 0 : spent / budget;
}

class ForecastPoint {
  final String date;
  final int balance;
  const ForecastPoint(this.date, this.balance);
}

class PayeeRank {
  final String payee;
  final int cents;
  final int count;
  const PayeeRank(this.payee, this.cents, this.count);
}

class AnalyticsSnapshot {
  final String currency;
  final int income, expense, net, netWorth;
  final int cashNetWorth, investmentsNetWorth;
  final int prevIncome, prevExpense;
  final double savingsRate;
  final int burnPerDay;
  final int projectedMonthExpense;
  final double runwayMonths;
  final double fixedCommitment;
  final int healthScore;
  final List<MonthPoint> monthly;
  final List<CategorySlice> byCategory;
  final List<BudgetProgress> budgets;
  final List<ForecastPoint> forecast;
  final List<PayeeRank> topPayees;
  final Map<String, int> dailySpend; // ISO date -> centavos (mês final)
  final List<String> insights;

  const AnalyticsSnapshot({
    required this.currency,
    required this.income,
    required this.expense,
    required this.net,
    required this.netWorth,
    this.cashNetWorth = 0,
    this.investmentsNetWorth = 0,
    required this.prevIncome,
    required this.prevExpense,
    required this.savingsRate,
    required this.burnPerDay,
    required this.projectedMonthExpense,
    required this.runwayMonths,
    required this.fixedCommitment,
    required this.healthScore,
    required this.monthly,
    required this.byCategory,
    required this.budgets,
    required this.forecast,
    required this.topPayees,
    required this.dailySpend,
    required this.insights,
  });

  int get prevNet => prevIncome - prevExpense;
}

/// Motor de cálculo puro (somente leitura) dos KPIs do Dashboard de Gráficos.
class AnalyticsEngine {
  AnalyticsEngine._();

  // ---------- Helpers de mês ----------
  static String addMonths(String ym, int delta) {
    final y = int.parse(ym.substring(0, 4));
    final m = int.parse(ym.substring(5, 7));
    final idx = y * 12 + (m - 1) + delta;
    final ny = idx ~/ 12;
    final nm = idx % 12 + 1;
    return '$ny-${nm.toString().padLeft(2, '0')}';
  }

  static int monthsBetween(String from, String to) {
    final a = int.parse(from.substring(0, 4)) * 12 + int.parse(from.substring(5, 7));
    final b = int.parse(to.substring(0, 4)) * 12 + int.parse(to.substring(5, 7));
    return b - a;
  }

  // ---------- Cálculo ----------
  static AnalyticsSnapshot compute(MoneyStore store, AnalyticsFilter f,
      {DateTime? now}) {
    final today = now ?? DateTime.now();
    final todayStr =
        '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
    final currentYM = todayStr.substring(0, 7);
    final base = store.baseCurrency;
    final accounts = store.db.accounts;
    final accFilterOk = f.accountIds.isEmpty
        ? (String id) => true
        : (String id) => f.accountIds.contains(id);

    int conv(Transaction t, int cents) {
      final cur = store.accById(t.acc)?.effectiveCurrency ?? base;
      return store.convertToBase(cents, cur, txRateToBrl: t.rate);
    }

    final len = math.max(1, monthsBetween(f.fromYM, f.toYM) + 1);
    final prevFrom = addMonths(f.fromYM, -len);
    final prevTo = addMonths(f.fromYM, -1);

    // Série mensal cobre: período anterior + período atual (para comparação)
    final inc = <String, int>{};
    final exp = <String, int>{};
    final catTotals = <String, int>{};
    final catSubs = <String, Map<String, int>>{};
    final prevCatTotals = <String, int>{};
    final payeeTotals = <String, int>{};
    final payeeCounts = <String, int>{};
    final payeeNames = <String, String>{};
    final daily = <String, int>{};
    final budgetSpent = <String, int>{}; // top e "top › sub"
    int fixedExpense = 0;

    for (final t in store.db.txs) {
      if (!accFilterOk(t.acc)) continue;

      // Transferências entre contas (ou compra/venda de investimentos): rigorosamente igual ao relatório contábil (buildMonthlyReport)
      if (isTransferTransaction(t)) continue;

      // Categorias incluídas em relatórios: rigorosamente igual ao relatório contábil
      if (!store.isCategoryIncludedInReports(t.cat)) continue;

      // Status de conciliação (Conciliados vs Não conciliados)
      switch (f.statusFilter) {
        case CashFlowStatusFilter.all:
          break;
        case CashFlowStatusFilter.reconciledOnly:
          if (!t.rec) continue;
          break;
        case CashFlowStatusFilter.pendingOnly:
          if (t.rec) continue;
          break;
      }

      // Competência contábil: alinhada 100% à data do lançamento contábil
      if (t.date.length < 7) continue;
      final ym = t.date.substring(0, 7);
      if (!f.isAllTime) {
        if (ym.compareTo(prevFrom) < 0 || ym.compareTo(f.toYM) > 0) continue;
      } else {
        if (ym.compareTo(f.fromYM) < 0 || ym.compareTo(f.toYM) > 0) continue;
      }

      final parts =
          t.cat.isEmpty ? ['Sem categoria'] : t.cat.split(kCategorySep);
      final topCat = parts[0];
      final subCat = parts.length > 1 ? parts[1] : null;

      if (f.categoryTop != null && topCat != f.categoryTop) {
        continue;
      }

      final v = conv(t, t.amt);
      if (v > 0) {
        inc[ym] = (inc[ym] ?? 0) + v;
      } else if (v < 0) {
        final a = -v;
        exp[ym] = (exp[ym] ?? 0) + a;
        final inCurrent =
            ym.compareTo(f.fromYM) >= 0 && ym.compareTo(f.toYM) <= 0;
        if (inCurrent) {
          catTotals[topCat] = (catTotals[topCat] ?? 0) + a;
          if (subCat != null) {
            final m = catSubs.putIfAbsent(topCat, () => <String, int>{});
            m[subCat] = (m[subCat] ?? 0) + a;
          }
          final key =
              FinancialInsightsEngine.normalizePayeeForGrouping(t.payee);
          if (key.isNotEmpty) {
            payeeTotals[key] = (payeeTotals[key] ?? 0) + a;
            payeeCounts[key] = (payeeCounts[key] ?? 0) + 1;
            payeeNames.putIfAbsent(key, () => t.payee.trim());
          }
          if (t.recId != null || t.pn != null) fixedExpense += a;
        } else {
          prevCatTotals[topCat] = (prevCatTotals[topCat] ?? 0) + a;
        }
        if (ym == f.toYM) {
          budgetSpent[topCat] = (budgetSpent[topCat] ?? 0) + a;
          if (subCat != null) {
            final k = '$topCat$kCategorySep$subCat';
            budgetSpent[k] = (budgetSpent[k] ?? 0) + a;
          }
          if (t.date.length >= 10) {
            daily[t.date] = (daily[t.date] ?? 0) + a;
          }
        }
      }
    }

    int sumRange(Map<String, int> m, String from, String to) {
      int s = 0;
      for (final e in m.entries) {
        if (e.key.compareTo(from) >= 0 && e.key.compareTo(to) <= 0) s += e.value;
      }
      return s;
    }

    final income = sumRange(inc, f.fromYM, f.toYM);
    final expense = sumRange(exp, f.fromYM, f.toYM);
    final prevIncome = f.isAllTime ? 0 : sumRange(inc, prevFrom, prevTo);
    final prevExpense = f.isAllTime ? 0 : sumRange(exp, prevFrom, prevTo);

    // ---------- Patrimônio Líquido Consolidado Atual ----------
    final nwAccounts =
        accounts.where((a) => a.isActive && accFilterOk(a.id)).toList();
    int cashNetWorth = 0;
    int investmentsNetWorth = 0;
    if (f.accountIds.isEmpty) {
      cashNetWorth = store.totalBalance(predicted: false);
      investmentsNetWorth = store.portfolioMarketValue();
    } else {
      for (final a in nwAccounts) {
        cashNetWorth += store.convertToBase(
            store.balance(a, predicted: false), a.effectiveCurrency);
        final accMarket = store.portfolioMarketValue(
          accountId: a.id,
          targetCurrency: a.effectiveCurrency,
        );
        if (accMarket != 0) {
          investmentsNetWorth +=
              store.convertToBase(accMarket, a.effectiveCurrency);
        }
      }
    }
    final currentConsolidatedNetWorth = cashNetWorth + investmentsNetWorth;

    // ---------- Patrimônio mês a mês (Histórico) ----------
    int opening = 0;
    for (final a in nwAccounts) {
      opening += store.convertToBase(a.opening, a.effectiveCurrency);
    }
    final nwIds = nwAccounts.map((a) => a.id).toSet();
    final flowByMonth = <String, int>{};
    for (final t in store.db.txs) {
      if (!nwIds.contains(t.acc)) continue;
      if (isPredictionPayee(t.payee)) continue;
      if (t.investOpId != null && isTransferTransaction(t)) continue;
      if (t.date.length < 7) continue;
      final v = conv(t, t.amt);
      final ym = t.date.substring(0, 7);
      flowByMonth[ym] = (flowByMonth[ym] ?? 0) + v;
    }
    final sortedMonths = flowByMonth.keys.toList()..sort();
    int nwAt(String ym) {
      int s = opening;
      for (final k in sortedMonths) {
        if (k.compareTo(ym) > 0) break;
        s += flowByMonth[k]!;
      }
      return s;
    }

    final monthly = <MonthPoint>[];
    for (int i = 0; i < len; i++) {
      final ym = addMonths(f.fromYM, i);
      final isCurrentOrFuture = ym.compareTo(currentYM) >= 0;
      final nwVal = (isCurrentOrFuture && ym == currentYM)
          ? currentConsolidatedNetWorth
          : nwAt(ym);
      monthly.add(MonthPoint(ym, inc[ym] ?? 0, exp[ym] ?? 0, nwVal));
    }

    final netWorthNow = f.toYM.compareTo(currentYM) >= 0
        ? currentConsolidatedNetWorth
        : nwAt(f.toYM);

    // ---------- Categorias ----------
    final byCategory = catTotals.entries
        .map((e) => CategorySlice(e.key, e.value, catSubs[e.key] ?? const {}))
        .toList()
      ..sort((a, b) => b.cents.compareTo(a.cents));

    // ---------- Orçamento ----------
    final budgets = <BudgetProgress>[];
    store.db.budgets.forEach((k, v) {
      if (v > 0) budgets.add(BudgetProgress(k, v, budgetSpent[k] ?? 0));
    });
    budgets.sort((a, b) => b.ratio.compareTo(a.ratio));

    // ---------- KPIs derivados ----------
    final savingsRate = income > 0 ? (income - expense) / income : 0.0;

    // Burn rate: mês final do filtro
    final isCurrentMonth = f.toYM == currentYM;
    final daysInMonth = DateTime(int.parse(f.toYM.substring(0, 4)),
            int.parse(f.toYM.substring(5, 7)) + 1, 0)
        .day;
    final elapsed = isCurrentMonth
        ? today.day
        : (f.toYM.compareTo(currentYM) < 0 ? daysInMonth : 1);
    final lastMonthExpense = exp[f.toYM] ?? 0;
    final burn = elapsed > 0 ? (lastMonthExpense / elapsed).round() : 0;
    final projected = isCurrentMonth ? burn * daysInMonth : lastMonthExpense;

    // ---------- Reserva de Emergência (Runway) ----------
    // Considera TODO o patrimônio líquido total do usuário (contas, investimentos, etc.)
    final totalReserve = math.max(0, netWorthNow);
    int sum3 = 0;
    int n3 = 0;
    final refEnd = isCurrentMonth ? addMonths(currentYM, -1) : f.toYM;
    for (int i = 0; i < 3; i++) {
      final ym = addMonths(refEnd, -i);
      final e = exp[ym];
      if (e != null && e > 0) {
        sum3 += e;
        n3++;
      }
    }
    double avgExp = 0;
    if (n3 > 0 && sum3 > 0) {
      avgExp = sum3 / n3;
    } else if (expense > 0 && len > 0) {
      avgExp = expense / len;
    } else if ((exp[f.toYM] ?? 0) > 0) {
      avgExp = (exp[f.toYM]!).toDouble();
    }
    final runway = avgExp > 0 ? (totalReserve / avgExp).clamp(0, 999).toDouble() : 0.0;

    final fixedCommit = income > 0 ? fixedExpense / income : 0.0;

    // ---------- Previsão 90 dias ----------
    final forecast = <ForecastPoint>[];
    final startBal = currentConsolidatedNetWorth;
    final future = <String, int>{};
    final horizon = today.add(const Duration(days: 90));
    final horizonStr =
        '${horizon.year}-${horizon.month.toString().padLeft(2, '0')}-${horizon.day.toString().padLeft(2, '0')}';
    for (final t in store.db.txs) {
      if (!nwIds.contains(t.acc)) continue;
      if (t.date.compareTo(todayStr) <= 0 || t.date.compareTo(horizonStr) > 0) {
        continue;
      }
      future[t.date] = (future[t.date] ?? 0) + conv(t, t.amt);
    }
    int run = startBal;
    forecast.add(ForecastPoint(todayStr, run));
    final dates = future.keys.toList()..sort();
    for (final d in dates) {
      run += future[d]!;
      forecast.add(ForecastPoint(d, run));
    }

    // ---------- Ranking de estabelecimentos ----------
    final topPayees = payeeTotals.entries
        .map((e) => PayeeRank(payeeNames[e.key] ?? e.key, e.value, payeeCounts[e.key] ?? 0))
        .toList()
      ..sort((a, b) => b.cents.compareTo(a.cents));

    // ---------- Score de saúde (0-100) ----------
    double score = 0;
    score += 30 * (f.savingsGoal > 0 ? (savingsRate / f.savingsGoal).clamp(0, 1) : 1);
    score += 25 * (f.reserveGoalMonths > 0 ? (runway / f.reserveGoalMonths).clamp(0, 1) : 1);
    score += 15 * (1 - (fixedCommit / 0.5).clamp(0, 1));
    if (budgets.isEmpty) {
      score += 15;
    } else {
      final ok = budgets.where((b) => b.ratio <= 1).length;
      score += 15 * ok / budgets.length;
    }
    final posMonths = monthly.where((m) => m.net >= 0).length;
    score += 15 * (monthly.isEmpty ? 0 : posMonths / monthly.length);

    // ---------- Insights ----------
    final insights = <String>[];
    String c(int v) => formatCurrency(v, base);
    if (!f.isAllTime && prevExpense > 0 && expense > 0) {
      final d = (expense - prevExpense) / prevExpense;
      if (d.abs() >= 0.1) {
        insights.add(d > 0
            ? 'Despesas ${(d * 100).toStringAsFixed(0)}% acima do período anterior (${c(expense - prevExpense)} a mais).'
            : 'Despesas ${(-d * 100).toStringAsFixed(0)}% abaixo do período anterior. Bom trabalho!');
      }
    }
    String? worstCat;
    int worstDelta = 0;
    catTotals.forEach((k, v) {
      final d = v - (prevCatTotals[k] ?? 0);
      if (d > worstDelta) {
        worstDelta = d;
        worstCat = k;
      }
    });
    if (worstCat != null && worstDelta > 0 && (prevCatTotals[worstCat] ?? 0) > 0) {
      insights.add('Maior alta: "$worstCat" subiu ${c(worstDelta)} vs. período anterior.');
    }
    if (income > 0 && savingsRate < f.savingsGoal) {
      insights.add(
          'Taxa de poupança de ${(savingsRate * 100).toStringAsFixed(0)}% está abaixo da meta de ${(f.savingsGoal * 100).toStringAsFixed(0)}%.');
    }
    for (final b in budgets.where((b) => b.ratio > 1).take(2)) {
      insights.add('Orçamento de "${b.category}" estourado em ${(b.ratio * 100).toStringAsFixed(0)}%.');
    }
    if (runway > 0 && runway < f.reserveGoalMonths) {
      insights.add(
          'Reserva cobre ${runway.toStringAsFixed(1)} meses; meta é ${f.reserveGoalMonths.toStringAsFixed(0)}.');
    }
    if (fixedCommit > 0.5) {
      insights.add('Comprometimento fixo (recorrências e parcelas) acima de 50% da receita.');
    }
    if (isCurrentMonth && projected > 0) {
      insights.add('Projeção de despesas do mês: ${c(projected)}.');
    }

    return AnalyticsSnapshot(
      currency: base,
      income: income,
      expense: expense,
      net: income - expense,
      netWorth: netWorthNow,
      cashNetWorth: cashNetWorth,
      investmentsNetWorth: investmentsNetWorth,
      prevIncome: prevIncome,
      prevExpense: prevExpense,
      savingsRate: savingsRate,
      burnPerDay: burn,
      projectedMonthExpense: projected,
      runwayMonths: runway,
      fixedCommitment: fixedCommit,
      healthScore: score.round().clamp(0, 100),
      monthly: monthly,
      byCategory: byCategory,
      budgets: budgets,
      forecast: forecast,
      topPayees: topPayees.take(8).toList(),
      dailySpend: daily,
      insights: insights,
    );
  }
}
