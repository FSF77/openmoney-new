import 'package:flutter/material.dart';
import '../../models/agenda_models.dart';
import '../../models/openmoney_models.dart';
import '../../services/agenda_engine.dart';
import '../../services/category_icon_registry.dart';
import '../../services/pdf_report_generator.dart';
import '../../store/money_store.dart';
import '../modals/agenda_help_modal.dart';
import '../modals/investment_modals.dart';
import '../modals/transaction_modal.dart';
import '../theme/liquid_glass.dart';

class AgendaView extends StatefulWidget {
  final MoneyStore store;

  const AgendaView({super.key, required this.store});

  @override
  State<AgendaView> createState() => _AgendaViewState();
}

class _AgendaViewState extends State<AgendaView> {
  late String _currentMonth; // "YYYY-MM"
  final Set<String> _selectedFilters = {'bills', 'income'};
  String? _selectedMobileDate;

  MoneyStore get store => widget.store;

  @override
  void initState() {
    super.initState();
    final today = todayISO();
    _currentMonth = today.substring(0, 7);
    _selectedMobileDate = today;

    // Carregar filtros persistidos se existirem
    if (store.agendaFilters.isNotEmpty) {
      _selectedFilters.clear();
      _selectedFilters.addAll(store.agendaFilters);
    }
  }

  void _prevMonth() {
    final parts = _currentMonth.split('-');
    int y = int.parse(parts[0]);
    int m = int.parse(parts[1]) - 1;
    if (m < 1) {
      m = 12;
      y -= 1;
    }
    setState(() {
      _currentMonth = '$y-${m.toString().padLeft(2, "0")}';
      _selectedMobileDate = '$_currentMonth-01';
    });
  }

  void _nextMonth() {
    final parts = _currentMonth.split('-');
    int y = int.parse(parts[0]);
    int m = int.parse(parts[1]) + 1;
    if (m > 12) {
      m = 1;
      y += 1;
    }
    setState(() {
      _currentMonth = '$y-${m.toString().padLeft(2, "0")}';
      _selectedMobileDate = '$_currentMonth-01';
    });
  }

  void _jumpToToday() {
    final today = todayISO();
    setState(() {
      _currentMonth = today.substring(0, 7);
      _selectedMobileDate = today;
    });
  }

  void _toggleFilter(String key) {
    setState(() {
      if (_selectedFilters.contains(key)) {
        if (_selectedFilters.length > 1) {
          _selectedFilters.remove(key);
        }
      } else {
        _selectedFilters.add(key);
      }
      store.setAgendaFilters(_selectedFilters.toList());
    });
  }

  void _openTransactionModal({required String txType, String? initialDate}) {
    final targetDate = initialDate ??
        (_currentMonth == todayISO().substring(0, 7)
            ? todayISO()
            : '$_currentMonth-01');
    showTransactionCreateModal(
      context,
      store,
      initialDateIso: targetDate,
      initialTxType: txType,
    ).then((_) => setState(() {}));
  }

