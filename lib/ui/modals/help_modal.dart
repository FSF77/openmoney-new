import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../services/help_manager.dart';
import '../../store/money_store.dart';
import '../theme/liquid_glass.dart';

/// Abre a modal de Ajuda e Manual Integrado do OpenMoney
Future<void> showHelpModal(BuildContext context, MoneyStore store) async {
  // Garante que o HelpManager esteja inicializado
  if (!HelpManager.instance.isLoaded) {
    await HelpManager.instance.reload();
  }
  if (!context.mounted) return;

  await showDialog(
    context: context,
    builder: (ctx) => _HelpDialog(store: store),
  );
}

class _HelpDialog extends StatefulWidget {
  final MoneyStore store;

  const _HelpDialog({required this.store});

  @override
  State<_HelpDialog> createState() => _HelpDialogState();
}

class _HelpDialogState extends State<_HelpDialog> {
  final TextEditingController _searchController = TextEditingController();
  final HelpManager _manager = HelpManager.instance;
  String _searchText = '';
  String? _selectedSectionId;
  bool _sectionCopiedFeedback = false;

  @override
  void initState() {
    super.initState();
    _manager.addListener(_onManagerUpdated);
    if (_manager.sections.isNotEmpty) {
      _selectedSectionId = _manager.sections.first.id;
    }
  }

  @override
  void dispose() {
    _manager.removeListener(_onManagerUpdated);
    _searchController.dispose();
    super.dispose();
  }

  void _onManagerUpdated() {
    if (mounted) setState(() {});
  }

  List<HelpSection> get _filteredSections {
    final q = _searchText.trim().toLowerCase();
    if (q.isEmpty) return _manager.sections;
    return _manager.sections.where((sec) {
      return sec.title.toLowerCase().contains(q) ||
          sec.parentGroup.toLowerCase().contains(q) ||
          sec.rawMarkdown.toLowerCase().contains(q);
    }).toList();
  }

  HelpSection? get _activeSection {
    final filtered = _filteredSections;
    if (_selectedSectionId != null) {
      final found = _manager.sections.where((s) => s.id == _selectedSectionId);
      if (found.isNotEmpty) return found.first;
    }
    return filtered.isNotEmpty ? filtered.first : null;
  }

  Map<String, List<HelpSection>> get _groupedSections {
    final map = <String, List<HelpSection>>{};
    for (final sec in _filteredSections) {
      map.putIfAbsent(sec.parentGroup, () => []).add(sec);
    }
    return map;
  }

