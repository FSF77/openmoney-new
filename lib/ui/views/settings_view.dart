import 'package:flutter/material.dart';
import '../../store/money_store.dart';
import '../theme/liquid_glass.dart';

class SettingsView extends StatefulWidget {
  final MoneyStore store;
  const SettingsView({super.key, required this.store});

  @override
  State<SettingsView> createState() => _SettingsViewState();
}

class _SettingsViewState extends State<SettingsView> {
  late TextEditingController _geminiKeyCtrl;
  bool _obscureGeminiKey = true;

  @override
  void initState() {
    super.initState();
    _geminiKeyCtrl = TextEditingController(text: widget.store.geminiApiKey);
  }

  @override
  void dispose() {
    _geminiKeyCtrl.dispose();
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
                        icon: Icon(Icons.dashboard_outlined, size: 16),
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
                      title: const Text('Exibir contas com saldo R\$ 0,00', style: TextStyle(fontSize: 13)),
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
                  title: const Text('Radar de Vencimentos Próximos'),
                  subtitle: const Text('Contas e faturas a pagar com botão de quitação rápida.'),
                  value: widget.store.dashboardWidgets['dueBills'] ?? true,
                  onChanged: (v) => widget.store.setDashboardWidget('dueBills', v ?? true),
                ),
                CheckboxListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  title: const Text('Faturas de Cartões de Crédito'),
                  subtitle: const Text('Barras de limite, fechamento e vencimento de cada cartão.'),
                  value: widget.store.dashboardWidgets['cards'] ?? true,
                  onChanged: (v) => widget.store.setDashboardWidget('cards', v ?? true),
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
              ],
            ),
            const SizedBox(height: 16),

            // =================================================================
            // 6. INTELIGÊNCIA ARTIFICIAL (GEMINI BYOK)
            // =================================================================
            _buildSectionCard(
              colors: colors,
              title: 'Inteligência Artificial (Google Gemini BYOK)',
              icon: Icons.psychology_outlined,
              children: [
                _buildSettingRow(
                  colors: colors,
                  title: 'Assistente de Comprovantes com IA',
                  subtitle:
                      'Permite extrair favorecido, data, valor e categoria automaticamente de fotos e PDFs de comprovantes.',
                  trailing: Switch(
                    value: widget.store.isGeminiAiEnabled,
                    onChanged: (v) => widget.store.setGeminiAiEnabled(v),
                  ),
                ),
                if (widget.store.isGeminiAiEnabled) ...[
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _geminiKeyCtrl,
                          obscureText: _obscureGeminiKey,
                          decoration: InputDecoration(
                            labelText: 'Chave Gemini API (Google AI Studio)',
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
                      const SizedBox(width: 8),
                      FilledButton(
                        onPressed: () {
                          widget.store.setGeminiApiKey(_geminiKeyCtrl.text.trim());
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('Chave Gemini API salva com sucesso!'),
                              duration: Duration(seconds: 2),
                            ),
                          );
                        },
                        child: const Text('Salvar Chave'),
                      ),
                    ],
                  ),
                ],
              ],
            ),
            const SizedBox(height: 16),

            // =================================================================
            // 7. GUIA DE ATALHOS DE TECLADO
            // =================================================================
            _buildSectionCard(
              colors: colors,
              title: 'Atalhos Rápidos de Teclado',
              icon: Icons.keyboard_outlined,
              children: [
                _buildShortcutRow(colors, 'Cmd / Ctrl + K', 'Abrir Command Palette (Busca e Comandos)'),
                _buildShortcutRow(colors, 'Cmd / Ctrl + ,', 'Abrir esta tela de Ajustes & Personalização'),
                _buildShortcutRow(colors, 'Cmd / Ctrl + B', 'Alternar Barra Lateral (Expandida / Mini / Oculta)'),
                _buildShortcutRow(colors, 'Cmd / Ctrl + D', 'Alternar Modo Escuro / Claro'),
                _buildShortcutRow(colors, 'Cmd / Ctrl + F', 'Ir para Pesquisa Global'),
                _buildShortcutRow(colors, 'F1', 'Abrir Ajuda e Manual do Usuário'),
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
