import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../../models/openmoney_models.dart';
import '../../services/bank_logo_registry.dart';
import '../../services/category_icon_registry.dart';
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
  final bool allowTransfers;

  const CategorySelectFormField({
    super.key,
    required this.store,
    required this.categoryType,
    required this.currentSelection,
    this.excludeAccountId,
    required this.onChanged,
    this.labelText = 'Categoria / Transferência',
    this.width,
    this.allowTransfers = true,
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
      if (top.isBlocked) continue;
      final subs = store.subCategories(top.name, type: categoryType)
          .where((s) => !s.isBlocked)
          .toList();
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

    // Contas ativas para transferência (ordenadas com Favoritas primeiro e depois Ativas)
    final transferAccounts = allowTransfers
        ? store.transferDestinationAccounts(excludeId: excludeAccountId)
        : <Account>[];

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
          child: Row(
            children: [
              if (currentSelection.startsWith('xfer:')) ...[
                Builder(
                  builder: (_) {
                    final xferAcc =
                        store.accById(currentSelection.substring(5));
                    if (xferAcc != null) {
                      return AccountLogoWidget(
                        account: xferAcc,
                        size: 18,
                        cornerRadius: 4,
                      );
                    }
                    return Icon(
                      Icons.swap_horiz_rounded,
                      size: 16,
                      color: colors.accent,
                    );
                  },
                ),
                const SizedBox(width: 8),
              ] else if (currentSelection.isNotEmpty) ...[
                CategoryIconBadge(
                  store: store,
                  categoryPath: currentSelection,
                  fallbackType: categoryType,
                  size: 18,
                  borderRadius: 5,
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
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
          ),
        ),
      ],
      onChanged: (_) {},
    );

    void openMenu() {
      final RenderBox box = context.findRenderObject()! as RenderBox;
      final Offset position = box.localToGlobal(Offset.zero);
      final size = box.size;
      final screen = MediaQuery.sizeOf(context);
      final isMobile = screen.width < 600;

      final groups = <({CategoryItem top, List<CategoryItem> subs})>[];
      for (final top in store.topCategories(type: categoryType)) {
        if (top.isBlocked) continue;
        final subs = store
            .subCategories(top.name, type: categoryType)
            .where((s) => !s.isBlocked)
            .toList();
        groups.add((top: top, subs: subs));
      }

      showGeneralDialog<String>(
        context: context,
        barrierDismissible: true,
        barrierLabel: 'Fechar seletor de categoria',
        barrierColor: isMobile ? Colors.black45 : Colors.transparent,
        transitionDuration: const Duration(milliseconds: 120),
        pageBuilder: (dialogCtx, _, __) {
          final popup = _CategorySearchPopup(
            store: store,
            colors: colors,
            categoryType: categoryType,
            currentSelection: currentSelection,
            groups: groups,
            transferAccounts: transferAccounts,
          );

          if (isMobile) {
            return AnimatedPadding(
              duration: const Duration(milliseconds: 100),
              padding: EdgeInsets.only(
                left: 16,
                right: 16,
                top: 24,
                bottom: math.max(24, MediaQuery.viewInsetsOf(dialogCtx).bottom + 12),
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: 420,
                    maxHeight: screen.height * 0.72,
                  ),
                  child: popup,
                ),
              ),
            );
          }

          final double popupWidth = (size.width < 300 ? 300.0 : size.width)
              .clamp(280.0, math.min(420.0, screen.width - 16.0))
              .toDouble();
          final double left = position.dx
              .clamp(8.0, math.max(8.0, screen.width - popupWidth - 8.0))
              .toDouble();

          final spaceBelow = screen.height - (position.dy + size.height + 2) - 8.0;
          final spaceAbove = position.dy - 8.0;
          final openAbove = spaceBelow < 260 && spaceAbove > spaceBelow;
          final availableVertical = openAbove ? spaceAbove : spaceBelow;
          final double maxHeight =
              math.min(400.0, availableVertical - 12.0).clamp(180.0, 400.0).toDouble();

          final topPos = openAbove
              ? math.max(8.0, position.dy - maxHeight - 2)
              : position.dy + size.height + 2;

          return Stack(
            children: [
              Positioned(
                left: left,
                top: topPos,
                width: popupWidth,
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: maxHeight),
                  child: popup,
                ),
              ),
            ],
          );
        },
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

