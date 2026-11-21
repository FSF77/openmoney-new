import 'dart:math' as math;
import 'package:flutter/services.dart';

/// Automatically formats text input as DD/MM/AAAA by inserting '/'
/// after 2 digits and after 4 digits, prevents invalid calendar numbers,
/// and smoothly supports backspace/deletion.
class DateInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (newValue.text.isEmpty) {
      return newValue;
    }

    final isDeleting = newValue.text.length < oldValue.text.length;

    // If deleting and ends with slash, drop the slash smoothly
    if (isDeleting && oldValue.text.endsWith('/') && newValue.text.length == oldValue.text.length - 1) {
      final stripped = newValue.text.substring(0, math.max(0, newValue.text.length - 1));
      return TextEditingValue(
        text: stripped,
        selection: TextSelection.collapsed(offset: stripped.length),
      );
    }

    final digits = newValue.text.replaceAll(RegExp(r'\D'), '');
    if (digits.isEmpty) {
      return const TextEditingValue(text: '', selection: TextSelection.collapsed(offset: 0));
    }

    final cappedDigits = digits.substring(0, math.min(8, digits.length));

    // When deleting, format digits into DD/MM/YYYY without clamping to allow easy correction
    if (isDeleting) {
      final buffer = StringBuffer();
      if (cappedDigits.length <= 2) {
        buffer.write(cappedDigits);
      } else if (cappedDigits.length <= 4) {
        buffer.write(cappedDigits.substring(0, 2));
        buffer.write('/');
        buffer.write(cappedDigits.substring(2));
      } else {
        buffer.write(cappedDigits.substring(0, 2));
        buffer.write('/');
        buffer.write(cappedDigits.substring(2, 4));
        buffer.write('/');
        buffer.write(cappedDigits.substring(4));
      }
      final res = buffer.toString();
      return TextEditingValue(
        text: res,
        selection: TextSelection.collapsed(offset: res.length),
      );
    }

    // When typing: validate and format
    if (cappedDigits.length == 1) {
      final d1 = int.parse(cappedDigits[0]);
      if (d1 > 3) {
        // e.g. User types '5' -> auto-pad to '05/'
        return const TextEditingValue(
          text: '0',
          selection: TextSelection.collapsed(offset: 1),
        );
      }
      return TextEditingValue(
        text: cappedDigits,
        selection: TextSelection.collapsed(offset: cappedDigits.length),
      );
    }

    // 2 digits (Day)
    var day = int.parse(cappedDigits.substring(0, 2));
    if (day > 31) day = 31;
    if (day == 0) day = 1;
    final dayStr = day.toString().padLeft(2, '0');

    if (cappedDigits.length == 2) {
      final res = '$dayStr/';
      return TextEditingValue(
        text: res,
        selection: TextSelection.collapsed(offset: res.length),
      );
    }

    // 3 digits (Day + first digit of Month)
    if (cappedDigits.length == 3) {
      final m1 = int.parse(cappedDigits[2]);
      if (m1 > 1) {
        // e.g. Day is 15 and user types 7 -> auto pad month to 07/
        var validDay = day;
        if (m1 == 2 && validDay > 29) validDay = 29;
        if ([4, 6, 9, 11].contains(m1) && validDay > 30) validDay = 30;
        final res = '${validDay.toString().padLeft(2, '0')}/0$m1/';
        return TextEditingValue(
          text: res,
          selection: TextSelection.collapsed(offset: res.length),
        );
      }
      final res = '$dayStr/${cappedDigits[2]}';
      return TextEditingValue(
        text: res,
        selection: TextSelection.collapsed(offset: res.length),
      );
    }

    // 4 digits (Day + Month)
    var month = int.parse(cappedDigits.substring(2, 4));
    if (month > 12) month = 12;
    if (month == 0) month = 1;

    var validDay = day;
    if (month == 2 && validDay > 29) validDay = 29;
    if ([4, 6, 9, 11].contains(month) && validDay > 30) validDay = 30;
    final validDayStr = validDay.toString().padLeft(2, '0');
    final monthStr = month.toString().padLeft(2, '0');

    if (cappedDigits.length == 4) {
      final res = '$validDayStr/$monthStr/';
      return TextEditingValue(
        text: res,
        selection: TextSelection.collapsed(offset: res.length),
      );
    }

    // 5 to 8 digits (Day + Month + Year)
    final yDigits = cappedDigits.substring(4);
    if (yDigits.length == 4) {
      final y = int.parse(yDigits);
      final dt = DateTime(y, month, validDay);
      if (dt.month != month) {
        // February 29 on non-leap year
        validDay = 28;
      }
    }

    final finalDayStr = validDay.toString().padLeft(2, '0');
    final res = '$finalDayStr/$monthStr/$yDigits';
    return TextEditingValue(
      text: res,
      selection: TextSelection.collapsed(offset: res.length),
    );
  }
}
