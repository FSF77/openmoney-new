import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/openmoney_models.dart';
import '../store/money_store.dart';
import 'modals/account_modal.dart';
import 'modals/batch_delete_modal.dart';
import 'modals/csv_qif_modal.dart';
import 'theme/liquid_glass.dart';
import 'views/account_ledger_view.dart';
import 'views/budget_view.dart';
import 'views/cash_flow_view.dart';
import 'views/categories_view.dart';
import 'views/due_bills_view.dart';
import 'views/global_search_view.dart';
import 'views/reports_view.dart';

class OpenMoneyAppShell extends StatefulWidget {
  final MoneyStore store;
  const OpenMoneyAppShell({super.key, required this.store});

  @override
  State<OpenMoneyAppShell> createState() => _OpenMoneyAppShellState();
}

class _OpenMoneyAppShellState extends State<OpenMoneyAppShell> {
  bool _showInactiveAccounts = false;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.store,
      builder: (context, _) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final colors = OpenMoneyColors(isDark);
        final width = MediaQuery.of(context).size.width;
        final isDesktopOrTablet = width >= 860;

        if (widget.store.showMissingDatabasePrompt) {
          return _buildMissingDatabaseRescueScreen(context, colors);
        }

        return CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.keyF,
                control: true, shift: true): () {
              widget.store.navigateTo(NavModule.search);
            },
            const SingleActivator(LogicalKeyboardKey.keyF,
                meta: true, shift: true): () {
              widget.store.navigateTo(NavModule.search);
            },
            const SingleActivator(LogicalKeyboardKey.keyI,
                control: true, alt: true): () {
              showCsvQifCenterModal(context, widget.store);
            },
            const SingleActivator(LogicalKeyboardKey.keyI,
                meta: true, alt: true): () {
              showCsvQifCenterModal(context, widget.store);
            },
            const SingleActivator(LogicalKeyboardKey.keyO, control: true): () {
              showDatabaseFileManagerModal(context, widget.store);
            },
            const SingleActivator(LogicalKeyboardKey.keyO, meta: true): () {
              showDatabaseFileManagerModal(context, widget.store);
            },
          },
          child: Focus(
            autofocus: true,
            child: Scaffold(
              backgroundColor: colors.bgPrimary,
              appBar: isDesktopOrTablet
                  ? null
                  : AppBar(
                      backgroundColor: colors.bgSecondary,
                      title: Text(
                        widget.store.windowTitle,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      actions: [
                        IconButton(
                          tooltip: 'Sincronizar Base (.json)',
                          icon: const Icon(Icons.cloud_sync_outlined),
                          onPressed: () => showDatabaseFileManagerModal(
                            context,
                            widget.store,
                          ),
                        ),
                        IconButton(
                          tooltip: 'Alternar Tema Claro / Escuro',
                          icon: Icon(
                            widget.store.isDarkMode
                                ? Icons.light_mode_outlined
                                : Icons.dark_mode_outlined,
                          ),
                          onPressed: widget.store.toggleThemeMode,
                        ),
                      ],
                    ),
              drawer: isDesktopOrTablet
                  ? null
                  : Drawer(
                      backgroundColor: colors.bgSecondary,
                      child: SafeArea(
                        child: _buildSidebarContent(
                          context,
                          colors,
                          closeDrawerOnSelect: true,
                        ),
                      ),
                    ),
              bottomNavigationBar: isDesktopOrTablet
                  ? null
                  : NavigationBar(
                      selectedIndex: _mobileNavIndex(widget.store.activeModule),
                      onDestinationSelected: (idx) {
                        setState(() {
                          switch (idx) {
                            case 0:
                              widget.store.activeModule = NavModule.account;
                              break;
                            case 1:
                              widget.store.activeModule = NavModule.dueBills;
                              break;
                            case 2:
                              widget.store.activeModule = NavModule.cashFlow;
                              break;
                            case 3:
                              widget.store.activeModule = NavModule.reports;
                              break;
                            case 4:
                              widget.store.activeModule = NavModule.search;
                              break;
                          }
                        });
                      },
                      destinations: const [
                        NavigationDestination(
                          icon: Icon(Icons.account_balance_wallet_outlined),
                          label: 'Extrato',
                        ),
                        NavigationDestination(
                          icon: Icon(Icons.notifications_active_outlined),
                          label: 'Vencimentos',
                        ),
                        NavigationDestination(
                          icon: Icon(Icons.grid_on_rounded),
                          label: 'Fluxo',
                        ),
                        NavigationDestination(
                          icon: Icon(Icons.pie_chart_outline),
                          label: 'Relatórios',
                        ),
                        NavigationDestination(
                          icon: Icon(Icons.search),
                          label: 'Buscar',
                        ),
                      ],
                    ),
              body: SafeArea(
                child: Row(
                  children: [
                    if (isDesktopOrTablet)
                      Container(
                        width: 285,
                        decoration: BoxDecoration(
                          color: colors.bgSecondary,
                          border: Border(
                            right: BorderSide(color: colors.borderGlass),
                          ),
                        ),
                        child: _buildSidebarContent(
                          context,
                          colors,
                          closeDrawerOnSelect: false,
                        ),
                      ),
                    Expanded(
                      child: _buildActiveMainView(context),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  int _mobileNavIndex(NavModule m) {
    switch (m) {
      case NavModule.account:
        return 0;
      case NavModule.dueBills:
        return 1;
      case NavModule.cashFlow:
        return 2;
      case NavModule.reports:
      case NavModule.budget:
      case NavModule.categories:
        return 3;
      case NavModule.search:
        return 4;
    }
  }

  Widget _buildActiveMainView(BuildContext context) {
    switch (widget.store.activeModule) {
      case NavModule.account:
        final acc = widget.store.accById(widget.store.selectedAccountId) ??
            (widget.store.db.accounts.isNotEmpty
                ? widget.store.db.accounts.first
                : Account(
                    id: 'a1',
                    name: 'Conta Corrente',
                    type: 'Corrente',
                    opening: 0,
                  ));
        return AccountLedgerView(store: widget.store, account: acc);
      case NavModule.cashFlow:
        return CashFlowView(store: widget.store);
      case NavModule.reports:
        return ReportsView(store: widget.store);
      case NavModule.budget:
        return BudgetView(store: widget.store);
      case NavModule.categories:
        return CategoriesView(store: widget.store);
      case NavModule.dueBills:
        return DueBillsView(store: widget.store);
      case NavModule.search:
        return GlobalSearchView(store: widget.store);
    }
  }

  Widget _buildSidebarContent(
    BuildContext context,
    OpenMoneyColors colors, {
    required bool closeDrawerOnSelect,
  }) {
    final totalReal = widget.store.totalBalance(predicted: false);
    final totalPred = widget.store.totalBalance(predicted: true);
    final dueSummary = widget.store.dueBillsSummary();

    final favAccounts = widget.store.favoriteAccounts;
    final regActive = widget.store.regularActiveAccounts;
    final regInactive = widget.store.regularInactiveAccounts;

    void selectModule(NavModule m, {String? accountId}) {
      widget.store.navigateTo(m, accountId: accountId);
      if (closeDrawerOnSelect) {
        Navigator.of(context).pop();
      }
    }

    return Column(
      children: [
        // Top Brand & Database File Selector
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(7),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [colors.accent, colors.accentIndigo],
                            ),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(
                            Icons.account_balance,
                            color: Colors.white,
                            size: 18,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'OpenMoney',
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontWeight: FontWeight.w900,
                                  fontSize: 16,
                                  color: colors.textPrimary,
                                ),
                              ),
                              Text(
                                widget.store.databaseDisplayName,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: colors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        tooltip: 'Base de Dados (iCloud / OneDrive)',
                        icon: const Icon(Icons.folder_open_outlined, size: 18),
                        onPressed: () => showDatabaseFileManagerModal(
                          context,
                          widget.store,
                        ),
                      ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        tooltip: 'Alternar Tema Claro / Escuro',
                        icon: Icon(
                          widget.store.isDarkMode
                              ? Icons.light_mode_outlined
                              : Icons.dark_mode_outlined,
                          size: 18,
                        ),
                        onPressed: widget.store.toggleThemeMode,
                      ),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 10),
              // Consolidated Patrimony Card
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colors.surfaceGlass,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: colors.borderGlass),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'PATRIMÔNIO CONSOLIDADO (REAL)',
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.4,
                        color: colors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      brl(totalReal),
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w900,
                        color: totalReal >= 0 ? colors.income : colors.expense,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Previsto no mês: ${brl(totalPred)}',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: colors.textSecondary,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            children: [
              // Analytical Modules Section
              _SidebarSectionHeader(title: 'MÓDULOS E PLANEJAMENTO'),
              _SidebarNavTile(
                icon: Icons.notifications_active_outlined,
                label: 'Contas a Pagar & Receber',
                selected: widget.store.activeModule == NavModule.dueBills,
                badgeText: dueSummary.totalCount > 0
                    ? '${dueSummary.totalCount}'
                    : null,
                badgeColor: dueSummary.overdueCount > 0
                    ? colors.expense
                    : colors.warning,
                onTap: () => selectModule(NavModule.dueBills),
              ),
              _SidebarNavTile(
                icon: Icons.grid_on_rounded,
                label: 'Fluxo de Caixa Matricial',
                selected: widget.store.activeModule == NavModule.cashFlow,
                onTap: () => selectModule(NavModule.cashFlow),
              ),
              _SidebarNavTile(
                icon: Icons.pie_chart_outline,
                label: 'Relatórios Mensais',
                selected: widget.store.activeModule == NavModule.reports,
                onTap: () => selectModule(NavModule.reports),
              ),
              _SidebarNavTile(
                icon: Icons.track_changes,
                label: 'Orçamento (Budget)',
                selected: widget.store.activeModule == NavModule.budget,
                onTap: () => selectModule(NavModule.budget),
              ),
              _SidebarNavTile(
                icon: Icons.category_outlined,
                label: 'Categorias e Subcategorias',
                selected: widget.store.activeModule == NavModule.categories,
                onTap: () => selectModule(NavModule.categories),
              ),
              _SidebarNavTile(
                icon: Icons.manage_search,
                label: 'Pesquisa Global',
                selected: widget.store.activeModule == NavModule.search,
                onTap: () => selectModule(NavModule.search),
              ),

              const SizedBox(height: 10),
              if (favAccounts.isNotEmpty) ...[
                _SidebarSectionHeader(title: 'CONTAS FAVORITAS ★'),
                ...favAccounts.map(
                  (a) => _SidebarAccountTile(
                    account: a,
                    balanceCents: widget.store.balance(a, predicted: false),
                    selected: widget.store.activeModule == NavModule.account &&
                        widget.store.selectedAccountId == a.id,
                    colors: colors,
                    onTap: () =>
                        selectModule(NavModule.account, accountId: a.id),
                  ),
                ),
                const SizedBox(height: 8),
              ],

              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _SidebarSectionHeader(title: 'CONTAS ATIVAS'),
                  IconButton(
                    tooltip: 'Nova Conta',
                    icon: Icon(Icons.add_circle_outline,
                        size: 17, color: colors.accent),
                    onPressed: () => showAccountModal(context, widget.store),
                  ),
                ],
              ),
              ...regActive.map(
                (a) => _SidebarAccountTile(
                  account: a,
                  balanceCents: widget.store.balance(a, predicted: false),
                  selected: widget.store.activeModule == NavModule.account &&
                      widget.store.selectedAccountId == a.id,
                  colors: colors,
                  onTap: () =>
                      selectModule(NavModule.account, accountId: a.id),
                ),
              ),

              if (regInactive.isNotEmpty) ...[
                const SizedBox(height: 8),
                InkWell(
                  onTap: () => setState(
                      () => _showInactiveAccounts = !_showInactiveAccounts),
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'CONTAS INATIVAS (${regInactive.length})',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: colors.textMuted,
                          ),
                        ),
                        Icon(
                          _showInactiveAccounts
                              ? Icons.expand_less
                              : Icons.expand_more,
                          size: 16,
                          color: colors.textMuted,
                        ),
                      ],
                    ),
                  ),
                ),
                if (_showInactiveAccounts)
                  ...regInactive.map(
                    (a) => _SidebarAccountTile(
                      account: a,
                      balanceCents: widget.store.balance(a, predicted: false),
                      selected:
                          widget.store.activeModule == NavModule.account &&
                              widget.store.selectedAccountId == a.id,
                      colors: colors,
                      onTap: () =>
                          selectModule(NavModule.account, accountId: a.id),
                    ),
                  ),
              ],
            ],
          ),
        ),

        // Bottom Utility Bar (CSV/QIF & Batch Clean)
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: colors.borderGlass)),
          ),
          child: Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.import_export, size: 16),
                  label: const Text(
                    'CSV / QIF',
                    style: TextStyle(fontSize: 12),
                  ),
                  onPressed: () =>
                      showCsvQifCenterModal(context, widget.store),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'Limpeza de Lançamentos em Lote',
                icon: const Icon(Icons.cleaning_services_outlined, size: 18),
                onPressed: () => showBatchDeleteModal(context, widget.store),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildMissingDatabaseRescueScreen(
    BuildContext context,
    OpenMoneyColors colors,
  ) {
    return Scaffold(
      backgroundColor: colors.bgPrimary,
      body: Center(
        child: SizedBox(
          width: 520,
          child: GlassCard(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.folder_off_outlined,
                        color: colors.warning, size: 28),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        'Proteção contra Perda de Base',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: colors.textPrimary,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  'A base de dados configurada anteriormente não foi localizada no caminho:\n${widget.store.missingDatabasePath}\n\nPor segurança, o OpenMoney não cria um banco vazio silenciosamente.',
                  style: TextStyle(color: colors.textSecondary, fontSize: 13.5),
                ),
                const SizedBox(height: 20),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    FilledButton.icon(
                      icon: const Icon(Icons.folder_open),
                      label: const Text('Localizar / Escolher Base (.json)'),
                      onPressed: () => showDatabaseFileManagerModal(
                        context,
                        widget.store,
                      ),
                    ),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.add),
                      label: const Text('Iniciar Nova Base Padrão'),
                      onPressed: () {
                        final dir = widget.store.defaultCloudOrDocumentsDir();
                        widget.store
                            .createNewDatabaseAtPath('$dir/openmoney.json');
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SidebarSectionHeader extends StatelessWidget {
  final String title;
  const _SidebarSectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colors = OpenMoneyColors(isDark);
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.5,
          color: colors.textMuted,
        ),
      ),
    );
  }
}

