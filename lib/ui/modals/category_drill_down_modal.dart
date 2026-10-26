import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/openmoney_models.dart';
import '../../services/native_file_picker.dart';
import '../../store/money_store.dart';
import '../theme/liquid_glass.dart';
import 'transaction_modal.dart';

Future<void> showCategoryDrillDownModal(
  BuildContext context,
  MoneyStore store,
  String categoryPath, {
  bool initialCurrentMonthOnly = false,
}) async {
  await showDialog(
    context: context,
    builder: (ctx) => _CategoryDrillDownDialog(
      store: store,
      categoryPath: categoryPath,
      initialCurrentMonthOnly: initialCurrentMonthOnly,
    ),
  );
}

class _CategoryDrillDownDialog extends StatefulWidget {
  final MoneyStore store;
  final String categoryPath;
  final bool initialCurrentMonthOnly;

  const _CategoryDrillDownDialog({
    required this.store,
    required this.categoryPath,
    required this.initialCurrentMonthOnly,
  });

  @override
  State<_CategoryDrillDownDialog> createState() =>
      _CategoryDrillDownDialogState();
}

class _CategoryDrillDownDialogState extends State<_CategoryDrillDownDialog> {
  late bool _filterCurrentMonthOnly;
  String _searchQuery = '';
  String _sortField = 'date'; // 'date', 'payee', 'amount'
  bool _sortAsc = false;

  @override
  void initState() {
    super.initState();
    _filterCurrentMonthOnly = widget.initialCurrentMonthOnly;
  }

  List<Transaction> _buildFilteredTransactions() {
    final monthYM = widget.store.month;
    final affected = widget.store.affectedCategoryPaths(widget.categoryPath);
    final prefix = '${widget.categoryPath}$kCategorySep';

    final list = widget.store.db.txs.where((t) {
      if (t.auto == true) return false;
      final matchesCat = affected.contains(t.cat) ||
          t.cat == widget.categoryPath ||
          t.cat.startsWith(prefix);
      if (!matchesCat) return false;

      if (_filterCurrentMonthOnly && !t.date.startsWith(monthYM)) {
        return false;
      }

      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        final p = t.payee.toLowerCase();
        final m = t.memo.toLowerCase();
        final c = t.cat.toLowerCase();
        final accName =
            (widget.store.accById(t.acc)?.name ?? '').toLowerCase();
        if (!p.contains(q) &&
            !m.contains(q) &&
            !c.contains(q) &&
            !accName.contains(q)) {
          return false;
        }
      }
      return true;
    }).toList();

    list.sort((a, b) {
      int comp;
      switch (_sortField) {
        case 'payee':
          comp = a.payee.toLowerCase().compareTo(b.payee.toLowerCase());
          break;
        case 'amount':
          comp = a.amt.compareTo(b.amt);
          break;
        case 'date':
        default:
          comp = a.date.compareTo(b.date);
          break;
      }
      return _sortAsc ? comp : -comp;
    });

