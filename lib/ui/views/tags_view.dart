import 'package:flutter/material.dart';
import '../../store/money_store.dart';
import '../modals/category_drill_down_modal.dart';
import '../theme/liquid_glass.dart';

class TagsView extends StatefulWidget {
  final MoneyStore store;

  const TagsView({super.key, required this.store});

  @override
  State<TagsView> createState() => _TagsViewState();
}

class _TagsViewState extends State<TagsView> {
  final TextEditingController _searchCtrl = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _showAddTagDialog(BuildContext context, MoneyStore store) async {
    final ctrl = TextEditingController();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final c = OpenMoneyColors(isDark);
    String? errorMsg;

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              backgroundColor: c.surfaceCard,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(color: c.borderGlass),
              ),
              title: Row(
                children: [
                  Icon(Icons.label_outline, color: c.accent, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    'Nova Tag',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: c.textPrimary,
                    ),
                  ),
                ],
              ),
              content: SizedBox(
                width: 360,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'As tags complementam suas categorias para organizar movimentações do seu jeito.',
                      style: TextStyle(fontSize: 12, color: c.textMuted),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: ctrl,
                      autofocus: true,
                      style: TextStyle(fontSize: 14, color: c.textPrimary),
                      decoration: InputDecoration(
                        labelText: 'Nome da tag',
                        hintText: 'Ex: Viagem, Reembolso, Trabalho',
                        errorText: errorMsg,
                        filled: true,
                        fillColor: c.bgSecondary,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      onSubmitted: (_) {
                        final ok = store.addTag(ctrl.text);
                        if (ok) {
                          Navigator.of(ctx).pop();
                        } else {
                          setDialogState(() {
                            errorMsg = ctrl.text.trim().isEmpty
                                ? 'Informe um nome válido.'
                                : 'Já existe uma tag com esse nome.';
                          });
                        }
                      },
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child:
                      Text('Cancelar', style: TextStyle(color: c.textMuted)),
                ),
                ElevatedButton(
                  onPressed: () {
                    final ok = store.addTag(ctrl.text);
                    if (ok) {
                      Navigator.of(ctx).pop();
                    } else {
                      setDialogState(() {
                        errorMsg = ctrl.text.trim().isEmpty
                            ? 'Informe um nome válido.'
                            : 'Já existe uma tag com esse nome.';
                      });
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: c.accent,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Confirmar'),
                ),
              ],
            );
          },
        );
      },
    );
    ctrl.dispose();
  }

  Future<void> _showRenameTagDialog(
    BuildContext context,
    MoneyStore store,
    String oldName,
  ) async {
    final ctrl = TextEditingController(text: oldName);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final c = OpenMoneyColors(isDark);
    String? errorMsg;

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setDialogState) {
            return AlertDialog(
              backgroundColor: c.surfaceCard,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(color: c.borderGlass),
              ),
              title: Text(
                'Renomear Tag',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: c.textPrimary,
                ),
              ),
              content: SizedBox(
                width: 360,
                child: TextField(
                  controller: ctrl,
                  autofocus: true,
                  style: TextStyle(fontSize: 14, color: c.textPrimary),
                  decoration: InputDecoration(
                    labelText: 'Novo nome',
                    errorText: errorMsg,
                    filled: true,
                    fillColor: c.bgSecondary,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onSubmitted: (_) {
                    final ok = store.renameTag(oldName, ctrl.text);
                    if (ok) {
                      Navigator.of(ctx).pop();
                    } else {
                      setDialogState(() {
                        errorMsg = ctrl.text.trim().isEmpty
                            ? 'Informe um nome válido.'
                            : 'Já existe outra tag com esse nome.';
                      });
                    }
                  },
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(ctx).pop(),
                  child:
                      Text('Cancelar', style: TextStyle(color: c.textMuted)),
                ),
                ElevatedButton(
                  onPressed: () {
                    final ok = store.renameTag(oldName, ctrl.text);
                    if (ok) {
                      Navigator.of(ctx).pop();
                    } else {
                      setDialogState(() {
                        errorMsg = ctrl.text.trim().isEmpty
                            ? 'Informe um nome válido.'
                            : 'Já existe outra tag com esse nome.';
                      });
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: c.accent,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('Salvar'),
                ),
              ],
            );
          },
        );
      },
    );
    ctrl.dispose();
  }

  Future<void> _confirmDeleteTag(
    BuildContext context,
    MoneyStore store,
    String tagName,
    int txCount,
  ) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final c = OpenMoneyColors(isDark);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: c.surfaceCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: c.borderGlass),
        ),
        title: Text(
          'Excluir Tag "#$tagName"?',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: c.textPrimary,
          ),
        ),
        content: Text(
          txCount > 0
              ? 'Esta tag está vinculada a $txCount lançamento(s) e será removida de todos eles.'
              : 'Tem certeza que deseja excluir esta tag?',
          style: TextStyle(fontSize: 13, color: c.textMuted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('Cancelar', style: TextStyle(color: c.textMuted)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: c.expense,
              foregroundColor: Colors.white,
            ),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      store.deleteTag(tagName);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.store,
      builder: (context, _) {
        final store = widget.store;
        final isDark = Theme.of(context).brightness == Brightness.dark;
        final c = OpenMoneyColors(isDark);
        final isMobile = MediaQuery.sizeOf(context).width < 700;

        final allTags = store.allTags;
        final query = _searchQuery.trim().toLowerCase();
        final filtered = query.isEmpty
            ? allTags
            : allTags.where((t) => t.toLowerCase().contains(query)).toList();

        return Scaffold(
          backgroundColor: c.bgPrimary,
          body: Padding(
            padding: EdgeInsets.all(isMobile ? 12 : 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Tags',
                            style: TextStyle(
                              fontSize: isMobile ? 20 : 24,
                              fontWeight: FontWeight.w700,
                              color: c.textPrimary,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Complemente suas categorias marcando lançamentos com tags personalizadas.',
                            style:
                                TextStyle(fontSize: 12.5, color: c.textMuted),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    ElevatedButton.icon(
                      onPressed: () => _showAddTagDialog(context, store),
                      icon: const Icon(Icons.add, size: 18),
                      label: Text(isMobile ? 'Nova' : 'Nova Tag'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: c.accent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 11,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _searchCtrl,
                  onChanged: (v) => setState(() => _searchQuery = v),
                  style: TextStyle(fontSize: 13, color: c.textPrimary),
                  decoration: InputDecoration(
                    hintText: 'Buscar tag...',
                    hintStyle: TextStyle(fontSize: 13, color: c.textMuted),
                    prefixIcon:
                        Icon(Icons.search, size: 18, color: c.textMuted),
                    suffixIcon: _searchQuery.isNotEmpty
                        ? IconButton(
                            icon: Icon(Icons.clear,
                                size: 16, color: c.textMuted),
                            onPressed: () {
                              _searchCtrl.clear();
                              setState(() => _searchQuery = '');
                            },
                          )
                        : null,
                    isDense: true,
                    filled: true,
                    fillColor: c.surfaceCard,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: c.borderGlass),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: c.borderGlass),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Expanded(
                  child: filtered.isEmpty
                      ? Center(
                          child: Container(
                            padding: const EdgeInsets.all(28),
                            decoration: BoxDecoration(
                              color: c.surfaceCard,
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: c.borderGlass),
                            ),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.label_off_outlined,
                                    size: 42, color: c.textMuted),
                                const SizedBox(height: 12),
                                Text(
                                  allTags.isEmpty
                                      ? 'Nenhuma tag cadastrada ainda'
                                      : 'Nenhuma tag encontrada para "$_searchQuery"',
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                    color: c.textPrimary,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  'Clique no botão "+" acima para criar sua primeira tag, ou adicione tags separadas por vírgula ao criar um lançamento.',
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                      fontSize: 12.5, color: c.textMuted),
                                ),
                              ],
                            ),
                          ),
                        )
                      : ListView.separated(
                          itemCount: filtered.length,
                          separatorBuilder: (_, _) =>
                              const SizedBox(height: 8),
                          itemBuilder: (ctx, idx) {
                            final tag = filtered[idx];
                            final count = store.transactionCountForTag(tag);
                            return InkWell(
                              onTap: () => showCategoryDrillDownModal(
                                context,
                                store,
                                null,
                                tagFilter: tag,
                              ),
                              borderRadius: BorderRadius.circular(10),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 14,
                                  vertical: 10,
                                ),
                                decoration: BoxDecoration(
                                  color: c.surfaceCard,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: c.borderGlass),
                                ),
                                child: Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 5,
                                      ),
                                      decoration: BoxDecoration(
                                        color: c.accent.withValues(alpha: 0.12),
                                        borderRadius: BorderRadius.circular(18),
                                      ),
                                      child: Text(
                                        '#$tag',
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                          color: c.accent,
                                        ),
                                      ),
                                    ),
                                    const Spacer(),
                                    Text(
                                      '$count ${count == 1 ? "lançamento" : "lançamentos"}',
                                      style: TextStyle(
                                          fontSize: 12, color: c.textMuted),
                                    ),
                                    const SizedBox(width: 8),
                                    IconButton(
                                      icon: Icon(Icons.edit_outlined,
                                          size: 18, color: c.textMuted),
                                      tooltip: 'Renomear tag',
                                      onPressed: () => _showRenameTagDialog(
                                          context, store, tag),
                                    ),
                                    IconButton(
                                      icon: Icon(Icons.delete_outline,
                                          size: 18, color: c.expense),
                                      tooltip: 'Excluir tag',
                                      onPressed: () => _confirmDeleteTag(
                                        context,
                                        store,
                                        tag,
                                        count,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