class _SidebarNavTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final String? badgeText;
  final Color? badgeColor;
  final VoidCallback onTap;

  const _SidebarNavTile({
    required this.icon,
    required this.label,
    required this.selected,
    this.badgeText,
    this.badgeColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colors = OpenMoneyColors(isDark);

    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        margin: const EdgeInsets.only(bottom: 2),
        decoration: BoxDecoration(
          color: selected
              ? colors.accent.withValues(alpha: 0.16)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Icon(
              icon,
              size: 18,
              color: selected ? colors.accent : colors.textSecondary,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected ? colors.accent : colors.textPrimary,
                ),
              ),
            ),
            if (badgeText != null)
              StatusBadge(
                text: badgeText!,
                color: badgeColor ?? colors.accent,
              ),
          ],
        ),
      ),
    );
  }
}

class _SidebarAccountTile extends StatelessWidget {
  final Account account;
  final int balanceCents;
  final bool selected;
  final OpenMoneyColors colors;
  final VoidCallback onTap;

  const _SidebarAccountTile({
    required this.account,
    required this.balanceCents,
    required this.selected,
    required this.colors,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isCard = account.type == kCardType;
    return InkWell(
      borderRadius: BorderRadius.circular(10),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        margin: const EdgeInsets.only(bottom: 2),
        decoration: BoxDecoration(
          color: selected
              ? colors.accent.withValues(alpha: 0.16)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Icon(
              isCard
                  ? Icons.credit_card
                  : Icons.account_balance_wallet_outlined,
              size: 16,
              color: selected ? colors.accent : colors.textSecondary,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                account.name,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected ? colors.accent : colors.textPrimary,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              brl(balanceCents),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: balanceCents >= 0 ? colors.income : colors.expense,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
