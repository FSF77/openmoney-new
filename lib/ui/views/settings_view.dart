import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../models/openmoney_models.dart';
import '../../services/ai_assistant_service.dart';
import '../../services/cloud_sync_service.dart';
import '../../services/platform_io.dart';
import '../../store/money_store.dart';
import '../modals/mcp_tokens_modal.dart';
import '../theme/liquid_glass.dart';

class SettingsView extends StatefulWidget {
  final MoneyStore store;
  const SettingsView({super.key, required this.store});

  @override
  State<SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends State<SettingsView> {
  late TextEditingController _geminiKeyCtrl;
  late TextEditingController _openrouterKeyCtrl;
  late TextEditingController _claudeKeyCtrl;
  late TextEditingController _openaiKeyCtrl;
  bool _obscureGeminiKey = true;
  bool _obscureOpenrouterKey = true;
  bool _obscureClaudeKey = true;
  bool _obscureOpenaiKey = true;
  bool _isTestingAi = false;
  String _aiTestStatusMessage = '';
  bool _isRecalculatingHistory = false;

  @override
  void initState() {
    super.initState();
    _geminiKeyCtrl = TextEditingController(text: widget.store.geminiApiKey);
    _openrouterKeyCtrl =
        TextEditingController(text: widget.store.openrouterApiKey);
    _claudeKeyCtrl = TextEditingController(text: widget.store.claudeApiKey);
    _openaiKeyCtrl = TextEditingController(text: widget.store.openaiApiKey);
  }

  @override
  void dispose() {
    _geminiKeyCtrl.dispose();
    _openrouterKeyCtrl.dispose();
    _claudeKeyCtrl.dispose();
    _openaiKeyCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colors = OpenMoneyColors(isDark);
    final isCompact = widget.store.uiDensityMode == 'compact';

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: ListView(
          padding: EdgeInsets.symmetric(
            horizontal: isCompact ? 16 : 24,
            vertical: isCompact ? 14 : 20,
          ),
          children: [
            // Cabeçalho da Tela de Ajustes
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: colors.accent.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: colors.accent.withValues(alpha: 0.35),
                    ),
                  ),
                  child: Icon(Icons.settings, color: colors.accent, size: 26),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Ajustes & Personalização',
                        style: TextStyle(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          color: colors.textPrimary,
                          letterSpacing: -0.3,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Personalize o comportamento, aparência, densidade, layout e widgets do OpenMoney.',
                        style: TextStyle(
                          fontSize: 13,
                          color: colors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),

            // =================================================================
            // 1. GERAL & INICIALIZAÇÃO
            // =================================================================
            _buildSectionCard(
              colors: colors,
              title: 'Geral & Inicialização',
              icon: Icons.tune,
              children: [
                _buildSettingRow(
                  colors: colors,
                  title: 'Tela Padrão de Abertura',
                  subtitle:
                      'Escolha qual tela deve ser carregada inicialmente ao abrir o app.',
                  trailing: SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(
                        value: 'dashboard',
                        label: Text('Dashboard Geral'),
                        icon: Icon(Icons.dashboard, size: 16),
                      ),
                      ButtonSegment(
                        value: 'lastAccount',
                        label: Text('Última Conta'),
                        icon: Icon(Icons.account_balance_wallet_outlined, size: 16),
                      ),
                    ],
                    selected: {widget.store.startupView},
                    onSelectionChanged: (set) {
                      widget.store.setStartupView(set.first);
                    },
                  ),
                ),
                const Divider(height: 20),
                _buildSettingRow(
                  colors: colors,
                  title: 'Lembretes de Vencimento',
                  subtitle:
                      'Avisar sobre contas e faturas que vencem nos próximos ${widget.store.reminderDaysAhead} dia(s).',
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.remove_circle_outline, size: 18),
                        onPressed: widget.store.reminderDaysAhead > 1
                            ? () => widget.store.setReminderDaysAhead(
                                  widget.store.reminderDaysAhead - 1,
                                )
                            : null,
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 4),
                        decoration: BoxDecoration(
                          color: colors.surfaceGlass,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: colors.borderGlass),
                        ),
                        child: Text(
                          '${widget.store.reminderDaysAhead} dias',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: colors.textPrimary,
                          ),
                        ),
                      ),
                      IconButton(
                        visualDensity: VisualDensity.compact,
                        icon: const Icon(Icons.add_circle_outline, size: 18),
                        onPressed: widget.store.reminderDaysAhead < 60
                            ? () => widget.store.setReminderDaysAhead(
                                  widget.store.reminderDaysAhead + 1,
                                )
                            : null,
                      ),
                    ],
                  ),
                ),
                const Divider(height: 20),
                _buildSettingRow(
                  colors: colors,
                  title: 'Privacidade de Saldos',
                  subtitle:
                      'Ocultar valores e saldos consolidados de patrimônio por padrão (••••••).',
                  trailing: Switch(
                    value: widget.store.hidePatrimonyBalance,
                    onChanged: (v) =>
                        widget.store.toggleHidePatrimonyBalance(),
                  ),
                ),
                const Divider(height: 20),
                _buildSettingRow(
                  colors: colors,
                  title: 'Meses no Ajuste de Previsões',
                  subtitle:
                      'Quantidade de meses consecutivos avaliados ao rodar o abatimento automático de previsões orçamentárias.',
                  trailing: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                    decoration: BoxDecoration(
                      color: colors.surfaceGlass,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: colors.borderGlass),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<int>(
                        value: [1, 2, 3, 6, 12].contains(widget.store.db.predMonths)
                            ? widget.store.db.predMonths
                            : 3,
                        dropdownColor: colors.surfaceCard,
                        style: TextStyle(fontSize: 13, color: colors.textPrimary),
                        items: const [
                          DropdownMenuItem(value: 1, child: Text('1 mês')),
                          DropdownMenuItem(value: 2, child: Text('2 meses')),
                          DropdownMenuItem(value: 3, child: Text('3 meses (Padrão)')),
                          DropdownMenuItem(value: 6, child: Text('6 meses')),
                          DropdownMenuItem(value: 12, child: Text('12 meses')),
                        ],
                        onChanged: (v) {
                          if (v != null) {
                            setState(() {
                              widget.store.setPredMonths(v);
                            });
                          }
                        },
                      ),
                    ),
                  ),
                ),
                const Divider(height: 20),
                _buildSettingRow(
                  colors: colors,
                  title: 'Modo de Abatimento de Previsões',
                  subtitle:
                      'Define se o abatimento considera o mês civil do lançamento ou a competência de vencimento das faturas de cartão.',
                  trailing: SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(
                        value: 'month',
                        label: Text('Por Mês'),
                        icon: Icon(Icons.calendar_today, size: 16),
                      ),
                      ButtonSegment(
                        value: 'invoice',
                        label: Text('Por Fatura'),
                        icon: Icon(Icons.credit_card, size: 16),
                      ),
                    ],
                    selected: {widget.store.db.predMode},
                    onSelectionChanged: (set) {
                      setState(() {
                        widget.store.setPredMode(set.first);
                      });
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // =================================================================
            // 2. APARÊNCIA & CORES
            // =================================================================
            _buildSectionCard(
              colors: colors,
              title: 'Aparência & Cores de Destaque',
              icon: Icons.palette_outlined,
              children: [
                _buildSettingRow(
                  colors: colors,
                  title: 'Modo de Cor',
                  subtitle: 'Alterne entre o tema escuro e claro.',
                  trailing: SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(
                        value: true,
                        label: Text('Escuro'),
                        icon: Icon(Icons.dark_mode_outlined, size: 16),
                      ),
                      ButtonSegment(
                        value: false,
                        label: Text('Claro'),
                        icon: Icon(Icons.light_mode_outlined, size: 16),
                      ),
                    ],
                    selected: {widget.store.isDarkMode},
                    onSelectionChanged: (_) => widget.store.toggleThemeMode(),
                  ),
                ),
                const Divider(height: 20),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Cor de Destaque do Sistema (Accent Color)',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        color: colors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Personaliza a tonalidade primária dos botões, gráficos e seleções.',
                      style: TextStyle(
                        fontSize: 12,
                        color: colors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: OpenMoneyColors.accentPalettes.entries.map((e) {
                        final key = e.key;
                        final palette = e.value;
                        final isSelected = widget.store.accentColorKey == key;
                        final colorSample = isDark
                            ? palette.darkColor
                            : palette.lightColor;

                        return InkWell(
                          borderRadius: BorderRadius.circular(10),
                          onTap: () => widget.store.setAccentColorKey(key),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 180),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? colorSample.withValues(alpha: 0.18)
                                  : colors.surfaceGlass,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: isSelected
                                    ? colorSample
                                    : colors.borderGlass,
                                width: isSelected ? 2 : 1,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Container(
                                  width: 14,
                                  height: 14,
                                  decoration: BoxDecoration(
                                    color: colorSample,
                                    shape: BoxShape.circle,
                                    boxShadow: [
                                      BoxShadow(
                                        color: colorSample.withValues(alpha: 0.4),
                                        blurRadius: 4,
                                        offset: const Offset(0, 1),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  palette.label,
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: isSelected
                                        ? FontWeight.w800
                                        : FontWeight.w500,
                                    color: isSelected
                                        ? colors.textPrimary
                                        : colors.textSecondary,
                                  ),
                                ),
                                if (isSelected) ...[
                                  const SizedBox(width: 6),
                                  Icon(Icons.check, size: 14, color: colorSample),
                                ],
                              ],
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ],
                ),
                const Divider(height: 20),
                _buildSettingRow(
                  colors: colors,
                  title: 'Estilo de Superfície',
                  subtitle:
                      'Liquid Glass utiliza blur e transparências suaves; Flat Clean oferece superfícies sólidas de alto contraste.',
                  trailing: SegmentedButton<bool>(
                    segments: const [
                      ButtonSegment(
                        value: false,
                        label: Text('Liquid Glass'),
                        icon: Icon(Icons.auto_awesome, size: 16),
                      ),
                      ButtonSegment(
                        value: true,
                        label: Text('Flat Clean'),
                        icon: Icon(Icons.crop_square, size: 16),
                      ),
                    ],
                    selected: {widget.store.isFlatClean},
                    onSelectionChanged: (set) =>
                        widget.store.setIsFlatClean(set.first),
                  ),
                ),
                const Divider(height: 20),
                _buildSettingRow(
                  colors: colors,
                  title: 'Escala de Zoom da Interface',
                  subtitle:
                      'Ajusta o tamanho das fontes e proporção geral dos elementos (${widget.store.fontScaleLabel}).',
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        tooltip: 'Diminuir Zoom',
                        icon: const Icon(Icons.zoom_out, size: 18),
                        onPressed: () => widget.store.zoomOut(),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: colors.surfaceGlass,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: colors.borderGlass),
                        ),
                        child: Text(
                          widget.store.fontScaleLabel,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: colors.textPrimary,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Aumentar Zoom',
                        icon: const Icon(Icons.zoom_in, size: 18),
                        onPressed: () => widget.store.zoomIn(),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // =================================================================
            // 3. LAYOUT & BARRA LATERAL
            // =================================================================
            _buildSectionCard(
              colors: colors,
              title: 'Layout & Barra Lateral',
              icon: Icons.view_sidebar_outlined,
              children: [
                _buildSettingRow(
                  colors: colors,
                  title: 'Densidade de Conteúdo',
                  subtitle:
                      'Modo Compacto reduz espaçamentos para exibir mais dados simultaneamente no Desktop.',
                  trailing: SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(
                        value: 'compact',
                        label: Text('Compacta'),
                        icon: Icon(Icons.density_small, size: 16),
                      ),
                      ButtonSegment(
                        value: 'comfortable',
                        label: Text('Confortável'),
                        icon: Icon(Icons.density_medium, size: 16),
                      ),
                    ],
                    selected: {widget.store.uiDensityMode},
                    onSelectionChanged: (set) =>
                        widget.store.setUiDensityMode(set.first),
                  ),
                ),
                const Divider(height: 20),
                _buildSettingRow(
                  colors: colors,
                  title: 'Modo da Barra Lateral',
                  subtitle:
                      'Mini Rail exibe apenas os ícones e logotipos dos bancos com tooltips flutuantes ao passar o mouse.',
                  trailing: SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(
                        value: 'expanded',
                        label: Text('Expandida (280px)'),
                      ),
                      ButtonSegment(
                        value: 'miniRail',
                        label: Text('Mini Rail (64px)'),
                      ),
                    ],
                    selected: {
                      widget.store.sidebarMode == 'miniRail'
                          ? 'miniRail'
                          : 'expanded'
                    },
                    onSelectionChanged: (set) =>
                        widget.store.setSidebarMode(set.first),
                  ),
                ),
                const Divider(height: 20),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Seções Visíveis na Barra Lateral',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 14,
                        color: colors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 12,
                      runSpacing: 8,
                      children: [
                        FilterChip(
                          label: const Text('Contas Favoritas'),
                          selected: widget.store.sidebarShowFavorites,
                          onSelected: (_) =>
                              widget.store.toggleSidebarFavorites(),
                        ),
                        FilterChip(
                          label: const Text('Contas Ativas'),
                          selected: widget.store.sidebarShowActiveAccounts,
                          onSelected: (_) =>
                              widget.store.toggleSidebarActiveAccounts(),
                        ),
                        FilterChip(
                          label: const Text('Contas Inativas'),
                          selected: widget.store.sidebarShowInactiveAccounts,
                          onSelected: (_) =>
                              widget.store.toggleSidebarInactiveAccounts(),
                        ),
                        FilterChip(
                          label: const Text('Planejamento'),
                          selected: widget.store.sidebarShowPlanning,
                          onSelected: (_) =>
                              widget.store.toggleSidebarPlanning(),
                        ),
                        FilterChip(
                          label: const Text('Módulos & Ferramentas'),
                          selected: widget.store.sidebarShowModules,
                          onSelected: (_) =>
                              widget.store.toggleSidebarModules(),
                        ),
                      ],
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 16),

            // =================================================================
            // 4. DASHBOARD & WIDGETS
            // =================================================================
            _buildSectionCard(
              colors: colors,
              title: 'Widgets do Dashboard Geral',
              icon: Icons.dashboard_customize_outlined,
              children: [
                Text(
                  'Escolha quais blocos e gráficos devem aparecer na tela inicial do Dashboard:',
                  style: TextStyle(fontSize: 12.5, color: colors.textSecondary),
                ),
                const SizedBox(height: 12),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: const Text('Patrimônio Consolidado & Gráfico Histórico'),
                  subtitle: const Text('Evolução do saldo real e previsto dos últimos meses.'),
                  value: widget.store.dashboardWidgets['patrimony'] ?? true,
                  onChanged: (v) => widget.store.setDashboardWidget('patrimony', v ?? true),
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: const Text('Contas Bancárias & Saldos'),
                  subtitle: const Text('Lista rápida de contas bancárias com ordenação direta e saldos.'),
                  value: widget.store.dashboardWidgets['accounts'] ?? true,
                  onChanged: (v) => widget.store.setDashboardWidget('accounts', v ?? true),
                ),
                if (widget.store.dashboardWidgets['accounts'] ?? true) ...[
                  Padding(
                    padding: const EdgeInsets.only(left: 28, bottom: 4),
                    child: SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      title: const Text('Exibir demais contas ativas no card', style: TextStyle(fontSize: 13)),
                      subtitle: const Text(
                        'Quando desativado, o card exibe apenas as contas marcadas como favoritas ★.',
                        style: TextStyle(fontSize: 11.5),
                      ),
                      value: widget.store.dashboardAccountsShowActive,
                      onChanged: (v) => widget.store.setDashboardAccountsShowActive(v),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(left: 28, bottom: 8),
                    child: SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      title: Text(
                        'Exibir contas com saldo ${formatCurrency(0, widget.store.baseCurrency)}',
                        style: const TextStyle(fontSize: 13),
                      ),
                      subtitle: const Text(
                        'Quando desativado, oculta do card as contas que estiverem com saldo exatamente zerado.',
                        style: TextStyle(fontSize: 11.5),
                      ),
                      value: widget.store.dashboardAccountsShowZeroBalance,
                      onChanged: (v) => widget.store.setDashboardAccountsShowZeroBalance(v),
                    ),
                  ),
                ],
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: const Text('Investimentos & Poupança'),
                  subtitle: const Text('Aplicações financeiras, investimentos e reservas de poupança.'),
                  value: widget.store.dashboardWidgets['investments'] ?? true,
                  onChanged: (v) => widget.store.setDashboardWidget('investments', v ?? true),
                ),
                if (widget.store.dashboardWidgets['investments'] ?? true) ...[
                  Padding(
                    padding: const EdgeInsets.only(left: 28, bottom: 8),
                    child: SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      title: Text(
                        'Exibir investimentos com saldo ${formatCurrency(0, widget.store.baseCurrency)}',
                        style: const TextStyle(fontSize: 13),
                      ),
                      subtitle: const Text(
                        'Quando desativado, oculta do card as contas de investimento e poupança com saldo zerado.',
                        style: TextStyle(fontSize: 11.5),
                      ),
                      value: widget.store.dashboardInvestmentsShowZeroBalance,
                      onChanged: (v) => widget.store.setDashboardInvestmentsShowZeroBalance(v),
                    ),
                  ),
                ],
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: const Text('Contas a Pagar'),
                  subtitle: const Text('Despesas e contas a pagar com botão de quitação rápida.'),
                  value: widget.store.dashboardWidgets['dueBills'] ?? true,
                  onChanged: (v) => widget.store.setDashboardWidget('dueBills', v ?? true),
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: const Text('Contas a Receber'),
                  subtitle: const Text('Receitas e valores a receber com botão de confirmação rápida.'),
                  value: widget.store.dashboardWidgets['receivables'] ?? true,
                  onChanged: (v) => widget.store.setDashboardWidget('receivables', v ?? true),
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: const Text('Faturas de Cartões de Crédito'),
                  subtitle: const Text('Barras de limite, fechamento e vencimento de cada cartão.'),
                  value: widget.store.dashboardWidgets['cards'] ?? true,
                  onChanged: (v) => widget.store.setDashboardWidget('cards', v ?? true),
                ),
                if (widget.store.dashboardWidgets['cards'] ?? true) ...[
                  Padding(
                    padding: const EdgeInsets.only(left: 28, bottom: 8),
                    child: SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      title: Text(
                        'Exibir faturas com valor zerado (${formatCurrency(0, widget.store.baseCurrency)})',
                        style: const TextStyle(fontSize: 13),
                      ),
                      subtitle: const Text(
                        'Quando desativado, oculta do card os cartões com fatura zerada no ciclo atual.',
                        style: TextStyle(fontSize: 11.5),
                      ),
                      value: widget.store.dashboardCardsShowZeroBalance,
                      onChanged: (v) => widget.store.setDashboardCardsShowZeroBalance(v),
                    ),
                  ),
                ],
                if (widget.store.isAiAssistantEnabled)
                  CheckboxListTile(
                    contentPadding: EdgeInsets.zero,
                    dense: true,
                    title: const Text('Assistente & Insights IA'),
                    subtitle: const Text(
                      'Resumo proativo de variações de categorias, recorrências detectadas e acesso rápido à Assistente IA.',
                    ),
                    value: widget.store.dashboardWidgets['aiInsights'] ?? true,
                    onChanged: (v) =>
                        widget.store.setDashboardWidget('aiInsights', v ?? true),
                  ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: const Text('Despesas por Categoria do Mês'),
                  subtitle: const Text('Gráfico Donut com distribuição proporcional dos gastos.'),
                  value: widget.store.dashboardWidgets['categories'] ?? true,
                  onChanged: (v) => widget.store.setDashboardWidget('categories', v ?? true),
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: const Text('Atalhos de Ações Rápidas'),
                  subtitle: const Text('Botões rápidos para novo lançamento, fatura e importação.'),
                  value: widget.store.dashboardWidgets['quickActions'] ?? true,
                  onChanged: (v) => widget.store.setDashboardWidget('quickActions', v ?? true),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // =================================================================
            // 5. EXTRATO & LANÇAMENTOS
            // =================================================================
            _buildSectionCard(
              colors: colors,
              title: 'Extrato & Visualização de Lançamentos',
              icon: Icons.receipt_long_outlined,
              children: [
                _buildSettingRow(
                  colors: colors,
                  title: 'Modo de Visualização Padrão',
                  subtitle:
                      'Alterne entre o extrato diário agrupado e a tabela contínua (Datagrid) com ações de hover.',
                  trailing: SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(
                        value: 'list',
                        label: Text('Lista Diária'),
                        icon: Icon(Icons.view_agenda_outlined, size: 16),
                      ),
                      ButtonSegment(
                        value: 'table',
                        label: Text('Tabela Datagrid'),
                        icon: Icon(Icons.table_chart_outlined, size: 16),
                      ),
                    ],
                    selected: {widget.store.ledgerViewMode},
                    onSelectionChanged: (set) =>
                        widget.store.setLedgerViewMode(set.first),
                  ),
                ),
                const Divider(height: 20),
                _buildSettingRow(
                  colors: colors,
                  title: 'Inserção rápida no extrato das contas',
                  subtitle:
                      'Exibe o bloco de campos inline no topo do extrato. Desative para ocultar os campos, ganhar espaço e adicionar o botão "+" no cabeçalho.',
                  trailing: Switch(
                    value: widget.store.showInlineTransactionEntry,
                    onChanged: (v) =>
                        widget.store.setShowInlineTransactionEntry(v),
                  ),
                ),
                const Divider(height: 20),
                _buildSettingRow(
                  colors: colors,
                  title: 'Preenchimento Automático por Histórico',
                  subtitle:
                      'Ao digitar o Favorecido/Descrição, sugere automaticamente os dados aprendidos de lançamentos anteriores.',
                  trailing: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                    decoration: BoxDecoration(
                      color: colors.surfaceGlass,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: colors.borderGlass),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<bool>(
                        value: widget.store.payeeSuggestionIncludeAccount,
                        dropdownColor: colors.surfaceCard,
                        style: TextStyle(fontSize: 13, color: colors.textPrimary),
                        items: const [
                          DropdownMenuItem(
                            value: false,
                            child: Text('Apenas Nome e Categoria (Padrão)'),
                          ),
                          DropdownMenuItem(
                            value: true,
                            child: Text('Nome, Categoria e Conta'),
                          ),
                        ],
                        onChanged: (v) {
                          if (v != null) {
                            widget.store.setPayeeSuggestionIncludeAccount(v);
                          }
                        },
                      ),
                    ),
                  ),
                ),
                const Divider(height: 20),
                _buildSettingRow(
                  colors: colors,
                  title: 'Período do Histórico para Sugestões',
                  subtitle:
                      'Intervalo de tempo dos lançamentos considerado para buscar sugestões de favorecidos.',
                  trailing: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                    decoration: BoxDecoration(
                      color: colors.surfaceGlass,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: colors.borderGlass),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<int>(
                        value: [30, 60, 90, 180, 365, 0].contains(widget.store.payeeSuggestionLookbackDays)
                            ? widget.store.payeeSuggestionLookbackDays
                            : 90,
                        dropdownColor: colors.surfaceCard,
                        style: TextStyle(fontSize: 13, color: colors.textPrimary),
                        items: const [
                          DropdownMenuItem(value: 30, child: Text('Últimos 30 dias')),
                          DropdownMenuItem(value: 60, child: Text('Últimos 60 dias')),
                          DropdownMenuItem(value: 90, child: Text('Últimos 90 dias (Padrão)')),
                          DropdownMenuItem(value: 180, child: Text('Últimos 6 meses')),
                          DropdownMenuItem(value: 365, child: Text('Último 1 ano')),
                          DropdownMenuItem(value: 0, child: Text('Todo o histórico')),
                        ],
                        onChanged: (v) {
                          if (v != null) {
                            widget.store.setPayeeSuggestionLookbackDays(v);
                          }
                        },
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // =================================================================
            // 6. INTELIGÊNCIA ARTIFICIAL & ASSISTENTE (MULTI-PROVEDOR)
            // =================================================================
            _buildSectionCard(
              colors: colors,
              title:
                  'Assistente Financeira & Inteligência Artificial (Gemini, Claude, ChatGPT e Siri)',
              icon: Icons.auto_awesome_outlined,
              children: [
                _buildSettingRow(
                  colors: colors,
                  title: 'Ativar Assistente Financeira com IA',
                  subtitle:
                      'Habilita lançamento por texto, leitura de documentos/faturas PDF, análise de tendências, explicação de aumentos em categorias e detecção de recorrências.',
                  trailing: Switch(
                    value: widget.store.isAiAssistantEnabled,
                    onChanged: (v) => widget.store.setAiAssistantEnabled(v),
                  ),
                ),
                if (widget.store.isAiAssistantEnabled) ...[
                  const Divider(height: 20),
                _buildSettingRow(
                  colors: colors,
                  title: 'Provedor de IA Preferido',
                  subtitle:
                      'Escolha qual inteligência artificial responderá no painel da Assistente (Cmd/Ctrl + J). Os cálculos contábeis base sempre rodam 100% localmente.',
                  trailing: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                    decoration: BoxDecoration(
                      color: colors.surfaceGlass,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: colors.borderGlass),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: AIProviderType.fromId(widget.store.aiProvider).id,
                        dropdownColor: colors.surfaceCard,
                        style: TextStyle(fontSize: 13, color: colors.textPrimary),
                        items: [
                          for (final p in AIProviderType.values)
                            if (p != AIProviderType.appleIntelligence ||
                                (!kIsWeb &&
                                    (Platform.isMacOS || Platform.isIOS)))
                              DropdownMenuItem(
                                value: p.id,
                                child: Text('${p.label} — ${p.subtitle}'),
                              ),
                        ],
                        onChanged: (v) {
                          if (v != null) {
                            widget.store.setAiAssistantConfig(
                              enabled: true,
                              provider: v,
                              consumptionMode: v == AIProviderType.bridge.id
                                  ? 'promptBridge'
                                  : (widget.store.aiConsumptionMode ==
                                          'promptBridge'
                                      ? 'byok'
                                      : widget.store.aiConsumptionMode),
                            );
                          }
                        },
                      ),
                    ),
                  ),
                ),
                const Divider(height: 20),
                _buildSettingRow(
                  colors: colors,
                  title: 'Forma de Consumo',
                  subtitle:
                      'Use sua própria chave (BYOK), a nuvem OpenMoney Cloud (quando autenticado) ou o Modo Sem Chave (copiar/colar prompt pronto no ChatGPT/Claude Web).',
                  trailing: SegmentedButton<String>(
                    segments: [
                      const ButtonSegment(
                        value: 'byok',
                        label: Text('Minha Chave'),
                        icon: Icon(Icons.key_outlined, size: 15),
                        tooltip:
                            'Usa sua própria chave de API (Gemini gratuito, Claude ou ChatGPT) conectando direto do seu dispositivo ao provedor.',
                      ),
                      if (CloudSyncService.instance.isAuthenticated)
                        const ButtonSegment(
                          value: 'cloudManaged',
                          label: Text('Nuvem Cloud'),
                          icon: Icon(Icons.cloud_outlined, size: 15),
                          tooltip:
                              'Usa a IA integrada da nuvem OpenMoney Cloud da sua conta, sem precisar criar ou configurar chaves de API externas.',
                        ),
                      const ButtonSegment(
                        value: 'promptBridge',
                        label: Text('Sem Chave'),
                        icon: Icon(Icons.copy_all_outlined, size: 15),
                        tooltip:
                            'Gera o contexto financeiro pronto para você copiar e colar gratuitamente no ChatGPT, Claude ou Gemini Web.',
                      ),
                    ],
                    selected: {
                      AIConsumptionMode.fromId(widget.store.aiConsumptionMode).id
                    },
                    onSelectionChanged: (s) {
                      final mode = s.first;
                      widget.store.setAiAssistantConfig(
                        enabled: true,
                        consumptionMode: mode,
                        provider: mode == 'promptBridge'
                            ? AIProviderType.bridge.id
                            : (widget.store.aiProvider ==
                                    AIProviderType.bridge.id
                                ? AIProviderType.openrouter.id
                                : widget.store.aiProvider),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 14),
                // Chave Google Gemini
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _geminiKeyCtrl,
                        obscureText: _obscureGeminiKey,
                        decoration: InputDecoration(
                          labelText:
                              'Chave Google Gemini API (Google AI Studio — Gratuita)',
                          hintText: 'AIzaSy...',
                          isDense: true,
                          border: const OutlineInputBorder(),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscureGeminiKey
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                              size: 18,
                            ),
                            onPressed: () {
                              setState(() {
                                _obscureGeminiKey = !_obscureGeminiKey;
                              });
                            },
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                // Chave OpenRouter.ai
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _openrouterKeyCtrl,
                        obscureText: _obscureOpenrouterKey,
                        decoration: InputDecoration(
                          labelText:
                              'Chave OpenRouter.ai API (Centenas de Modelos com 1 Chave — openrouter.ai)',
                          hintText: 'sk-or-v1-...',
                          isDense: true,
                          border: const OutlineInputBorder(),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscureOpenrouterKey
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                              size: 18,
                            ),
                            onPressed: () {
                              setState(() {
                                _obscureOpenrouterKey = !_obscureOpenrouterKey;
                              });
                            },
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                // Chave Anthropic Claude
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _claudeKeyCtrl,
                        obscureText: _obscureClaudeKey,
                        decoration: InputDecoration(
                          labelText:
                              'Chave Anthropic Claude API (Console Anthropic — Opcional)',
                          hintText: 'sk-ant-...',
                          isDense: true,
                          border: const OutlineInputBorder(),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscureClaudeKey
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                              size: 18,
                            ),
                            onPressed: () {
                              setState(() {
                                _obscureClaudeKey = !_obscureClaudeKey;
                              });
                            },
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                // Chave OpenAI ChatGPT
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _openaiKeyCtrl,
                        obscureText: _obscureOpenaiKey,
                        decoration: InputDecoration(
                          labelText:
                              'Chave OpenAI ChatGPT API (Platform OpenAI — Opcional)',
                          hintText: 'sk-proj-...',
                          isDense: true,
                          border: const OutlineInputBorder(),
                          suffixIcon: IconButton(
                            icon: Icon(
                              _obscureOpenaiKey
                                  ? Icons.visibility_outlined
                                  : Icons.visibility_off_outlined,
                              size: 18,
                            ),
                            onPressed: () {
                              setState(() {
                                _obscureOpenaiKey = !_obscureOpenaiKey;
                              });
                            },
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    FilledButton.icon(
                      icon: const Icon(Icons.save_outlined, size: 16),
                      label: const Text('Salvar Chaves de IA'),
                      onPressed: () {
                        widget.store.setAiAssistantConfig(
                          enabled: true,
                          geminiKey: _geminiKeyCtrl.text.trim(),
                          openrouterKey: _openrouterKeyCtrl.text.trim(),
                          claudeKey: _claudeKeyCtrl.text.trim(),
                          openaiKey: _openaiKeyCtrl.text.trim(),
                        );
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              'Configurações e chaves de IA salvas localmente com segurança!',
                            ),
                            duration: Duration(seconds: 2),
                          ),
                        );
                      },
                    ),
                    OutlinedButton.icon(
                      icon: _isTestingAi
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.bolt_outlined, size: 16),
                       label: const Text('Testar Conexão'),
                      onPressed: _isTestingAi
                          ? null
                          : () async {
                              setState(() {
                                _isTestingAi = true;
                                _aiTestStatusMessage =
                                    'Validando conexão com o provedor selecionado...';
                              });
                              final prov =
                                  AIProviderType.fromId(widget.store.aiProvider);
                              final key = prov == AIProviderType.openrouter
                                  ? _openrouterKeyCtrl.text.trim()
                                  : prov == AIProviderType.claude
                                      ? _claudeKeyCtrl.text.trim()
                                      : prov == AIProviderType.openai
                                          ? _openaiKeyCtrl.text.trim()
                                          : _geminiKeyCtrl.text.trim();
                              final res = await AIAssistantService.instance
                                  .testProviderConnection(
                                provider: prov,
                                apiKey: key,
                                useCloudManaged:
                                    widget.store.aiConsumptionMode ==
                                        'cloudManaged',
                              );
                              if (!mounted) return;
                              setState(() {
                                _isTestingAi = false;
                                _aiTestStatusMessage =
                                    '${res.ok ? "✅" : "⚠️"} ${res.message}';
                              });
                            },
                    ),
                  ],
                ),
                if (_aiTestStatusMessage.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text(
                    _aiTestStatusMessage,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: colors.textPrimary,
                    ),
                  ),
                ],
                const Divider(height: 22),
                _buildSettingRow(
                  colors: colors,
                  title: 'Siri IA, Spotlight & Atalhos (macOS / iOS / Web)',
                  subtitle:
                      'Você pode acionar a Assistente por voz via Siri/Atalhos da Apple abrindo a URL "openmoney://?prompt=Seu+Comando" ou "https://openmoney.app.br/?prompt=Seu+Comando".',
                  trailing: Icon(
                    Icons.mic_none_rounded,
                    color: colors.accent,
                    size: 20,
                  ),
                ),
                const Divider(height: 22),
                _buildSettingRow(
                  colors: colors,
                  title: 'Servidor MCP & Acesso Externo',
                  subtitle:
                      'Permite que ferramentas externas de IA consultem seus saldos, transações e fluxo de caixa ou criem lançamentos via Model Context Protocol.',
                  trailing: OutlinedButton.icon(
                    icon: const Icon(Icons.hub_outlined, size: 16),
                    label: const Text('Configurar MCP'),
                    onPressed: () => showMcpTokensModal(context, widget.store),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 16),

          // =================================================================
          // 7. MOEDAS & COTAÇÕES
          // =================================================================
          _buildSectionCard(
            colors: colors,
            title: 'Moedas & Cotações',
              icon: Icons.currency_exchange_outlined,
              children: [
                _buildSettingRow(
                  colors: colors,
                  title: 'Moeda Padrão / Base do Sistema',
                  subtitle:
                      'Moeda principal utilizada na consolidação do patrimônio, relatórios e dashboards.',
                  trailing: SizedBox(
                    width: 210,
                    child: DropdownButtonFormField<String>(
                      initialValue: kSupportedCurrencies
                              .any((c) => c.code == widget.store.baseCurrency)
                          ? widget.store.baseCurrency
                          : 'BRL',
                      isDense: true,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        contentPadding:
                            EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      ),
                      items: kSupportedCurrencies
                          .map((c) => DropdownMenuItem(
                                value: c.code,
                                child: Text(
                                  '${c.flag} ${c.code} - ${c.name}',
                                  style: const TextStyle(fontSize: 12.5),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ))
                          .toList(),
                      onChanged: (val) {
                        if (val != null) {
                          widget.store.setBaseCurrency(val);
                        }
                      },
                    ),
                  ),
                ),
                const Divider(height: 20),
                _buildSettingRow(
                  colors: colors,
                  title: 'Cotações Online (AwesomeAPI)',
                  subtitle:
                      'Consultadas automaticamente 1x ao dia quando há contas em moeda estrangeira. Taxas manuais são preservadas.',
                  trailing: FilledButton.tonalIcon(
                    icon: widget.store.isRefreshingRates
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.sync, size: 16),
                    label: Text(
                      widget.store.isRefreshingRates
                          ? 'Atualizando...'
                          : 'Atualizar Agora',
                      style: const TextStyle(fontSize: 12),
                    ),
                    onPressed: widget.store.isRefreshingRates
                        ? null
                        : () async {
                            final ok = await widget.store
                                .refreshOnlineRates(force: true);
                            if (!context.mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  ok
                                      ? 'Cotações atualizadas com sucesso!'
                                      : 'Nenhuma atualização pendente ou sem conexão.',
                                ),
                                duration: const Duration(seconds: 3),
                              ),
                            );
                          },
                  ),
                ),
                if (widget.store.countPastForeignTransactionsForRateSync() >
                    0) ...[
                  const Divider(height: 20),
                  _buildSettingRow(
                    colors: colors,
                    title: 'Cotações Históricas (Lançamentos Passados)',
                    subtitle:
                        'Aplica a taxa da transferência cambial da época ou consulta o histórico BCB PTAX/AwesomeAPI para receitas e despesas passadas.',
                    trailing: FilledButton.tonalIcon(
                      icon: _isRecalculatingHistory
                          ? const SizedBox(
                              width: 14,
                              height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.history, size: 16),
                      label: Text(
                        _isRecalculatingHistory
                            ? 'Recalculando...'
                            : 'Corrigir Passados (${widget.store.countPastForeignTransactionsForRateSync()})',
                        style: const TextStyle(fontSize: 12),
                      ),
                      onPressed: _isRecalculatingHistory
                          ? null
                          : () => _confirmAndRecalculateHistory(context),
                    ),
                  ),
                ],
                const SizedBox(height: 10),
                Container(
                  decoration: BoxDecoration(
                    color: colors.surfaceGlass,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: colors.borderGlass),
                  ),
                  child: Column(
                    children: [
                      for (int i = 0;
                          i <
                              kSupportedCurrencies
                                  .where((c) => c.code != 'BRL')
                                  .length;
                          i++) ...[
                        Builder(builder: (context) {
                          final foreignCurrencies = kSupportedCurrencies
                              .where((c) => c.code != 'BRL')
                              .toList();
                          final cur = foreignCurrencies[i];
                          final info = widget.store.rateInfoFor(cur.code);
                          final rateVal = info?.rate ??
                              kFallbackRatesBrl[cur.code] ??
                              1.0;
                          final isManual = info?.manual ?? false;
                          final dateLabel =
                              info != null && info.updatedAt.isNotEmpty
                                  ? formatRateDate(info.updatedAt)
                                  : 'Estimada';

                          return Column(
                            children: [
                              if (i > 0)
                                Divider(
                                    height: 1,
                                    color: colors.borderGlass
                                        .withValues(alpha: 0.5)),
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 8),
                                child: Row(
                                  children: [
                                    Text(cur.flag,
                                        style: const TextStyle(fontSize: 18)),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            '${cur.code} · ${cur.name}',
                                            style: TextStyle(
                                              fontSize: 12.5,
                                              fontWeight: FontWeight.w600,
                                              color: colors.textPrimary,
                                            ),
                                          ),
                                          Text(
                                            '${isManual ? "Manual" : (info?.source ?? "Padrão")} · $dateLabel',
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: colors.textMuted,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Text(
                                      'R\$ ${rateVal.toStringAsFixed(cur.decimals == 0 ? 6 : 4).replaceAll('.', ',')}',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w700,
                                        color: colors.textPrimary,
                                        fontFeatures: const [
                                          FontFeature.tabularFigures()
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    if (isManual)
                                      IconButton(
                                        tooltip:
                                            'Voltar para cotação automática',
                                        icon: const Icon(Icons.autorenew,
                                            size: 16),
                                        visualDensity: VisualDensity.compact,
                                        onPressed: () => widget.store
                                            .setCurrencyRateAuto(cur.code),
                                      ),
                                    IconButton(
                                      tooltip: 'Definir cotação manual',
                                      icon: const Icon(Icons.edit_outlined,
                                          size: 16),
                                      visualDensity: VisualDensity.compact,
                                      onPressed: () =>
                                          _showManualRateDialog(cur, rateVal),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          );
                        }),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // =================================================================
            // 8. GUIA DE ATALHOS DE TECLADO
            // =================================================================
            _buildSectionCard(
              colors: colors,
              title: 'Atalhos Rápidos de Teclado',
              icon: Icons.keyboard_outlined,
              children: [
                if (widget.store.isAiAssistantEnabled)
                  _buildShortcutRow(colors, 'Cmd / Ctrl + J',
                      'Abrir / Fechar Assistente Financeira IA'),
                _buildShortcutRow(colors, 'Cmd / Ctrl + K',
                    'Abrir Command Palette (Busca e Comandos)'),
                _buildShortcutRow(colors, 'Cmd / Ctrl + ,',
                    'Abrir esta tela de Ajustes & Personalização'),
                _buildShortcutRow(colors, 'Cmd / Ctrl + B',
                    'Alternar Barra Lateral (Expandida / Mini / Oculta)'),
                _buildShortcutRow(
                    colors, 'Cmd / Ctrl + D', 'Alternar Modo Escuro / Claro'),
                _buildShortcutRow(
                    colors, 'Cmd / Ctrl + F', 'Ir para Pesquisa Global'),
                _buildShortcutRow(
                    colors, 'F1', 'Abrir Ajuda e Manual do Usuário'),
              ],
            ),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionCard({
    required OpenMoneyColors colors,
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    return GlassCard(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: colors.accent, size: 20),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: colors.textPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ...children,
        ],
      ),
    );
  }

  Future<void> _confirmAndRecalculateHistory(BuildContext context) async {
    final total = widget.store.countPastForeignTransactionsForRateSync();
    if (total == 0) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Recalcular Cotações Históricas'),
        content: Text(
          'Foram encontrados $total lançamento(s) passado(s) em contas de moeda estrangeira.\n\n'
          'O OpenMoney irá aplicar automaticamente:\n'
          '1) A taxa da última transferência cambial na conta até a data de cada lançamento (se existir);\n'
          '2) A cotação oficial da data no Banco Central (PTAX) ou AwesomeAPI.\n\n'
          'Transferências entre contas nunca são alteradas. Deseja continuar?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Recalcular'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _isRecalculatingHistory = true);
    try {
      final res = await widget.store.recalculatePastTransactionRates();
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            res.updated > 0
                ? '${res.updated} lançamento(s) atualizado(s) (${res.fromTransfer} via transferência, ${res.fromApi} via BCB/API).'
                : 'Nenhuma alteração necessária (${res.totalScanned} analisado(s)).',
          ),
          duration: const Duration(seconds: 4),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isRecalculatingHistory = false);
      }
    }
  }

  Widget _buildSettingRow({
    required OpenMoneyColors colors,
    required String title,
    required String subtitle,
    required Widget trailing,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 580;
        if (isNarrow) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 14,
                  color: colors.textPrimary,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 12,
                  color: colors.textSecondary,
                ),
              ),
              const SizedBox(height: 10),
              trailing,
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 14,
                      color: colors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: colors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            trailing,
          ],
        );
      },
    );
  }

  Future<void> _showManualRateDialog(CurrencyMeta cur, double currentRate) async {
    final ctrl = TextEditingController(
      text: currentRate
          .toStringAsFixed(cur.decimals == 0 ? 6 : 4)
          .replaceAll('.', ','),
    );
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Cotação Manual: ${cur.flag} ${cur.code}'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Informe quanto vale 1 ${cur.code} em Reais (BRL).\nEsta taxa ficará fixa até você restaurar para o modo automático.',
              style: const TextStyle(fontSize: 12.5),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              autofocus: true,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(
                labelText: '1 ${cur.code} em BRL (R\$)',
                prefixText: 'R\$ ',
                border: const OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              final raw = ctrl.text.trim().replaceAll(' ', '');
              final norm = raw.contains(',')
                  ? raw.replaceAll('.', '').replaceAll(',', '.')
                  : raw;
              final parsed = double.tryParse(norm);
              if (parsed != null && parsed > 0) {
                widget.store.updateCurrencyRate(cur.code, parsed, manual: true);
                Navigator.pop(ctx);
              }
            },
            child: const Text('Salvar Taxa'),
          ),
        ],
      ),
    );
    ctrl.dispose();
  }

  Widget _buildShortcutRow(
      OpenMoneyColors colors, String shortcut, String description) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            description,
            style: TextStyle(fontSize: 13, color: colors.textSecondary),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: colors.surfaceGlass,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: colors.borderGlass),
            ),
            child: Text(
              shortcut,
              style: TextStyle(
                fontFamily: 'monospace',
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: colors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