String _normalizeSearch(String input) {
  final lower = input.toLowerCase();
  const accents = 'áàâãäéèêëíìîïóòôõöúùûüç';
  const plain = 'aaaaaeeeeiiiiooooouuuuc';
  final sb = StringBuffer();
  for (int i = 0; i < lower.length; i++) {
    final ch = lower[i];
    final idx = accents.indexOf(ch);
    sb.write(idx >= 0 ? plain[idx] : ch);
  }
  return sb.toString();
}

sealed class _PopupEntry {}

class _CategoryEntry extends _PopupEntry {
  final String label;
  final String value;
  final bool isHeader;
  final bool isSub;

  _CategoryEntry({
    required this.label,
    required this.value,
    required this.isHeader,
    required this.isSub,
  });
}

class _DividerEntry extends _PopupEntry {}

class _TransferEntry extends _PopupEntry {
  final Account account;

  _TransferEntry(this.account);
}

class _CategorySearchPopup extends StatefulWidget {
  final MoneyStore store;
  final OpenMoneyColors colors;
  final String categoryType;
  final String currentSelection;
  final List<({CategoryItem top, List<CategoryItem> subs})> groups;
  final List<Account> transferAccounts;

  const _CategorySearchPopup({
    required this.store,
    required this.colors,
    required this.categoryType,
    required this.currentSelection,
    required this.groups,
    required this.transferAccounts,
  });

  @override
  State<_CategorySearchPopup> createState() => _CategorySearchPopupState();
}

