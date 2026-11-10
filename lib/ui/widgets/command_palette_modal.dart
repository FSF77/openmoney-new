import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/openmoney_models.dart';
import '../../store/money_store.dart';
import '../modals/transaction_modal.dart';
import '../theme/liquid_glass.dart';

class _CommandItem {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color? iconColor;
  final String category;
  final VoidCallback onSelect;

  _CommandItem({
    required this.title,
    required this.subtitle,
    required this.icon,
    this.iconColor,
    required this.category,
    required this.onSelect,
  });
}

Future<void> showCommandPaletteModal(
    BuildContext context, MoneyStore store) async {
  await showDialog(
    context: context,
    barrierColor: Colors.black.withValues(alpha: 0.55),
    builder: (ctx) => _CommandPaletteDialog(store: store),
  );
}

class _CommandPaletteDialog extends StatefulWidget {
  final MoneyStore store;
  const _CommandPaletteDialog({required this.store});

  @override
  State<_CommandPaletteDialog> createState() => _CommandPaletteDialogState();
}

class _CommandPaletteDialogState extends State<_CommandPaletteDialog> {
  final TextEditingController _searchCtrl = TextEditingController();
  final FocusNode _focusNode = FocusNode();
  int _selectedIndex = 0;

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(() {
      setState(() {
        _selectedIndex = 0;
      });
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  List<_CommandItem> _buildAllCommands(OpenMoneyColors colors) {
    final list = <_CommandItem>[];

    // Ações Rápidas
    list.add(_CommandItem(
      title: 'Novo Lançamento',
      subtitle: 'Criar uma nova receita, despesa ou transferência',
      icon: Icons.add_circle,
      iconColor: colors.accent,
      category: 'AÇÕES RÁPIDAS',
      onSelect: () {
        Navigator.of(context).pop();
        showTransactionCreateModal(context, widget.store);
      },
    ));
    list.add(_CommandItem(
      title: 'Ajustes & Personalização',
      subtitle: 'Configurar cores, densidade, layout e widgets',
      icon: Icons.settings,
      iconColor: colors.textSecondary,
      category: 'AÇÕES RÁPIDAS',
      onSelect: () {
        Navigator.of(context).pop();
        widget.store.navigateTo(NavModule.settings);
      },
    ));
    list.add(_CommandItem(
      title: 'Alternar Tema Claro / Escuro',
      subtitle: 'Trocar entre modo escuro e claro',
      icon: widget.store.isDarkMode
          ? Icons.light_mode_outlined
          : Icons.dark_mode_outlined,
      iconColor: Colors.amber,
      category: 'AÇÕES RÁPIDAS',
      onSelect: () {
        Navigator.of(context).pop();
        widget.store.toggleThemeMode();
      },
    ));

    // Módulos
    list.add(_CommandItem(
      title: 'Dashboard Geral (Cockpit)',
      subtitle: 'Visão executiva com KPIs e widgets consolidados',
      icon: Icons.dashboard,
      category: 'MÓDULOS DO SISTEMA',
      onSelect: () {
        Navigator.of(context).pop();
        widget.store.navigateTo(NavModule.dashboard);
      },
    ));
    list.add(_CommandItem(
      title: 'Lançamentos Consolidados',
      subtitle: 'Visualizar todas as transações de todas as contas',
      icon: Icons.receipt_long_outlined,
      category: 'MÓDULOS DO SISTEMA',
      onSelect: () {
        Navigator.of(context).pop();
        widget.store.navigateTo(NavModule.transactions);
      },
    ));
    list.add(_CommandItem(
      title: 'Contas a Pagar & Receber',
      subtitle: 'Vencimentos próximos e conciliação de faturas',
      icon: Icons.notifications_active_outlined,
      category: 'MÓDULOS DO SISTEMA',
      onSelect: () {
        Navigator.of(context).pop();
        widget.store.navigateTo(NavModule.dueBills);
      },
    ));
    list.add(_CommandItem(
      title: 'Compras Parceladas',
      subtitle: 'Acompanhar carnês e parcelamentos de cartão',
      icon: Icons.credit_score,
      category: 'MÓDULOS DO SISTEMA',
      onSelect: () {
        Navigator.of(context).pop();
        widget.store.navigateTo(NavModule.installments);
      },
    ));
    list.add(_CommandItem(
      title: 'Fluxo de Caixa',
      subtitle: 'Matriz temporal de receitas e despesas por período',
      icon: Icons.grid_on_rounded,
      category: 'MÓDULOS DO SISTEMA',
      onSelect: () {
        Navigator.of(context).pop();
        widget.store.navigateTo(NavModule.cashFlow);
      },
    ));
    list.add(_CommandItem(
      title: 'Relatórios Financeiros',
      subtitle: 'Gráficos e demonstrativos de evolução',
      icon: Icons.pie_chart_outline,
      category: 'MÓDULOS DO SISTEMA',
      onSelect: () {
        Navigator.of(context).pop();
        widget.store.navigateTo(NavModule.reports);
      },
    ));
    list.add(_CommandItem(
      title: 'Limite de Gastos',
      subtitle: 'Metas e tetos orçamentários por categoria',
      icon: Icons.track_changes,
      category: 'MÓDULOS DO SISTEMA',
      onSelect: () {
        Navigator.of(context).pop();
        widget.store.navigateTo(NavModule.budget);
      },
    ));
    list.add(_CommandItem(
      title: 'Categorias e Subcategorias',
      subtitle: 'Gerenciar plano de contas e grupos',
      icon: Icons.category_outlined,
      category: 'MÓDULOS DO SISTEMA',
      onSelect: () {
        Navigator.of(context).pop();
        widget.store.navigateTo(NavModule.categories);
      },
    ));
    list.add(_CommandItem(
      title: 'Pesquisa Global',
      subtitle: 'Buscar lançamentos em todo o histórico',
      icon: Icons.manage_search,
      category: 'MÓDULOS DO SISTEMA',
      onSelect: () {
        Navigator.of(context).pop();
        widget.store.navigateTo(NavModule.search);
      },
    ));

    // Contas
    for (final acc in widget.store.db.accounts.where((a) => !a.isInactive)) {
      final bal = widget.store.balance(acc, predicted: false);
      list.add(_CommandItem(
        title: acc.name,
        subtitle: '${acc.type} • Saldo Real: ${brl(bal)}',
        icon: acc.type == kCardType
            ? Icons.credit_card
            : Icons.account_balance_wallet_outlined,
        category: 'CONTAS BANCÁRIAS',
        onSelect: () {
          Navigator.of(context).pop();
          widget.store.navigateTo(NavModule.account, accountId: acc.id);
        },
      ));
    }

    // Se houver busca digitada, também pesquisa lançamentos recentes
    final query = _searchCtrl.text.trim().toLowerCase();
    if (query.isNotEmpty) {
      int count = 0;
      for (final tx in widget.store.db.txs.reversed) {
        if (count >= 5) break;
        if (tx.payee.toLowerCase().contains(query) ||
            tx.cat.toLowerCase().contains(query) ||
            tx.memo.toLowerCase().contains(query)) {
          final accName = widget.store.accById(tx.acc)?.name ?? 'Conta';
          list.add(_CommandItem(
            title: '${tx.payee} (${brl(tx.amt)})',
            subtitle: '${fmtDate(tx.date)} • $accName • ${tx.cat}',
            icon: tx.amt >= 0 ? Icons.trending_up : Icons.trending_down,
            iconColor: tx.amt >= 0 ? colors.income : colors.expense,
            category: 'LANÇAMENTOS ENCONTRADOS',
            onSelect: () {
              Navigator.of(context).pop();
              widget.store.navigateTo(NavModule.account, accountId: tx.acc);
              widget.store.highlightedTxId = tx.id;
            },
          ));
          count++;
        }
      }
    }

    return list;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colors = OpenMoneyColors(isDark);
    final allCommands = _buildAllCommands(colors);

    final query = _searchCtrl.text.trim().toLowerCase();
    final filtered = query.isEmpty
        ? allCommands
        : allCommands.where((cmd) {
            return cmd.title.toLowerCase().contains(query) ||
                cmd.subtitle.toLowerCase().contains(query) ||
                cmd.category.toLowerCase().contains(query);
          }).toList();

    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      child: Focus(
        autofocus: true,
        onKeyEvent: (node, event) {
          if (event is KeyDownEvent) {
            if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
              setState(() {
                if (_selectedIndex < filtered.length - 1) {
                  _selectedIndex++;
                }
              });
              return KeyEventResult.handled;
            } else if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
              setState(() {
                if (_selectedIndex > 0) {
                  _selectedIndex--;
                }
              });
              return KeyEventResult.handled;
            } else if (event.logicalKey == LogicalKeyboardKey.enter) {
              if (filtered.isNotEmpty && _selectedIndex < filtered.length) {
                filtered[_selectedIndex].onSelect();
                return KeyEventResult.handled;
              }
            } else if (event.logicalKey == LogicalKeyboardKey.escape) {
              Navigator.of(context).pop();
              return KeyEventResult.handled;
            }
          }
          return KeyEventResult.ignored;
        },
        child: Container(
          width: 620,
          constraints: const BoxConstraints(maxHeight: 520),
          decoration: BoxDecoration(
            color: colors.surfaceCard,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: colors.borderGlass, width: 1.2),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.45 : 0.15),
                blurRadius: 28,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Barra de Busca do Spotlight
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: colors.bgSecondary,
                    border: Border(
                      bottom: BorderSide(color: colors.borderGlass),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.search, size: 22, color: colors.accent),
                      const SizedBox(width: 12),
                      Expanded(
                        child: TextField(
                          controller: _searchCtrl,
                          focusNode: _focusNode,
                          autofocus: true,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: colors.textPrimary,
                          ),
                          decoration: InputDecoration(
                            hintText:
                                'Buscar conta, módulo, lançamento ou atalho...',
                            hintStyle: TextStyle(
                              fontSize: 15,
                              color: colors.textMuted,
                            ),
                            border: InputBorder.none,
                            isDense: true,
                            contentPadding: EdgeInsets.zero,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: colors.surfaceGlass,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: colors.borderGlass),
                        ),
                        child: Text(
                          'ESC',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                            color: colors.textSecondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // Lista de Resultados
                Flexible(
                  child: filtered.isEmpty
                      ? Padding(
                          padding: const EdgeInsets.symmetric(vertical: 40),
                          child: Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.search_off,
                                    size: 36, color: colors.textMuted),
                                const SizedBox(height: 8),
                                Text(
                                  'Nenhum comando ou lançamento encontrado.',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: colors.textSecondary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          itemCount: filtered.length,
                          itemBuilder: (context, index) {
                            final item = filtered[index];
                            final isSelected = index == _selectedIndex;

                            return InkWell(
                              onTap: item.onSelect,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 10,
                                ),
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? colors.accent.withValues(alpha: 0.16)
                                      : Colors.transparent,
                                  border: Border(
                                    left: BorderSide(
                                      color: isSelected
                                          ? colors.accent
                                          : Colors.transparent,
                                      width: 3,
                                    ),
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.all(7),
                                      decoration: BoxDecoration(
                                        color: (item.iconColor ?? colors.accent)
                                            .withValues(alpha: 0.12),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Icon(
                                        item.icon,
                                        size: 18,
                                        color: item.iconColor ?? colors.accent,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            item.title,
                                            style: TextStyle(
                                              fontSize: 13.5,
                                              fontWeight: isSelected
                                                  ? FontWeight.w800
                                                  : FontWeight.w600,
                                              color: colors.textPrimary,
                                            ),
                                          ),
                                          const SizedBox(height: 1),
                                          Text(
                                            item.subtitle,
                                            style: TextStyle(
                                              fontSize: 11.5,
                                              color: colors.textSecondary,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ],
                                      ),
                                    ),
                                    Text(
                                      item.category,
                                      style: TextStyle(
                                        fontSize: 9.5,
                                        fontWeight: FontWeight.w800,
                                        color: colors.textMuted,
                                        letterSpacing: 0.5,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),

                // Rodapé com dicas de atalho
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: colors.bgSecondary,
                    border: Border(
                      top: BorderSide(color: colors.borderGlass),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.keyboard_return,
                              size: 14, color: colors.textMuted),
                          const SizedBox(width: 4),
                          Text(
                            'Enter para selecionar',
                            style: TextStyle(
                                fontSize: 11, color: colors.textMuted),
                          ),
                          const SizedBox(width: 14),
                          Icon(Icons.swap_vert,
                              size: 14, color: colors.textMuted),
                          const SizedBox(width: 4),
                          Text(
                            'Setas para navegar',
                            style: TextStyle(
                                fontSize: 11, color: colors.textMuted),
                          ),
                        ],
                      ),
                      Text(
                        'OpenMoney Spotlight',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: colors.textMuted,
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
  }
}
