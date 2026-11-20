import '../models/openmoney_models.dart';

class MathExpressionEvaluator {
  /// Checks whether the string contains any mathematical operation symbols (+, -, *, x, /, ÷)
  /// beyond a simple leading negative sign.
  static bool hasMathExpression(String input) {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return false;

    // Remove leading sign if any
    final withoutLeading = trimmed.startsWith('-') || trimmed.startsWith('+')
        ? trimmed.substring(1)
        : trimmed;

    return withoutLeading.contains('+') ||
        withoutLeading.contains('-') ||
        withoutLeading.contains('*') ||
        withoutLeading.contains('x') ||
        withoutLeading.contains('X') ||
        withoutLeading.contains('/') ||
        withoutLeading.contains('÷');
  }

  /// Evaluates a math expression string and returns the result as double, or null if invalid.
  static double? evaluate(String input) {
    if (input.trim().isEmpty) return null;

    try {
      // 1. Normalize characters
      var expr = input
          .replaceAll(' ', '')
          .replaceAll('X', '*')
          .replaceAll('x', '*')
          .replaceAll('÷', '/');

      // Filter out currency symbols if present
      expr = expr.replaceAll(RegExp(r'[R$€£US]+', caseSensitive: false), '');

      // 2. Tokenize with support for both comma and dot decimals
      final tokens = _tokenize(expr);
      if (tokens.isEmpty) return null;

      // 3. Parse with operator precedence
      final parser = _Parser(tokens);
      final result = parser.parseExpression();
      if (!result.isFinite || result.isNaN) return null;
      return result;
    } catch (_) {
      return null;
    }
  }

  /// Evaluates the expression and formats it as a currency input string (e.g. "25,50"),
  /// or returns null if not an evaluatable expression.
  static String? evaluateToFormatted(String input) {
    if (!hasMathExpression(input)) return null;
    final val = evaluate(input);
    if (val == null) return null;
    final cents = (val * 100).round();
    return formatInputCents(cents);
  }

  static List<_Token> _tokenize(String expr) {
    final tokens = <_Token>[];
    int i = 0;

    while (i < expr.length) {
      final ch = expr[i];

      if (ch == '+' || ch == '-' || ch == '*' || ch == '/' || ch == '(' || ch == ')') {
        tokens.add(_Token(ch == '+'
            ? _TokenType.plus
            : ch == '-'
                ? _TokenType.minus
                : ch == '*'
                    ? _TokenType.multiply
                    : ch == '/'
                        ? _TokenType.divide
                        : ch == '('
                            ? _TokenType.lParen
                            : _TokenType.rParen));
        i++;
        continue;
      }

      // Read number: digits, dots, commas
      if (_isDigit(ch) || ch == '.' || ch == ',') {
        final start = i;
        while (i < expr.length && (_isDigit(expr[i]) || expr[i] == '.' || expr[i] == ',')) {
          i++;
        }
        final rawNum = expr.substring(start, i);
        final numVal = _parseNumber(rawNum);
        if (numVal == null) throw FormatException('Invalid number: $rawNum');
        tokens.add(_Token(_TokenType.number, numVal));
        continue;
      }

      // Skip unexpected char
      i++;
    }

    return tokens;
  }

  static bool _isDigit(String s) => s.codeUnitAt(0) >= 48 && s.codeUnitAt(0) <= 57;

  static double? _parseNumber(String raw) {
    var s = raw.trim();
    if (s.isEmpty) return null;

    if (s.contains(',') && s.contains('.')) {
      // e.g. 1.250,50 or 1,250.50
      final lastComma = s.lastIndexOf(',');
      final lastDot = s.lastIndexOf('.');
      if (lastComma > lastDot) {
        // Brazilian format: 1.250,50
        s = s.replaceAll('.', '').replaceAll(',', '.');
      } else {
        // US format: 1,250.50
        s = s.replaceAll(',', '');
      }
    } else if (s.contains(',')) {
      // e.g. 10,50
      s = s.replaceAll(',', '.');
    }

    return double.tryParse(s);
  }
}

enum _TokenType { number, plus, minus, multiply, divide, lParen, rParen }

class _Token {
  final _TokenType type;
  final double value;

  _Token(this.type, [this.value = 0.0]);
}

class _Parser {
  final List<_Token> tokens;
  int _pos = 0;

  _Parser(this.tokens);

  _Token get _current => _pos < tokens.length ? tokens[_pos] : _Token(_TokenType.plus);

  double parseExpression() {
    double value = _parseTerm();

    while (_pos < tokens.length) {
      if (_current.type == _TokenType.plus) {
        _pos++;
        value += _parseTerm();
      } else if (_current.type == _TokenType.minus) {
        _pos++;
        value -= _parseTerm();
      } else {
        break;
      }
    }

    return value;
  }

  double _parseTerm() {
    double value = _parseFactor();

    while (_pos < tokens.length) {
      if (_current.type == _TokenType.multiply) {
        _pos++;
        value *= _parseFactor();
      } else if (_current.type == _TokenType.divide) {
        _pos++;
        final divisor = _parseFactor();
        if (divisor == 0) throw Exception('Division by zero');
        value /= divisor;
      } else {
        break;
      }
    }

    return value;
  }

  double _parseFactor() {
    if (_pos >= tokens.length) throw FormatException('Unexpected end of expression');

    // Unary plus/minus
    if (_current.type == _TokenType.minus) {
      _pos++;
      return -_parseFactor();
    }
    if (_current.type == _TokenType.plus) {
      _pos++;
      return _parseFactor();
    }

    if (_current.type == _TokenType.number) {
      final val = _current.value;
      _pos++;
      return val;
    }

    if (_current.type == _TokenType.lParen) {
      _pos++;
      final val = parseExpression();
      if (_pos < tokens.length && _current.type == _TokenType.rParen) {
        _pos++;
      }
      return val;
    }

    throw FormatException('Unexpected token: ${_current.type}');
  }
}
