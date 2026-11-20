import 'package:flutter/material.dart';
import '../../services/math_expression_evaluator.dart';
import '../theme/liquid_glass.dart';

Future<String?> showMiniCalculatorDialog({
  required BuildContext context,
  required String initialValue,
  required OpenMoneyColors colors,
}) {
  return showDialog<String>(
    context: context,
    builder: (ctx) => _MiniCalculatorDialog(
      initialValue: initialValue,
      colors: colors,
    ),
  );
}

class _MiniCalculatorDialog extends StatefulWidget {
  final String initialValue;
  final OpenMoneyColors colors;

  const _MiniCalculatorDialog({
    required this.initialValue,
    required this.colors,
  });

  @override
  State<_MiniCalculatorDialog> createState() => _MiniCalculatorDialogState();
}

class _MiniCalculatorDialogState extends State<_MiniCalculatorDialog> {
  late String _expr;
  String _previewResult = '';

  @override
  void initState() {
    super.initState();
    _expr = widget.initialValue.trim();
    _updatePreview();
  }

  void _updatePreview() {
    if (MathExpressionEvaluator.hasMathExpression(_expr)) {
      final res = MathExpressionEvaluator.evaluateToFormatted(_expr);
      _previewResult = res != null ? '= $res' : '';
    } else {
      _previewResult = '';
    }
  }

  void _onPressKey(String key) {
    setState(() {
      if (key == 'C') {
        _expr = '';
        _previewResult = '';
      } else if (key == '⌫') {
        if (_expr.isNotEmpty) {
          _expr = _expr.substring(0, _expr.length - 1);
        }
      } else if (key == '=') {
        final evaluated = MathExpressionEvaluator.evaluateToFormatted(_expr);
        if (evaluated != null) {
          _expr = evaluated;
        }
      } else {
        _expr += key;
      }
      _updatePreview();
    });
  }

  void _onApply() {
    final evaluated = MathExpressionEvaluator.evaluateToFormatted(_expr);
    final finalResult = evaluated ?? _expr.trim();
    Navigator.of(context).pop(finalResult);
  }

  @override
  Widget build(BuildContext context) {
    final colors = widget.colors;
    final keys = [
      ['C', '⌫', '(', ')'],
      ['7', '8', '9', ' / '],
      ['4', '5', '6', ' * '],
      ['1', '2', '3', ' - '],
      ['0', ',', '=', ' + '],
    ];

    return Dialog(
      backgroundColor: colors.bgSecondary,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: colors.borderGlass),
      ),
      child: Container(
        width: 320,
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(Icons.calculate_outlined, size: 20, color: colors.accent),
                    const SizedBox(width: 8),
                    Text(
                      'Calculadora',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: colors.textPrimary,
                      ),
                    ),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () => Navigator.of(context).pop(),
                  tooltip: 'Fechar',
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Display
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: colors.bgPrimary,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: colors.borderGlass),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    _expr.isEmpty ? '0' : _expr,
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: colors.textPrimary,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (_previewResult.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      _previewResult,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: colors.accent,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Keypad
            for (final row in keys) ...[
              Row(
                children: [
                  for (final k in row) ...[
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.all(2.5),
                        child: _buildKeyBtn(k, colors),
                      ),
                    ),
                  ],
                ],
              ),
            ],
            const SizedBox(height: 14),

            // Apply Button
            FilledButton.icon(
              icon: const Icon(Icons.check, size: 18),
              label: const Text('Aplicar Valor'),
              style: FilledButton.styleFrom(
                backgroundColor: colors.accent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              onPressed: _onApply,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildKeyBtn(String key, OpenMoneyColors colors) {
    final displayLabel = key.trim() == '*'
        ? '×'
        : key.trim() == '/'
            ? '÷'
            : key.trim();
    final isOp = ['+', '-', '*', '/', '='].contains(key.trim());
    final isAction = ['C', '⌫'].contains(key.trim());

    final bgColor = isOp
        ? colors.accent.withValues(alpha: 0.15)
        : isAction
            ? colors.bgPrimary
            : colors.bgSecondary;
    final textColor = isOp ? colors.accent : colors.textPrimary;

    return Material(
      color: bgColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: colors.borderGlass),
      ),
      child: InkWell(
        onTap: () => _onPressKey(key),
        borderRadius: BorderRadius.circular(8),
        child: Container(
          height: 38,
          alignment: Alignment.center,
          child: Text(
            displayLabel,
            style: TextStyle(
              fontSize: 15,
              fontWeight: isOp || isAction ? FontWeight.bold : FontWeight.w500,
              color: textColor,
            ),
          ),
        ),
      ),
    );
  }
}
