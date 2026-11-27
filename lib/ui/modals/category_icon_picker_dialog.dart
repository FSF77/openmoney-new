import 'dart:math' as math;
import 'dart:ui' show PointerDeviceKind;
import 'package:flutter/material.dart';
import '../../models/openmoney_models.dart';
import '../../services/category_icon_registry.dart';
import '../theme/liquid_glass.dart';

Future<({String? icon, String? color})?> showCategoryIconPickerDialog(
  BuildContext context, {
  required String categoryName,
  required String categoryType,
  bool isSubcategory = false,
  CategoryItem? parentCategory,
  String? initialIcon,
  String? initialColor,
}) {
  return showDialog<({String? icon, String? color})>(
    context: context,
    builder: (ctx) => _CategoryIconPickerDialog(
      categoryName: categoryName,
      categoryType: categoryType,
      isSubcategory: isSubcategory,
      parentCategory: parentCategory,
      initialIcon: initialIcon,
      initialColor: initialColor,
    ),
  );
}

class _CategoryIconPickerDialog extends StatefulWidget {
  final String categoryName;
  final String categoryType;
  final bool isSubcategory;
  final CategoryItem? parentCategory;
  final String? initialIcon;
  final String? initialColor;

  const _CategoryIconPickerDialog({
    required this.categoryName,
    required this.categoryType,
    required this.isSubcategory,
    this.parentCategory,
    this.initialIcon,
    this.initialColor,
  });

  @override
  State<_CategoryIconPickerDialog> createState() =>
      _CategoryIconPickerDialogState();
}

class _CategoryIconPickerDialogState extends State<_CategoryIconPickerDialog> {
  final TextEditingController _searchCtrl = TextEditingController();
  final ScrollController _groupScrollCtrl = ScrollController();
  String _search = '';
  String _selectedGroup = 'Todos';
  String? _selectedIcon;
  String? _selectedColor;

  @override
  void initState() {
    super.initState();
    _selectedIcon = widget.initialIcon;
    _selectedColor = widget.initialColor;
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _groupScrollCtrl.dispose();
    super.dispose();
  }