    return list;
  }

  Future<void> _exportCsv(List<Transaction> txs) async {
    const header = 'Data;Conta;Favorecido;Categoria;Nota;Valor (R\$);Conciliado';
    final rows = txs.map((t) {
      final acc = widget.store.accById(t.acc)?.name ?? 'Conta';
      final valor = (t.amt / 100.0).toStringAsFixed(2).replaceAll('.', ',');
      return '${fmtDate(t.date)};"$acc";"${t.payee}";"${t.cat}";"${t.memo}";$valor;${t.rec ? "Sim" : "Não"}';
    }).join('\r\n');
    final csv = '\uFEFF$header\r\n$rows';

    if (!kIsWeb) {
      final safeCat = widget.categoryPath
          .replaceAll(':', '-')
          .replaceAll('/', '-')
          .replaceAll(' ', '_');
      final savePath = await NativeFilePicker.saveFile(
        title: 'Exportar Lançamentos da Categoria (CSV)',
        defaultName: 'Categoria-$safeCat.csv',
        allowedExtensions: ['csv'],
      );
      if (savePath != null && savePath.isNotEmpty) {
        try {
          final f = File(savePath);
          f.parent.createSync(recursive: true);
          f.writeAsStringSync(csv, flush: true);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('✓ CSV exportado com sucesso em:\n$savePath'),
              ),
            );
          }
          return;
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Erro ao salvar CSV: $e'),
                backgroundColor: Colors.redAccent,
              ),
            );
          }
          return;
        }
      }
      return;
    }

    Clipboard.setData(ClipboardData(text: csv));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('✓ Lançamentos copiados em formato CSV!'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colors = OpenMoneyColors(isDark);
    final monthYM = widget.store.month;
    final txs = _buildFilteredTransactions();
    final totalCents = txs.fold<int>(0, (s, t) => s + t.amt);

    return Dialog(
      backgroundColor: colors.bgSecondary,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colors.borderGlass),
      ),
      child: SizedBox(
        width: 780,
        height: 560,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
                children: [
                  Icon(Icons.manage_search, color: colors.accent, size: 24),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Auditoria de Lançamentos: ${widget.categoryPath}',
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                            color: colors.textPrimary,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          'Clique em qualquer lançamento abaixo para abrir ou editar',
                          style: TextStyle(
                            fontSize: 11.5,
                            color: colors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.tonalIcon(
                    icon: const Icon(Icons.download, size: 16),
                    label: const Text('Exportar CSV'),
                    onPressed: () => _exportCsv(txs),
                  ),
                  const SizedBox(width: 8),
                  // Botões de escopo temporal (sem SegmentedButton dentro de IntrinsicWidth)
                  Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: colors.borderGlass),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        InkWell(
                          borderRadius: const BorderRadius.horizontal(
                            left: Radius.circular(7),
                          ),
                          onTap: () =>
                              setState(() => _filterCurrentMonthOnly = false),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: !_filterCurrentMonthOnly
                                  ? colors.accent.withValues(alpha: 0.2)
                                  : Colors.transparent,
                              borderRadius: const BorderRadius.horizontal(
                                left: Radius.circular(7),
                              ),
                            ),
                            child: Text(
                              'Todo o Histórico',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: !_filterCurrentMonthOnly
                                    ? FontWeight.w800
                                    : FontWeight.w500,
                                color: !_filterCurrentMonthOnly
                                    ? colors.accent
                                    : colors.textSecondary,
                              ),
                            ),
                          ),
                        ),
                        InkWell(
                          borderRadius: const BorderRadius.horizontal(
                            right: Radius.circular(7),
                          ),
                          onTap: () =>
                              setState(() => _filterCurrentMonthOnly = true),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: _filterCurrentMonthOnly
                                  ? colors.accent.withValues(alpha: 0.2)
                                  : Colors.transparent,
                              borderRadius: const BorderRadius.horizontal(
                                right: Radius.circular(7),
                              ),
                            ),
                            child: Text(
                              fmtMonth(monthYM),
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: _filterCurrentMonthOnly
                                    ? FontWeight.w800
                                    : FontWeight.w500,
                                color: _filterCurrentMonthOnly
                                    ? colors.accent
                                    : colors.textSecondary,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              // Barra de Pesquisa e Ordenação
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      decoration: InputDecoration(
                        hintText:
                            'Pesquisar nos resultados (favorecido, nota, conta)...',
                        prefixIcon: const Icon(Icons.search, size: 18),
                        isDense: true,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 9,
                        ),
                      ),
                      onChanged: (v) =>
                          setState(() => _searchQuery = v.trim()),
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Text(
                    'Ordenar:',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(width: 6),
                  DropdownButton<String>(
                    value: _sortField,
                    underline: const SizedBox(),
                    items: const [
                      DropdownMenuItem(value: 'date', child: Text('Data')),
                      DropdownMenuItem(value: 'payee', child: Text('Nome')),
                      DropdownMenuItem(value: 'amount', child: Text('Valor')),
                    ],
                    onChanged: (v) {
                      if (v != null) setState(() => _sortField = v);
                    },
                  ),
                  IconButton(
                    tooltip:
                        _sortAsc ? 'Ordem Crescente' : 'Ordem Decrescente',
                    icon: Icon(
                      _sortAsc ? Icons.arrow_upward : Icons.arrow_downward,
                      size: 18,
                    ),
                    onPressed: () => setState(() => _sortAsc = !_sortAsc),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${txs.length} lançamento(s) encontrado(s)',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 12.5,
                      color: colors.textSecondary,
                    ),
                  ),
                  Text(
                    'Total: ${brl(totalCents)}',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 13.5,
                      color: totalCents >= 0 ? colors.income : colors.expense,
                    ),
                  ),
                ],
              ),
              const Divider(height: 16),
              // Lista de Lançamentos
              Expanded(
                child: txs.isEmpty
                    ? Center(
                        child: Text(
                          'Nenhum lançamento encontrado para este filtro.',
                          style: TextStyle(color: colors.textSecondary),
                        ),
                      )
                    : ListView.separated(
                        itemCount: txs.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (context, i) {
                          final t = txs[i];
                          final accName =
                              widget.store.accById(t.acc)?.name ?? 'Conta';
                          return ListTile(
                            dense: true,
                            contentPadding:
                                const EdgeInsets.symmetric(horizontal: 6),
                            leading: Icon(
                              t.rec
                                  ? Icons.check_circle
                                  : Icons.radio_button_unchecked,
                              size: 16,
                              color:
                                  t.rec ? colors.income : colors.textMuted,
                            ),
                            title: Text(
                              t.payee,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 13,
                              ),
                            ),
                            subtitle: Text(
                              '${fmtDate(t.date)} • $accName • ${t.cat}${t.memo.isNotEmpty ? " • ${t.memo}" : ""}',
                              style: const TextStyle(fontSize: 11.5),
                            ),
                            trailing: Text(
                              brl(t.amt),
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                fontSize: 13,
                                color: t.amt >= 0
                                    ? colors.income
                                    : colors.expense,
                              ),
                            ),
                            onTap: () {
                              Navigator.pop(context);
                              showTransactionEditModal(
                                context,
                                widget.store,
                                t,
                              );
                            },
                          );
                        },
                      ),
              ),
              const Divider(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  FilledButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Fechar'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
