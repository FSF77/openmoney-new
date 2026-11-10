import 'package:flutter/material.dart';
import '../../models/openmoney_models.dart';
import '../../services/bank_logo_registry.dart';
import '../../services/cloud_sync_service.dart';
import '../../store/money_store.dart';
import '../modals/transaction_modal.dart';
import '../theme/liquid_glass.dart';

class DashboardOverviewView extends StatelessWidget {
  final MoneyStore store;
  const DashboardOverviewView({super.key, required this.store});

  String _fmtMonthShort(String ym) {
    final parts = ym.split('-');
    if (parts.length < 2) return ym;
    final y = parts[0];
    final m = int.tryParse(parts[1]) ?? 1;
    const mShort = [
      'jan', 'fev', 'mar', 'abr', 'mai', 'jun',
      'jul', 'ago', 'set', 'out', 'nov', 'dez'
    ];
    final mName = m >= 1 && m <= 12 ? mShort[m - 1] : parts[1];
    final y2 = y.length >= 4 ? y.substring(2) : y;
    return '$mName/$y2';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colors = OpenMoneyColors(isDark);
    final width = MediaQuery.sizeOf(context).width;
    final isCompact = width < 760 || store.uiDensityMode == 'compact';

    final totalReal = store.totalBalance(predicted: false);
    final totalPred = store.totalBalance(predicted: true);
    final totalPredYear = store.totalBalancePredictedYear();
    final dueSummary = store.dueBillsSummary();
    final dueItems = store.dueBillItems(withinDays: store.reminderDaysAhead);
    final cardAccounts = store.db.accounts
        .where((a) => a.type == kCardType && a.card != null && !a.isInactive)
        .toList();

    // Monta a lista de widgets ativos na ordem definida pelo usuário
    final activeWidgets = <({String key, Widget widget, bool fullWidth})>[];

    for (final key in store.dashboardWidgetsOrder) {
      if (key == 'budget') continue; // Card de orçamento/limite eliminado
      if (!(store.dashboardWidgets[key] ?? true)) continue;

      Widget? cardWidget;
      bool fullWidth = false;

      switch (key) {
        case 'patrimony':
          fullWidth = false;
          cardWidget = _buildPatrimonyCard(
            context,
            colors,
            totalReal: totalReal,
            totalPred: totalPred,
            totalPredYear: totalPredYear,
            width: width,
            widgetKey: key,
          );
          break;
        case 'accounts':
          cardWidget = _buildAccountsOverviewCard(
            context,
            colors,
            widgetKey: key,
          );
          break;
        case 'investments':
          cardWidget = _buildInvestmentsOverviewCard(
            context,
            colors,
            widgetKey: key,
          );
          break;
        case 'dueBills':
          cardWidget = _buildDueBillsRadarCard(
            context,
            colors,
            dueSummary,
            dueItems,
            widgetKey: key,
          );
          break;
        case 'cards':
          if (cardAccounts.isNotEmpty) {
            cardWidget = _buildCardsOverviewCard(
              context,
              colors,
              cardAccounts,
              widgetKey: key,
            );
          }
          break;
        case 'categories':
          cardWidget = _buildCategoriesDonutCard(
            context,
            colors,
            widgetKey: key,
          );
          break;
        case 'quickActions':
          cardWidget = _buildQuickActionsCard(
            context,
            colors,
            widgetKey: key,
          );
          break;
      }

      if (cardWidget != null) {
        activeWidgets.add((key: key, widget: cardWidget, fullWidth: fullWidth));
      }
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: EdgeInsets.symmetric(
            horizontal: isCompact ? 16 : 24,
            vertical: isCompact ? 14 : 20,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildDashboardHeader(context, colors, isCompact: isCompact),
              const SizedBox(height: 16),
              LayoutBuilder(
                builder: (context, constraints) {
                  final totalW = constraints.maxWidth;
                  final int cols = totalW >= 1200 ? 3 : (totalW >= 760 ? 2 : 1);
                  final double spacing = 16.0;
                  final double colW = cols == 1
                      ? totalW
                      : (totalW - (cols - 1) * spacing) / cols;

                  return Wrap(
                    spacing: spacing,
                    runSpacing: spacing,
                    children: activeWidgets.map((item) {
                      final itemW =
                          (item.fullWidth || cols == 1) ? totalW : colW;
                      return SizedBox(
                        key: ValueKey(item.key),
                        width: itemW,
                        child: item.widget,
                      );
                    }).toList(),
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDashboardHeader(
    BuildContext context,
    OpenMoneyColors colors, {
    required bool isCompact,
  }) {
    final now = DateTime.now();
    String greeting;
    if (now.hour < 12) {
      greeting = 'Bom dia';
    } else if (now.hour < 18) {
      greeting = 'Boa tarde';
    } else {
      greeting = 'Boa noite';
    }

    String greetingName = '';
    if (CloudSyncService.instance.isAuthenticated &&
        CloudSyncService.instance.userName.trim().isNotEmpty) {
      final firstName =
          CloudSyncService.instance.userName.trim().split(RegExp(r'\s+')).first;
      if (firstName.isNotEmpty) {
        greetingName = ', $firstName';
      }
    }
    final greetingTitle = '$greeting$greetingName';

    const weekdays = [
      'Segunda-feira',
      'Terça-feira',
      'Quarta-feira',
      'Quinta-feira',
      'Sexta-feira',
      'Sábado',
      'Domingo',
    ];
    final weekday = weekdays[now.weekday - 1];
    final dateStr = '$weekday, ${now.day.toString().padLeft(2, '0')}/${now.month.toString().padLeft(2, '0')}/${now.year}';

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                greetingTitle,
                style: TextStyle(
                  fontSize: isCompact ? 19 : 22,
                  fontWeight: FontWeight.w900,
                  color: colors.textPrimary,
                  letterSpacing: -0.3,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                dateStr,
                style: TextStyle(
                  fontSize: isCompact ? 12 : 13,
                  color: colors.textSecondary,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (isCompact)
              IconButton.filled(
                visualDensity: VisualDensity.compact,
                tooltip: 'Novo Lançamento',
                icon: const Icon(Icons.add, size: 20),
                style: IconButton.styleFrom(
                  backgroundColor: colors.accent,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(9),
                  ),
                ),
                onPressed: () {
                  showTransactionCreateModal(context, store);
                },
              )
            else
              FilledButton.icon(
                icon: const Icon(Icons.add_circle, size: 16),
                label: const Text('Novo Lançamento'),
                style: FilledButton.styleFrom(
                  backgroundColor: colors.accent,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(9),
                  ),
                ),
                onPressed: () {
                  showTransactionCreateModal(context, store);
                },
              ),
            const SizedBox(width: 8),
            IconButton(
              tooltip: 'Ajustes & Personalização',
              icon: const Icon(Icons.tune),
              onPressed: () => store.navigateTo(NavModule.settings),
            ),
          ],
        ),
      ],
    );
  }

  /// Botões discretos e elegantes para reposicionar o card horizontal e verticalmente
  Widget _buildMoveButtons(String widgetKey, OpenMoneyColors colors) {
    final idx = store.dashboardWidgetsOrder.indexOf(widgetKey);
    final isFirst = idx <= 0;
    final isLast = idx >= store.dashboardWidgetsOrder.length - 1;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
          tooltip: 'Mover card para a esquerda / cima',
          icon: Icon(
            Icons.chevron_left_rounded,
            size: 20,
            color: isFirst ? colors.borderGlass : colors.textMuted,
          ),
          onPressed: isFirst ? null : () => store.moveDashboardWidgetStep(widgetKey, -1),
        ),
        IconButton(
          visualDensity: VisualDensity.compact,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
          tooltip: 'Mover card para a direita / baixo',
          icon: Icon(
            Icons.chevron_right_rounded,
            size: 20,
            color: isLast ? colors.borderGlass : colors.textMuted,
          ),
          onPressed: isLast ? null : () => store.moveDashboardWidgetStep(widgetKey, 1),
        ),
      ],
    );
  }

  // =========================================================================
  // 1. CARD DE PATRIMÔNIO CONSOLIDADO
  // =========================================================================
  Widget _buildPatrimonyCard(
    BuildContext context,
    OpenMoneyColors colors, {
    required int totalReal,
    required int totalPred,
    required int totalPredYear,
    required double width,
    required String widgetKey,
  }) {
    return GlassCard(
      margin: EdgeInsets.zero,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Icon(Icons.account_balance_outlined,
                        color: colors.accent, size: 20),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        'Patrimônio Consolidado',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: colors.textPrimary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Tooltip(
                    message: store.hidePatrimonyBalance
                        ? 'Exibir valores'
                        : 'Ocultar valores',
                    child: InkWell(
                      borderRadius: BorderRadius.circular(6),
                      onTap: store.toggleHidePatrimonyBalance,
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: Icon(
                          store.hidePatrimonyBalance
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                          size: 16,
                          color: colors.textSecondary,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  _buildMoveButtons(widgetKey, colors),
                ],
              ),
            ],
          ),
          const SizedBox(height: 16),
          LayoutBuilder(
            builder: (context, constraints) {
              final isNarrow = constraints.maxWidth < 380;
              final items = [
                _buildKpiBox(
                  colors: colors,
                  label: 'Saldo Real',
                  valueCents: totalReal,
                  isHide: store.hidePatrimonyBalance,
                  highlightColor: totalReal >= 0 ? colors.income : colors.expense,
                  isCompact: isNarrow,
                ),
                _buildKpiBox(
                  colors: colors,
                  label: 'Previsto Mês',
                  valueCents: totalPred,
                  isHide: store.hidePatrimonyBalance,
                  highlightColor: totalPred >= 0 ? colors.income : colors.expense,
                  isCompact: isNarrow,
                ),
                _buildKpiBox(
                  colors: colors,
                  label: 'Previsto Ano',
                  valueCents: totalPredYear,
                  isHide: store.hidePatrimonyBalance,
                  highlightColor:
                      totalPredYear >= 0 ? colors.income : colors.expense,
                  isCompact: isNarrow,
                ),
              ];

              if (isNarrow) {
                return Column(
                  children: items
                      .map((w) => Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: SizedBox(width: double.infinity, child: w),
                          ))
                      .toList(),
                );
              }

              return Row(
                children: items
                    .map((w) => Expanded(
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 2.5),
                            child: w,
                          ),
                        ))
                    .toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildKpiBox({
    required OpenMoneyColors colors,
    required String label,
    required int valueCents,
    required bool isHide,
    required Color highlightColor,
    bool isCompact = false,
  }) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(
        horizontal: isCompact ? 6 : 8,
        vertical: isCompact ? 6 : 8,
      ),
      decoration: BoxDecoration(
        color: colors.surfaceGlass,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colors.borderGlass),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              color: colors.textSecondary,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 3),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              isHide ? '••••••' : brl(valueCents),
              style: TextStyle(
                fontSize: isCompact ? 12 : 13,
                fontWeight: FontWeight.w800,
                color: isHide ? colors.textPrimary : highlightColor,
                letterSpacing: -0.2,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
              maxLines: 1,
            ),
          ),
        ],
      ),
    );
  }

  // =========================================================================
  // 2. CARD DE CONTAS BANCÁRIAS E SALDOS (SEM CARTÕES DE CRÉDITO E COM FILTRO DE SALDO ZERO)
  // =========================================================================
  Widget _buildAccountsOverviewCard(
    BuildContext context,
    OpenMoneyColors colors, {
    required String widgetKey,
  }) {
    final showZero = store.dashboardAccountsShowZeroBalance;

    bool isAccountVisible(Account a) {
      if (a.type == kCardType || a.card != null) return false;
      if (a.type == 'Poupança' || a.type == 'Investimento') return false;
      if (!showZero && store.balance(a, predicted: false) == 0) {
        return false;
      }
      return true;
    }

    final favAccounts = store.favoriteAccounts.where(isAccountVisible).toList();
    final regActive = store.regularActiveAccounts.where(isAccountVisible).toList();

    final showActive = store.dashboardAccountsShowActive;
    final totalAccounts = favAccounts.length + (showActive ? regActive.length : 0);

    return GlassCard(
      margin: EdgeInsets.zero,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Icon(Icons.account_balance_wallet_outlined,
                        color: colors.accent, size: 20),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        'Contas',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: colors.textPrimary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Tooltip(
                message: store.hideAccountsBalance
                    ? 'Exibir valores'
                    : 'Ocultar valores',
                child: InkWell(
                  borderRadius: BorderRadius.circular(6),
                  onTap: store.toggleHideAccountsBalance,
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(
                      store.hideAccountsBalance
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      size: 16,
                      color: colors.textSecondary,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              _buildMoveButtons(widgetKey, colors),
            ],
          ),
          const SizedBox(height: 12),
          if (totalAccounts == 0)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: Text(
                  !showZero
                      ? 'Nenhuma conta com saldo diferente de zero.'
                      : (showActive
                          ? 'Nenhuma conta bancária ativa cadastrada.'
                          : 'Nenhuma conta favorita. Clique acima para exibir todas as ativas.'),
                  style: TextStyle(color: colors.textSecondary, fontSize: 13),
                  textAlign: TextAlign.center,
                ),
              ),
            )
          else ...[
            if (favAccounts.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  'CONTAS FAVORITAS ★',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w800,
                    color: colors.textMuted,
                    letterSpacing: 0.5,
                  ),
                ),
              ),
              ...favAccounts.map((a) {
                final real = store.balance(a, predicted: false);
                final pred = store.balance(a, predicted: true);
                return _buildAccountDashboardRow(
                  context,
                  colors,
                  account: a,
                  realCents: real,
                  predCents: pred,
                );
              }),
              const SizedBox(height: 8),
            ],
            if (showActive && regActive.isNotEmpty) ...[
              if (favAccounts.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    'DEMAIS CONTAS ATIVAS',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      color: colors.textMuted,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ...regActive.map((a) {
                final real = store.balance(a, predicted: false);
                final pred = store.balance(a, predicted: true);
                return _buildAccountDashboardRow(
                  context,
                  colors,
                  account: a,
                  realCents: real,
                  predCents: pred,
                );
              }),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildAccountDashboardRow(
    BuildContext context,
    OpenMoneyColors colors, {
    required Account account,
    required int realCents,
    required int predCents,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: colors.surfaceGlass,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.borderGlass),
      ),
      child: Row(
        children: [
          AccountLogoWidget(account: account, size: 24, cornerRadius: 6),
          const SizedBox(width: 8),
          Expanded(
            child: InkWell(
              onTap: () =>
                  store.navigateTo(NavModule.account, accountId: account.id),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    account.name,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                      color: colors.textPrimary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    account.type,
                    style: TextStyle(fontSize: 11, color: colors.textSecondary),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                store.hideAccountsBalance ? '••••••' : brl(realCents),
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w800,
                  color: realCents >= 0 ? colors.income : colors.expense,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              if (predCents != realCents) ...[
                const SizedBox(height: 2),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Prev. mês ',
                      style: TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w500,
                        color: colors.textMuted,
                      ),
                    ),
                    Text(
                      store.hideAccountsBalance ? '••••••' : brl(predCents),
                      style: TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w500,
                        color: colors.textMuted,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  // =========================================================================
  // 2.1 INVESTIMENTOS & POUPANÇA
  // =========================================================================
  Widget _buildInvestmentsOverviewCard(
    BuildContext context,
    OpenMoneyColors colors, {
    required String widgetKey,
  }) {
    final showZero = store.dashboardInvestmentsShowZeroBalance;

    bool isInvestmentAccount(Account a) {
      if (a.type != 'Poupança' && a.type != 'Investimento') return false;
      if (a.isInactive) return false;
      if (!showZero) {
        final real = store.balance(a, predicted: false);
        final pred = store.balance(a, predicted: true);
        if (real == 0 && pred == 0) return false;
      }
      return true;
    }

    final favAccounts = store.favoriteAccounts.where(isInvestmentAccount).toList();
    final regActive = store.regularActiveAccounts.where(isInvestmentAccount).toList();
    final allInvestments = [...favAccounts, ...regActive];

    return GlassCard(
      margin: EdgeInsets.zero,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Icon(Icons.trending_up_rounded,
                        color: colors.income, size: 20),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        'Investimentos',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: colors.textPrimary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Tooltip(
                message: store.hideInvestmentsBalance
                    ? 'Exibir valores'
                    : 'Ocultar valores',
                child: InkWell(
                  borderRadius: BorderRadius.circular(6),
                  onTap: store.toggleHideInvestmentsBalance,
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(
                      store.hideInvestmentsBalance
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      size: 16,
                      color: colors.textSecondary,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              _buildMoveButtons(widgetKey, colors),
            ],
          ),
          const SizedBox(height: 12),
          if (allInvestments.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: Text(
                  'Nenhuma conta de investimento a exibir.',
                  style: TextStyle(fontSize: 12, color: colors.textSecondary),
                ),
              ),
            )
          else
            ...allInvestments.map((acc) {
              final realBalance = store.balance(acc, predicted: false);
              final predBalance = store.balance(acc, predicted: true);

              return Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: colors.surfaceGlass,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: colors.borderGlass),
                ),
                child: InkWell(
                  onTap: () {
                    store.navigateTo(NavModule.account, accountId: acc.id);
                  },
                  borderRadius: BorderRadius.circular(8),
                  child: Row(
                    children: [
                      AccountLogoWidget(
                        account: acc,
                        size: 24,
                        cornerRadius: 6,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              acc.name,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: colors.textPrimary,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              acc.type,
                              style: TextStyle(
                                fontSize: 10.5,
                                color: colors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            store.hideInvestmentsBalance
                                ? '••••••'
                                : brl(realBalance),
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w800,
                              color: realBalance < 0
                                  ? colors.expense
                                  : (realBalance > 0 ? colors.income : colors.textPrimary),
                              fontFeatures: const [FontFeature.tabularFigures()],
                            ),
                          ),
                          if (predBalance != realBalance) ...[
                            const SizedBox(height: 2),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  'Prev. mês ',
                                  style: TextStyle(
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.w500,
                                    color: colors.textMuted,
                                  ),
                                ),
                                Text(
                                  store.hideInvestmentsBalance
                                      ? '••••••'
                                      : brl(predBalance),
                                  style: TextStyle(
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.w500,
                                    color: colors.textMuted,
                                    fontFeatures: const [FontFeature.tabularFigures()],
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
              );
            }),
        ],
      ),
    );
  }

  // =========================================================================
  // 3. RADAR DE VENCIMENTOS
  // =========================================================================
  Widget _buildDueBillsRadarCard(
    BuildContext context,
    OpenMoneyColors colors,
    dynamic summary,
    List<DueBillItem> items, {
    required String widgetKey,
  }) {
    return GlassCard(
      margin: EdgeInsets.zero,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Icon(Icons.notifications_active_outlined,
                        color: colors.warning, size: 20),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        'Radar de Vencimentos',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: colors.textPrimary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (summary.totalCount > 0) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: (summary.overdueCount > 0
                                  ? colors.expense
                                  : colors.warning)
                              .withValues(alpha: 0.18),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '${summary.totalCount}',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            color: summary.overdueCount > 0
                                ? colors.expense
                                : colors.warning,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextButton(
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                    ),
                    onPressed: () => store.navigateTo(NavModule.dueBills),
                    child:
                        const Text('Ver todos →', style: TextStyle(fontSize: 12)),
                  ),
                  const SizedBox(width: 4),
                  _buildMoveButtons(widgetKey, colors),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (items.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Column(
                  children: [
                    Icon(Icons.check_circle_outline,
                        color: colors.income, size: 32),
                    const SizedBox(height: 8),
                    Text(
                      'Nenhum vencimento pendente nos próximos ${store.reminderDaysAhead} dias!',
                      style: TextStyle(
                          fontSize: 13, color: colors.textSecondary),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            )
          else ...[
            ...items.take(4).map((item) {
              final isOverdue = item.isOverdue;
              return Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: isOverdue
                      ? colors.expense.withValues(alpha: 0.08)
                      : colors.surfaceGlass,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: isOverdue
                        ? colors.expense.withValues(alpha: 0.3)
                        : colors.borderGlass,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      isOverdue
                          ? Icons.warning_amber_rounded
                          : Icons.calendar_today_outlined,
                      size: 16,
                      color: isOverdue ? colors.expense : colors.warning,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            item.tx.payee.isEmpty
                                ? 'Sem favorecido'
                                : item.tx.payee,
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: colors.textPrimary,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            'Vence: ${item.dueDate != null ? fmtDate(item.dueDate!) : ''} • ${item.accountName}',
                            style: TextStyle(
                              fontSize: 11,
                              color: isOverdue
                                  ? colors.expense
                                  : colors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      brl(item.tx.amt.abs()),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: colors.expense,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      tooltip: 'Marcar como Pago',
                      icon: Icon(Icons.check_circle_outline,
                          size: 18, color: colors.income),
                      onPressed: () {
                        store.toggleReconciled(item.tx.id);
                      },
                    ),
                  ],
                ),
              );
            }),
          ],
        ],
      ),
    );
  }

  // =========================================================================
  // 4. FATURAS DE CARTÕES DE CRÉDITO
  // =========================================================================
  Widget _buildCardsOverviewCard(
    BuildContext context,
    OpenMoneyColors colors,
    List<Account> cardAccounts, {
    required String widgetKey,
  }) {
    return GlassCard(
      margin: EdgeInsets.zero,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Icon(Icons.credit_card_outlined,
                        color: colors.accentIndigo, size: 20),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        'Faturas de Cartão de Crédito',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                          color: colors.textPrimary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Tooltip(
                message: store.hideCardsBalance
                    ? 'Exibir valores'
                    : 'Ocultar valores',
                child: InkWell(
                  borderRadius: BorderRadius.circular(6),
                  onTap: store.toggleHideCardsBalance,
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(
                      store.hideCardsBalance
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      size: 16,
                      color: colors.textSecondary,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 4),
              _buildMoveButtons(widgetKey, colors),
            ],
          ),
          const SizedBox(height: 12),
          () {
            final showZero = store.dashboardCardsShowZeroBalance;
            final filtered = cardAccounts.where((acc) {
              if (showZero) return true;
              final card = acc.card;
              if (card == null) return true;
              final currentIk = invKeyFor(card, todayISO());
              final summary = store.invoiceSummary(acc.id, currentIk);
              final remainingCents = summary?.remainingCents ?? 0;
              final clearedCents = summary?.clearedCents ?? 0;
              return remainingCents != 0 || clearedCents != 0;
            }).toList();

            if (filtered.isEmpty) {
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Center(
                  child: Text(
                    'Nenhum cartão com fatura ativa.',
                    style: TextStyle(fontSize: 12, color: colors.textSecondary),
                  ),
                ),
              );
            }

            return Column(
              children: filtered.map((acc) {
                final card = acc.card!;
                final currentIk = invKeyFor(card, todayISO());
                final summary = store.invoiceSummary(acc.id, currentIk);
                final remainingCents = summary?.remainingCents ?? 0;
                final clearedCents = summary?.clearedCents ?? 0;
                final closeDate = summary?.closeDate ?? '';
                final dueDate = summary?.dueDate ?? '';

                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: colors.surfaceGlass,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: colors.borderGlass),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              AccountLogoWidget(account: acc, size: 22, cornerRadius: 4),
                              const SizedBox(width: 8),
                              Text(
                                acc.name,
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13,
                                  color: colors.textPrimary,
                                ),
                              ),
                            ],
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                store.hideCardsBalance
                                    ? '••••••'
                                    : brl(remainingCents > 0
                                        ? -remainingCents
                                        : remainingCents),
                                style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w800,
                                  color: remainingCents > 0
                                      ? colors.expense
                                      : colors.income,
                                  fontFeatures: const [FontFeature.tabularFigures()],
                                ),
                              ),
                              if (clearedCents != remainingCents) ...[
                                const SizedBox(height: 2),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      'Conciliado ',
                                      style: TextStyle(
                                        fontSize: 9.5,
                                        fontWeight: FontWeight.w500,
                                        color: colors.textMuted,
                                      ),
                                    ),
                                    Text(
                                      store.hideCardsBalance
                                          ? '••••••'
                                          : brl(clearedCents > 0
                                              ? -clearedCents
                                              : clearedCents),
                                      style: TextStyle(
                                        fontSize: 9.5,
                                        fontWeight: FontWeight.w500,
                                        color: colors.textMuted,
                                        fontFeatures: const [FontFeature.tabularFigures()],
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            closeDate.isNotEmpty && dueDate.isNotEmpty
                                ? 'Fecha: ${fmtDate(closeDate)} • Vence: ${fmtDate(dueDate)}'
                                : 'Fatura do ciclo',
                            style: TextStyle(fontSize: 11, color: colors.textSecondary),
                          ),
                          InkWell(
                            onTap: () {
                              store.navigateTo(NavModule.account, accountId: acc.id);
                            },
                            child: Text(
                              'Ver Fatura →',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: colors.accent,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              }).toList(),
            );
          }(),
        ],
      ),
    );
  }

  // =========================================================================
  // 5. GASTOS POR CATEGORIA DO MÊS (DESCONSIDERA TRANSFERÊNCIAS, MÊS COMO NOV/26)
  // =========================================================================
  Widget _buildCategoriesDonutCard(
    BuildContext context,
    OpenMoneyColors colors, {
    required String widgetKey,
  }) {
    final curMonth = store.month;
    // Usa o relatório contábil oficial que desconsidera estritamente transferências entre contas e traz os pagamentos reais
    final reportData = store.buildMonthlyReport(curMonth);
    final totalExpenses = reportData.totalExpense;
    final topCategories = reportData.expenseGroups.take(5).toList();

    return GlassCard(
      margin: EdgeInsets.zero,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Row(
                  children: [
                    Icon(Icons.pie_chart_outline, color: colors.accent, size: 20),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(
                        'Gastos por Categoria (${_fmtMonthShort(curMonth)})',
                        style: TextStyle(
                          fontSize: 14.5,
                          fontWeight: FontWeight.w800,
                          color: colors.textPrimary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Total: ${brl(totalExpenses > 0 ? -totalExpenses : totalExpenses)}',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: colors.expense,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  const SizedBox(width: 4),
                  _buildMoveButtons(widgetKey, colors),
                ],
              ),
            ],
          ),
          const SizedBox(height: 14),
          if (topCategories.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text(
                  'Nenhum pagamento registrado neste mês.',
                  style: TextStyle(color: colors.textSecondary, fontSize: 13),
                ),
              ),
            )
          else ...[
            ...topCategories.map((group) {
              final pct = totalExpenses > 0 ? (group.total / totalExpenses) : 0.0;
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          group.name,
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w600,
                            color: colors.textPrimary,
                          ),
                        ),
                        Text(
                          '${brl(group.total > 0 ? -group.total : group.total)} (${(pct * 100).toStringAsFixed(1)}%)',
                          style: TextStyle(
                            fontSize: 12,
                            color: colors.textSecondary,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: pct,
                        minHeight: 5,
                        backgroundColor: colors.borderGlass,
                        valueColor: AlwaysStoppedAnimation(colors.accent),
                      ),
                    ),
                  ],
                ),
              );
            }),
          ],
        ],
      ),
    );
  }

  // =========================================================================
  // 6. AÇÕES RÁPIDAS
  // =========================================================================
  Widget _buildQuickActionsCard(
    BuildContext context,
    OpenMoneyColors colors, {
    required String widgetKey,
  }) {
    return GlassCard(
      margin: EdgeInsets.zero,
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  'Ações Rápidas & Atalhos',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: colors.textPrimary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 6),
              _buildMoveButtons(widgetKey, colors),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              ActionChip(
                avatar: Icon(Icons.receipt_long_outlined,
                    size: 16, color: colors.accent),
                label: const Text('Lançamentos'),
                onPressed: () => store.navigateTo(NavModule.transactions),
              ),
              ActionChip(
                avatar: Icon(Icons.notifications_active_outlined,
                    size: 16, color: colors.warning),
                label: const Text('Contas a Pagar & Receber'),
                onPressed: () => store.navigateTo(NavModule.dueBills),
              ),
              ActionChip(
                avatar: Icon(Icons.credit_score,
                    size: 16, color: colors.accentIndigo),
                label: const Text('Compras Parceladas'),
                onPressed: () => store.navigateTo(NavModule.installments),
              ),
              ActionChip(
                avatar:
                    Icon(Icons.grid_on_rounded, size: 16, color: colors.accent),
                label: const Text('Fluxo de Caixa'),
                onPressed: () => store.navigateTo(NavModule.cashFlow),
              ),
              ActionChip(
                avatar: Icon(Icons.pie_chart_outline,
                    size: 16, color: colors.income),
                label: const Text('Relatórios'),
                onPressed: () => store.navigateTo(NavModule.reports),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
