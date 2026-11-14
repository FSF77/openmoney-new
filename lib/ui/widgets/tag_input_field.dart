import 'package:flutter/material.dart';
import '../theme/liquid_glass.dart';

/// Campo reutilizável de entrada de tags com suporte a chips, vírgula (,), Enter e sugestões.
class TagInputField extends StatefulWidget {
  final List<String> tags;
  final ValueChanged<List<String>> onChanged;
  final List<String> availableTags;
  final OpenMoneyColors colors;
  final String label;
  final String placeholder;

  const TagInputField({
    super.key,
    required this.tags,
    required this.onChanged,
    required this.availableTags,
    required this.colors,
    this.label = 'Tags',
    this.placeholder = 'Digite uma tag e pressione vírgula ou Enter...',
  });

  @override
  State<TagInputField> createState() => _TagInputFieldState();
}

class _TagInputFieldState extends State<TagInputField> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _addTagsFromRaw(String raw) {
    final parts = raw
        .split(',')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    if (parts.isEmpty) return;

    final updated = List<String>.from(widget.tags);
    final existingKeys = updated.map((e) => e.toLowerCase()).toSet();
    bool changed = false;

    for (final part in parts) {
      final key = part.toLowerCase();
      if (existingKeys.add(key)) {
        updated.add(part);
        changed = true;
      }
    }

    if (changed) {
      widget.onChanged(updated);
    }
  }

  void _handleTextChanged(String val) {
    if (!val.contains(',')) {
      setState(() {});
      return;
    }

    final hasTrailingComma = val.endsWith(',');
    final parts = val.split(',');
    if (hasTrailingComma) {
      _addTagsFromRaw(val);
      _controller.clear();
    } else {
      final toCommit = parts.sublist(0, parts.length - 1).join(',');
      final remainder = parts.last;
      _addTagsFromRaw(toCommit);
      _controller.value = TextEditingValue(
        text: remainder,
        selection: TextSelection.collapsed(offset: remainder.length),
      );
    }
    setState(() {});
  }

  void _handleSubmitted(String val) {
    if (val.trim().isNotEmpty) {
      _addTagsFromRaw(val);
      _controller.clear();
      setState(() {});
    }
    _focusNode.requestFocus();
  }

  void _removeTag(String tag) {
    final key = tag.toLowerCase();
    final updated =
        widget.tags.where((t) => t.toLowerCase() != key).toList();
    widget.onChanged(updated);
  }

  void _addSuggestedTag(String tag) {
    _addTagsFromRaw(tag);
    _controller.clear();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.colors;
    final selectedKeys = widget.tags.map((e) => e.toLowerCase()).toSet();
    final query = _controller.text.trim().toLowerCase();

    final suggestions = widget.availableTags
        .where((t) => !selectedKeys.contains(t.toLowerCase()))
        .where((t) => query.isEmpty || t.toLowerCase().contains(query))
        .take(10)
        .toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.label.isNotEmpty) ...[
          Text(
            widget.label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: c.textMuted,
            ),
          ),
          const SizedBox(height: 6),
        ],
        if (widget.tags.isNotEmpty) ...[
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: widget.tags.map((tag) {
              return Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: c.accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: c.accent.withValues(alpha: 0.35),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '#$tag',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: c.accent,
                      ),
                    ),
                    const SizedBox(width: 4),
                    InkWell(
                      onTap: () => _removeTag(tag),
                      borderRadius: BorderRadius.circular(10),
                      child: Icon(
                        Icons.close,
                        size: 14,
                        color: c.accent,
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 8),
        ],
        TextField(
          controller: _controller,
          focusNode: _focusNode,
          onChanged: _handleTextChanged,
          onSubmitted: _handleSubmitted,
          textInputAction: TextInputAction.done,
          style: TextStyle(fontSize: 13, color: c.textPrimary),
          decoration: InputDecoration(
            hintText: widget.placeholder,
            hintStyle: TextStyle(fontSize: 12, color: c.textMuted),
            prefixIcon: Icon(Icons.label_outline, size: 18, color: c.textMuted),
            suffixIcon: _controller.text.trim().isNotEmpty
                ? IconButton(
                    icon: Icon(Icons.add_circle, size: 18, color: c.accent),
                    tooltip: 'Adicionar tag',
                    onPressed: () => _handleSubmitted(_controller.text),
                  )
                : null,
            isDense: true,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            filled: true,
            fillColor: c.bgSecondary,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: c.borderGlass),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: c.borderGlass),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: c.accent, width: 1.5),
            ),
          ),
        ),
        if (suggestions.isNotEmpty) ...[
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: suggestions.map((s) {
              return InkWell(
                onTap: () => _addSuggestedTag(s),
                borderRadius: BorderRadius.circular(14),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: c.bgSecondary,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: c.borderGlass),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.add, size: 12, color: c.textMuted),
                      const SizedBox(width: 3),
                      Text(
                        s,
                        style: TextStyle(fontSize: 11, color: c.textPrimary),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ],
    );
  }
}
