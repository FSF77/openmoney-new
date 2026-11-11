import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/openmoney_models.dart';
import '../services/bank_logo_registry.dart';
import '../services/cloud_sync_service.dart';
import '../services/native_file_picker.dart';
import '../services/platform_io.dart';
import '../services/shortcut_url_service.dart';
import '../services/sync_engine.dart';
import '../services/update_service.dart';
import '../store/money_store.dart';
import 'modals/about_modal.dart';
import 'modals/account_modal.dart';
import 'modals/audit_logs_modal.dart';
import 'modals/backups_history_modal.dart';
import 'modals/batch_delete_modal.dart';
import 'modals/cloud_account_modal.dart';
import 'modals/csv_qif_modal.dart';
import 'modals/help_modal.dart';
import 'modals/transaction_modal.dart';
import 'modals/welcome_database_modal.dart';
import 'theme/liquid_glass.dart';
import 'views/account_ledger_view.dart';
import 'views/all_transactions_view.dart';
import 'views/budget_view.dart';
import 'views/cash_flow_view.dart';
import 'views/categories_view.dart';
import 'views/dashboard_overview_view.dart';
import 'views/due_bills_view.dart';
import 'views/installments_view.dart';
import 'views/global_search_view.dart';
import 'views/reports_view.dart';
import 'views/settings_view.dart';
import 'widgets/command_palette_modal.dart';
import 'widgets/zoom_control_pill.dart';

class OpenMoneyAppShell extends StatefulWidget {
  final MoneyStore store;
  const OpenMoneyAppShell({super.key, required this.store});

  @override
  State<OpenMoneyAppShell> createState() => _OpenMoneyAppShellState();
}

class _OpenMoneyAppShellState extends State<OpenMoneyAppShell> {
  late final Listenable _shortcutReadinessListenable;

