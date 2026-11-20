import 'dart:math' as math;
import 'package:flutter/services.dart';

/// Automatically formats text input as DD/MM/AAAA by inserting '/'
/// after 2 digits and after 4 digits, while smoothly supporting backspace/deletion.
class DateInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    // If text was cleared, keep it empty
    if (newValue.text.isEmpty) {
      return newValue;
    }

    final isDeleting = newValue.text.length < oldValue.text.length;

    // If deleting and ends with slash, drop the slash
    if (isDeleting && oldValue.text.endsWith('/') && newValue.text.length == oldValue.text.length - 1) {
      final stripped = newValue.text.substring(0, math.max(0, newValue.text.length - 1));
      return TextEditingValue(
        text: stripped,
        selection: TextSelection.collapsed(offset: stripped.length),
      );
    }

    // Extract digits only
    final digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    final cappedDigits = digits.substring(0, math.min(8, digits.length));

    final buffer = StringBuffer();
    if (cappedDigits.length <= 2) {
      buffer.write(cappedDigits);
      if (!isDeleting && cappedDigits.length == 2 && newValue.text.length > oldValue.text.length) {
        buffer.write('/');
      }
    } else if (cappedDigits.length <= 4) {
      buffer.write(cappedDigits.substring(0, 2));
      buffer.write('/');
      buffer.write(cappedDigits.substring(2));
      if (!isDeleting && cappedDigits.length == 4 && newValue.text.length > oldValue.text.length) {
        buffer.write('/');
      }
    } else {
      buffer.write(cappedDigits.substring(0, 2));
      buffer.write('/');
      buffer.write(cappedDigits.substring(2, 4));
      buffer.write('/');
      buffer.write(cappedDigits.substring(4));
    }

    final formatted = buffer.toString();
    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }
}
