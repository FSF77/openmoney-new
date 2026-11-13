import 'openmoney_models.dart';

class PredictionItemDetail {
  final Transaction tx;
  final String accountName;
  final String accountCurrency;
  final int baseCents;
  final int currentCents;
  final int deductedCents;
  final bool isExhausted;

  const PredictionItemDetail({
    required this.tx,
    required this.accountName,
    required this.accountCurrency,
    required this.baseCents,
    required this.currentCents,
    required this.deductedCents,
    required this.isExhausted,
  });

  String get id => tx.id;
}

class PredictionCategoryGroup {
  final String category;
  final int totalBaseCents;
  final int totalCurrentCents;
  final int totalSpentCents;
  final int totalDeductedCents;
  final int remainingCents;
  final double percentSpent;
  final List<PredictionItemDetail> predictions;
  final List<Transaction> spentTransactions;

  const PredictionCategoryGroup({
    required this.category,
    required this.totalBaseCents,
    required this.totalCurrentCents,
    required this.totalSpentCents,
    required this.totalDeductedCents,
    required this.remainingCents,
    required this.percentSpent,
    required this.predictions,
    required this.spentTransactions,
  });
}

class PredictionsSummaryReport {
  final String periodLabel;
  final int totalPlannedBaseCents;
  final int totalCurrentCents;
  final int totalSpentCents;
  final int totalDeductedCents;
  final int totalRemainingCents;
  final List<PredictionCategoryGroup> groups;
  final List<PredictionItemDetail> allPredictions;

  const PredictionsSummaryReport({
    required this.periodLabel,
    required this.totalPlannedBaseCents,
    required this.totalCurrentCents,
    required this.totalSpentCents,
    required this.totalDeductedCents,
    required this.totalRemainingCents,
    required this.groups,
    required this.allPredictions,
  });
}
