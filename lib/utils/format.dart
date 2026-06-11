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
