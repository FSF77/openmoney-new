import '../models/openmoney_models.dart';

enum CashFlowPeriodKind {
  monthly('Mensal'),
  quarterly('Trimestral'),
  semiannual('Semestral'),
  yearly('Anual');

  final String label;
  const CashFlowPeriodKind(this.label);
}

enum CashFlowStatusFilter {
  all('Todos os status', 'Todos os status'),
  reconciledOnly('Apenas Conciliados', 'Conciliados'),
  pendingOnly('Apenas Não Conciliados', 'Não conciliados');

  final String label;
  final String shortLabel;
  const CashFlowStatusFilter(this.label, this.shortLabel);
}

enum CashFlowDateMode {
  transactionDate('Data do Lançamento', 'Data Lançamento'),
  paymentDate('Data de Pagamento (Fatura)', 'Data Pagamento');

  final String label;
  final String shortLabel;
  const CashFlowDateMode(this.label, this.shortLabel);
}

class CashFlowColumnDef {
  final String id;
  final String title;
  final String shortTitle;
  final bool isCurrent;
  final bool Function(String date) matchesDate;

  const CashFlowColumnDef({
    required this.id,
    required this.title,
    required this.shortTitle,
    required this.isCurrent,
    required this.matchesDate,
  });
}

class CashFlowSubcategoryRow {
  final String name;
  final List<int> periodAmounts; // In cents per column
  final int total;

  const CashFlowSubcategoryRow({
    required this.name,
    required this.periodAmounts,
    required this.total,
  });
}

class CashFlowCategoryGroup {
  final String name;
  final bool hasSubcategories;
  final List<CashFlowSubcategoryRow> subcategories;
  final List<int> periodTotals;
  final int grandTotal;

  const CashFlowCategoryGroup({
    required this.name,
    required this.hasSubcategories,
    required this.subcategories,
    required this.periodTotals,
    required this.grandTotal,
  });
}

class CashFlowSection {
  final String title; // "Rendimento" ou "Despesas"
  final List<CashFlowCategoryGroup> groups;
  final List<int> periodTotals;
  final int grandTotal;

  const CashFlowSection({
    required this.title,
    required this.groups,
    required this.periodTotals,
    required this.grandTotal,
  });
}

class CashFlowMatrix {
  final CashFlowPeriodKind periodKind;
  final int year;
  final String periodSubtitle;
  final CashFlowStatusFilter statusFilter;
  final CashFlowDateMode dateMode;
  final List<CashFlowColumnDef> columns;
  final CashFlowSection incomeSection;
  final CashFlowSection expenseSection;
  final List<int> netPeriodTotals;
  final int netGrandTotal;
  final List<int> priorBalancePeriodTotals;
  final int priorBalanceGrandTotal;
  final List<int> endingBalancePeriodTotals;
  final int endingBalanceGrandTotal;

  const CashFlowMatrix({
    required this.periodKind,
    required this.year,
    required this.periodSubtitle,
    required this.statusFilter,
    required this.dateMode,
    required this.columns,
    required this.incomeSection,
    required this.expenseSection,
    required this.netPeriodTotals,
    required this.netGrandTotal,
    required this.priorBalancePeriodTotals,
    required this.priorBalanceGrandTotal,
    required this.endingBalancePeriodTotals,
    required this.endingBalanceGrandTotal,
  });
}

String fmtCashFlowCents(int cents, {bool showZero = false}) {
  if (cents == 0 && !showZero) return '';
  final isNeg = cents < 0;
  final absCents = cents.abs();
  final intPart = absCents ~/ 100;
  final decPart = (absCents % 100).toString().padLeft(2, '0');

  final intStr = intPart.toString();
  final buffer = StringBuffer();
  for (int i = 0; i < intStr.length; i++) {
    if (i > 0 && (intStr.length - i) % 3 == 0) {
      buffer.write('.');
    }
    buffer.write(intStr[i]);
  }
  final formatted = '${buffer.toString()},$decPart';
  return isNeg ? '-$formatted' : formatted;
}

