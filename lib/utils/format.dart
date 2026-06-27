import 'dart:math';

import 'package:intl/intl.dart';

/// Small formatting helpers shared across screens.
class Fmt {
  static const _symbols = {
    'INR': '₹',
    'USD': '\$',
    'EUR': '€',
    'GBP': '£',
    'AED': 'د.إ',
    'AUD': 'A\$',
    'CAD': 'C\$',
    'SGD': 'S\$',
  };

  static String currency(num value, {String code = 'INR'}) {
    final symbol = _symbols[code] ?? '$code ';
    final f = NumberFormat.currency(symbol: symbol, decimalDigits: 2);
    return f.format(value);
  }

  static String compact(num value, {String code = 'INR'}) {
    final symbol = _symbols[code] ?? '$code ';
    final f = NumberFormat.compactCurrency(symbol: symbol, decimalDigits: 1);
    return f.format(value);
  }

  static String date(DateTime d) => DateFormat.yMMMd().format(d);
  static String time(DateTime d) => DateFormat.jm().format(d);

  /// "Today" / "Yesterday" / "12 Jun 2026" for grouping activity by day.
  static String dayLabel(DateTime d) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final that = DateTime(d.year, d.month, d.day);
    final diff = today.difference(that).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    return DateFormat.yMMMEd().format(d);
  }
  static String monthYear(int year, int month) =>
      DateFormat.yMMMM().format(DateTime(year, month));
  static String monthShort(int month) =>
      DateFormat.MMM().format(DateTime(2000, month));

  static const List<String> currencyCodes = [
    'INR', 'USD', 'EUR', 'GBP', 'AED', 'AUD', 'CAD', 'SGD',
  ];
}

/// Generate a reasonably-unique id without extra packages.
String newId([String prefix = 'id']) {
  final now = DateTime.now().microsecondsSinceEpoch;
  return '${prefix}_$now';
}

/// A random, human-friendly family code used as the shared Family ID and as
/// the "join" token in invites, e.g. `FAM-7KQ4-9XPM`. Excludes ambiguous
/// characters (0/O, 1/I/L) so it's easy to read out or type.
String generateFamilyCode() {
  const chars = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
  final r = Random.secure();
  String block() =>
      List.generate(4, (_) => chars[r.nextInt(chars.length)]).join();
  return 'FAM-${block()}-${block()}';
}
