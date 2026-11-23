import 'openmoney_models.dart';

enum AgendaEntryKind {
  bill,
  invoice,
  income,
}

class AgendaEntry {
  final String id;
  final AgendaEntryKind kind;
  final String date; // "YYYY-MM-DD" de vencimento ou competência
  final String title;
  final String category;
  final String accountName;
  final int amountCents; // Valor absoluto em centavos
  final String currency;
  final bool isDone;
  final bool isOverdue;

  // Referência para contas a pagar e receitas
  final Transaction? tx;

  // Referências para fatura de cartão de crédito
  final String? cardId;
  final String? invoiceKey;
  final String? invoiceCloseDate;
  final String? invoiceDueDate;
  final int? invoiceChargesCents;
  final int? invoicePaymentsCents;
  final int? invoiceRemainingCents;

  const AgendaEntry({
    required this.id,
    required this.kind,
    required this.date,
    required this.title,
    required this.category,
    required this.accountName,
    required this.amountCents,
    required this.currency,
    required this.isDone,
    required this.isOverdue,
    this.tx,
    this.cardId,
    this.invoiceKey,
    this.invoiceCloseDate,
    this.invoiceDueDate,
    this.invoiceChargesCents,
    this.invoicePaymentsCents,
    this.invoiceRemainingCents,
  });

  bool get isBill => kind == AgendaEntryKind.bill;
  bool get isInvoice => kind == AgendaEntryKind.invoice;
  bool get isIncome => kind == AgendaEntryKind.income;
  bool get isPayable => isBill || isInvoice;
}

class AgendaMonthSummary {
  final int pendingPayCount;
  final int pendingPayTotalCents;
  final int pendingReceiveCount;
  final int pendingReceiveTotalCents;
  final int overdueCount;
  final int overdueTotalCents;
  final String? nextIncomeTitle;
  final String? nextIncomeDate;
  final int? nextIncomeAmountCents;
  final String currency;

  const AgendaMonthSummary({
    required this.pendingPayCount,
    required this.pendingPayTotalCents,
    required this.pendingReceiveCount,
    required this.pendingReceiveTotalCents,
    required this.overdueCount,
    required this.overdueTotalCents,
    this.nextIncomeTitle,
    this.nextIncomeDate,
    this.nextIncomeAmountCents,
    required this.currency,
  });
}
