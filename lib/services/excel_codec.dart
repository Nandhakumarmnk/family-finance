import 'dart:typed_data';

import 'package:excel/excel.dart';

/// Low-level helpers to turn typed rows into an .xlsx byte stream and back.
/// The rest of the app deals in `List<List<dynamic>>` (plain strings/numbers);
/// this file is the only place that touches the `excel` package.
///
/// Uses the `excel` 2.x dynamic-value API: rows are plain Dart values
/// (String / int / double / bool) on the way in, and `cell.value` is read
/// back as a dynamic on the way out.
class ExcelCodec {
  /// Build an .xlsx from a map of sheet name -> rows. The FIRST row of each
  /// sheet is expected to be the header. Returns encoded bytes.
  static Uint8List encode(Map<String, List<List<dynamic>>> sheets) {
    final excel = Excel.createExcel();
    final defaultSheet = excel.getDefaultSheet();

    sheets.forEach((name, rows) {
      final sheet = excel[name];
      for (final row in rows) {
        sheet.appendRow(row);
      }
    });

    // Remove the auto-created default sheet if we didn't use it.
    if (defaultSheet != null && !sheets.containsKey(defaultSheet)) {
      excel.delete(defaultSheet);
    }

    final encoded = excel.encode();
    return Uint8List.fromList(encoded ?? <int>[]);
  }

  /// Parse .xlsx bytes into a map of sheet name -> rows of plain values
  /// (header row included as the first row).
  static Map<String, List<List<dynamic>>> decode(Uint8List bytes) {
    final excel = Excel.decodeBytes(bytes);
    final out = <String, List<List<dynamic>>>{};
    for (final name in excel.tables.keys) {
      final table = excel.tables[name];
      if (table == null) continue;
      final rows = <List<dynamic>>[];
      for (final row in table.rows) {
        rows.add(row.map((cell) => _normalize(cell?.value)).toList());
      }
      out[name] = rows;
    }
    return out;
  }

  /// Read the data rows (excluding header) of a single sheet, dropping any
  /// fully-blank rows.
  static List<List<dynamic>> dataRows(
    Map<String, List<List<dynamic>>> wb,
    String sheet,
  ) {
    final rows = wb[sheet];
    if (rows == null || rows.length <= 1) return const [];
    return rows
        .sublist(1)
        .where((r) => r.any((c) => '${c ?? ''}'.trim().isNotEmpty))
        .toList();
  }

  /// Coerce a raw cell value into a plain String/num/bool the models expect.
  static dynamic _normalize(dynamic v) {
    if (v == null) return '';
    if (v is String || v is int || v is double || v is bool) return v;
    // DateTime or any other type -> ISO/string form.
    if (v is DateTime) return v.toIso8601String();
    return v.toString();
  }
}