bool isTransferTransaction(Transaction tx) {
  if (tx.xfer != null) return true;
  if (tx.auto == true) return true;
  final trimmed = tx.cat.trim();
  if (trimmed.isEmpty) return false;
  if (trimmed.startsWith('xfer:')) return true;

  final norm = removeDiacritics(trimmed).toLowerCase();
  if (norm.startsWith('transferencia') ||
      norm.startsWith('transf:') ||
      norm.startsWith('transf.') ||
      norm == 'transf') {
    return true;
  }

  final parts = trimmed.split(RegExp(r'[›:/]'));
  if (parts.isNotEmpty) {
    final firstNorm = removeDiacritics(parts.first.trim()).toLowerCase();
    if (firstNorm == 'transferencia' ||
        firstNorm == 'transf' ||
        firstNorm == 'transfer') {
      return true;
    }
  }
  return false;
}

String effectiveDateForTransaction(
  Transaction tx,
  List<Account> accounts,
  CashFlowDateMode dateMode,
) {
  if (dateMode != CashFlowDateMode.paymentDate) {
    return tx.date;
  }
  Account? acc;
  for (final a in accounts) {
    if (a.id == tx.acc) {
      acc = a;
      break;
    }
  }
  if (acc == null || (acc.type != kCardType && acc.card == null)) {
    return tx.date;
  }
  final cardCfg = acc.card;
  if (cardCfg != null) {
    final ik = tx.ik ?? invKeyFor(cardCfg, tx.date);
    final invInfo = acc.invoices?[ik];
    if (invInfo != null && invInfo.due.isNotEmpty) {
      return invInfo.due;
    }
    return invDates(cardCfg, ik).due;
  }
  return tx.date;
}

