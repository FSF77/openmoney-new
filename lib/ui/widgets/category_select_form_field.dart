import 'package:flutter/material.dart';
import '../../store/money_store.dart';
import '../theme/liquid_glass.dart';

/// Seletor compacto de categoria/transferência com espaçamento de linha sutil
class CategorySelectFormField extends StatelessWidget {
  final MoneyStore store;
  final String categoryType; // 'Despesa' ou 'Receita'
  final String currentSelection;
  final String? excludeAccountId;
  final ValueChanged<String> onChanged;
  final String labelText;
  final double? width;

  const CategorySelectFormField({
    super.key,
    required this.store,
    required this.categoryType,
    required this.currentSelection,
    this.excludeAccountId,
    required this.onChanged,
    this.labelText = 'Categoria / Transferência',
    this.width,
  });

  String _displayLabel(List<({String label, String value, bool isHeader})> options) {
    if (currentSelection.startsWith('xfer:')) {
      final accId = currentSelection.substring(5);
      final acc = store.accById(accId);
      return '⇄ Transferência: ${acc?.name ?? accId}';
    }
    for (final opt in options) {
      if (opt.value == currentSelection) {
        return opt.label.trim();
      }
    }
    return currentSelection.isEmpty ? 'Selecione a categoria' : currentSelection;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final colors = OpenMoneyColors(isDark);

    // Constrói lista estruturada: Categorias principais, subcategorias e transferências
    final options = <({String label, String value, bool isHeader})>[];
    for (final top in store.topCategories(type: categoryType)) {
      final subs = store.subCategories(top.name, type: categoryType);
      if (subs.isEmpty) {
        options.add((label: top.name, value: top.path, isHeader: false));
      } else {
        // Categoria pai atua como cabeçalho de grupo
        options.add((label: top.name, value: top.path, isHeader: true));
        for (final sub in subs) {
          options.add((label: '↳ ${sub.name}', value: sub.path, isHeader: false));
        }
      }
    }

    // Contas ativas para transferência
    final transferAccounts = store.activeAccounts
        .where((a) => excludeAccountId == null || a.id != excludeAccountId)
        .toList();

    final displayText = _displayLabel(options);

    final formField = DropdownButtonFormField<String>(
      key: ValueKey('cs_${categoryType}_$currentSelection'),
      initialValue: 'current',
      isExpanded: true,
      style: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w500,
        color: colors.textPrimary,
      ),
      decoration: InputDecoration(
        labelText: labelText,
        labelStyle: const TextStyle(fontSize: 13),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        border: const OutlineInputBorder(),
      ),
      icon: Icon(
        Icons.arrow_drop_down,
        size: 20,
        color: colors.textSecondary,
      ),
      items: [
        DropdownMenuItem<String>(
          value: 'current',
          child: Text(
            displayText,
            style: TextStyle(
              fontSize: 13,
              color: colors.textPrimary,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
      onChanged: (_) {},
    );

    void openMenu() {
      final RenderBox box = context.findRenderObject()! as RenderBox;
      final Offset position = box.localToGlobal(Offset.zero);
      final size = box.size;

      final menuItems = <PopupMenuEntry<String>>[];

      for (final opt in options) {
        if (opt.isHeader) {
          menuItems.add(
            PopupMenuItem<String>(
              value: opt.value,
              height: 28,
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 2),
              child: Text(
                opt.label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  color: colors.textPrimary,
                ),
              ),
            ),
          );
        } else {
          final isSelected = opt.value == currentSelection;
          final isSub = opt.label.startsWith('↳');
          menuItems.add(
            PopupMenuItem<String>(
              value: opt.value,
              height: 26,
              padding: EdgeInsets.fromLTRB(isSub ? 24 : 12, 2, 12, 2),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      opt.label,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: isSelected ? FontWeight.w700 : FontWeight.w400,
                        color: isSelected ? colors.accent : colors.textPrimary,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (isSelected)
                    Icon(Icons.check, size: 14, color: colors.accent),
                ],
              ),
            ),
          );
        }
      }

      if (transferAccounts.isNotEmpty) {
        menuItems.add(const PopupMenuDivider(height: 10));
        for (final a in transferAccounts) {
          final val = 'xfer:${a.id}';
          final isSelected = val == currentSelection;
          menuItems.add(
            PopupMenuItem<String>(
              value: val,
              height: 26,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
              child: Row(
                children: [
                  Icon(
                    Icons.swap_horiz,
                    size: 15,
                    color: isSelected ? colors.accent : colors.textSecondary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '⇄ Transferência: ${a.name}',
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: isSelected ? FontWeight.w700 : FontWeight.w400,
                        color: isSelected ? colors.accent : colors.textPrimary,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (isSelected)
                    Icon(Icons.check, size: 14, color: colors.accent),
                ],
              ),
            ),
          );
        }
      }

      showMenu<String>(
        context: context,
        position: RelativeRect.fromLTRB(
          position.dx,
          position.dy + size.height + 2,
          position.dx + size.width,
          position.dy + size.height + 400,
        ),
        constraints: BoxConstraints(
          minWidth: size.width,
          maxWidth: size.width < 280 ? 280 : size.width,
          maxHeight: 380,
        ),
        elevation: 8,
        color: colors.bgSecondary,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: BorderSide(color: colors.borderGlass),
        ),
        items: menuItems,
      ).then((selected) {
        if (selected != null) {
          onChanged(selected);
        }
      });
    }

    final clickable = InkWell(
      borderRadius: BorderRadius.circular(4),
      onTap: openMenu,
      child: IgnorePointer(
        child: formField,
      ),
    );

    if (width != null) {
      return SizedBox(width: width, child: clickable);
    }
    return clickable;
  }
}