  Future<void> _exportPdf() async {
    final bytes = PdfReportGenerator.buildAgendaReportPdfBytes(
      store,
      _currentMonth,
      includeDone: _selectedFilters.contains('done'),
    );
    final fileName = 'agenda_${_currentMonth.replaceAll("-", "_")}.pdf';
    await PdfReportGenerator.saveAndOpenPdfBytes(
      context,
      pdfBytes: bytes,
      defaultFileName: fileName,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colors = OpenMoneyColors(isDark);
    final isMobile = MediaQuery.sizeOf(context).width < 760;

    final showBills = _selectedFilters.contains('bills');
    final showIncome = _selectedFilters.contains('income');
    final showDone = _selectedFilters.contains('done');

    // Gerar dados
    final allEntries = AgendaEngine.generateMonthEntries(
      store: store,
      month: _currentMonth,
      includeDone: true,
    );

    // Contadores para chips
    int billsCount = 0;
    int incomeCount = 0;
    int doneCount = 0;
    for (final e in allEntries) {
      if (e.isDone) {
        doneCount++;
      } else if (e.isPayable) {
        billsCount++;
      } else if (e.isIncome) {
        incomeCount++;
      }
    }

    // Filtrar entradas de acordo com chips selecionados
    final visibleEntries = allEntries.where((e) {
      if (e.isDone) {
        return showDone;
      }
      if (e.isPayable && !showBills) return false;
      if (e.isIncome && !showIncome) return false;
      return true;
    }).toList();

    final summary = AgendaEngine.calculateMonthSummary(
      store: store,
      month: _currentMonth,
    );

    final gridDays = AgendaEngine.buildGridDays(
      month: _currentMonth,
      entries: visibleEntries,
    );

    return Scaffold(
      backgroundColor: colors.bgPrimary,
      body: SingleChildScrollView(
        padding: EdgeInsets.symmetric(
          horizontal: isMobile ? 12 : 24,
          vertical: isMobile ? 12 : 18,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. Cabeçalho Superior (Título, Mês, Hoje, Botões de Despesa/Receita/Transf)
            _buildTopHeader(colors, isMobile),
            const SizedBox(height: 14),

            // 2. Barra de Filtros e Ações (Como funciona, Imprimir)
            _buildFilterChipsBar(
              colors,
              isMobile,
              billsCount: billsCount,
              incomeCount: incomeCount,
              doneCount: doneCount,
            ),
            const SizedBox(height: 12),

            // 4. Cartões de Resumo
            _buildSummaryCards(colors, summary, isMobile),
            const SizedBox(height: 14),

            // 5. Grade do Calendário (Desktop / Mobile)
            if (isMobile)
              _buildMobileCalendar(colors, gridDays)
            else
              _buildDesktopCalendar(colors, gridDays),

            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  // MARK: - 1. Top Header
  Widget _buildTopHeader(OpenMoneyColors colors, bool isMobile) {
    final monthParts = _currentMonth.split('-');
    final y = monthParts[0];
    final mLabel = fmtMonth(_currentMonth);

    final actionButtons = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildActionButton(
          label: isMobile ? null : 'Nova Despesa',
          tooltip: 'Registrar Nova Despesa',
          icon: Icons.arrow_downward_rounded,
          color: Colors.redAccent,
          bgColor: Colors.redAccent.withValues(alpha: 0.16),
          onPressed: () => _openTransactionModal(txType: 'expense'),
        ),
        const SizedBox(width: 6),
        _buildActionButton(
          label: isMobile ? null : 'Nova Receita',
          tooltip: 'Registrar Nova Receita',
          icon: Icons.arrow_upward_rounded,
          color: Colors.green,
          bgColor: Colors.green.withValues(alpha: 0.16),
          onPressed: () => _openTransactionModal(txType: 'income'),
        ),
        const SizedBox(width: 6),
        _buildActionButton(
          label: isMobile ? null : 'Transferência',
          tooltip: 'Registrar Nova Transferência',
          icon: Icons.swap_horiz_rounded,
          color: colors.accent,
          bgColor: colors.accent.withValues(alpha: 0.16),
          onPressed: () => _openTransactionModal(txType: 'transfer'),
        ),
      ],
    );

    if (isMobile) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Agenda',
                style: TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w900,
                  color: colors.textPrimary,
                  letterSpacing: -0.5,
                ),
              ),
              actionButtons,
            ],
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                decoration: BoxDecoration(
                  color: colors.bgSecondary,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: colors.borderGlass),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.chevron_left, size: 20),
                      color: colors.textPrimary,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                      tooltip: 'Mês anterior',
                      onPressed: _prevMonth,
                    ),
                    Flexible(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        child: Text(
                          '$mLabel de $y',
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: colors.textPrimary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.chevron_right, size: 20),
                      color: colors.textPrimary,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                      tooltip: 'Próximo mês',
                      onPressed: _nextMonth,
                    ),
                  ],
                ),
              ),
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  side: BorderSide(color: colors.borderGlass),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: _jumpToToday,
                child: Text(
                  'Hoje',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: colors.textPrimary,
                  ),
                ),
              ),
            ],
          ),
        ],
      );
    }

    return Wrap(
      spacing: 12,
      runSpacing: 10,
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Agenda',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w900,
                color: colors.textPrimary,
                letterSpacing: -0.5,
              ),
            ),
            const SizedBox(width: 16),

            // Navegação de mês < Mês AAAA >
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              decoration: BoxDecoration(
                color: colors.bgSecondary,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: colors.borderGlass),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.chevron_left, size: 20),
                    color: colors.textPrimary,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                    tooltip: 'Mês anterior',
                    onPressed: _prevMonth,
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 6),
                    child: Text(
                      '$mLabel de $y',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: colors.textPrimary,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.chevron_right, size: 20),
                    color: colors.textPrimary,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                    tooltip: 'Próximo mês',
                    onPressed: _nextMonth,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),

            OutlinedButton(
              style: OutlinedButton.styleFrom(
                visualDensity: VisualDensity.compact,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                side: BorderSide(color: colors.borderGlass),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: _jumpToToday,
              child: Text(
                'Hoje',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: colors.textPrimary,
                ),
              ),
            ),
          ],
        ),

        actionButtons,
      ],
    );
  }

  Widget _buildActionButton({
    String? label,
    required String tooltip,
    required IconData icon,
    required Color color,
    required Color bgColor,
    required VoidCallback onPressed,
  }) {
    if (label == null) {
      return Tooltip(
        message: tooltip,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(20),
          child: Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: bgColor,
              shape: BoxShape.circle,
              border: Border.all(color: color.withValues(alpha: 0.3)),
            ),
            child: Icon(icon, size: 16, color: color),
          ),
        ),
      );
    }

    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: BoxDecoration(
            color: bgColor,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color.withValues(alpha: 0.3)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, size: 13, color: color),
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // MARK: - 3. Filter Chips Bar
  Widget _buildFilterChipsBar(
    OpenMoneyColors colors,
    bool isMobile, {
    required int billsCount,
    required int incomeCount,
    required int doneCount,
  }) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        _buildChip(
          label: 'Contas e faturas',
          count: billsCount,
          dotColor: const Color(0xFFF59E0B), // Laranja âmbar
          selected: _selectedFilters.contains('bills'),
          colors: colors,
          onTap: () => _toggleFilter('bills'),
        ),
        _buildChip(
          label: 'Receitas previstas',
          count: incomeCount,
          dotColor: const Color(0xFF10B981), // Verde esmeralda
          selected: _selectedFilters.contains('income'),
          colors: colors,
          onTap: () => _toggleFilter('income'),
        ),
        _buildChip(
          label: 'Concluídos',
          count: doneCount,
          dotColor: Colors.grey,
          selected: _selectedFilters.contains('done'),
          colors: colors,
          onTap: () => _toggleFilter('done'),
        ),

        const SizedBox(width: 8),

        InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: () => showAgendaHelpModal(context),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.help_outline, size: 15, color: colors.accent),
                const SizedBox(width: 4),
                Text(
                  'Como funciona',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: colors.accent,
                  ),
                ),
              ],
            ),
          ),
        ),

        InkWell(
          borderRadius: BorderRadius.circular(6),
          onTap: _exportPdf,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.print_outlined, size: 15, color: colors.accent),
                const SizedBox(width: 4),
                Text(
                  'Imprimir',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w600,
                    color: colors.accent,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildChip({
    required String label,
    required int count,
    required Color dotColor,
    required bool selected,
    required OpenMoneyColors colors,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? dotColor.withValues(alpha: 0.15)
              : colors.bgSecondary,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? dotColor.withValues(alpha: 0.6) : colors.borderGlass,
            width: selected ? 1.2 : 1.0,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: dotColor,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 7),
            Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                color: selected ? colors.textPrimary : colors.textSecondary,
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: selected
                    ? dotColor.withValues(alpha: 0.25)
                    : colors.borderGlass.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: selected ? colors.textPrimary : colors.textSecondary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // MARK: - 4. Summary Cards (Compact 2-line KPI Pills)
  Widget _buildSummaryCards(
    OpenMoneyColors colors,
    AgendaMonthSummary summary,
    bool isMobile,
  ) {
    final cur = summary.currency;

    final cardPay = _buildCompactKpiCard(
      label: isMobile ? 'A Pagar' : 'A Pagar no Mês',
      info: summary.overdueCount > 0
          ? '${summary.overdueCount} atrasada${summary.overdueCount > 1 ? "s" : ""}'
          : '${summary.pendingPayCount} ${summary.pendingPayCount == 1 ? "conta" : "contas"}',
      isAlertInfo: summary.overdueCount > 0,
      cents: summary.pendingPayTotalCents,
      currency: cur,
      color: colors.expense,
      icon: Icons.trending_down,
      colors: colors,
      isMobile: isMobile,
    );

    final cardRec = _buildCompactKpiCard(
      label: isMobile ? 'A Receber' : 'A Receber no Mês',
      info: '${summary.pendingReceiveCount} ${summary.pendingReceiveCount == 1 ? "receita" : "receitas"}',
      isAlertInfo: false,
      cents: summary.pendingReceiveTotalCents,
      currency: cur,
      color: colors.income,
      icon: Icons.trending_up,
      colors: colors,
      isMobile: isMobile,
    );

    return Row(
      children: [
        Expanded(child: cardPay),
        SizedBox(width: isMobile ? 8 : 12),
        Expanded(child: cardRec),
      ],
    );
  }

  Widget _buildCompactKpiCard({
    required String label,
    required String info,
    required bool isAlertInfo,
    required int cents,
    required String currency,
    required Color color,
    required IconData icon,
    required OpenMoneyColors colors,
    required bool isMobile,
  }) {
    final valStr = formatCurrency(cents, currency);

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: isMobile ? 10 : 14,
        vertical: isMobile ? 8 : 10,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.22)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Linha 1: Ícone + Rótulo + Contador/Atrasados
          Row(
            children: [
              Icon(icon, size: isMobile ? 13 : 15, color: color),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: isMobile ? 11 : 12,
                    fontWeight: FontWeight.w600,
                    color: colors.textSecondary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                info,
                style: TextStyle(
                  fontSize: isMobile ? 10 : 11,
                  fontWeight: isAlertInfo ? FontWeight.w700 : FontWeight.w500,
                  color: isAlertInfo ? colors.expense : colors.textSecondary,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
          const SizedBox(height: 4),

          // Linha 2: Valor formatado
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              valStr,
              style: TextStyle(
                fontSize: isMobile ? 15 : 18,
                fontWeight: FontWeight.w800,
                color: color,
                letterSpacing: -0.3,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // MARK: - 5. Desktop Calendar Grid
  Widget _buildDesktopCalendar(OpenMoneyColors colors, List<AgendaGridDay> gridDays) {
    const weekdays = ['DOM', 'SEG', 'TER', 'QUA', 'QUI', 'SEX', 'SÁB'];
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final gridBorderColor = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : const Color(0xFFE2E8F0);

    return Container(
      decoration: BoxDecoration(
        color: colors.bgSecondary,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.borderGlass),
      ),
      child: Column(
        children: [
          // Cabeçalho dos dias da semana
          Container(
            padding: const EdgeInsets.symmetric(vertical: 9),
            decoration: BoxDecoration(
              border: Border(
                bottom: BorderSide(color: gridBorderColor, width: 0.8),
              ),
            ),
            child: Row(
              children: weekdays.map((wd) {
                return Expanded(
                  child: Center(
                    child: Text(
                      wd,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: colors.textSecondary,
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),

          // Grade de semanas (altura um pouco maior e proporção 1.18)
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: gridDays.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              childAspectRatio: 1.18,
            ),
            itemBuilder: (context, index) {
              final day = gridDays[index];
              return _buildCalendarCell(
                colors,
                day,
                index: index,
                totalCount: gridDays.length,
                borderColor: gridBorderColor,
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildCalendarCell(
    OpenMoneyColors colors,
    AgendaGridDay day, {
    required int index,
    required int totalCount,
    required Color borderColor,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const maxItems = 4;
    final visibleItems = day.entries.take(maxItems).toList();
    final extraCount = day.entries.length - maxItems;

    final isLastCol = (index % 7) == 6;
    final isLastRow = index >= (totalCount - 7);

    return Container(
      decoration: BoxDecoration(
        color: day.isToday
            ? colors.accent.withValues(alpha: isDark ? 0.08 : 0.04)
            : (day.isCurrentMonth
                ? Colors.transparent
                : (isDark
                    ? Colors.white.withValues(alpha: 0.02)
                    : const Color(0xFFF8FAFC))),
        border: Border(
          right: isLastCol ? BorderSide.none : BorderSide(color: borderColor, width: 0.8),
          bottom: isLastRow ? BorderSide.none : BorderSide(color: borderColor, width: 0.8),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Número do dia e ações
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Número do dia clicável com tooltip e feedback
              Tooltip(
                message: 'Ver lançamentos do dia ${day.dayNumber}',
                child: InkWell(
                  onTap: () => _showDayEntriesDialog(day),
                  borderRadius: BorderRadius.circular(10),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
                    child: Container(
                      width: 18,
                      height: 18,
                      alignment: Alignment.center,
                      decoration: day.isToday
                          ? BoxDecoration(
                              color: colors.accent,
                              shape: BoxShape.circle,
                            )
                          : null,
                      child: Text(
                        '${day.dayNumber}',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: day.isToday ? FontWeight.w900 : FontWeight.w700,
                          color: day.isToday
                              ? Colors.white
                              : (day.isCurrentMonth
                                  ? colors.textPrimary
                                  : colors.textSecondary.withValues(alpha: 0.4)),
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              // Ação à direita: Novo lançamento (+)
              PopupMenuButton<String>(
                tooltip: 'Novo lançamento',
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                iconSize: 13,
                icon: Icon(
                  Icons.add,
                  size: 13,
                  color: colors.textSecondary.withValues(alpha: 0.4),
                ),
                onSelected: (txType) => _openTransactionModal(
                  txType: txType,
                  initialDate: day.date,
                ),
                itemBuilder: (ctx) => [
                  const PopupMenuItem(
                    value: 'expense',
                    height: 32,
                    child: Row(
                      children: [
                        Icon(Icons.arrow_downward_rounded, size: 14, color: Colors.redAccent),
                        SizedBox(width: 8),
                        Text('Nova Despesa', style: TextStyle(fontSize: 12)),
                      ],
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'income',
                    height: 32,
                    child: Row(
                      children: [
                        Icon(Icons.arrow_upward_rounded, size: 14, color: Colors.green),
                        SizedBox(width: 8),
                        Text('Nova Receita', style: TextStyle(fontSize: 12)),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'transfer',
                    height: 32,
                    child: Row(
                      children: [
                        Icon(Icons.swap_horiz_rounded, size: 14, color: colors.accent),
                        const SizedBox(width: 8),
                        const Text('Nova Transferência', style: TextStyle(fontSize: 12)),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 2),

          // Lista de pílulas do dia (mais itens com fonte compacta)
          Expanded(
            child: ListView.separated(
              physics: const NeverScrollableScrollPhysics(),
              itemCount: visibleItems.length,
              separatorBuilder: (_, _) => const SizedBox(height: 2),
              itemBuilder: (context, idx) {
                final entry = visibleItems[idx];
                return _buildEntryPill(colors, entry);
              },
            ),
          ),

          // Botão +N mais
          if (extraCount > 0)
            InkWell(
              onTap: () => _showDayEntriesDialog(day),
              child: Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Text(
                  '+$extraCount mais',
                  style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.w700,
                    color: colors.accent,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildEntryPill(OpenMoneyColors colors, AgendaEntry entry) {
    final isIncome = entry.isIncome;
    final prefix = isIncome ? '+' : '';
    final valStr = '$prefix${formatCurrency(entry.amountCents, entry.currency)}';

    final pillBg = entry.isDone
        ? colors.borderGlass.withValues(alpha: 0.3)
        : (isIncome
            ? const Color(0xFF10B981).withValues(alpha: 0.15)
            : const Color(0xFFF59E0B).withValues(alpha: 0.15));

    final dotColor = entry.isDone
        ? Colors.grey
        : (isIncome ? const Color(0xFF10B981) : const Color(0xFFF59E0B));

    final textStyle = TextStyle(
      fontSize: 9.5,
      fontWeight: FontWeight.w700,
      decoration: entry.isDone ? TextDecoration.lineThrough : null,
      color: entry.isDone
          ? colors.textSecondary
          : colors.textPrimary,
    );

    return InkWell(
      onTap: () => _showEntryDetailsDialog(entry),
      borderRadius: BorderRadius.circular(5),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1.5),
        decoration: BoxDecoration(
          color: pillBg,
          borderRadius: BorderRadius.circular(5),
          border: Border.all(
            color: entry.isOverdue
                ? colors.expense.withValues(alpha: 0.6)
                : dotColor.withValues(alpha: 0.3),
            width: 0.6,
          ),
        ),
        child: Row(
          children: [
            CategoryIconBadge(
              store: widget.store,
              categoryPath: entry.category,
              fallbackType: entry.isIncome ? 'Receita' : 'Despesa',
              size: 13,
              iconSize: 8.5,
              borderRadius: 3.5,
            ),
            const SizedBox(width: 3),
            Expanded(
              child: Text(
                '$valStr ${entry.title}',
                style: textStyle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (entry.isOverdue)
              Padding(
                padding: const EdgeInsets.only(left: 2),
                child: Icon(Icons.error_outline, size: 9, color: colors.expense),
              ),
          ],
        ),
      ),
    );
  }

  // MARK: - 6. Mobile Calendar View
  Widget _buildMobileCalendar(OpenMoneyColors colors, List<AgendaGridDay> gridDays) {
    const weekdays = ['D', 'S', 'T', 'Q', 'Q', 'S', 'S'];

    final selectedDay = gridDays.firstWhere(
      (d) => d.date == _selectedMobileDate,
      orElse: () => gridDays.firstWhere((d) => d.isCurrentMonth, orElse: () => gridDays.first),
    );

    return Column(
      children: [
        // Grade compacta
        Container(
          decoration: BoxDecoration(
            color: colors.bgSecondary,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: colors.borderGlass),
          ),
          padding: const EdgeInsets.all(10),
          child: Column(
            children: [
              Row(
                children: weekdays.map((wd) {
                  return Expanded(
                    child: Center(
                      child: Text(
                        wd,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: colors.textSecondary,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 8),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: gridDays.length,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 7,
                  childAspectRatio: 1.1,
                ),
                itemBuilder: (context, index) {
                  final day = gridDays[index];
                  final isSelected = day.date == _selectedMobileDate;
                  final hasBills = day.entries.any((e) => e.isPayable && !e.isDone);
                  final hasIncome = day.entries.any((e) => e.isIncome && !e.isDone);
                  final hasDone = day.entries.any((e) => e.isDone);

                  return InkWell(
                    onTap: () {
                      setState(() {
                        _selectedMobileDate = day.date;
                      });
                    },
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      decoration: BoxDecoration(
                        color: isSelected
                            ? colors.accent.withValues(alpha: 0.2)
                            : (day.isToday ? colors.accent.withValues(alpha: 0.08) : Colors.transparent),
                        borderRadius: BorderRadius.circular(8),
                        border: isSelected ? Border.all(color: colors.accent, width: 1.2) : null,
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            '${day.dayNumber}',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: day.isToday || isSelected ? FontWeight.w800 : FontWeight.w500,
                              color: day.isCurrentMonth
                                  ? colors.textPrimary
                                  : colors.textSecondary.withValues(alpha: 0.4),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              if (hasBills)
                                Container(
                                  width: 4,
                                  height: 4,
                                  margin: const EdgeInsets.symmetric(horizontal: 1),
                                  decoration: const BoxDecoration(
                                    color: Color(0xFFF59E0B),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              if (hasIncome)
                                Container(
                                  width: 4,
                                  height: 4,
                                  margin: const EdgeInsets.symmetric(horizontal: 1),
                                  decoration: const BoxDecoration(
                                    color: Color(0xFF10B981),
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              if (hasDone && !hasBills && !hasIncome)
                                Container(
                                  width: 4,
                                  height: 4,
                                  margin: const EdgeInsets.symmetric(horizontal: 1),
                                  decoration: const BoxDecoration(
                                    color: Colors.grey,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),

        const SizedBox(height: 14),

        // Lista de itens do dia selecionado
        GlassCard(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Dia ${fmtDate(selectedDay.date)}',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                      color: colors.textPrimary,
                    ),
                  ),
                  OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    ),
                    icon: const Icon(Icons.add, size: 14),
                    label: const Text('Lançar', style: TextStyle(fontSize: 12)),
                    onPressed: () => _openTransactionModal(txType: 'expense', initialDate: selectedDay.date),
                  ),
                ],
              ),
              const Divider(height: 18),
              if (selectedDay.entries.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Center(
                    child: Text(
                      'Nenhum vencimento ou receita para este dia.',
                      style: TextStyle(fontSize: 13, color: colors.textSecondary),
                    ),
                  ),
                )
              else
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: selectedDay.entries.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, idx) {
                    final entry = selectedDay.entries[idx];
                    return _buildMobileEntryTile(colors, entry);
                  },
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMobileEntryTile(OpenMoneyColors colors, AgendaEntry entry) {
    final isIncome = entry.isIncome;
    final prefix = isIncome ? '+' : '';
    final valStr = '$prefix${formatCurrency(entry.amountCents, entry.currency)}';

    return InkWell(
      onTap: () => _showEntryDetailsDialog(entry),
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: colors.bgSecondary,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: colors.borderGlass),
        ),
        child: Row(
          children: [
            Opacity(
              opacity: entry.isDone ? 0.55 : 1.0,
              child: CategoryIconBadge(
                store: widget.store,
                categoryPath: entry.category,
                fallbackType: isIncome ? 'Receita' : 'Despesa',
                size: 26,
                borderRadius: 7,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    entry.title,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      decoration: entry.isDone ? TextDecoration.lineThrough : null,
                      color: entry.isDone ? colors.textSecondary : colors.textPrimary,
                    ),
                  ),
                  Text(
                    '${entry.accountName} • ${entry.category}',
                    style: TextStyle(fontSize: 11, color: colors.textSecondary),
                  ),
                ],
              ),
            ),
            Text(
              valStr,
              style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w800,
                color: entry.isDone
                    ? colors.textSecondary
                    : (isIncome ? colors.income : colors.expense),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // MARK: - 7. Detalhes & Ações Diretas no Calendário
  void _showEntryDetailsDialog(AgendaEntry entry) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colors = OpenMoneyColors(isDark);
    final isIncome = entry.isIncome;
    final valStr = formatCurrency(entry.amountCents, entry.currency);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: colors.bgSecondary,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: colors.borderGlass),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: (entry.isDone
                        ? Colors.grey
                        : (isIncome ? const Color(0xFF10B981) : const Color(0xFFF59E0B)))
                    .withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                entry.isInvestmentMaturity
                    ? Icons.savings_outlined
                    : (entry.isInvoice
                        ? Icons.credit_card
                        : (isIncome ? Icons.trending_up : Icons.receipt_long)),
                color: entry.isDone
                    ? Colors.grey
                    : (isIncome ? const Color(0xFF10B981) : const Color(0xFFF59E0B)),
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                entry.title,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: colors.textPrimary,
                ),
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 400,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Valor: $valStr',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  color: isIncome ? colors.income : colors.expense,
                ),
              ),
              const SizedBox(height: 12),
              _buildDetailRow('Data de vencimento:', fmtDate(entry.date), colors),
              _buildDetailRow('Conta:', entry.accountName, colors),
              _buildDetailRow('Categoria:', entry.category, colors),
              _buildDetailRow(
                'Situação:',
                entry.isInvestmentMaturity
                    ? (entry.isOverdue
                        ? 'Título vencido — aguardando resgate'
                        : 'Vencimento de título (Renda Fixa / Tesouro)')
                    : (entry.isDone
                        ? 'Concluído / Conciliado'
                        : (entry.isOverdue
                            ? 'Atrasado'
                            : 'Aguardando pagamento')),
                colors,
                highlightColor: entry.isOverdue ? colors.expense : null,
              ),

              if (entry.isInvoice && entry.invoiceChargesCents != null) ...[
                const Divider(height: 20),
                Text(
                  'Detalhamento da Fatura:',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: colors.textPrimary,
                  ),
                ),
                const SizedBox(height: 6),
                _buildDetailRow(
                  'Total de compras:',
                  formatCurrency(entry.invoiceChargesCents!, entry.currency),
                  colors,
                ),
                _buildDetailRow(
                  'Pagamentos realizados:',
                  formatCurrency(entry.invoicePaymentsCents ?? 0, entry.currency),
                  colors,
                ),
                _buildDetailRow(
                  'Saldo restante a pagar:',
                  formatCurrency(entry.invoiceRemainingCents ?? 0, entry.currency),
                  colors,
                  highlightColor: colors.expense,
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('Fechar', style: TextStyle(color: colors.textSecondary)),
          ),

          // Se for vencimento de título de Renda Fixa / Tesouro
          if (entry.investAsset != null) ...[
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor:
                    entry.isOverdue ? colors.expense : colors.income,
                foregroundColor: Colors.white,
              ),
              icon: const Icon(Icons.savings_outlined, size: 16),
              label: const Text('Resgatar',
                  style: TextStyle(fontWeight: FontWeight.w700)),
              onPressed: () async {
                Navigator.of(ctx).pop();
                await showInvestmentOperationModal(
                  context,
                  store,
                  initialAsset: entry.investAsset!,
                  initialType: InvestOpType.sell,
                  initialDateIso: entry.date,
                  initialGrossCents: entry.amountCents,
                );
                setState(() {});
              },
            ),
          ] else if (entry.isInvoice && entry.cardId != null && entry.invoiceKey != null) ...[
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: colors.accent,
                foregroundColor: Colors.white,
              ),
              icon: const Icon(Icons.payment, size: 16),
              label: const Text('Pagar Fatura', style: TextStyle(fontWeight: FontWeight.w700)),
              onPressed: () async {
                Navigator.of(ctx).pop();
                final cardAcc = store.accById(entry.cardId!);
                final summary = store.invoiceSummary(entry.cardId!, entry.invoiceKey!);
                if (cardAcc != null && summary != null) {
                  await showInvoicePaymentModal(context, store, cardAccount: cardAcc, summary: summary);
                  setState(() {});
                }
              },
            ),
          ] else if (entry.tx != null) ...[
            // Se for conta a pagar ou receita normal
            OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                side: BorderSide(color: colors.borderGlass),
              ),
              icon: const Icon(Icons.edit_outlined, size: 16),
              label: const Text('Editar'),
              onPressed: () async {
                Navigator.of(ctx).pop();
                await showTransactionEditModal(context, store, entry.tx!);
                setState(() {});
              },
            ),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: entry.isDone ? Colors.grey : const Color(0xFF16A34A),
                foregroundColor: Colors.white,
              ),
              icon: Icon(entry.isDone ? Icons.undo : Icons.check, size: 16),
              label: Text(
                entry.isDone
                    ? 'Desmarcar'
                    : (isIncome ? 'Marcar como Recebida' : 'Marcar como Paga'),
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              onPressed: () {
                store.markTransactionRec(entry.tx!.id, !entry.isDone);
                Navigator.of(ctx).pop();
                setState(() {});
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      entry.isDone
                          ? 'Item marcado como pendente.'
                          : '✓ "${entry.title}" marcado como ${isIncome ? "recebido" : "pago"} com sucesso!',
                    ),
                    duration: const Duration(seconds: 3),
                  ),
                );
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDetailRow(
    String label,
    String value,
    OpenMoneyColors colors, {
    Color? highlightColor,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: 12.5, color: colors.textSecondary)),
          Text(
            value,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: highlightColor ?? colors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  void _showDayEntriesDialog(AgendaGridDay day) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colors = OpenMoneyColors(isDark);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: colors.bgSecondary,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: colors.borderGlass),
        ),
        title: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Dia ${fmtDate(day.date)}',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: colors.textPrimary,
              ),
            ),
            PopupMenuButton<String>(
              tooltip: 'Adicionar lançamento neste dia',
              icon: const Icon(Icons.add_circle_outline),
              onSelected: (txType) {
                Navigator.of(ctx).pop();
                _openTransactionModal(txType: txType, initialDate: day.date);
              },
              itemBuilder: (ctx) => [
                const PopupMenuItem(
                  value: 'expense',
                  height: 32,
                  child: Row(
                    children: [
                      Icon(Icons.arrow_downward_rounded, size: 14, color: Colors.redAccent),
                      SizedBox(width: 8),
                      Text('Nova Despesa', style: TextStyle(fontSize: 12)),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'income',
                  height: 32,
                  child: Row(
                    children: [
                      Icon(Icons.arrow_upward_rounded, size: 14, color: Colors.green),
                      SizedBox(width: 8),
                      Text('Nova Receita', style: TextStyle(fontSize: 12)),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'transfer',
                  height: 32,
                  child: Row(
                    children: [
                      Icon(Icons.swap_horiz_rounded, size: 14, color: colors.accent),
                      const SizedBox(width: 8),
                      const Text('Nova Transferência', style: TextStyle(fontSize: 12)),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
        content: SizedBox(
          width: 440,
          child: day.entries.isEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  child: Center(
                    child: Text(
                      'Nenhum vencimento ou receita para este dia.',
                      style: TextStyle(fontSize: 13, color: colors.textSecondary),
                    ),
                  ),
                )
              : ListView.separated(
                  shrinkWrap: true,
                  itemCount: day.entries.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 8),
                  itemBuilder: (context, idx) {
                    final entry = day.entries[idx];
                    return _buildMobileEntryTile(colors, entry);
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('Fechar', style: TextStyle(color: colors.textSecondary)),
          ),
        ],
      ),
    );
  }
}