  @override
  void initState() {
    super.initState();
    _shortcutReadinessListenable = Listenable.merge([
      widget.store,
      CloudSyncService.instance,
      SyncEngine.instance,
      ShortcutUrlService.instance,
    ]);
    _shortcutReadinessListenable.addListener(_onShortcutReadinessChanged);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      ShortcutUrlService.instance.captureFromCurrentUrl();
      _maybeOpenPendingShortcutModal();
      UpdateService.showUpdateDialog(context, manual: false);
      final isSmall = MediaQuery.of(context).size.width < 760;
      if (isSmall || widget.store.startupView == 'dashboard') {
        widget.store.navigateTo(NavModule.dashboard);
      }
    });
  }

  @override
  void dispose() {
    _shortcutReadinessListenable.removeListener(_onShortcutReadinessChanged);
    super.dispose();
  }

  void _onShortcutReadinessChanged() {
    _maybeOpenPendingShortcutModal();
  }

  void _maybeOpenPendingShortcutModal() {
    if (!mounted) return;
    final shortcutSvc = ShortcutUrlService.instance;
    if (!shortcutSvc.hasPendingDraft || shortcutSvc.isModalOpen) return;
    if (widget.store.showWelcomeScreen ||
        widget.store.showMissingDatabasePrompt) {
      return;
    }

    if (kIsWeb && CloudSyncService.instance.isAuthenticated) {
      final syncReady = SyncEngine.instance.hasLoadedRemoteState ||
          (!webIsOnline() && widget.store.db.accounts.isNotEmpty);
      if (!syncReady) return;
    } else if (widget.store.db.accounts.isEmpty) {
      return;
    }

    final draft = shortcutSvc.consumePendingDraft();
    if (draft == null) return;

    shortcutSvc.setModalOpen(true);
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) {
        shortcutSvc.setModalOpen(false);
        return;
      }
      try {
        final resolved = ShortcutUrlService.resolveDraft(draft, widget.store);
        widget.store.navigateTo(
          NavModule.account,
          accountId: resolved.accountId,
        );
        final acc = widget.store.accById(resolved.accountId);
        if (acc != null && acc.type == kCardType && acc.card != null) {
          widget.store.month = invKeyFor(acc.card!, resolved.dateIso);
        } else if (resolved.dateIso.length >= 7) {
          widget.store.month = resolved.dateIso.substring(0, 7);
        }

        await showTransactionCreateModal(
          context,
          widget.store,
          initialAccountId: resolved.accountId,
          initialDateIso: resolved.dateIso,
          initialPayee: resolved.payee,
          initialAmountCents: resolved.amountCents,
          initialCategory: resolved.category,
          initialMemo: resolved.memo,
          initialIsExpense: resolved.isExpense,
          shortcutRawAccountName: resolved.rawAccountName,
          fromShortcut: true,
        );
      } finally {
        webClearUrlQueryParams();
        shortcutSvc.setModalOpen(false);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        widget.store,
        CloudSyncService.instance,
        SyncEngine.instance,
      ]),
      builder: (context, _) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final colors = OpenMoneyColors(isDark);
        final width = MediaQuery.of(context).size.width;
        final isDesktopOrTablet = width >= 860;

        if (kIsWeb &&
            CloudSyncService.instance.isAuthenticated &&
            !SyncEngine.instance.hasLoadedRemoteState) {
          return _buildCloudLoadingScreen(context, colors);
        }

        if (widget.store.showWelcomeScreen) {
          return WelcomeDatabaseSelectionScreen(store: widget.store);
        }

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
            const SingleActivator(LogicalKeyboardKey.keyB,
                control: true, shift: true): () {
              showBackupsHistoryModal(context, widget.store);
            },
            const SingleActivator(LogicalKeyboardKey.keyB,
                meta: true, shift: true): () {
              showBackupsHistoryModal(context, widget.store);
            },
            const SingleActivator(LogicalKeyboardKey.keyL,
                control: true, shift: true): () {
              showAuditLogsModal(context, widget.store);
            },
            const SingleActivator(LogicalKeyboardKey.keyL,
                meta: true, shift: true): () {
              showAuditLogsModal(context, widget.store);
            },
            // Atalhos de Zoom / Acessibilidade de Fontes
            const SingleActivator(LogicalKeyboardKey.equal, meta: true): () {
              widget.store.zoomIn();
            },
            const SingleActivator(LogicalKeyboardKey.equal, control: true): () {
              widget.store.zoomIn();
            },
            const SingleActivator(LogicalKeyboardKey.add, meta: true): () {
              widget.store.zoomIn();
            },
            const SingleActivator(LogicalKeyboardKey.add, control: true): () {
              widget.store.zoomIn();
            },
            const SingleActivator(LogicalKeyboardKey.minus, meta: true): () {
              widget.store.zoomOut();
            },
            const SingleActivator(LogicalKeyboardKey.minus, control: true): () {
              widget.store.zoomOut();
            },
            const SingleActivator(LogicalKeyboardKey.numpadSubtract, meta: true): () {
              widget.store.zoomOut();
            },
            const SingleActivator(LogicalKeyboardKey.numpadSubtract, control: true): () {
              widget.store.zoomOut();
            },
            const SingleActivator(LogicalKeyboardKey.digit0, meta: true): () {
              widget.store.resetZoom();
            },
            const SingleActivator(LogicalKeyboardKey.digit0, control: true): () {
              widget.store.resetZoom();
            },
            const SingleActivator(LogicalKeyboardKey.numpad0, meta: true): () {
              widget.store.resetZoom();
            },
            const SingleActivator(LogicalKeyboardKey.numpad0, control: true): () {
              widget.store.resetZoom();
            },
            // Alternar menu lateral (Expandida <-> Mini Rail)
            const SingleActivator(LogicalKeyboardKey.keyB, meta: true): () {
              if (widget.store.sidebarMode == 'expanded') {
                widget.store.setSidebarMode('miniRail');
              } else {
                widget.store.setSidebarMode('expanded');
              }
            },
            const SingleActivator(LogicalKeyboardKey.keyB, control: true): () {
              if (widget.store.sidebarMode == 'expanded') {
                widget.store.setSidebarMode('miniRail');
              } else {
                widget.store.setSidebarMode('expanded');
              }
            },
            // Command Palette (Spotlight / Raycast)
            const SingleActivator(LogicalKeyboardKey.keyK, meta: true): () {
              showCommandPaletteModal(context, widget.store);
            },
            const SingleActivator(LogicalKeyboardKey.keyK, control: true): () {
              showCommandPaletteModal(context, widget.store);
            },
            // Ajustes & Personalização (Cmd/Ctrl + ,)
            const SingleActivator(LogicalKeyboardKey.comma, meta: true): () {
              widget.store.navigateTo(NavModule.settings);
            },
            const SingleActivator(LogicalKeyboardKey.comma, control: true): () {
              widget.store.navigateTo(NavModule.settings);
            },
            // Ajuda e Manual do OpenMoney
            const SingleActivator(LogicalKeyboardKey.f1): () {
              showHelpModal(context, widget.store);
            },
            const SingleActivator(LogicalKeyboardKey.slash, meta: true, shift: true): () {
              showHelpModal(context, widget.store);
            },
            const SingleActivator(LogicalKeyboardKey.slash, control: true, shift: true): () {
              showHelpModal(context, widget.store);
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
                      leadingWidth: 100,
                      titleSpacing: 2,
                      leading: Builder(
                        builder: (ctx) => Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const SizedBox(width: 4),
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              tooltip: 'Menu Lateral',
                              icon: Icon(
                                Icons.menu,
                                color: colors.textPrimary,
                              ),
                              onPressed: () => Scaffold.of(ctx).openDrawer(),
                            ),
                            IconButton(
                              visualDensity: VisualDensity.compact,
                              tooltip: 'Dashboard Geral',
                              icon: _DashboardVectorIcon(
                                size: 21,
                                color: widget.store.activeModule == NavModule.dashboard
                                    ? colors.accent
                                    : colors.textPrimary,
                                filled: widget.store.activeModule == NavModule.dashboard,
                              ),
                              onPressed: () {
                                widget.store.navigateTo(NavModule.dashboard);
                              },
                            ),
                          ],
                        ),
                      ),
                      title: Text(
                        widget.store.activeModule == NavModule.dashboard
                            ? 'Dashboard Geral'
                            : widget.store.windowTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      actions: [
                        ListenableBuilder(
                          listenable: CloudSyncService.instance,
                          builder: (context, _) {
                            if (kIsWeb &&
                                CloudSyncService.instance.isAuthenticated) {
                              return IconButton(
                                tooltip: 'Cloud & Sincronização',
                                icon: Icon(
                                  Icons.cloud_done_outlined,
                                  color: colors.income,
                                ),
                                onPressed: () =>
                                    showCloudAccountModal(context, widget.store),
                              );
                            }
                            return IconButton(
                              tooltip: 'Base de Dados Local',
                              icon: const Icon(Icons.folder_open_outlined),
                              onPressed: () => showDatabaseFileManagerModal(
                                context,
                                widget.store,
                              ),
                            );
                          },
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
              body: SafeArea(
                child: Row(
                  children: [
                    if (isDesktopOrTablet && widget.store.isSidebarVisible)
                      Container(
                        width: widget.store.sidebarMode == 'miniRail' ? 64 : 285,
                        decoration: BoxDecoration(
                          color: colors.bgSecondary,
                          border: Border(
                            right: BorderSide(color: colors.borderGlass),
                          ),
                        ),
                        child: widget.store.sidebarMode == 'miniRail'
                            ? _buildMiniRailContent(context, colors)
                            : _buildSidebarContent(
                                context,
                                colors,
                                closeDrawerOnSelect: false,
                              ),
                      ),
                    Expanded(
                      child: Column(
                        children: [
                          if (isDesktopOrTablet)
                            _buildDesktopTopBar(context, colors),
                          Expanded(
                            child: Stack(
                              children: [
                                Positioned.fill(
                                  child: _buildActiveMainView(
                                    context,
                                    isDesktopOrTablet: isDesktopOrTablet,
                                    colors: colors,
                                  ),
                                ),
                                if (isDesktopOrTablet && !widget.store.isSidebarVisible)
                                  Positioned(
                                    top: 12,
                                    left: 12,
                                    child: Material(
                                      color: colors.bgSecondary.withValues(alpha: 0.92),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(8),
                                        side: BorderSide(color: colors.borderGlass),
                                      ),
                                      elevation: 4,
                                      child: InkWell(
                                        borderRadius: BorderRadius.circular(8),
                                        onTap: widget.store.toggleSidebar,
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 10,
                                            vertical: 6,
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(
                                                Icons.menu,
                                                size: 16,
                                                color: colors.textPrimary,
                                              ),
                                              const SizedBox(width: 6),
                                              Text(
                                                'Menu',
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.bold,
                                                  color: colors.textPrimary,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
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

  Widget _buildDesktopTopBar(BuildContext context, OpenMoneyColors colors) {
    String moduleTitle = 'OpenMoney';
    String? subTitle;

    switch (widget.store.activeModule) {
      case NavModule.dashboard:
        moduleTitle = 'Dashboard Geral';
        subTitle = 'Cockpit';
        break;
      case NavModule.account:
        final acc = widget.store.accById(widget.store.selectedAccountId);
        moduleTitle = acc?.name ?? 'Conta';
        subTitle = acc?.type;
        break;
      case NavModule.transactions:
        moduleTitle = 'Lançamentos';
        subTitle = 'Consolidado';
        break;
      case NavModule.cashFlow:
        moduleTitle = 'Fluxo de Caixa';
        subTitle = fmtMonth(widget.store.month);
        break;
      case NavModule.reports:
        moduleTitle = 'Relatórios';
        break;
      case NavModule.budget:
        moduleTitle = 'Limite de Gastos';
        break;
      case NavModule.categories:
        moduleTitle = 'Categorias';
        break;
      case NavModule.dueBills:
        moduleTitle = 'Contas a Pagar & Receber';
        break;
      case NavModule.installments:
        moduleTitle = 'Compras Parceladas';
        break;
      case NavModule.search:
        moduleTitle = 'Pesquisa Global';
        break;
      case NavModule.settings:
        moduleTitle = 'Ajustes & Personalização';
        break;
    }

    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: colors.bgSecondary,
        border: Border(
          bottom: BorderSide(color: colors.borderGlass),
        ),
      ),
      child: Row(
        children: [
          // Breadcrumbs
          Flexible(
            flex: 3,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                  icon: _DashboardVectorIcon(
                    size: 18,
                    color: colors.accent,
                    filled: widget.store.activeModule == NavModule.dashboard,
                  ),
                  tooltip: 'Dashboard Geral',
                  onPressed: () {
                    widget.store.navigateTo(NavModule.dashboard);
                  },
                ),
                const SizedBox(width: 8),
                InkWell(
                  borderRadius: BorderRadius.circular(4),
                  onTap: () {
                    widget.store.navigateTo(NavModule.dashboard);
                  },
                  child: Text(
                    'OpenMoney',
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      color: colors.accent,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Icon(Icons.chevron_right, size: 14, color: colors.textMuted),
                ),
                Flexible(
                  child: Text(
                    moduleTitle,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w800,
                      color: colors.textPrimary,
                    ),
                  ),
                ),
                if (subTitle != null) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    child: Icon(Icons.chevron_right, size: 14, color: colors.textMuted),
                  ),
                  Flexible(
                    child: Text(
                      subTitle,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                        color: colors.textSecondary,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),

          // Spotlight / Command Palette Button
          Flexible(
            flex: 2,
            child: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => showCommandPaletteModal(context, widget.store),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: colors.surfaceGlass,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: colors.borderGlass),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.search, size: 13, color: colors.textSecondary),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        'Buscar (Cmd+K)...',
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 11, color: colors.textMuted),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                      decoration: BoxDecoration(
                        color: colors.bgSecondary,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: colors.borderGlass),
                      ),
                      child: Text(
                        '⌘K',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          color: colors.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),

          // Status de Conexão / Nuvem
          ListenableBuilder(
            listenable: CloudSyncService.instance,
            builder: (context, _) {
              final isCloud = widget.store.isCloudMode;
              if (isCloud) {
                return Tooltip(
                  message: 'Conectado à Nuvem (Cloud Sync v2)',
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: colors.income.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: colors.income.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: colors.income,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'Online',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: colors.income,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }
              return Tooltip(
                message:
                    'Base de dados local ativa: ${widget.store.databaseDisplayName}',
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: colors.surfaceGlass,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: colors.borderGlass),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.folder_outlined,
                          size: 13, color: colors.textSecondary),
                      const SizedBox(width: 6),
                      Text(
                        'Local',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: colors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          const SizedBox(width: 8),

          // Botão Ajustes e Personalização
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: 'Ajustes & Personalização (Cmd+,)',
            icon: Icon(
              Icons.tune,
              size: 18,
              color: widget.store.activeModule == NavModule.settings
                  ? colors.accent
                  : colors.textSecondary,
            ),
            onPressed: () => widget.store.navigateTo(NavModule.settings),
          ),

          // Botão Alternar Tema
          IconButton(
            visualDensity: VisualDensity.compact,
            tooltip: 'Alternar Tema Claro / Escuro (Cmd+D)',
            icon: Icon(
              widget.store.isDarkMode
                  ? Icons.light_mode_outlined
                  : Icons.dark_mode_outlined,
              size: 18,
              color: colors.textSecondary,
            ),
            onPressed: widget.store.toggleThemeMode,
          ),
        ],
      ),
    );
  }

  Widget _buildMiniRailContent(BuildContext context, OpenMoneyColors colors) {
    void selectModule(NavModule m, {String? accountId}) {
      widget.store.navigateTo(m, accountId: accountId);
    }

    // Contas favoritas primeiro e depois ativas regulares (sem inativas)
    final railAccounts = [
      ...widget.store.favoriteAccounts,
      ...widget.store.regularActiveAccounts,
    ];

    return Column(
      children: [
        const SizedBox(height: 10),
        // Botão padronizado no topo para expandir o menu lateral
        Tooltip(
          message: 'Expandir Menu Lateral (Cmd+B)',
          child: IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.menu_open, size: 20),
            onPressed: () => widget.store.setSidebarMode('expanded'),
          ),
        ),
        const SizedBox(height: 6),

        // Logo do App
        Tooltip(
          message: 'OpenMoney',
          child: ClipRRect(
            borderRadius: BorderRadius.circular(7),
            child: Image.asset(
              'logo/openmoney_app_icon.png',
              width: 28,
              height: 28,
              filterQuality: FilterQuality.medium,
            ),
          ),
        ),
        const SizedBox(height: 10),

        // 1. Dashboard Icon (posicionado acima do incluir lançamento)
        Tooltip(
          message: 'Dashboard Geral',
          child: IconButton(
            icon: _DashboardVectorIcon(
              size: 20,
              color: widget.store.activeModule == NavModule.dashboard
                  ? colors.accent
                  : colors.textSecondary,
              filled: widget.store.activeModule == NavModule.dashboard,
            ),
            onPressed: () => selectModule(NavModule.dashboard),
          ),
        ),
        const SizedBox(height: 4),

        // 2. Botão Novo Lançamento (mesmo tamanho dos demais ícones)
        Tooltip(
          message: 'Novo Lançamento',
          child: IconButton(
            icon: Icon(
              Icons.add_circle_outline,
              size: 20,
              color: colors.accent,
            ),
            onPressed: () => showTransactionCreateModal(context, widget.store),
          ),
        ),
        const Divider(height: 16),

        // Contas Bancárias (Ícones: favoritas e depois ativas regulares)
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            children: [
              ...railAccounts.map((a) {
                final isSelected =
                    widget.store.activeModule == NavModule.account &&
                        widget.store.selectedAccountId == a.id;
                final bal = widget.store.balance(a, predicted: false);

                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Tooltip(
                    message: () {
                      final cur = a.effectiveCurrency;
                      final baseCur = widget.store.baseCurrency;
                      final mainStr = formatCurrency(bal, cur);
                      if (cur != baseCur) {
                        final conv = widget.store.convertToBase(bal, cur);
                        return '${a.name}\n${a.type} ($cur) • Saldo: $mainStr (≈ ${formatCurrency(conv, baseCur)})';
                      }
                      return '${a.name}\n${a.type} • Saldo: $mainStr';
                    }(),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(8),
                      onTap: () =>
                          selectModule(NavModule.account, accountId: a.id),
                      child: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? colors.accent.withValues(alpha: 0.22)
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color:
                                isSelected ? colors.accent : Colors.transparent,
                          ),
                        ),
                        child: Center(
                          child: AccountLogoWidget(
                            account: a,
                            size: 24,
                            cornerRadius: 5,
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }),
              const Divider(height: 16),

              // Atalhos de Módulos
              Tooltip(
                message: 'Lançamentos Consolidados',
                child: IconButton(
                  icon: Icon(
                    Icons.receipt_long_outlined,
                    size: 20,
                    color: widget.store.activeModule == NavModule.transactions
                        ? colors.accent
                        : colors.textSecondary,
                  ),
                  onPressed: () => selectModule(NavModule.transactions),
                ),
              ),
              Tooltip(
                message: 'Contas a Pagar & Receber',
                child: IconButton(
                  icon: Icon(
                    Icons.notifications_active_outlined,
                    size: 20,
                    color: widget.store.activeModule == NavModule.dueBills
                        ? colors.warning
                        : colors.textSecondary,
                  ),
                  onPressed: () => selectModule(NavModule.dueBills),
                ),
              ),
              Tooltip(
                message: 'Compras Parceladas',
                child: IconButton(
                  icon: Icon(
                    Icons.credit_score,
                    size: 20,
                    color: widget.store.activeModule == NavModule.installments
                        ? colors.accentIndigo
                        : colors.textSecondary,
                  ),
                  onPressed: () => selectModule(NavModule.installments),
                ),
              ),
              Tooltip(
                message: 'Fluxo de Caixa',
                child: IconButton(
                  icon: Icon(
                    Icons.grid_on_rounded,
                    size: 20,
                    color: widget.store.activeModule == NavModule.cashFlow
                        ? colors.accent
                        : colors.textSecondary,
                  ),
                  onPressed: () => selectModule(NavModule.cashFlow),
                ),
              ),
              Tooltip(
                message: 'Relatórios',
                child: IconButton(
                  icon: Icon(
                    Icons.pie_chart_outline,
                    size: 20,
                    color: widget.store.activeModule == NavModule.reports
                        ? colors.income
                        : colors.textSecondary,
                  ),
                  onPressed: () => selectModule(NavModule.reports),
                ),
              ),
            ],
          ),
        ),

        // Rodapé do Mini Rail
        const Divider(height: 16),
        Tooltip(
          message: 'Ajustes & Personalização',
          child: IconButton(
            icon: Icon(
              Icons.tune,
              size: 20,
              color: widget.store.activeModule == NavModule.settings
                  ? colors.accent
                  : colors.textSecondary,
            ),
            onPressed: () => selectModule(NavModule.settings),
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _buildActiveMainView(
    BuildContext context, {
    required bool isDesktopOrTablet,
    required OpenMoneyColors colors,
  }) {
    switch (widget.store.activeModule) {
      case NavModule.dashboard:
        return DashboardOverviewView(store: widget.store);
      case NavModule.settings:
        return SettingsView(store: widget.store);
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
      case NavModule.transactions:
        return AllTransactionsView(store: widget.store);
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
      case NavModule.installments:
        return InstallmentsView(store: widget.store);
      case NavModule.search:
        return GlobalSearchView(store: widget.store);
    }
  }


  Widget _buildSidebarContent(
    BuildContext context,
    OpenMoneyColors colors, {
    required bool closeDrawerOnSelect,
  }) {
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
                        ClipRRect(
                          borderRadius: BorderRadius.circular(7),
                          child: Image.asset(
                            'logo/openmoney_app_icon.png',
                            width: 28,
                            height: 28,
                            filterQuality: FilterQuality.medium,
                          ),
                        ),
                        const SizedBox(width: 9),
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
                                  color: colors.accent,
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
                      ListenableBuilder(
                        listenable: CloudSyncService.instance,
                        builder: (context, _) {
                          if (CloudSyncService.instance.isAuthenticated) {
                            return const SizedBox.shrink();
                          }
                          return IconButton(
                            visualDensity: VisualDensity.compact,
                            tooltip: 'Base de Dados Local',
                            icon: const Icon(Icons.folder_open_outlined, size: 18),
                            onPressed: () => showDatabaseFileManagerModal(
                              context,
                              widget.store,
                            ),
                          );
                        },
                      ),
                      if (!closeDrawerOnSelect)
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          tooltip: 'Recolher para Mini Rail (Ctrl/Cmd+B)',
                          icon: const Icon(Icons.menu_open, size: 18),
                          onPressed: () => widget.store.setSidebarMode(
                            widget.store.sidebarMode == 'expanded'
                                ? 'miniRail'
                                : 'expanded',
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),

        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            children: [
              // 1. Dashboard Geral (posicionado acima do Novo Lançamento)
              _SidebarNavTile(
                iconWidget: _DashboardVectorIcon(
                  size: 18,
                  color: widget.store.activeModule == NavModule.dashboard
                      ? colors.accent
                      : colors.textSecondary,
                  filled: widget.store.activeModule == NavModule.dashboard,
                ),
                label: 'Dashboard Geral',
                selected: widget.store.activeModule == NavModule.dashboard,
                onTap: () => selectModule(NavModule.dashboard),
              ),
              const SizedBox(height: 6),

              // 2. Botão para inclusão de novos lançamentos (alinhado à esquerda)
              Padding(
                padding: const EdgeInsets.fromLTRB(2, 2, 2, 10),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    icon: const Icon(Icons.add_circle, size: 16),
                    label: const Text(
                      'Novo Lançamento',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 13,
                        letterSpacing: 0.2,
                      ),
                    ),
                    style: FilledButton.styleFrom(
                      alignment: Alignment.centerLeft,
                      backgroundColor: colors.accent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        vertical: 10,
                        horizontal: 14,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(9),
                      ),
                      elevation: 1,
                    ),
                    onPressed: () {
                      if (closeDrawerOnSelect) {
                        Navigator.of(context).pop();
                      }
                      final currentAccId =
                          widget.store.activeModule == NavModule.account
                              ? widget.store.selectedAccountId
                              : null;
                      showTransactionCreateModal(
                        context,
                        widget.store,
                        initialAccountId: currentAccId,
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(height: 4),

              // 1. Contas Favoritas (se houver)
              if (favAccounts.isNotEmpty) ...[
                InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: widget.store.toggleSidebarFavorites,
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                    child: Row(
                      children: [
                        Icon(
                          widget.store.sidebarShowFavorites
                              ? Icons.expand_less
                              : Icons.expand_more,
                          size: 16,
                          color: colors.textMuted,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          'CONTAS FAVORITAS ★ (${favAccounts.length})',
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.5,
                            color: colors.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                if (widget.store.sidebarShowFavorites)
                  ...favAccounts.map((a) {
                    final idx = favAccounts.indexOf(a);
                    return _SidebarAccountTile(
                      key: ValueKey(a.id),
                      account: a,
                      balanceCents: widget.store.balance(a, predicted: false),
                      predCents: widget.store.balance(a, predicted: true),
                      selected:
                          widget.store.activeModule == NavModule.account &&
                              widget.store.selectedAccountId == a.id,
                      colors: colors,
                      store: widget.store,
                      isFirstInGroup: idx == 0,
                      isLastInGroup: idx == favAccounts.length - 1,
                      onMoveUp: () => widget.store.moveAccountStepWithinGroup(
                        favAccounts,
                        a.id,
                        -1,
                      ),
                      onMoveDown: () => widget.store.moveAccountStepWithinGroup(
                        favAccounts,
                        a.id,
                        1,
                      ),
                      onTap: () =>
                          selectModule(NavModule.account, accountId: a.id),
                    );
                  }),
                const SizedBox(height: 8),
              ],

              // 2. Contas Ativas com colapso/expansão persistido em config.json
              InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: widget.store.toggleSidebarActiveAccounts,
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Icon(
                            widget.store.sidebarShowActiveAccounts
                                ? Icons.expand_less
                                : Icons.expand_more,
                            size: 16,
                            color: colors.textMuted,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'CONTAS ATIVAS (${regActive.length})',
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 0.5,
                              color: colors.textMuted,
                            ),
                          ),
                        ],
                      ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        tooltip: 'Nova Conta',
                        icon: Icon(Icons.add_circle_outline,
                            size: 17, color: colors.accent),
                        onPressed: () =>
                            showAccountModal(context, widget.store),
                      ),
                    ],
                  ),
                ),
              ),
              if (widget.store.sidebarShowActiveAccounts)
                ...regActive.map((a) {
                  final idx = regActive.indexOf(a);
                  return _SidebarAccountTile(
                    key: ValueKey(a.id),
                    account: a,
                    balanceCents: widget.store.balance(a, predicted: false),
                    predCents: widget.store.balance(a, predicted: true),
                    selected: widget.store.activeModule == NavModule.account &&
                        widget.store.selectedAccountId == a.id,
                    colors: colors,
                    store: widget.store,
                    isFirstInGroup: idx == 0,
                    isLastInGroup: idx == regActive.length - 1,
                    onMoveUp: () => widget.store.moveAccountStepWithinGroup(
                      regActive,
                      a.id,
                      -1,
                    ),
                    onMoveDown: () => widget.store.moveAccountStepWithinGroup(
                      regActive,
                      a.id,
                      1,
                    ),
                    onTap: () =>
                        selectModule(NavModule.account, accountId: a.id),
                  );
                }),

              // 3. Contas Inativas (colapsável e persistido em config.json)
              if (regInactive.isNotEmpty) ...[
                const SizedBox(height: 6),
                InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: widget.store.toggleSidebarInactiveAccounts,
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          children: [
                            Icon(
                              widget.store.sidebarShowInactiveAccounts
                                  ? Icons.expand_less
                                  : Icons.expand_more,
                              size: 16,
                              color: colors.textMuted,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'CONTAS INATIVAS (${regInactive.length})',
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.5,
                                color: colors.textMuted,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                if (widget.store.sidebarShowInactiveAccounts)
                  ...regInactive.map((a) {
                    final idx = regInactive.indexOf(a);
                    return _SidebarAccountTile(
                      key: ValueKey(a.id),
                      account: a,
                      balanceCents: widget.store.balance(a, predicted: false),
                      predCents: widget.store.balance(a, predicted: true),
                      selected:
                          widget.store.activeModule == NavModule.account &&
                              widget.store.selectedAccountId == a.id,
                      colors: colors,
                      store: widget.store,
                      isFirstInGroup: idx == 0,
                      isLastInGroup: idx == regInactive.length - 1,
                      onMoveUp: () => widget.store.moveAccountStepWithinGroup(
                        regInactive,
                        a.id,
                        -1,
                      ),
                      onMoveDown: () => widget.store.moveAccountStepWithinGroup(
                        regInactive,
                        a.id,
                        1,
                      ),
                      onTap: () =>
                          selectModule(NavModule.account, accountId: a.id),
                    );
                  }),
              ],

              const SizedBox(height: 14),

              // 4. PLANEJAMENTO (colapsável e persistido)
              InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: widget.store.toggleSidebarPlanning,
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                  child: Row(
                    children: [
                      Icon(
                        widget.store.sidebarShowPlanning
                            ? Icons.expand_less
                            : Icons.expand_more,
                        size: 16,
                        color: colors.textMuted,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'PLANEJAMENTO',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.5,
                          color: colors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (widget.store.sidebarShowPlanning) ...[
                _SidebarNavTile(
                  icon: Icons.receipt_long_outlined,
                  label: 'Lançamentos',
                  selected: widget.store.activeModule == NavModule.transactions,
                  onTap: () => selectModule(NavModule.transactions),
                ),
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
                  icon: Icons.credit_score,
                  label: 'Compras Parceladas',
                  selected: widget.store.activeModule == NavModule.installments,
                  onTap: () => selectModule(NavModule.installments),
                ),
                _SidebarNavTile(
                  icon: Icons.grid_on_rounded,
                  label: 'Fluxo de Caixa',
                  selected: widget.store.activeModule == NavModule.cashFlow,
                  onTap: () => selectModule(NavModule.cashFlow),
                ),
                _SidebarNavTile(
                  icon: Icons.pie_chart_outline,
                  label: 'Relatório',
                  selected: widget.store.activeModule == NavModule.reports,
                  onTap: () => selectModule(NavModule.reports),
                ),
                _SidebarNavTile(
                  icon: Icons.track_changes,
                  label: 'Limite de Gastos',
                  selected: widget.store.activeModule == NavModule.budget,
                  onTap: () => selectModule(NavModule.budget),
                ),
                _SidebarNavTile(
                  icon: Icons.manage_search,
                  label: 'Pesquisa Global',
                  selected: widget.store.activeModule == NavModule.search,
                  onTap: () => selectModule(NavModule.search),
                ),
              ],

              const SizedBox(height: 10),

              // 5. MÓDULOS (colapsável e persistido, por padrão recolhido)
              InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: widget.store.toggleSidebarModules,
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                  child: Row(
                    children: [
                      Icon(
                        widget.store.sidebarShowModules
                            ? Icons.expand_less
                            : Icons.expand_more,
                        size: 16,
                        color: colors.textMuted,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'MÓDULOS',
                        style: TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.5,
                          color: colors.textMuted,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (widget.store.sidebarShowModules) ...[
                // 1º Categoria e Subcategoria
                _SidebarNavTile(
                  icon: Icons.category_outlined,
                  label: 'Categorias e Subcategorias',
                  selected: widget.store.activeModule == NavModule.categories,
                  onTap: () => selectModule(NavModule.categories),
                ),
                // 2º Ajustes & Personalização
                _SidebarNavTile(
                  icon: Icons.tune,
                  label: 'Ajustes & Personalização',
                  selected: widget.store.activeModule == NavModule.settings,
                  onTap: () => selectModule(NavModule.settings),
                ),
                // 3º Incluir Nova Conta
                _SidebarNavTile(
                  icon: Icons.account_balance_outlined,
                  label: 'Incluir Nova Conta',
                  selected: false,
                  onTap: () {
                    if (closeDrawerOnSelect) Navigator.of(context).pop();
                    showAccountModal(context, widget.store);
                  },
                ),
                if (kIsWeb)
                  _SidebarNavTile(
                    icon: Icons.cloud_sync_outlined,
                    label: 'Conta Cloud & Sincronização',
                    selected: false,
                    badgeText: CloudSyncService.instance.isAuthenticated
                        ? 'On'
                        : null,
                    badgeColor: colors.accentGreen,
                    onTap: () => showCloudAccountModal(context, widget.store),
                  ),
                if (!kIsWeb)
                  _SidebarNavTile(
                    icon: Icons.archive_outlined,
                    label: 'Backups de Segurança',
                    selected: false,
                    onTap: () => showBackupsHistoryModal(context, widget.store),
                  ),
                _SidebarNavTile(
                  icon: Icons.history_edu_outlined,
                  label: 'Logs de Alterações',
                  selected: false,
                  onTap: () => showAuditLogsModal(context, widget.store),
                ),
                _SidebarNavTile(
                  icon: Icons.import_export,
                  label: 'Importação / Exportação',
                  selected: false,
                  onTap: () => showCsvQifCenterModal(context, widget.store),
                ),
                _SidebarNavTile(
                  icon: Icons.cleaning_services_outlined,
                  label: 'Excluir Lançamentos',
                  selected: false,
                  onTap: () => showBatchDeleteModal(context, widget.store),
                ),
                if (!kIsWeb)
                  _SidebarNavTile(
                    icon: Icons.system_update_alt,
                    label: 'Buscar Atualizações',
                    selected: false,
                    onTap: () => UpdateService.showUpdateDialog(
                      context,
                      manual: true,
                    ),
                  ),
                _SidebarNavTile(
                  icon: Icons.help_outline,
                  label: 'Ajuda e Manual',
                  selected: false,
                  onTap: () => showHelpModal(context, widget.store),
                ),
                _SidebarNavTile(
                  icon: Icons.info_outline,
                  label: 'Sobre o OpenMoney',
                  selected: false,
                  onTap: () => showAboutOpenMoneyModal(context, colors),
                ),
              ],
            ],
          ),
        ),
        // ====================================================================
        // Seletor Simples Local ↔ Online no Rodapé da Barra Lateral
        // ====================================================================
        ListenableBuilder(
          listenable: Listenable.merge(
            [widget.store, CloudSyncService.instance, SyncEngine.instance],
          ),
          builder: (context, _) {
            final isCloud = widget.store.isCloudMode;
            final cloud = CloudSyncService.instance;
            return Container(
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: colors.borderGlass)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 1. Segmented Control / Pílula de Alternância Rápida (Apenas no Desktop)
                  if (!kIsWeb)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(10, 8, 10, 4),
                      child: Container(
                      height: 28,
                      decoration: BoxDecoration(
                        color: colors.bgPrimary.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: colors.borderGlass),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: InkWell(
                              borderRadius: BorderRadius.circular(7),
                              onTap: () {
                                if (isCloud) {
                                  if (widget.store.hasConfiguredLocalDatabase) {
                                    widget.store.switchToLocalMode();
                                  } else {
                                    showDatabaseFileManagerModal(context, widget.store);
                                  }
                                } else if (!widget.store.hasConfiguredLocalDatabase) {
                                  showDatabaseFileManagerModal(context, widget.store);
                                }
                              },
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 150),
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: !isCloud
                                      ? colors.accent.withValues(alpha: 0.18)
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(7),
                                  border: !isCloud
                                      ? Border.all(
                                          color: colors.accent
                                              .withValues(alpha: 0.4),
                                          width: 1,
                                        )
                                      : null,
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.laptop_mac_rounded,
                                      size: 13,
                                      color: !isCloud
                                          ? colors.accent
                                          : colors.textMuted,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      'Local',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: !isCloud
                                            ? FontWeight.w800
                                            : FontWeight.w500,
                                        color: !isCloud
                                            ? colors.textPrimary
                                            : colors.textMuted,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          Expanded(
                            child: InkWell(
                              borderRadius: BorderRadius.circular(7),
                              onTap: () {
                                if (!isCloud) {
                                  if (cloud.isAuthenticated) {
                                    widget.store.switchToCloudMode();
                                  } else {
                                    showCloudAccountModal(context, widget.store);
                                  }
                                } else if (!cloud.isAuthenticated) {
                                  showCloudAccountModal(context, widget.store);
                                }
                              },
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 150),
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: isCloud
                                      ? colors.accentGreen
                                          .withValues(alpha: 0.18)
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(7),
                                  border: isCloud
                                      ? Border.all(
                                          color: colors.accentGreen
                                              .withValues(alpha: 0.4),
                                          width: 1,
                                        )
                                      : null,
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(
                                      Icons.cloud_done_rounded,
                                      size: 13,
                                      color: isCloud
                                          ? colors.accentGreen
                                          : colors.textMuted,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      'Online',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: isCloud
                                            ? FontWeight.w800
                                            : FontWeight.w500,
                                        color: isCloud
                                            ? colors.textPrimary
                                            : colors.textMuted,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // 2. Linha descritiva clicável (abre o modal correspondente)
                  if (isCloud || kIsWeb)
                    Tooltip(
                      message:
                          '${cloud.userEmail} • ${cloud.statusLabel}\nClique para gerenciar a conta Cloud',
                      child: InkWell(
                        onTap: () =>
                            showCloudAccountModal(context, widget.store),
                        child: Padding(
                          padding: EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: kIsWeb ? 10 : 6,
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 7,
                                height: 7,
                                decoration: BoxDecoration(
                                  color: cloud.state == CloudSyncState.error
                                      ? colors.warning
                                      : colors.accentGreen,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  '${cloud.userEmail.isNotEmpty ? cloud.userEmail : "Cloud"} • ${cloud.statusLabel}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w600,
                                    color: colors.textPrimary,
                                  ),
                                ),
                              ),
                              Icon(Icons.chevron_right,
                                  size: 14, color: colors.textSecondary),
                            ],
                          ),
                        ),
                      ),
                    )
                  else if (!kIsWeb)
                    Tooltip(
                      message:
                          'Base Local: ${widget.store.databaseDisplayName}\nClique para gerenciar arquivos e backups locais',
                      child: InkWell(
                        onTap: () => showDatabaseFileManagerModal(
                            context, widget.store),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 6),
                          child: Row(
                            children: [
                              Icon(
                                Icons.folder_open_rounded,
                                size: 14,
                                color: colors.textSecondary,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  'Base Local • v${OpenMoneyVersion.version} • ${widget.store.databaseDisplayName}',
                                  maxLines: 1,
                                  softWrap: false,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: FontWeight.w600,
                                    color: colors.textSecondary,
                                  ),
                                ),
                              ),
                              Icon(Icons.chevron_right,
                                  size: 14, color: colors.textSecondary),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: colors.borderGlass)),
          ),
          child: Row(
            children: [
              Icon(Icons.format_size, size: 16, color: colors.textSecondary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'Fontes',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                    color: colors.textSecondary,
                  ),
                ),
              ),
              ZoomControlPill(store: widget.store, colors: colors),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCloudLoadingScreen(
    BuildContext context,
    OpenMoneyColors colors,
  ) {
    final cloud = CloudSyncService.instance;
    final sync = SyncEngine.instance;
    final hasError = cloud.state == CloudSyncState.error && !sync.isSyncing;
    final email = cloud.userEmail.isNotEmpty ? cloud.userEmail : 'sua conta';

    return Scaffold(
      backgroundColor: colors.bgPrimary,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: GlassCard(
              padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    decoration: BoxDecoration(
                      color: (hasError ? colors.warning : colors.income)
                          .withValues(alpha: 0.14),
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: hasError
                          ? Icon(
                              Icons.cloud_off_rounded,
                              size: 32,
                              color: colors.warning,
                            )
                          : SizedBox(
                              width: 30,
                              height: 30,
                              child: CircularProgressIndicator(
                                strokeWidth: 3,
                                color: colors.income,
                              ),
                            ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    hasError
                        ? 'Falha ao carregar dados da nuvem'
                        : 'Carregando seus dados...',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: colors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    hasError
                        ? (cloud.lastError ??
                            'Não foi possível conectar ao servidor no momento. Verifique sua conexão e tente novamente.')
                        : 'Sincronizando e descriptografando a base de $email na nuvem. Isso leva apenas alguns segundos...',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 13,
                      height: 1.45,
                      color: colors.textSecondary,
                    ),
                  ),
                  if (hasError) ...[
                    const SizedBox(height: 22),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      alignment: WrapAlignment.center,
                      children: [
                        FilledButton.icon(
                          icon: const Icon(Icons.refresh, size: 18),
                          label: const Text('Tentar Novamente'),
                          onPressed: () {
                            SyncEngine.instance.syncNow(forceFullPull: true);
                          },
                        ),
                        OutlinedButton.icon(
                          icon: const Icon(Icons.cloud_outlined, size: 18),
                          label: const Text('Conta Cloud'),
                          onPressed: () {
                            showCloudAccountModal(context, widget.store);
                          },
                        ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
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
                      label: const Text('Procurar Base no Finder (.json)'),
                      onPressed: () async {
                        final selected = await NativeFilePicker.pickFile(
                          title: 'Localizar Base de Dados OpenMoney (.json)',
                          allowedExtensions: ['json'],
                        );
                        if (selected != null && selected.isNotEmpty) {
                          widget.store.openDatabaseFromPath(selected);
                        }
                      },
                    ),
                    OutlinedButton.icon(
                      icon: const Icon(Icons.add),
                      label: const Text('Criar Nova Base em Outro Local'),
                      onPressed: () async {
                        final savePath = await NativeFilePicker.saveFile(
                          title: 'Escolher Local para Salvar Nova Base',
                          defaultName: 'openmoney.json',
                        );
                        if (savePath != null && savePath.isNotEmpty) {
                          widget.store.createNewDatabaseAtPath(savePath);
                        }
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

class _SidebarNavTile extends StatelessWidget {
  final IconData? icon;
  final Widget? iconWidget;
  final String label;
  final bool selected;
  final String? badgeText;
  final Color? badgeColor;
  final VoidCallback onTap;

  const _SidebarNavTile({
    this.icon,
    this.iconWidget,
    required this.label,
    required this.selected,
    this.badgeText,
    this.badgeColor,
    required this.onTap,
  }) : assert(icon != null || iconWidget != null);

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
            if (iconWidget != null)
              iconWidget!
            else if (icon != null)
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
  final int predCents;
  final bool selected;
  final OpenMoneyColors colors;
  final MoneyStore store;
  final bool isFirstInGroup;
  final bool isLastInGroup;
  final VoidCallback onMoveUp;
  final VoidCallback onMoveDown;
  final VoidCallback onTap;

  const _SidebarAccountTile({
    super.key,
    required this.account,
    required this.balanceCents,
    required this.predCents,
    required this.selected,
    required this.colors,
    required this.store,
    required this.isFirstInGroup,
    required this.isLastInGroup,
    required this.onMoveUp,
    required this.onMoveDown,
    required this.onTap,
  });

  void _showContextMenu(BuildContext context, Offset globalPos) {
    final RenderBox overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;
    final position = RelativeRect.fromRect(
      Rect.fromPoints(globalPos, globalPos),
      Offset.zero & overlay.size,
    );

    final future = showMenu<String>(
      context: context,
      position: position,
      items: [
        PopupMenuItem(
          value: 'edit',
          child: Row(
            children: [
              Icon(Icons.edit_outlined, size: 16, color: colors.textSecondary),
              const SizedBox(width: 8),
              const Text('Editar conta...'),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'toggle_favorite',
          child: Row(
            children: [
              Icon(
                account.isFavorite ? Icons.star_border : Icons.star,
                size: 16,
                color: colors.warning,
              ),
              const SizedBox(width: 8),
              Text(account.isFavorite
                  ? 'Remover dos favoritos'
                  : 'Marcar como favorita'),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'toggle_inactive',
          child: Row(
            children: [
              Icon(
                account.isInactive
                    ? Icons.check_circle_outline
                    : Icons.archive_outlined,
                size: 16,
                color: colors.textSecondary,
              ),
              const SizedBox(width: 8),
              Text(account.isInactive ? 'Reativar conta' : 'Desativar conta'),
            ],
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem(
          value: 'move_up',
          enabled: !isFirstInGroup,
          child: Row(
            children: [
              Icon(
                Icons.arrow_upward,
                size: 16,
                color:
                    !isFirstInGroup ? colors.textSecondary : colors.textMuted,
              ),
              const SizedBox(width: 8),
              const Text('Mover para cima'),
            ],
          ),
        ),
        PopupMenuItem(
          value: 'move_down',
          enabled: !isLastInGroup,
          child: Row(
            children: [
              Icon(
                Icons.arrow_downward,
                size: 16,
                color:
                    !isLastInGroup ? colors.textSecondary : colors.textMuted,
              ),
              const SizedBox(width: 8),
              const Text('Mover para baixo'),
            ],
          ),
        ),
      ],
    );

    future.then((choice) {
      if (choice == null || !context.mounted) return;
      switch (choice) {
        case 'edit':
          showAccountModal(context, store, editingAccount: account);
          break;
        case 'toggle_favorite':
          store.toggleAccountFavorite(account.id);
          break;
        case 'toggle_inactive':
          store.toggleAccountInactive(account.id);
          break;
        case 'move_up':
          onMoveUp();
          break;
        case 'move_down':
          onMoveDown();
          break;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onSecondaryTapUp: (details) =>
          _showContextMenu(context, details.globalPosition),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 5),
          margin: const EdgeInsets.only(bottom: 2),
          decoration: BoxDecoration(
            color: selected
                ? colors.accent.withValues(alpha: 0.16)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Up / Down order arrows
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  InkWell(
                    borderRadius: BorderRadius.circular(4),
                    onTap: isFirstInGroup ? null : onMoveUp,
                    child: Padding(
                      padding: const EdgeInsets.all(2),
                      child: Icon(
                        Icons.keyboard_arrow_up,
                        size: 14,
                        color: isFirstInGroup
                            ? colors.textMuted.withValues(alpha: 0.25)
                            : colors.textSecondary.withValues(alpha: 0.65),
                      ),
                    ),
                  ),
                  InkWell(
                    borderRadius: BorderRadius.circular(4),
                    onTap: isLastInGroup ? null : onMoveDown,
                    child: Padding(
                      padding: const EdgeInsets.all(2),
                      child: Icon(
                        Icons.keyboard_arrow_down,
                        size: 14,
                        color: isLastInGroup
                            ? colors.textMuted.withValues(alpha: 0.25)
                            : colors.textSecondary.withValues(alpha: 0.65),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 4),
              AccountLogoWidget(
                account: account,
                size: 28,
                cornerRadius: 8,
                selected: selected,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        if (account.isInactive) ...[
                          Icon(
                            Icons.archive_outlined,
                            size: 11,
                            color: colors.textMuted,
                          ),
                          const SizedBox(width: 3),
                        ],
                        Expanded(
                          child: Tooltip(
                            message: account.name,
                            waitDuration: const Duration(milliseconds: 400),
                            child: Text(
                              account.name,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight:
                                    selected ? FontWeight.w700 : FontWeight.w500,
                                color: account.isInactive
                                    ? colors.textPrimary.withValues(alpha: 0.65)
                                    : (selected
                                        ? colors.accent
                                        : colors.textPrimary),
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 1.5),
                    Text(
                      () {
                        final accCur = account.effectiveCurrency;
                        final isForeign = accCur != store.baseCurrency;
                        final curPrefix = isForeign
                            ? '${currencyMetaFor(accCur).flag} $accCur • '
                            : '';
                        final typeStr = account.isInactive
                            ? '${account.type} • Inativa'
                            : account.type;
                        if (account.business != null &&
                            account.business!.isNotEmpty) {
                          return '$curPrefix$typeStr • ${account.business}';
                        }
                        return '$curPrefix$typeStr';
                      }(),
                      style: TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w500,
                        color: colors.textMuted,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    formatCurrency(
                      balanceCents,
                      account.effectiveCurrency,
                      showSymbol:
                          account.effectiveCurrency != store.baseCurrency,
                    ),
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: balanceCents >= 0 ? colors.income : colors.expense,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  if (account.effectiveCurrency != store.baseCurrency) ...[
                    const SizedBox(height: 1),
                    Text(
                      '≈ ${formatCurrency(store.convertToBase(balanceCents, account.effectiveCurrency), store.baseCurrency)}',
                      style: TextStyle(
                        fontSize: 9.0,
                        fontWeight: FontWeight.w500,
                        color: colors.textMuted,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                  if (predCents != balanceCents && predCents != 0) ...[
                    const SizedBox(height: 1),
                    Text(
                      'Prev: ${formatCurrency(predCents, account.effectiveCurrency, showSymbol: account.effectiveCurrency != store.baseCurrency)}',
                      style: TextStyle(
                        fontSize: 9.5,
                        fontWeight: FontWeight.w500,
                        color: colors.textMuted,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Ícone vetorial puro para o Dashboard Geral desenhado via CustomPaint.
/// Garante renderização instantânea e perfeita em navegadores Chromium (Chrome, Edge),
/// Safari, Firefox e Desktop sem depender de download ou cache de fontes web.
class _DashboardVectorIcon extends StatelessWidget {
  final double size;
  final Color color;
  final bool filled;

  const _DashboardVectorIcon({
    this.size = 18,
    required this.color,
    this.filled = false,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        size: Size.square(size),
        painter: _DashboardVectorPainter(color: color, filled: filled),
      ),
    );
  }
}

class _DashboardVectorPainter extends CustomPainter {
  final Color color;
  final bool filled;

  const _DashboardVectorPainter({
    required this.color,
    required this.filled,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    final strokeWidth = (w * 0.08).clamp(1.4, 1.8);
    final paint = Paint()
      ..color = color
      ..style = filled ? PaintingStyle.fill : PaintingStyle.stroke
      ..strokeWidth = strokeWidth;

    final pad = w * 0.08;
    final gap = w * 0.14;
    final cellW = (w - (pad * 2) - gap) / 2;
    final cellH = (h - (pad * 2) - gap) / 2;
    final r = Radius.circular(cellW * 0.28);

    // 4 blocos no grid 2x2: top-left, top-right, bottom-left, bottom-right
    final tl = RRect.fromRectAndRadius(
      Rect.fromLTWH(pad, pad, cellW, cellH),
      r,
    );
    final tr = RRect.fromRectAndRadius(
      Rect.fromLTWH(pad + cellW + gap, pad, cellW, cellH),
      r,
    );
    final bl = RRect.fromRectAndRadius(
      Rect.fromLTWH(pad, pad + cellH + gap, cellW, cellH),
      r,
    );
    final br = RRect.fromRectAndRadius(
      Rect.fromLTWH(pad + cellW + gap, pad + cellH + gap, cellW, cellH),
      r,
    );

    canvas.drawRRect(tl, paint);
    canvas.drawRRect(tr, paint);
    canvas.drawRRect(bl, paint);
    canvas.drawRRect(br, paint);
  }

  @override
  bool shouldRepaint(covariant _DashboardVectorPainter oldDelegate) {
    return oldDelegate.color != color || oldDelegate.filled != filled;
  }
}