class CashFlowEngine {
  static CashFlowMatrix buildMatrix({
    required List<Transaction> transactions,
    List<Account> accounts = const [],
    required CashFlowPeriodKind periodKind,
    required int year,
    String? accountFilterId,
    CashFlowStatusFilter statusFilter = CashFlowStatusFilter.all,
    CashFlowDateMode dateMode = CashFlowDateMode.transactionDate,
    String searchQuery = '',
  }) {
    final currentISO = todayISO();
    final currentYM = currentISO.substring(0, 7);
    final currentYearInt = int.tryParse(currentISO.substring(0, 4)) ?? year;

    late final List<CashFlowColumnDef> columns;
    late final String periodSubtitle;

    switch (periodKind) {
      case CashFlowPeriodKind.monthly:
        periodSubtitle = '01/01/$year até 31/12/$year';
        const monthNames = [
          'Jan',
          'Fev',
          'Mar',
          'Abr',
          'Mai',
          'Jun',
          'Jul',
          'Ago',
          'Set',
          'Out',
          'Nov',
          'Dez'
        ];
        columns = List.generate(12, (idx) {
          final m = idx + 1;
          final ymPrefix = '${year.toString().padLeft(4, '0')}-${pad2(m)}';
          final title = '${pad2(m)}/${year.toString().padLeft(4, '0')}';
          final short = '${monthNames[m - 1]}/${pad2(year % 100)}';
          return CashFlowColumnDef(
            id: ymPrefix,
            title: title,
            shortTitle: short,
            isCurrent: ymPrefix == currentYM,
            matchesDate: (d) => d.startsWith(ymPrefix),
          );
        });
        break;

      case CashFlowPeriodKind.quarterly:
        periodSubtitle = '01/01/$year até 31/12/$year';
        columns = List.generate(4, (idx) {
          final q = idx + 1;
          final startM = (q - 1) * 3 + 1;
          final ymPrefixes = List.generate(
            3,
            (i) => '${year.toString().padLeft(4, '0')}-${pad2(startM + i)}',
          );
          final isCurrentQ =
              (year == currentYearInt) && ymPrefixes.contains(currentYM);
          return CashFlowColumnDef(
            id: 'Q$q-$year',
            title: '$qº Trimestre',
            shortTitle: '$qº Trim',
            isCurrent: isCurrentQ,
            matchesDate: (d) => ymPrefixes.any((p) => d.startsWith(p)),
          );
        });
        break;

      case CashFlowPeriodKind.semiannual:
        periodSubtitle = '01/01/$year até 31/12/$year';
        columns = List.generate(2, (idx) {
          final s = idx + 1;
          final startM = s == 1 ? 1 : 7;
          final ymPrefixes = List.generate(
            6,
            (i) => '${year.toString().padLeft(4, '0')}-${pad2(startM + i)}',
          );
          final isCurrentS =
              (year == currentYearInt) && ymPrefixes.contains(currentYM);
          return CashFlowColumnDef(
            id: 'S$s-$year',
            title: '$sº Semestre',
            shortTitle: '$sº Sem',
            isCurrent: isCurrentS,
            matchesDate: (d) => ymPrefixes.any((p) => d.startsWith(p)),
          );
        });
        break;

      case CashFlowPeriodKind.yearly:
        final distinctYears = <int>{currentYearInt, year};
        for (final tx in transactions) {
          final d = effectiveDateForTransaction(tx, accounts, dateMode);
          if (d.length >= 4) {
            final y = int.tryParse(d.substring(0, 4));
            if (y != null && y >= 2000 && y <= 2100) {
              distinctYears.add(y);
            }
          }
        }
        final sortedYears = distinctYears.toList()..sort();
        final minYear = sortedYears.isNotEmpty ? sortedYears.first : year;
        final maxYear = sortedYears.isNotEmpty ? sortedYears.last : year;
        periodSubtitle = '01/01/$minYear até 31/12/$maxYear';
        columns = sortedYears.map((y) {
          final yStr = y.toString();
          return CashFlowColumnDef(
            id: yStr,
            title: yStr,
            shortTitle: yStr,
            isCurrent: y == currentYearInt,
            matchesDate: (d) => d.startsWith(yStr),
          );
        }).toList();
        break;
    }

    final numCols = columns.length;
    final isSpecificAccount =
        accountFilterId != null && accountFilterId.isNotEmpty;

    final filteredTxs = transactions.where((tx) {
      if (isSpecificAccount && tx.acc != accountFilterId) {
        return false;
      }
      if (!isSpecificAccount && isTransferTransaction(tx)) {
        return false;
      }
      switch (statusFilter) {
        case CashFlowStatusFilter.all:
          break;
        case CashFlowStatusFilter.reconciledOnly:
          if (!tx.rec) return false;
          break;
        case CashFlowStatusFilter.pendingOnly:
          if (tx.rec) return false;
          break;
      }
      return true;
    }).toList();

    ({String top, String? sub}) parseCat(Transaction tx) {
      final isXfer = isTransferTransaction(tx);
      final trimmed = tx.cat.trim();
      if (trimmed.isEmpty) {
        if (isXfer) {
          String? peerName;
          if (tx.peer != null) {
            for (final a in accounts) {
              if (a.id == tx.peer) {
                peerName = a.name;
                break;
              }
            }
          }
          if (peerName == null && tx.card != null) {
            for (final a in accounts) {
              if (a.id == tx.card) {
                peerName = a.name;
                break;
              }
            }
          }
          return (top: 'Transferência', sub: peerName);
        }
        return (top: 'Sem categoria', sub: null);
      }

      List<String> parts;
      if (trimmed.contains(kCategorySep)) {
        parts = trimmed.split(kCategorySep);
      } else if (trimmed.contains(' : ')) {
        parts = trimmed.split(' : ');
      } else if (trimmed.contains(':')) {
        parts = trimmed.split(':');
      } else if (trimmed.contains(' / ')) {
        parts = trimmed.split(' / ');
      } else {
        parts = [trimmed];
      }

      var top = parts[0].trim();
      String? sub = parts.length > 1 ? parts[1].trim() : null;

      final topNorm = removeDiacritics(top).toLowerCase();
      if (topNorm == 'transferencia' ||
          topNorm == 'transf' ||
          topNorm == 'transfer') {
        top = 'Transferência';
      }

      if ((sub == null || sub.isEmpty) && isXfer) {
        if (tx.peer != null) {
          for (final a in accounts) {
            if (a.id == tx.peer) {
              sub = a.name;
              break;
            }
          }
        } else if (tx.card != null) {
          for (final a in accounts) {
            if (a.id == tx.card) {
              sub = a.name;
              break;
            }
          }
        }
      }

      return (
        top: top.isEmpty ? 'Sem categoria' : top,
        sub: (sub != null && sub.isEmpty) ? null : sub,
      );
    }

    final incMap = <String, Map<String, List<int>>>{};
    final expMap = <String, Map<String, List<int>>>{};

    for (final tx in filteredTxs) {
      if (tx.amt == 0) continue;
      final effDate = effectiveDateForTransaction(tx, accounts, dateMode);
      int colIdx = -1;
      for (int i = 0; i < numCols; i++) {
        if (columns[i].matchesDate(effDate)) {
          colIdx = i;
          break;
        }
      }
      if (colIdx < 0) continue;

      final isIncome = tx.amt > 0;
      final absCents = tx.amt.abs();
      final parsed = parseCat(tx);
      final subKey = parsed.sub ?? '___DIRECT___';

      final targetMap = isIncome ? incMap : expMap;
      final topEntry = targetMap.putIfAbsent(parsed.top, () => {});
      final subEntry =
          topEntry.putIfAbsent(subKey, () => List<int>.filled(numCols, 0));
      subEntry[colIdx] += absCents;
    }

    CashFlowSection buildSection(
      String title,
      Map<String, Map<String, List<int>>> dataMap,
    ) {
      final groups = <CashFlowCategoryGroup>[];
      final sectionPeriodTotals = List<int>.filled(numCols, 0);
      int sectionGrandTotal = 0;

      final q = searchQuery.trim().toLowerCase();
      final sortedTops = dataMap.keys.toList()..sort(cmpPt);

      for (final top in sortedTops) {
        final subMap = dataMap[top]!;
        final realSubKeys =
            subMap.keys.where((k) => k != '___DIRECT___').toList();
        final hasNamedSubs = realSubKeys.isNotEmpty;

        var subRows = <CashFlowSubcategoryRow>[];
        final topPeriodTotals = List<int>.filled(numCols, 0);
        int topGrandTotal = 0;

        if (hasNamedSubs) {
          final directAmounts = subMap['___DIRECT___'];
          if (directAmounts != null) {
            final directSum = directAmounts.fold<int>(0, (a, b) => a + b);
            if (directSum > 0) {
              subRows.add(
                CashFlowSubcategoryRow(
                  name: '$top - Não-atribuído',
                  periodAmounts: directAmounts,
                  total: directSum,
                ),
              );
            }
          }

          realSubKeys.sort(cmpPt);
          for (final subName in realSubKeys) {
            final amounts = subMap[subName] ?? List<int>.filled(numCols, 0);
            final subSum = amounts.fold<int>(0, (a, b) => a + b);
            subRows.add(
              CashFlowSubcategoryRow(
                name: subName,
                periodAmounts: amounts,
                total: subSum,
              ),
            );
          }

          for (int i = 0; i < numCols; i++) {
            int sumForCol = 0;
            for (final r in subRows) {
              sumForCol += r.periodAmounts[i];
            }
            topPeriodTotals[i] = sumForCol;
          }
          topGrandTotal = topPeriodTotals.fold<int>(0, (a, b) => a + b);

          if (q.isNotEmpty) {
            final matchTop = top.toLowerCase().contains(q);
            final filteredSubs = subRows
                .where((r) => r.name.toLowerCase().contains(q))
                .toList();
            if (!matchTop && filteredSubs.isEmpty) {
              continue;
            }
            if (!matchTop) {
              subRows = filteredSubs;
              for (int i = 0; i < numCols; i++) {
                topPeriodTotals[i] =
                    subRows.fold<int>(0, (a, r) => a + r.periodAmounts[i]);
              }
              topGrandTotal = topPeriodTotals.fold<int>(0, (a, b) => a + b);
            }
          }

          if (topGrandTotal > 0) {
            groups.add(
              CashFlowCategoryGroup(
                name: top,
                hasSubcategories: true,
                subcategories: subRows,
                periodTotals: topPeriodTotals,
                grandTotal: topGrandTotal,
              ),
            );
            for (int i = 0; i < numCols; i++) {
              sectionPeriodTotals[i] += topPeriodTotals[i];
            }
            sectionGrandTotal += topGrandTotal;
          }
        } else {
          final amounts =
              subMap['___DIRECT___'] ?? List<int>.filled(numCols, 0);
          final catSum = amounts.fold<int>(0, (a, b) => a + b);
          if (q.isNotEmpty && !top.toLowerCase().contains(q)) {
            continue;
          }
          if (catSum > 0) {
            groups.add(
              CashFlowCategoryGroup(
                name: top,
                hasSubcategories: false,
                subcategories: const [],
                periodTotals: amounts,
                grandTotal: catSum,
              ),
            );
            for (int i = 0; i < numCols; i++) {
              sectionPeriodTotals[i] += amounts[i];
            }
            sectionGrandTotal += catSum;
          }
        }
      }

      return CashFlowSection(
        title: title,
        groups: groups,
        periodTotals: sectionPeriodTotals,
        grandTotal: sectionGrandTotal,
      );
    }

    final incomeSection = buildSection('Rendimento', incMap);
    final expenseSection = buildSection('Despesas', expMap);

    final netTotals = List<int>.generate(
      numCols,
      (i) => incomeSection.periodTotals[i] - expenseSection.periodTotals[i],
    );
    final netGrand = incomeSection.grandTotal - expenseSection.grandTotal;

    int initialOpening = 0;
    if (isSpecificAccount) {
      for (final a in accounts) {
        if (a.id == accountFilterId) {
          initialOpening = a.type == kCardType ? 0 : a.opening;
          break;
        }
      }
    } else {
      for (final a in accounts) {
        initialOpening += (a.type == kCardType ? 0 : a.opening);
      }
    }

    final colStartDates = List<String>.generate(numCols, (i) {
      switch (periodKind) {
        case CashFlowPeriodKind.monthly:
          return '${year.toString().padLeft(4, '0')}-${pad2(i + 1)}-01';
        case CashFlowPeriodKind.quarterly:
          final qMonth = i * 3 + 1;
          return '${year.toString().padLeft(4, '0')}-${pad2(qMonth)}-01';
        case CashFlowPeriodKind.semiannual:
          final sMonth = (i == 0 ? 1 : 7);
          return '${year.toString().padLeft(4, '0')}-${pad2(sMonth)}-01';
        case CashFlowPeriodKind.yearly:
          return '${columns[i].id}-01-01';
      }
    });

    final baseOpening =
        (statusFilter == CashFlowStatusFilter.pendingOnly ? 0 : initialOpening);
    final priorDeltas = List<int>.filled(numCols, 0);
    final firstColStart = colStartDates.isNotEmpty ? colStartDates.first : '';
    final validAccountIds = accounts.map((a) => a.id).toSet();

    for (final tx in transactions) {
      if (isSpecificAccount && tx.acc != accountFilterId) continue;
      if (accounts.isNotEmpty && !validAccountIds.contains(tx.acc)) continue;

      switch (statusFilter) {
        case CashFlowStatusFilter.all:
          break;
        case CashFlowStatusFilter.reconciledOnly:
          if (!tx.rec) continue;
          break;
        case CashFlowStatusFilter.pendingOnly:
          if (tx.rec) continue;
          break;
      }

      final effDate = effectiveDateForTransaction(tx, accounts, dateMode);
      if (effDate.compareTo(firstColStart) < 0) {
        if (numCols > 0) priorDeltas[0] += tx.amt;
      } else {
        for (int c = 1; c < numCols; c++) {
          if (effDate.compareTo(colStartDates[c]) < 0 &&
              effDate.compareTo(colStartDates[c - 1]) >= 0) {
            priorDeltas[c] += tx.amt;
            break;
          }
        }
      }
    }

    final priorBalances = List<int>.filled(numCols, 0);
    int runningPrior = baseOpening;
    for (int i = 0; i < numCols; i++) {
      runningPrior += priorDeltas[i];
      priorBalances[i] = runningPrior;
    }

    final endingBalances = List<int>.generate(
      numCols,
      (i) => priorBalances[i] + netTotals[i],
    );

    final priorGrandTotal = priorBalances.isNotEmpty ? priorBalances.first : 0;
    final endingGrandTotal = priorGrandTotal + netGrand;

    return CashFlowMatrix(
      periodKind: periodKind,
      year: year,
      periodSubtitle: periodSubtitle,
      statusFilter: statusFilter,
      dateMode: dateMode,
      columns: columns,
      incomeSection: incomeSection,
      expenseSection: expenseSection,
      netPeriodTotals: netTotals,
      netGrandTotal: netGrand,
      priorBalancePeriodTotals: priorBalances,
      priorBalanceGrandTotal: priorGrandTotal,
      endingBalancePeriodTotals: endingBalances,
      endingBalanceGrandTotal: endingGrandTotal,
    );
  }