  void _copyActiveSection() {
    final sec = _activeSection;
    if (sec == null) return;
    Clipboard.setData(ClipboardData(text: sec.rawMarkdown));
    setState(() => _sectionCopiedFeedback = true);
    Future.delayed(const Duration(milliseconds: 1500), () {
      if (mounted) setState(() => _sectionCopiedFeedback = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = OpenMoneyColors(widget.store.isDarkMode);
    final size = MediaQuery.of(context).size;
    final isCompact = size.width < 760;

    final dialogWidth = (size.width * 0.92).clamp(700.0, 1100.0);
    final dialogHeight = (size.height * 0.88).clamp(520.0, 800.0);

    return Dialog(
      backgroundColor: colors.bgSecondary,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colors.borderGlass),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: SizedBox(
          width: isCompact ? double.infinity : dialogWidth,
          height: isCompact ? double.infinity : dialogHeight,
          child: Column(
            children: [
              _buildHeader(colors),
              _buildBreadcrumbBar(colors),
              Expanded(
                child: isCompact
                    ? _buildCompactBody(colors)
                    : _buildSplitBody(colors),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // MARK: - Header Bar

  Widget _buildHeader(OpenMoneyColors colors) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      decoration: BoxDecoration(
        color: colors.surfaceCard,
        border: Border(bottom: BorderSide(color: colors.borderGlass)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: colors.accent.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(Icons.help_outline, color: colors.accent, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Ajuda e Manual do OpenMoney',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: colors.textPrimary,
                  ),
                ),
                Text(
                  'Guia completo de uso, regras de governança e atalhos',
                  style: TextStyle(
                    fontSize: 11,
                    color: colors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              visualDensity: VisualDensity.compact,
              side: BorderSide(color: colors.borderGlass),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            ),
            icon: const Icon(Icons.refresh, size: 14),
            label: const Text('Recarregar', style: TextStyle(fontSize: 11)),
            onPressed: () async {
              await _manager.reload();
              if (!mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Manual do OpenMoney recarregado.'),
                  duration: Duration(seconds: 2),
                ),
              );
            },
          ),
          const SizedBox(width: 8),
          OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              visualDensity: VisualDensity.compact,
              side: BorderSide(color: colors.borderGlass),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            ),
            icon: Icon(
              _sectionCopiedFeedback ? Icons.check : Icons.copy,
              size: 14,
              color: _sectionCopiedFeedback ? colors.income : null,
            ),
            label: Text(
              _sectionCopiedFeedback ? 'Copiado!' : 'Copiar Seção',
              style: TextStyle(
                fontSize: 11,
                color: _sectionCopiedFeedback ? colors.income : null,
              ),
            ),
            onPressed: _copyActiveSection,
          ),
          const SizedBox(width: 8),
          IconButton(
            tooltip: 'Fechar (Esc)',
            icon: Icon(Icons.close, size: 20, color: colors.textSecondary),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  // MARK: - Breadcrumb Subheader

  Widget _buildBreadcrumbBar(OpenMoneyColors colors) {
    final active = _activeSection;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
      decoration: BoxDecoration(
        color: colors.surfaceGlass,
        border: Border(bottom: BorderSide(color: colors.borderGlass)),
      ),
      child: Row(
        children: [
          Icon(Icons.menu_book, size: 13, color: colors.textSecondary),
          const SizedBox(width: 6),
          Text(
            'Manual Integrado OpenMoney',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w500,
              color: colors.textSecondary,
            ),
          ),
          if (active != null) ...[
            Text(
              '  ›  ',
              style: TextStyle(fontSize: 11, color: colors.textMuted),
            ),
            Text(
              active.parentGroup,
              style: TextStyle(fontSize: 11, color: colors.textSecondary),
            ),
            Text(
              '  ›  ',
              style: TextStyle(fontSize: 11, color: colors.textMuted),
            ),
            Expanded(
              child: Text(
                active.cleanTitle,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: colors.accent,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // MARK: - Split Master-Detail Layout (Desktop)

  Widget _buildSplitBody(OpenMoneyColors colors) {
    return Row(
      children: [
        // Sidebar Esquerda com Lista de Seções
        SizedBox(
          width: 300,
          child: Container(
            decoration: BoxDecoration(
              color: colors.bgPrimary,
              border: Border(right: BorderSide(color: colors.borderGlass)),
            ),
            child: Column(
              children: [
                _buildSearchField(colors),
                Divider(height: 1, color: colors.borderGlass),
                Expanded(child: _buildSectionsList(colors)),
              ],
            ),
          ),
        ),

        // Área de Conteúdo à Direita
        Expanded(
          child: Container(
            color: colors.bgSecondary,
            child: _buildDetailContent(colors),
          ),
        ),
      ],
    );
  }

  // MARK: - Compact Layout (Mobile / Small Window)

  Widget _buildCompactBody(OpenMoneyColors colors) {
    if (_selectedSectionId == null) {
      return Column(
        children: [
          _buildSearchField(colors),
          Divider(height: 1, color: colors.borderGlass),
          Expanded(child: _buildSectionsList(colors)),
        ],
      );
    }
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          color: colors.surfaceGlass,
          child: Row(
            children: [
              TextButton.icon(
                icon: const Icon(Icons.arrow_back, size: 16),
                label: const Text('Lista de Tópicos'),
                onPressed: () => setState(() => _selectedSectionId = null),
              ),
            ],
          ),
        ),
        Divider(height: 1, color: colors.borderGlass),
        Expanded(child: _buildDetailContent(colors)),
      ],
    );
  }

  // MARK: - Search Field

  Widget _buildSearchField(OpenMoneyColors colors) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: Container(
        height: 38,
        decoration: BoxDecoration(
          color: colors.surfaceCard,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: colors.borderGlass),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Row(
          children: [
            Icon(Icons.search, size: 18, color: colors.textSecondary),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _searchController,
                style: TextStyle(fontSize: 12, color: colors.textPrimary),
                decoration: InputDecoration(
                  hintText: 'Buscar tópicos ou regras...',
                  hintStyle: TextStyle(fontSize: 12, color: colors.textMuted),
                  border: InputBorder.none,
                  isDense: true,
                ),
                onChanged: (val) {
                  setState(() => _searchText = val);
                },
              ),
            ),
            if (_searchText.isNotEmpty)
              GestureDetector(
                onTap: () {
                  _searchController.clear();
                  setState(() => _searchText = '');
                },
                child: Icon(Icons.cancel, size: 16, color: colors.textSecondary),
              ),
          ],
        ),
      ),
    );
  }

  // MARK: - Sections List (Grouped)

  Widget _buildSectionsList(OpenMoneyColors colors) {
    final grouped = _groupedSections;

    if (grouped.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Text(
            'Nenhum tópico encontrado.',
            style: TextStyle(color: colors.textMuted, fontSize: 12),
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      children: [
        for (final entry in grouped.entries) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
            child: Text(
              entry.key.toUpperCase(),
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.6,
                color: colors.textMuted,
              ),
            ),
          ),
          for (final sec in entry.value) ...[
            _buildSectionTile(sec, colors),
          ],
        ],
      ],
    );
  }

  Widget _buildSectionTile(HelpSection sec, OpenMoneyColors colors) {
    final isSelected = (_activeSection?.id == sec.id);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Material(
        color: isSelected ? colors.accent.withValues(alpha: 0.18) : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () {
            setState(() => _selectedSectionId = sec.id);
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: isSelected ? colors.accent.withValues(alpha: 0.45) : Colors.transparent,
                width: 1,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  sec.icon,
                  size: 16,
                  color: isSelected ? colors.accent : colors.textSecondary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    sec.cleanTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                      color: isSelected ? colors.accent : colors.textPrimary,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // MARK: - Detail Content View

  Widget _buildDetailContent(OpenMoneyColors colors) {
    final sec = _activeSection;

    if (sec == null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.search_off, size: 48, color: colors.textMuted),
            const SizedBox(height: 12),
            Text(
              'Nenhum tópico encontrado para "$_searchText".',
              style: TextStyle(fontSize: 14, color: colors.textSecondary),
            ),
          ],
        ),
      );
    }

    return SelectionArea(
      child: ListView(
        padding: const EdgeInsets.all(28),
        children: [
          // Section Title Header
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: colors.accent.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(sec.icon, size: 24, color: colors.accent),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      sec.cleanTitle,
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: colors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: colors.surfaceGlass,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: colors.borderGlass),
                      ),
                      child: Text(
                        sec.parentGroup,
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: colors.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Divider(color: colors.borderGlass),
          const SizedBox(height: 16),

          // Blocks List
          for (final block in sec.blocks) ...[
            _HelpBlockWidget(block: block, colors: colors),
            const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}

// MARK: - Block Renderer Widget

class _HelpBlockWidget extends StatefulWidget {
  final MarkdownBlock block;
  final OpenMoneyColors colors;

  const _HelpBlockWidget({
    required this.block,
    required this.colors,
  });

  @override
  State<_HelpBlockWidget> createState() => _HelpBlockWidgetState();
}

class _HelpBlockWidgetState extends State<_HelpBlockWidget> {
  bool _copied = false;

  void _copyCode(String code) {
    Clipboard.setData(ClipboardData(text: code));
    setState(() => _copied = true);
    Future.delayed(const Duration(milliseconds: 1500), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final block = widget.block;
    final colors = widget.colors;

    if (block is HeadingBlock) {
      final double fontSize;
      final FontWeight weight;
      final Color color;

      switch (block.level) {
        case 1:
          fontSize = 18;
          weight = FontWeight.bold;
          color = colors.textPrimary;
          break;
        case 2:
          fontSize = 16;
          weight = FontWeight.bold;
          color = colors.textPrimary;
          break;
        case 3:
          fontSize = 14;
          weight = FontWeight.w600;
          color = colors.accent;
          break;
        default:
          fontSize = 13;
          weight = FontWeight.w600;
          color = colors.textSecondary;
      }

      return Padding(
        padding: EdgeInsets.only(top: block.level <= 2 ? 14 : 6, bottom: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              block.text,
              style: TextStyle(
                fontSize: fontSize,
                fontWeight: weight,
                color: color,
              ),
            ),
            if (block.level <= 2) ...[
              const SizedBox(height: 4),
              Divider(color: colors.borderGlass),
            ],
          ],
        ),
      );
    }

    if (block is ParagraphBlock) {
      return Text.rich(
        _buildRichSpans(block.text, colors),
        style: TextStyle(
          fontSize: 13,
          height: 1.5,
          color: colors.textPrimary,
        ),
      );
    }

    if (block is BulletBlock) {
      return Padding(
        padding: const EdgeInsets.only(left: 6, top: 2, bottom: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '•',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: colors.accent,
                height: 1.2,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text.rich(
                _buildRichSpans(block.text, colors),
                style: TextStyle(
                  fontSize: 13,
                  height: 1.45,
                  color: colors.textPrimary,
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (block is NumberedBlock) {
      return Padding(
        padding: const EdgeInsets.only(left: 4, top: 2, bottom: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
              decoration: BoxDecoration(
                color: colors.accent.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                block.num,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  fontFamily: 'monospace',
                  color: colors.accent,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text.rich(
                _buildRichSpans(block.text, colors),
                style: TextStyle(
                  fontSize: 13,
                  height: 1.45,
                  color: colors.textPrimary,
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (block is CodeBlock) {
      return Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        decoration: BoxDecoration(
          color: colors.surfaceCard,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: colors.borderGlass),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Code header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: colors.surfaceGlass,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(8)),
                border: Border(bottom: BorderSide(color: colors.borderGlass)),
              ),
              child: Row(
                children: [
                  Text(
                    block.lang.isEmpty ? 'CÓDIGO' : block.lang.toUpperCase(),
                    style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.8,
                      fontFamily: 'monospace',
                      color: colors.textMuted,
                    ),
                  ),
                  const Spacer(),
                  InkWell(
                    borderRadius: BorderRadius.circular(4),
                    onTap: () => _copyCode(block.code),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _copied ? Icons.check : Icons.copy,
                            size: 12,
                            color: _copied ? colors.income : colors.accent,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _copied ? 'Copiado' : 'Copiar',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: _copied ? colors.income : colors.accent,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Code text
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.all(12),
              child: Text(
                block.code,
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                  height: 1.4,
                  color: colors.textPrimary,
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (block is QuoteBlock) {
      return Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: colors.accent.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(6),
          border: Border(
            left: BorderSide(color: colors.accent, width: 3),
          ),
        ),
        child: Text.rich(
          _buildRichSpans(block.text, colors, isItalic: true),
          style: TextStyle(
            fontSize: 12,
            height: 1.45,
            color: colors.textPrimary,
          ),
        ),
      );
    }

    if (block is DividerBlock) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Divider(color: colors.borderGlass),
      );
    }

    if (block is ImageBlock) {
      return Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: colors.surfaceGlass,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: colors.borderGlass),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.image_outlined, size: 20, color: colors.textSecondary),
            const SizedBox(width: 8),
            Text(
              block.alt.isNotEmpty ? block.alt : block.src,
              style: TextStyle(fontSize: 12, color: colors.textSecondary),
            ),
          ],
        ),
      );
    }

    return const SizedBox.shrink();
  }

  // MARK: - Rich Inline Formatter (**bold**, *italic*, `code`)

  TextSpan _buildRichSpans(
    String text,
    OpenMoneyColors colors, {
    bool isItalic = false,
  }) {
    final spans = <InlineSpan>[];
    final pattern = RegExp(r'(\*\*[^*]+\*\*|\*[^*]+\*|`[^`]+`)');
    int lastMatchEnd = 0;

    for (final match in pattern.allMatches(text)) {
      if (match.start > lastMatchEnd) {
        spans.add(
          TextSpan(
            text: text.substring(lastMatchEnd, match.start),
            style: TextStyle(
              fontStyle: isItalic ? FontStyle.italic : FontStyle.normal,
            ),
          ),
        );
      }

      final token = match.group(0)!;
      if (token.startsWith('**') && token.endsWith('**')) {
        spans.add(
          TextSpan(
            text: token.substring(2, token.length - 2),
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontStyle: isItalic ? FontStyle.italic : FontStyle.normal,
              color: colors.textPrimary,
            ),
          ),
        );
      } else if (token.startsWith('*') && token.endsWith('*')) {
        spans.add(
          TextSpan(
            text: token.substring(1, token.length - 1),
            style: const TextStyle(fontStyle: FontStyle.italic),
          ),
        );
      } else if (token.startsWith('`') && token.endsWith('`')) {
        spans.add(
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              margin: const EdgeInsets.symmetric(horizontal: 2),
              decoration: BoxDecoration(
                color: colors.surfaceGlass,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(color: colors.borderGlass),
              ),
              child: Text(
                token.substring(1, token.length - 1),
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: colors.accent,
                ),
              ),
            ),
          ),
        );
      }

      lastMatchEnd = match.end;
    }

    if (lastMatchEnd < text.length) {
      spans.add(
        TextSpan(
          text: text.substring(lastMatchEnd),
          style: TextStyle(
            fontStyle: isItalic ? FontStyle.italic : FontStyle.normal,
          ),
        ),
      );
    }

    return TextSpan(children: spans);
  }
}
