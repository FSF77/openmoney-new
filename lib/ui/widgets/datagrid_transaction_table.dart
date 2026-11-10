import 'package:flutter/material.dart';
import '../../models/openmoney_models.dart';
import '../../services/bank_logo_registry.dart';
import '../../store/money_store.dart';
import '../modals/transaction_modal.dart';
import '../theme/liquid_glass.dart';

class DatagridTransactionTable extends StatefulWidget {
  final List<Transaction> transactions;
  final MoneyStore store;
  final bool showAccountColumn;

  const DatagridTransactionTable({
    super.key,
    required this.transactions,
    required this.store,
    this.showAccountColumn = false,
  });

  @override
  State<DatagridTransactionTable> createState() =>
      _DatagridTransactionTableState();
}

enum _SortField { date, payee, category, amount }

class _DatagridTransactionTableState extends State<DatagridTransactionTable> {
  _SortField _sortField = _SortField.date;
  bool _sortAscending = false;
  String? _hoveredTxId;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colors = OpenMoneyColors(isDark);
    final isCompact = widget.store.uiDensityMode == 'compact';
    final rowHeight = isCompact ? 34.0 : 42.0;

    final sortedList = List<Transaction>.from(widget.transactions);
    sortedList.sort((a, b) {
      int cmp = 0;
      switch (_sortField) {
        case _SortField.date:
          cmp = a.date.compareTo(b.date);
          break;
        case _SortField.payee:
          cmp = a.payee.toLowerCase().compareTo(b.payee.toLowerCase());
          break;
        case _SortField.category:
          cmp = a.cat.toLowerCase().compareTo(b.cat.toLowerCase());
          break;
        case _SortField.amount:
          cmp = a.amt.compareTo(b.amt);
          break;
      }
      return _sortAscending ? cmp : -cmp;
    });

