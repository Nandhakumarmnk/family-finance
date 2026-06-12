import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;

import '../state/app_state.dart';

/// Builds a polished PDF financial statement for a date range from the
/// in-memory AppState data. Uses currency *codes* (e.g. "INR 1,200.00") rather
/// than symbols so the default PDF fonts render correctly offline.
class StatementService {
  static final _num = NumberFormat('#,##0.00');
  static final _dateFmt = DateFormat('dd MMM yyyy');

  static String _money(num v, String code) => '$code ${_num.format(v)}';

  static Future<Uint8List> build(
    AppState s, {
    required DateTime start,
    required DateTime end,
    required String periodLabel,
  }) async {
    final code = s.currency;
    final expenses = s.expensesBetween(start, end);
    final salaries = s.salariesBetween(start, end);
    final income = salaries.fold<double>(0, (a, e) => a + e.amount);
    final spent = expenses.fold<double>(0, (a, e) => a + e.amount);
    final savings = income - spent;

    final byCategory = <String, double>{};
    for (final e in expenses) {
      byCategory[e.category] = (byCategory[e.category] ?? 0) + e.amount;
    }
    final cats = byCategory.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    const teal = PdfColor.fromInt(0xFF13726B);
    const ink = PdfColor.fromInt(0xFF0F1514);
    const muted = PdfColor.fromInt(0xFF5B6B69);
    const green = PdfColor.fromInt(0xFF1E8E5A);
    const red = PdfColor.fromInt(0xFFD0463B);

    final doc = pw.Document();

    pw.Widget kpi(String label, String value, PdfColor color) => pw.Expanded(
          child: pw.Container(
            margin: const pw.EdgeInsets.only(right: 8),
            padding: const pw.EdgeInsets.all(12),
            decoration: pw.BoxDecoration(
              color: PdfColors.grey100,
              borderRadius: pw.BorderRadius.circular(8),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Text(label,
                    style: const pw.TextStyle(fontSize: 9, color: muted)),
                pw.SizedBox(height: 4),
                pw.Text(value,
                    style: pw.TextStyle(
                        fontSize: 13, fontWeight: pw.FontWeight.bold, color: color)),
              ],
            ),
          ),
        );

    pw.TableRow txnRow(String date, String desc, String amount,
            {bool header = false}) =>
        pw.TableRow(
          decoration: header
              ? const pw.BoxDecoration(color: PdfColors.grey200)
              : null,
          children: [
            _cell(date, bold: header),
            _cell(desc, bold: header),
            _cell(amount, bold: header, align: pw.TextAlign.right),
          ],
        );

    doc.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(28),
        build: (context) => [
          // Header band
          pw.Container(
            padding: const pw.EdgeInsets.all(18),
            decoration: pw.BoxDecoration(
              color: teal,
              borderRadius: pw.BorderRadius.circular(12),
            ),
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Column(
                  crossAxisAlignment: pw.CrossAxisAlignment.start,
                  children: [
                    pw.Text('Family Finance',
                        style: pw.TextStyle(
                            color: PdfColors.white,
                            fontSize: 20,
                            fontWeight: pw.FontWeight.bold)),
                    pw.SizedBox(height: 2),
                    pw.Text('Statement · $periodLabel',
                        style: const pw.TextStyle(
                            color: PdfColors.white, fontSize: 11)),
                  ],
                ),
                pw.Text(s.profile?.displayName ?? '',
                    style: const pw.TextStyle(
                        color: PdfColors.white, fontSize: 11)),
              ],
            ),
          ),
          pw.SizedBox(height: 16),
          pw.Row(children: [
            kpi('Income', _money(income, code), green),
            kpi('Expenses', _money(spent, code), red),
            kpi('Savings', _money(savings, code), savings >= 0 ? green : red),
          ]),
          pw.SizedBox(height: 18),

          pw.Text('Spending by category',
              style: pw.TextStyle(
                  fontSize: 13, fontWeight: pw.FontWeight.bold, color: ink)),
          pw.SizedBox(height: 6),
          if (cats.isEmpty)
            pw.Text('No expenses in this period.',
                style: const pw.TextStyle(color: muted))
          else
            pw.Table(
              columnWidths: const {0: pw.FlexColumnWidth(3), 1: pw.FlexColumnWidth(1)},
              children: [
                for (final c in cats)
                  pw.TableRow(children: [
                    _cell(c.key),
                    _cell(_money(c.value, code), align: pw.TextAlign.right),
                  ]),
              ],
            ),
          pw.SizedBox(height: 18),

          pw.Text('Transactions',
              style: pw.TextStyle(
                  fontSize: 13, fontWeight: pw.FontWeight.bold, color: ink)),
          pw.SizedBox(height: 6),
          pw.Table(
            border: pw.TableBorder.symmetric(
                inside: const pw.BorderSide(color: PdfColors.grey300, width: 0.5)),
            columnWidths: const {
              0: pw.FlexColumnWidth(1.4),
              1: pw.FlexColumnWidth(3),
              2: pw.FlexColumnWidth(1.6),
            },
            children: [
              txnRow('Date', 'Description', 'Amount', header: true),
              for (final e in salaries)
                txnRow(_dateFmt.format(e.date), 'Income · ${e.source}',
                    '+ ${_money(e.amount, code)}'),
              for (final e in expenses)
                txnRow(
                    _dateFmt.format(e.date),
                    '${e.category}${e.notes.isEmpty ? '' : ' · ${e.notes}'}',
                    '- ${_money(e.amount, code)}'),
            ],
          ),
        ],
        footer: (context) => pw.Padding(
          padding: const pw.EdgeInsets.only(top: 8),
          child: pw.Text(
            'Generated by Family Finance · Page ${context.pageNumber}/${context.pagesCount}',
            style: const pw.TextStyle(fontSize: 8, color: muted),
          ),
        ),
      ),
    );

    return doc.save();
  }

  static pw.Widget _cell(String text,
      {bool bold = false, pw.TextAlign align = pw.TextAlign.left}) {
    return pw.Padding(
      padding: const pw.EdgeInsets.symmetric(vertical: 4, horizontal: 4),
      child: pw.Text(
        text,
        textAlign: align,
        style: pw.TextStyle(
            fontSize: 10,
            fontWeight: bold ? pw.FontWeight.bold : pw.FontWeight.normal),
      ),
    );
  }
}
