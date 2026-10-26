import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../../models/openmoney_models.dart';
import '../../services/native_file_picker.dart';
import '../../store/money_store.dart';
import '../modals/category_drill_down_modal.dart';
import '../theme/liquid_glass.dart';

class CategoriesView extends StatefulWidget {
  final MoneyStore store;
  const CategoriesView({super.key, required this.store});

  @override
  State<CategoriesView> createState() => _CategoriesViewState();
}

class _CategoriesViewState extends State<CategoriesView> {
  String _selectedType = 'Despesa';

  void _showCategoryDrillDown(String categoryPath) {
    showCategoryDrillDownModal(context, widget.store, categoryPath);
  }

  Future<void> _exportCategoriesCsv() async {
    if (kIsWeb) return;
    final savePath = await NativeFilePicker.saveFile(
      title: 'Exportar Categorias e Subcategorias (CSV)',
      defaultName: 'openmoney-categorias-${todayISO()}.csv',
      allowedExtensions: ['csv'],
    );
    if (savePath == null || savePath.isEmpty) return;

    try {
      final csv = widget.store.exportCategoriesCSVString();
      final f = File(savePath);
      f.parent.createSync(recursive: true);
      f.writeAsStringSync(csv, flush: true);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✓ Categorias exportadas com sucesso em:\n$savePath'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao exportar categorias: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  Future<void> _importCategoriesCsv() async {
    if (kIsWeb) return;
    final selectedPath = await NativeFilePicker.pickFile(
      title: 'Importar Categorias e Subcategorias (CSV)',
      allowedExtensions: ['csv'],
    );
    if (selectedPath == null || selectedPath.isEmpty) return;

    try {
      final bytes = File(selectedPath).readAsBytesSync();
      final summary = widget.store.importCategoriesCSVBytes(bytes);
      if (mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(summary.title),
            content: Text(summary.formattedMessage),
            actions: [
              FilledButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('OK'),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao importar categorias: $e'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  void _showCategoryFormModal({CategoryItem? editing, String? presetParent}) {
    final nameCtrl = TextEditingController(text: editing?.name ?? '');
    String type = editing?.type ?? _selectedType;
    String? parent = editing != null ? editing.parent : presetParent;
    bool includeInReports = editing?.effectiveIncludeInReports ?? true;
    String? errorMsg;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          final topParents = widget.store
              .topCategories(type: type)
              .where((c) => c.name != editing?.name)
              .toList();

          return AlertDialog(
            title: Text(
              editing == null ? 'Nova Categoria' : 'Editar Categoria',
            ),
            content: SizedBox(
              width: 420,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (errorMsg != null) ...[
                    Text(
                      errorMsg!,
                      style: const TextStyle(color: Colors.redAccent),
                    ),
                    const SizedBox(height: 10),
                  ],
                  TextField(
                    controller: nameCtrl,
                    autofocus: true,
                    decoration: const InputDecoration(
                      labelText: 'Nome da Categoria / Subcategoria',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: type,
                    decoration: const InputDecoration(
                      labelText: 'Tipo',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'Despesa',
                        child: Text('Despesa'),
                      ),
                      DropdownMenuItem(
                        value: 'Receita',
                        child: Text('Receita'),
                      ),
                    ],
                    onChanged: (v) {
                      if (v != null) {
                        setModalState(() {
                          type = v;
                          parent = null;
                        });
                      }
                    },
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    key: ValueKey('parent_${type}_$parent'),
                    initialValue: parent ?? '',
                    decoration: const InputDecoration(
                      labelText: 'Categoria Principal (Pai)',
                      border: OutlineInputBorder(),
                    ),
                    items: [
                      const DropdownMenuItem(
                        value: '',
                        child: Text('— Nenhuma (Categoria Principal) —'),
                      ),
                      ...topParents.map(
                        (p) => DropdownMenuItem(
                          value: p.name,
                          child: Text(p.name),
                        ),
                      ),
                    ],
                    onChanged: (v) {
                      setModalState(
                          () => parent = (v == null || v.isEmpty) ? null : v);
                    },
                  ),
                  const SizedBox(height: 10),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Incluir nos Relatórios Mensais'),
                    value: includeInReports,
                    onChanged: (v) =>
                        setModalState(() => includeInReports = v),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                onPressed: () {
                  final err = widget.store.saveCategory(
                    editingPath: editing?.path,
                    name: nameCtrl.text,
                    parent: parent,
                    type: type,
                    includeInReports: includeInReports,
                  );
                  if (err != null) {
                    setModalState(() => errorMsg = err);
                    return;
                  }
                  Navigator.pop(ctx);
                },
                child: const Text('Salvar'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _handleDeleteCategory(CategoryItem cat) {
    final usageCount = widget.store.categoryUsageCount(cat.path);
    if (usageCount == 0) {
      widget.store.deleteCategory(cat.path);
      return;
    }

    final affected = widget.store.affectedCategoryPaths(cat.path);
    final candidates = widget.store
        .allCategoryPaths(cat.type)
        .where((p) => !affected.contains(p))
        .toList();
    String replacement = candidates.isNotEmpty ? candidates.first : 'Outros';

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setModalState) {
          return AlertDialog(
            title: const Text('Reclassificar Lançamentos antes de Excluir'),
            content: SizedBox(
              width: 440,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'A categoria "${cat.path}" possui $usageCount lançamento(s) vinculado(s).\nSelecione a categoria substituta para migrar esses lançamentos:',
                  ),
                  const SizedBox(height: 14),
                  if (candidates.isNotEmpty)
                    DropdownButtonFormField<String>(
                      initialValue: replacement,
                      isExpanded: true,
                      decoration: const InputDecoration(
                        labelText: 'Categoria Substituta',
                        border: OutlineInputBorder(),
                      ),
                      items: candidates
                          .map((c) => DropdownMenuItem(
                                value: c,
                                child: Text(c),
                              ))
                          .toList(),
                      onChanged: (v) {
                        if (v != null) setModalState(() => replacement = v);
                      },
                    ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Cancelar'),
              ),
              FilledButton(
                style:
                    FilledButton.styleFrom(backgroundColor: Colors.redAccent),
                onPressed: () {
                  widget.store
                      .deleteCategory(cat.path, replacement: replacement);
                  Navigator.pop(ctx);
                },
                child: const Text('Reclassificar e Excluir'),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colors = OpenMoneyColors(isDark);
    final topCats = widget.store.topCategories(type: _selectedType);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
      children: [
        GlassCard(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 12,
            runSpacing: 10,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.category_outlined, color: colors.accent, size: 22),
                  const SizedBox(width: 10),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Catálogo de Categorias e Subcategorias',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: colors.textPrimary,
                        ),
                      ),
                      Text(
                        'Organização em árvore de 2 níveis com proteção contra perda de classificação',
                        style: TextStyle(
                          fontSize: 12,
                          color: colors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(
                          value: 'Despesa', label: Text('Despesas')),
                      ButtonSegment(
                          value: 'Receita', label: Text('Receitas')),
                    ],
                    selected: {_selectedType},
                    onSelectionChanged: (s) =>
                        setState(() => _selectedType = s.first),
                  ),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.file_upload_outlined, size: 16),
                    label: const Text('Importar CSV'),
                    onPressed: _importCategoriesCsv,
                  ),
                  OutlinedButton.icon(
                    icon: const Icon(Icons.download, size: 16),
                    label: const Text('Exportar CSV'),
                    onPressed: _exportCategoriesCsv,
                  ),
                  FilledButton.icon(
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Nova Categoria'),
                    onPressed: () => _showCategoryFormModal(),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        ...topCats.map((top) {
          final subs =
              widget.store.subCategories(top.name, type: _selectedType);
          final topCount = widget.store.categoryUsageCount(top.path);

          return GlassCard(
            margin: const EdgeInsets.only(bottom: 10),
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                Row(
                  children: [
                    Expanded(
                      child: MouseRegion(
                        cursor: SystemMouseCursors.click,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => _showCategoryDrillDown(top.path),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 6),
                            child: Row(
                              children: [
                                Text(
                                  top.name,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w800,
                                    fontSize: 14,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                StatusBadge(
                                  text: '$topCount lanç.',
                                  color: colors.accent,
                                ),
                                if (!top.effectiveIncludeInReports) ...[
                                  const SizedBox(width: 6),
                                  StatusBadge(
                                    text: 'OCULTA DE RELATÓRIOS',
                                    color: colors.textMuted,
                                  ),
                                ],
                                const SizedBox(width: 6),
                                Icon(
                                  Icons.open_in_new,
                                  size: 14,
                                  color: colors.accent,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                    TextButton.icon(
                      icon: const Icon(Icons.list_alt, size: 15),
                      label: const Text('Lançamentos'),
                      onPressed: () => _showCategoryDrillDown(top.path),
                    ),
                    TextButton.icon(
                      icon: const Icon(Icons.add, size: 15),
                      label: const Text('Subcategoria'),
                      onPressed: () =>
                          _showCategoryFormModal(presetParent: top.name),
                    ),
                    IconButton(
                      icon: const Icon(Icons.edit_outlined, size: 17),
                      onPressed: () => _showCategoryFormModal(editing: top),
                    ),
                    IconButton(
                      icon: Icon(Icons.delete_outline,
                          size: 17, color: colors.expense),
                      onPressed: () => _handleDeleteCategory(top),
                    ),
                  ],
                ),
                if (subs.isNotEmpty) ...[
                  const Divider(height: 12),
                  ...subs.map((sub) {
                    final subCount = widget.store.categoryUsageCount(sub.path);
                    return Padding(
                      padding: const EdgeInsets.only(left: 18),
                      child: Row(
                        children: [
                          Expanded(
                            child: MouseRegion(
                              cursor: SystemMouseCursors.click,
                              child: GestureDetector(
                                behavior: HitTestBehavior.opaque,
                                onTap: () => _showCategoryDrillDown(sub.path),
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 5),
                                  child: Row(
                                    children: [
                                      Text(
                                        '↳ ${sub.name}',
                                        style: TextStyle(
                                          fontSize: 13,
                                          color: colors.textSecondary,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        '($subCount lanç.)',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: colors.accent,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                      Icon(
                                        Icons.open_in_new,
                                        size: 12,
                                        color: colors.accent,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Ver Lançamentos',
                            icon: Icon(Icons.list_alt,
                                size: 16, color: colors.accent),
                            onPressed: () => _showCategoryDrillDown(sub.path),
                          ),
                          IconButton(
                            icon: const Icon(Icons.edit_outlined, size: 16),
                            onPressed: () =>
                                _showCategoryFormModal(editing: sub),
                          ),
                          IconButton(
                            icon: Icon(Icons.delete_outline,
                                size: 16, color: colors.expense),
                            onPressed: () => _handleDeleteCategory(sub),
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              ],
            ),
          );
        }),
      ],
    );
  }
}