  void _scrollGroupsBy(double delta) {
    if (!_groupScrollCtrl.hasClients) return;
    final target = (_groupScrollCtrl.offset + delta)
        .clamp(0.0, _groupScrollCtrl.position.maxScrollExtent);
    _groupScrollCtrl.animateTo(
      target,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colors = OpenMoneyColors(isDark);
    final screen = MediaQuery.sizeOf(context);
    final dialogWidth = math.min(540.0, screen.width - 28);
    final dialogHeight = math.min(620.0, screen.height - 48);

    final previewCat = CategoryItem(
      name: widget.categoryName.trim().isEmpty
          ? 'Nova Categoria'
          : widget.categoryName.trim(),
      parent: widget.isSubcategory ? widget.parentCategory?.name : null,
      type: widget.categoryType,
      icon: _selectedIcon,
      color: _selectedColor,
    );
    final resolvedPreview = CategoryIconRegistry.resolve(
      category: previewCat,
      parentCategory: widget.parentCategory,
      fallbackType: widget.categoryType,
      isDark: isDark,
    );

    final filtered = CategoryIconRegistry.searchIcons(
      _search,
      group: _selectedGroup,
    );

    final hasCustom = _selectedIcon != null || _selectedColor != null;
    final statusLabel = hasCustom
        ? 'Personalizado'
        : (widget.isSubcategory && widget.parentCategory != null
            ? 'Herdado de ${widget.parentCategory!.name}'
            : 'Padrão Automático');

    return AlertDialog(
      backgroundColor: colors.bgPrimary,
      titlePadding: const EdgeInsets.fromLTRB(20, 16, 16, 8),
      contentPadding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
      title: Row(
        children: [
          const Expanded(
            child: Text(
              'Escolher Ícone e Cor',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
            ),
          ),
          if (hasCustom)
            TextButton.icon(
              onPressed: () {
                setState(() {
                  _selectedIcon = null;
                  _selectedColor = null;
                });
              },
              icon: const Icon(Icons.restart_alt_rounded, size: 16),
              label: Text(
                widget.isSubcategory ? 'Herdar do Pai' : 'Automático',
                style: const TextStyle(fontSize: 12),
              ),
            ),
        ],
      ),
      content: SizedBox(
        width: dialogWidth,
        height: dialogHeight,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Prévia ao vivo
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: colors.surfaceGlass,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: colors.borderGlass),
              ),
              child: Row(
                children: [
                  CategoryIconBadge(
                    icon: resolvedPreview.icon,
                    color: resolvedPreview.color,
                    size: 38,
                    iconSize: 22,
                    borderRadius: 10,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          previewCat.name,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                            color: colors.textPrimary,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          statusLabel,
                          style: TextStyle(
                            fontSize: 11.5,
                            color: colors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Paleta de Cores
            Text(
              'Cor do ícone',
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: colors.textSecondary,
              ),
            ),
            const SizedBox(height: 6),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Tooltip(
                  message: widget.isSubcategory
                      ? 'Herdar cor da categoria principal'
                      : 'Cor automática',
                  child: InkWell(
                    onTap: () => setState(() => _selectedColor = null),
                    borderRadius: BorderRadius.circular(999),
                    child: Container(
                      height: 26,
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      decoration: BoxDecoration(
                        color: _selectedColor == null
                            ? colors.accent.withValues(alpha: 0.18)
                            : colors.surfaceGlass,
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(
                          color: _selectedColor == null
                              ? colors.accent
                              : colors.borderGlass,
                          width: _selectedColor == null ? 1.8 : 1,
                        ),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        'Auto',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: _selectedColor == null
                              ? colors.accent
                              : colors.textSecondary,
                        ),
                      ),
                    ),
                  ),
                ),
                ...CategoryIconRegistry.colors.map((opt) {
                  final isSel = _selectedColor == opt.key;
                  final c = opt.colorFor(isDark);
                  return Tooltip(
                    message: opt.label,
                    child: InkWell(
                      onTap: () => setState(() => _selectedColor = opt.key),
                      borderRadius: BorderRadius.circular(999),
                      child: Container(
                        width: 26,
                        height: 26,
                        decoration: BoxDecoration(
                          color: c,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: isSel
                                ? colors.textPrimary
                                : Colors.transparent,
                            width: 2.2,
                          ),
                          boxShadow: isSel
                              ? [
                                  BoxShadow(
                                    color: c.withValues(alpha: 0.45),
                                    blurRadius: 6,
                                  ),
                                ]
                              : null,
                        ),
                        child: isSel
                            ? const Icon(
                                Icons.check_rounded,
                                size: 15,
                                color: Colors.white,
                              )
                            : null,
                      ),
                    ),
                  );
                }),
              ],
            ),
            const SizedBox(height: 12),

            // Busca
            TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: 'Buscar ícone (ex: mercado, carro, saúde, streaming)...',
                prefixIcon: const Icon(Icons.search_rounded, size: 19),
                suffixIcon: _search.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear_rounded, size: 18),
                        onPressed: () {
                          _searchCtrl.clear();
                          setState(() => _search = '');
                        },
                      )
                    : null,
                border: const OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (v) => setState(() => _search = v),
            ),
            const SizedBox(height: 8),

            // Chips de Grupo (Wrap em telas largas; rolagem com setas + drag em telas estreitas)
            if (dialogWidth >= 420)
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: CategoryIconRegistry.groups.map((grp) {
                  final selected = _selectedGroup == grp;
                  return ChoiceChip(
                    label: Text(grp, style: const TextStyle(fontSize: 11.5)),
                    selected: selected,
                    visualDensity: VisualDensity.compact,
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    labelPadding: const EdgeInsets.symmetric(horizontal: 4),
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    onSelected: (_) => setState(() => _selectedGroup = grp),
                  );
                }).toList(),
              )
            else
              SizedBox(
                height: 32,
                child: Row(
                  children: [
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints:
                          const BoxConstraints(minWidth: 26, minHeight: 28),
                      tooltip: 'Grupos anteriores',
                      icon: const Icon(Icons.chevron_left_rounded, size: 18),
                      onPressed: () => _scrollGroupsBy(-140),
                    ),
                    Expanded(
                      child: ScrollConfiguration(
                        behavior: ScrollConfiguration.of(context).copyWith(
                          dragDevices: {
                            PointerDeviceKind.touch,
                            PointerDeviceKind.mouse,
                            PointerDeviceKind.trackpad,
                          },
                        ),
                        child: ListView.separated(
                          controller: _groupScrollCtrl,
                          scrollDirection: Axis.horizontal,
                          itemCount: CategoryIconRegistry.groups.length,
                          separatorBuilder: (_, _) => const SizedBox(width: 6),
                          itemBuilder: (ctx, i) {
                            final grp = CategoryIconRegistry.groups[i];
                            final selected = _selectedGroup == grp;
                            return ChoiceChip(
                              label: Text(
                                grp,
                                style: const TextStyle(fontSize: 11.5),
                              ),
                              selected: selected,
                              visualDensity: VisualDensity.compact,
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 6),
                              onSelected: (_) =>
                                  setState(() => _selectedGroup = grp),
                            );
                          },
                        ),
                      ),
                    ),
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints:
                          const BoxConstraints(minWidth: 26, minHeight: 28),
                      tooltip: 'Próximos grupos',
                      icon: const Icon(Icons.chevron_right_rounded, size: 18),
                      onPressed: () => _scrollGroupsBy(140),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 10),

            // Grid de Ícones
            Expanded(
              child: filtered.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.search_off_rounded,
                            size: 40,
                            color: colors.textMuted,
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Nenhum ícone encontrado',
                            style: TextStyle(
                              fontSize: 13,
                              color: colors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    )
                  : GridView.builder(
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: dialogWidth < 380 ? 3 : 4,
                        crossAxisSpacing: 8,
                        mainAxisSpacing: 8,
                        childAspectRatio: 1.05,
                      ),
                      itemCount: filtered.length,
                      itemBuilder: (ctx, idx) {
                        final item = filtered[idx];
                        final isSel = _selectedIcon == item.id;
                        final activeColor = resolvedPreview.color;
                        return InkWell(
                          borderRadius: BorderRadius.circular(10),
                          onTap: () => setState(() => _selectedIcon = item.id),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: isSel
                                  ? activeColor.withValues(alpha: 0.16)
                                  : colors.surfaceGlass,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: isSel ? activeColor : colors.borderGlass,
                                width: isSel ? 1.8 : 1,
                              ),
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  item.icon,
                                  size: 24,
                                  color: isSel
                                      ? activeColor
                                      : colors.textPrimary,
                                ),
                                const SizedBox(height: 5),
                                Text(
                                  item.label,
                                  style: TextStyle(
                                    fontSize: 10.5,
                                    fontWeight: isSel
                                        ? FontWeight.w700
                                        : FontWeight.w500,
                                    color: isSel
                                        ? activeColor
                                        : colors.textSecondary,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  textAlign: TextAlign.center,
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
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop((
            icon: _selectedIcon,
            color: _selectedColor,
          )),
          child: const Text('Aplicar'),
        ),
      ],
    );
  }
}