class _CategorySearchPopupState extends State<_CategorySearchPopup> {
  final TextEditingController _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  ({List<_PopupEntry> entries, String? firstMatchValue}) _buildFiltered() {
    final normQuery = _normalizeSearch(_query.trim());
    final entries = <_PopupEntry>[];
    String? firstMatchValue;

    for (final g in widget.groups) {
      if (normQuery.isEmpty) {
        entries.add(_CategoryEntry(
          label: g.top.name,
          value: g.top.path,
          isHeader: g.subs.isNotEmpty,
          isSub: false,
        ));
        firstMatchValue ??= g.top.path;
        for (final sub in g.subs) {
          entries.add(_CategoryEntry(
            label: '↳ ${sub.name}',
            value: sub.path,
            isHeader: false,
            isSub: true,
          ));
        }
      } else {
        final topMatches = _normalizeSearch(g.top.name).contains(normQuery) ||
            _normalizeSearch(g.top.path).contains(normQuery);
        if (topMatches) {
          entries.add(_CategoryEntry(
            label: g.top.name,
            value: g.top.path,
            isHeader: g.subs.isNotEmpty,
            isSub: false,
          ));
          firstMatchValue ??= g.top.path;
          for (final sub in g.subs) {
            entries.add(_CategoryEntry(
              label: '↳ ${sub.name}',
              value: sub.path,
              isHeader: false,
              isSub: true,
            ));
          }
        } else {
          final matchingSubs = g.subs
              .where((s) =>
                  _normalizeSearch(s.name).contains(normQuery) ||
                  _normalizeSearch(s.path).contains(normQuery))
              .toList();
          if (matchingSubs.isNotEmpty) {
            entries.add(_CategoryEntry(
              label: g.top.name,
              value: g.top.path,
              isHeader: true,
              isSub: false,
            ));
            for (final sub in matchingSubs) {
              entries.add(_CategoryEntry(
                label: '↳ ${sub.name}',
                value: sub.path,
                isHeader: false,
                isSub: true,
              ));
              firstMatchValue ??= sub.path;
            }
          }
        }
      }
    }

    final matchingTransfers = normQuery.isEmpty
        ? widget.transferAccounts
        : widget.transferAccounts
            .where((a) =>
                _normalizeSearch(a.name).contains(normQuery) ||
                'transferencia'.contains(normQuery))
            .toList();

    if (matchingTransfers.isNotEmpty) {
      if (entries.isNotEmpty) {
        entries.add(_DividerEntry());
      }
      for (final a in matchingTransfers) {
        entries.add(_TransferEntry(a));
        firstMatchValue ??= 'xfer:${a.id}';
      }
    }

    return (entries: entries, firstMatchValue: firstMatchValue);
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.colors;
    final filtered = _buildFiltered();

    return Material(
      color: c.bgSecondary,
      elevation: 8,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: c.borderGlass),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 10, 6),
            child: TextField(
              controller: _searchCtrl,
              autofocus: true,
              style: TextStyle(fontSize: 12.5, color: c.textPrimary),
              decoration: InputDecoration(
                isDense: true,
                hintText: 'Pesquisar categoria...',
                hintStyle: TextStyle(fontSize: 12, color: c.textMuted),
                prefixIcon: Icon(Icons.search, size: 16, color: c.textMuted),
                prefixIconConstraints:
                    const BoxConstraints(minWidth: 32, minHeight: 30),
                suffixIcon: _query.isNotEmpty
                    ? IconButton(
                        icon: Icon(Icons.close, size: 15, color: c.textMuted),
                        padding: EdgeInsets.zero,
                        constraints:
                            const BoxConstraints(minWidth: 28, minHeight: 28),
                        onPressed: () {
                          _searchCtrl.clear();
                          setState(() => _query = '');
                        },
                      )
                    : null,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: BorderSide(color: c.borderGlass),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: BorderSide(color: c.borderGlass),
                ),
              ),
              onChanged: (val) => setState(() => _query = val),
              onSubmitted: (_) {
                if (filtered.firstMatchValue != null) {
                  Navigator.of(context).pop(filtered.firstMatchValue);
                }
              },
            ),
          ),
          Divider(height: 1, color: c.borderGlass),
          Flexible(
            child: filtered.entries.isEmpty
                ? Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 20),
                    child: Text(
                      'Nenhuma categoria encontrada',
                      style: TextStyle(fontSize: 12.5, color: c.textMuted),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    shrinkWrap: true,
                    itemCount: filtered.entries.length,
                    itemBuilder: (ctx, idx) {
                      final entry = filtered.entries[idx];
                      if (entry is _DividerEntry) {
                        return Divider(height: 10, color: c.borderGlass);
                      }
                      if (entry is _TransferEntry) {
                        final a = entry.account;
                        final val = 'xfer:${a.id}';
                        final isSelected = val == widget.currentSelection;
                        return InkWell(
                          onTap: () => Navigator.of(context).pop(val),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 6),
                            child: Row(
                              children: [
                                AccountLogoWidget(
                                  account: a,
                                  size: 18,
                                  cornerRadius: 4,
                                  selected: isSelected,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    '⇄ Transferência: ${a.name}',
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: isSelected
                                          ? FontWeight.w700
                                          : FontWeight.w400,
                                      color: isSelected
                                          ? c.accent
                                          : c.textPrimary,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (isSelected)
                                  Icon(Icons.check, size: 14, color: c.accent),
                              ],
                            ),
                          ),
                        );
                      }

                      final cat = entry as _CategoryEntry;
                      final isSelected = cat.value == widget.currentSelection;
                      if (cat.isHeader) {
                        return InkWell(
                          onTap: () => Navigator.of(context).pop(cat.value),
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(12, 6, 12, 4),
                            child: Row(
                              children: [
                                CategoryIconBadge(
                                  store: widget.store,
                                  categoryPath: cat.value,
                                  fallbackType: widget.categoryType,
                                  size: 20,
                                  borderRadius: 6,
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    cat.label,
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w800,
                                      color: isSelected
                                          ? c.accent
                                          : c.textPrimary,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                if (isSelected)
                                  Icon(Icons.check, size: 14, color: c.accent),
                              ],
                            ),
                          ),
                        );
                      }

                      return InkWell(
                        onTap: () => Navigator.of(context).pop(cat.value),
                        child: Padding(
                          padding: EdgeInsets.fromLTRB(
                              cat.isSub ? 24 : 12, 5, 12, 5),
                          child: Row(
                            children: [
                              CategoryIconBadge(
                                store: widget.store,
                                categoryPath: cat.value,
                                fallbackType: widget.categoryType,
                                size: cat.isSub ? 16 : 18,
                                borderRadius: 5,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  cat.label,
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: isSelected
                                        ? FontWeight.w700
                                        : FontWeight.w400,
                                    color:
                                        isSelected ? c.accent : c.textPrimary,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (isSelected)
                                Icon(Icons.check, size: 14, color: c.accent),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