  static String generateCSV(CashFlowMatrix matrix) {
    final lines = <String>[];
    lines.add('Fluxo de caixa ${matrix.periodKind.label.toLowerCase()}');
    lines.add('');
    lines.add(matrix.periodSubtitle);
    lines.add(
      'Filtros: Status: ${matrix.statusFilter.label};Regime: ${matrix.dateMode.label}',
    );
    lines.add('');
    lines.add('');

    final headerCells = <String>[
      'Subcategoria',
      ...matrix.columns.map((c) => c.title),
      'Total',
    ];
    lines.add(headerCells.join(';'));
    lines.add('');

    String escape(String str) {
      if (str.contains(';') || str.contains('"') || str.contains('\n')) {
        return '"${str.replaceAll('"', '""')}"';
      }
      return str;
    }

    void writeSection(CashFlowSection sec) {
      lines.add(escape(sec.title));
      for (final group in sec.groups) {
        if (group.hasSubcategories) {
          lines.add(escape(group.name));
          for (final sub in group.subcategories) {
            final rowCells = <String>[
              escape(sub.name),
              ...sub.periodAmounts.map((amt) => fmtCashFlowCents(amt)),
              fmtCashFlowCents(sub.total, showZero: true),
            ];
            lines.add(rowCells.join(';'));
          }
          final totalRowCells = <String>[
            escape('Total ${group.name}'),
            ...group.periodTotals.map((amt) => fmtCashFlowCents(amt)),
            fmtCashFlowCents(group.grandTotal, showZero: true),
          ];
          lines.add(totalRowCells.join(';'));
        } else {
          final rowCells = <String>[
            escape(group.name),
            ...group.periodTotals.map((amt) => fmtCashFlowCents(amt)),
            fmtCashFlowCents(group.grandTotal, showZero: true),
          ];
          lines.add(rowCells.join(';'));
        }
      }

      final secTotalCells = <String>[
        escape('Total ${sec.title}'),
        ...sec.periodTotals.map((amt) => fmtCashFlowCents(amt)),
        fmtCashFlowCents(sec.grandTotal, showZero: true),
      ];
      lines.add(secTotalCells.join(';'));
      lines.add('');
    }

    writeSection(matrix.incomeSection);
    writeSection(matrix.expenseSection);

    lines.add([
      escape('Rendimento menos Despesas'),
      ...matrix.netPeriodTotals
          .map((amt) => fmtCashFlowCents(amt, showZero: true)),
      fmtCashFlowCents(matrix.netGrandTotal, showZero: true),
    ].join(';'));

    lines.add([
      escape('Saldo Anterior Acumulado'),
      ...matrix.priorBalancePeriodTotals
          .map((amt) => fmtCashFlowCents(amt, showZero: true)),
      fmtCashFlowCents(matrix.priorBalanceGrandTotal, showZero: true),
    ].join(';'));

    lines.add([
      escape('Saldo Final Acumulado'),
      ...matrix.endingBalancePeriodTotals
          .map((amt) => fmtCashFlowCents(amt, showZero: true)),
      fmtCashFlowCents(matrix.endingBalanceGrandTotal, showZero: true),
    ].join(';'));

    return '\uFEFF${lines.join('\r\n')}';
  }
}
