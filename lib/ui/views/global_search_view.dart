import 'package:flutter/material.dart';
import '../../models/openmoney_models.dart';
import '../../store/money_store.dart';
import '../theme/liquid_glass.dart';

class GlobalSearchView extends StatefulWidget {
  final MoneyStore store;
  const GlobalSearchView({super.key, required this.store});

  @override
  State<GlobalSearchView> createState() => _GlobalSearchViewState();
}

class _GlobalSearchViewState extends State<GlobalSearchView> {
  final TextEditingController _queryCtrl = TextEditingController();
  String _accFilter = 'all';
  int _signFilter = 0; // 0: all, 1: positive, -1: negative

  @override
  void dispose() {
    _queryCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colors = OpenMoneyColors(isDark);

    final results = widget.store.searchTransactions(
      query: _queryCtrl.text,
      accountId: _accFilter,
      signFilter: _signFilter,
    );
    final totalSum = results.fold<int>(0, (s, t) => s + t.amt);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
          child: GlassCard(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.manage_search, color: colors.accent, size: 24),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Pesquisa Global em Toda a Base de Dados',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              color: colors.textPrimary,
                            ),
                          ),
                          Text(
                            'Busca simultânea em Favorecido, Categoria, Nota, Conta, Data e Valor • Clique no resultado para saltar ao extrato',
                            style: TextStyle(
                              fontSize: 12,
                              color: colors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    SizedBox(
                      width: 340,
                      child: TextField(
                        controller: _queryCtrl,
                        autofocus: true,
                        decoration: InputDecoration(
                          labelText:
                              'Pesquisar (ex: mercado, 150,00, assinatura)...',
                          prefixIcon: const Icon(Icons.search),
                          suffixIcon: _queryCtrl.text.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear, size: 18),
                                  onPressed: () {
                                    setState(() => _queryCtrl.clear());
                                  },
                                )
                              : null,
                          isDense: true,
                          border: const OutlineInputBorder(),
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                    ),
                    SizedBox(
                      width: 210,
                      child: DropdownButtonFormField<String>(
                        initialValue: _accFilter,
                        isExpanded: true,
                        decoration: const InputDecoration(
                          labelText: 'Filtrar por Conta',
                          isDense: true,
                          border: OutlineInputBorder(),
                        ),
                        items: [
                          const DropdownMenuItem(
                            value: 'all',
                            child: Text('Todas as Contas'),
                          ),
                          ...widget.store.db.accounts.map(
                            (a) => DropdownMenuItem(
                              value: a.id,
                              child: Text(a.name),
                            ),
                          ),
                        ],
                        onChanged: (v) {
                          if (v != null) setState(() => _accFilter = v);
                        },
                      ),
                    ),
                    SegmentedButton<int>(
                      segments: const [
                        ButtonSegment(value: 0, label: Text('Todos')),
                        ButtonSegment(value: 1, label: Text('+ Receitas')),
                        ButtonSegment(value: -1, label: Text('− Despesas')),
                      ],
                      selected: {_signFilter},
                      onSelectionChanged: (s) =>
                          setState(() => _signFilter = s.first),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  '${results.length} resultado(s) encontrado(s) • Soma líquida: ${brl(totalSum)}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: colors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
            itemCount: results.length,
            itemBuilder: (context, idx) {
              final tx = results[idx];
              final accName = widget.store.accById(tx.acc)?.name ?? 'Conta';
              return GlassCard(
                margin: const EdgeInsets.only(bottom: 8),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                onTap: () => widget.store.navigateToTransaction(tx),
                child: Row(
                  children: [
                    Icon(
                      tx.rec
                          ? Icons.check_circle
                          : Icons.radio_button_unchecked,
                      size: 18,
                      color: tx.rec ? colors.income : colors.textMuted,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            tx.payee,
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 13.5,
                            ),
                          ),
                          Text(
                            '${fmtDate(tx.date)} • $accName • ${tx.cat}${tx.memo.isNotEmpty ? " • ${tx.memo}" : ""}',
                            style: TextStyle(
                              fontSize: 12,
                              color: colors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Text(
                      brl(tx.amt),
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 14,
                        color: tx.amt >= 0 ? colors.income : colors.expense,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Icon(
                      Icons.open_in_new,
                      size: 16,
                      color: colors.accent,
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
