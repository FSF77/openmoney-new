import 'package:flutter/material.dart';
import '../ui/theme/liquid_glass.dart';

class DateValidationResult {
  final bool isValid;
  final DateTime? date;
  final String? isoDate;
  final String? error;
  final bool isWarning;
  final String? warningMessage;

  const DateValidationResult({
    required this.isValid,
    this.date,
    this.isoDate,
    this.error,
    this.isWarning = false,
    this.warningMessage,
  });
}

/// Validates whether [rawInput] is a valid calendar date in DD/MM/AAAA or YYYY-MM-DD format,
/// and checks if the date is more than 30 days in the past or more than 12 months in the future.
DateValidationResult validateTransactionDate(String rawInput, {DateTime? now}) {
  final clean = rawInput.trim();
  if (clean.isEmpty) {
    return const DateValidationResult(isValid: false, error: 'Data não informada');
  }

  int? d, m, y;
  if (RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(clean)) {
    final parts = clean.split('-');
    y = int.tryParse(parts[0]);
    m = int.tryParse(parts[1]);
    d = int.tryParse(parts[2]);
  } else if (RegExp(r'^\d{1,2}/\d{1,2}/\d{4}$').hasMatch(clean)) {
    final parts = clean.split('/');
    d = int.tryParse(parts[0]);
    m = int.tryParse(parts[1]);
    y = int.tryParse(parts[2]);
  } else {
    return const DateValidationResult(
      isValid: false,
      error: 'Data incompleta ou inválida (use DD/MM/AAAA)',
    );
  }

  if (d == null || m == null || y == null) {
    return const DateValidationResult(isValid: false, error: 'Data inválida');
  }

  if (y < 1900 || y > 2100) {
    return const DateValidationResult(isValid: false, error: 'Ano deve estar entre 1900 e 2100');
  }
  if (m < 1 || m > 12) {
    return const DateValidationResult(isValid: false, error: 'Mês deve estar entre 01 e 12');
  }
  if (d < 1 || d > 31) {
    return const DateValidationResult(isValid: false, error: 'Dia deve estar entre 01 e 31');
  }

  final dt = DateTime(y, m, d);
  if (dt.year != y || dt.month != m || dt.day != d) {
    return DateValidationResult(isValid: false, error: 'Dia $d inválido para o mês $m/$y');
  }

  final iso = '${y.toString().padLeft(4, "0")}-${m.toString().padLeft(2, "0")}-${d.toString().padLeft(2, "0")}';
  final displayDate = '${d.toString().padLeft(2, "0")}/${m.toString().padLeft(2, "0")}/$y';

  final refNow = now ?? DateTime.now();
  final today = DateTime(refNow.year, refNow.month, refNow.day);
  final target = DateTime(y, m, d);

  // Alerta se mais de 30 dias anterior à data atual
  final diffDays = today.difference(target).inDays;
  if (diffDays > 30) {
    return DateValidationResult(
      isValid: true,
      date: target,
      isoDate: iso,
      isWarning: true,
      warningMessage: 'A data informada ($displayDate) é mais de 30 dias anterior à data atual ($diffDays dias no passado).',
    );
  }

  // Alerta se posterior a 12 meses da data atual (365/366 dias à frente)
  final maxFuture = DateTime(today.year + 1, today.month, today.day);
  if (target.isAfter(maxFuture)) {
    return DateValidationResult(
      isValid: true,
      date: target,
      isoDate: iso,
      isWarning: true,
      warningMessage: 'A data informada ($displayDate) é posterior a 12 meses da data atual.',
    );
  }

  return DateValidationResult(
    isValid: true,
    date: target,
    isoDate: iso,
    isWarning: false,
  );
}

/// Displays a confirmation dialog when the transaction date is more than 30 days in the past
/// or more than 12 months in the future. Returns true if the user chooses to proceed.
Future<bool> confirmDateWarningDialog(
  BuildContext context,
  String warningMessage, {
  required OpenMoneyColors colors,
}) async {
  final res = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: colors.bgSecondary,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colors.borderGlass),
      ),
      title: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, color: Colors.amber, size: 24),
          const SizedBox(width: 8),
          Text(
            'Confirmar Data',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: colors.textPrimary,
            ),
          ),
        ],
      ),
      content: Text(
        '$warningMessage\n\nDeseja salvar o lançamento com esta data mesmo assim?',
        style: TextStyle(fontSize: 13, color: colors.textPrimary),
      ),
      actions: [
        OutlinedButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Corrigir Data'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          style: FilledButton.styleFrom(
            backgroundColor: colors.accent,
            foregroundColor: Colors.white,
          ),
          child: const Text('Salvar Mesmo Assim'),
        ),
      ],
    ),
  );
  return res == true;
}