    return Container(
      decoration: BoxDecoration(
        color: colors.surfaceCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.borderGlass),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Column(
          children: [
            // Cabeçalho da Tabela
            Container(
              height: 38,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: colors.bgSecondary,
                border: Border(bottom: BorderSide(color: colors.borderGlass)),
              ),
              child: Row(
                children: [
                  // Coluna Status / Rec
                  SizedBox(
                    width: 32,
                    child: Center(
                      child: Icon(Icons.check, size: 14, color: colors.textMuted),
                    ),
                  ),
                  const SizedBox(width: 8),

                  // Coluna Data
                  _buildHeaderColumn(
                    title: 'Data',
                    field: _SortField.date,
                    width: 90,
                    colors: colors,
                  ),

                  // Coluna Conta (Opcional - posicionada após Data e antes de Favorecido)
                  if (widget.showAccountColumn) ...[
                    const SizedBox(width: 8),
                    Expanded(
                      flex: 2,
                      child: Text(
                        'Conta',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w700,
                          color: colors.textMuted,
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(width: 8),

                  // Coluna Favorecido
                  Expanded(
                    flex: 4,
                    child: _buildHeaderColumn(
                      title: 'Favorecido / Descrição',
                      field: _SortField.payee,
                      colors: colors,
                    ),
                  ),
                  const SizedBox(width: 8),

                  // Coluna Categoria
                  Expanded(
                    flex: 3,
                    child: _buildHeaderColumn(
                      title: 'Categoria',
                      field: _SortField.category,
                      colors: colors,
                    ),
                  ),
                  const SizedBox(width: 8),

                  // Coluna Valor
                  SizedBox(
                    width: 120,
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: _buildHeaderColumn(
                        title: 'Valor',
                        field: _SortField.amount,
                        colors: colors,
                        alignRight: true,
                      ),
                    ),
                  ),

                  // Espaço para as Ações Rápidas de Hover
                  const SizedBox(width: 90),
                ],
              ),
            ),

            // Linhas da Tabela
            if (sortedList.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 40),
                child: Center(
                  child: Text(
                    'Nenhum lançamento encontrado nesta competência.',
                    style: TextStyle(color: colors.textSecondary, fontSize: 13),
                  ),
                ),
              )
            else
              ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: sortedList.length,
                itemBuilder: (context, index) {
                  final tx = sortedList[index];
                  final isHovered = _hoveredTxId == tx.id;
                  final isHighlighted = widget.store.highlightedTxId == tx.id;
                  final isEven = index % 2 == 0;

                  final acc = widget.store.accById(tx.acc);
                  final accName = acc?.name ?? 'Conta';

                  return MouseRegion(
                    onEnter: (_) => setState(() => _hoveredTxId = tx.id),
                    onExit: (_) => setState(() => _hoveredTxId = null),
                    child: InkWell(
                      onTap: () => showTransactionEditModal(
                        context,
                        widget.store,
                        tx,
                      ),
                      child: Container(
                        height: rowHeight,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        decoration: BoxDecoration(
                          color: isHighlighted
                              ? colors.accent.withValues(alpha: 0.22)
                              : (isHovered
                                  ? colors.accent.withValues(alpha: 0.08)
                                  : (isEven
                                      ? Colors.transparent
                                      : colors.surfaceGlass
                                          .withValues(alpha: 0.3))),
                          border: Border(
                            bottom: BorderSide(
                              color: colors.borderGlass.withValues(alpha: 0.35),
                            ),
                          ),
                        ),
                        child: Row(
                          children: [
                            // Botão Conciliar (Rec)
                            SizedBox(
                              width: 32,
                              child: IconButton(
                                visualDensity: VisualDensity.compact,
                                padding: EdgeInsets.zero,
                                tooltip: tx.rec
                                    ? 'Conciliado (Clique para desmarcar)'
                                    : 'Pendente (Clique para conciliar)',
                                icon: Icon(
                                  tx.rec
                                      ? Icons.check_circle
                                      : Icons.radio_button_unchecked,
                                  color: tx.rec
                                      ? colors.income
                                      : colors.textMuted,
                                  size: 17,
                                ),
                                onPressed: () =>
                                    widget.store.toggleReconciled(tx.id),
                              ),
                            ),
                            const SizedBox(width: 8),

                            // Data
                            SizedBox(
                              width: 90,
                              child: Text(
                                fmtDate(tx.date),
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: colors.textSecondary,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures()
                                  ],
                                ),
                              ),
                            ),

                            // Conta (Opcional - posicionada após Data e antes de Favorecido com ícone da conta)
                            if (widget.showAccountColumn) ...[
                              const SizedBox(width: 8),
                              Expanded(
                                flex: 2,
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (acc != null) ...[
                                      AccountLogoWidget(
                                        account: acc,
                                        size: 16,
                                        cornerRadius: 4,
                                      ),
                                      const SizedBox(width: 6),
                                    ],
                                    Flexible(
                                      child: Text(
                                        accName,
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w600,
                                          color: colors.accent,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                            const SizedBox(width: 8),

                            // Favorecido / Descrição
                            Expanded(
                              flex: 4,
                              child: Row(
                                children: [
                                  Flexible(
                                    child: Text(
                                      tx.payee,
                                      style: TextStyle(
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w700,
                                        color: colors.textPrimary,
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  if (tx.memo.isNotEmpty) ...[
                                    const SizedBox(width: 6),
                                    Flexible(
                                      child: Text(
                                        '(${tx.memo})',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontStyle: FontStyle.italic,
                                          color: colors.textMuted,
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),

                            // Categoria
                            Expanded(
                              flex: 3,
                              child: Text(
                                tx.cat.isEmpty ? '—' : tx.cat,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: colors.textSecondary,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),

                            // Valor
                            SizedBox(
                              width: 120,
                              child: Text(
                                brl(tx.amt),
                                textAlign: TextAlign.right,
                                style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w800,
                                  color: tx.amt >= 0
                                      ? colors.income
                                      : colors.expense,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures()
                                  ],
                                ),
                              ),
                            ),

                            // Hover Actions Rápidas (Aparecem ao passar o mouse)
                            SizedBox(
                              width: 90,
                              child: AnimatedOpacity(
                                duration: const Duration(milliseconds: 140),
                                opacity: isHovered ? 1.0 : 0.0,
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    IconButton(
                                      visualDensity: VisualDensity.compact,
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(),
                                      tooltip: 'Editar',
                                      icon: Icon(Icons.edit_outlined,
                                          size: 15,
                                          color: colors.textSecondary),
                                      onPressed: () => showTransactionEditModal(
                                        context,
                                        widget.store,
                                        tx,
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    IconButton(
                                      visualDensity: VisualDensity.compact,
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(),
                                      tooltip: 'Duplicar',
                                      icon: Icon(Icons.copy_outlined,
                                          size: 15,
                                          color: colors.textSecondary),
                                      onPressed: () => showTransactionCopyModal(
                                        context,
                                        widget.store,
                                        tx,
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    IconButton(
                                      visualDensity: VisualDensity.compact,
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(),
                                      tooltip: 'Excluir',
                                      icon: Icon(Icons.delete_outline,
                                          size: 15,
                                          color: colors.expense),
                                      onPressed: () =>
                                          showDeleteTransactionDialog(
                                        context,
                                        widget.store,
                                        tx,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderColumn({
    required String title,
    required _SortField field,
    required OpenMoneyColors colors,
    double? width,
    bool alignRight = false,
  }) {
    final isSelected = _sortField == field;
    Widget content = InkWell(
      onTap: () {
        setState(() {
          if (_sortField == field) {
            _sortAscending = !_sortAscending;
          } else {
            _sortField = field;
            _sortAscending = true;
          }
        });
      },
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment:
            alignRight ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
              color: isSelected ? colors.accent : colors.textMuted,
            ),
          ),
          if (isSelected) ...[
            const SizedBox(width: 4),
            Icon(
              _sortAscending ? Icons.arrow_upward : Icons.arrow_downward,
              size: 12,
              color: colors.accent,
            ),
          ],
        ],
      ),
    );

    if (width != null) {
      return SizedBox(width: width, child: content);
    }
    return content;
  }
}
