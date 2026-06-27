import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config.dart';
import '../services/statement_service.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../utils/format.dart';
import '../widgets/common.dart';
import '../widgets/feedback.dart';

/// Generate a PDF statement for a chosen period (this/last month or a custom
/// range), preview/share/email it, open the underlying Excel in Drive, and
/// download the Android app.
class ReportsExportScreen extends StatefulWidget {
  const ReportsExportScreen({super.key});

  @override
  State<ReportsExportScreen> createState() => _ReportsExportScreenState();
}

enum _Period { thisMonth, lastMonth, custom }

class _ReportsExportScreenState extends State<ReportsExportScreen> {
  static const String _apkUrl = AppConfig.appDownloadUrl;

  _Period _period = _Period.thisMonth;
  DateTimeRange? _custom;
  bool _busy = false;

  (DateTime, DateTime, String) _range() {
    final now = DateTime.now();
    switch (_period) {
      case _Period.thisMonth:
        final start = DateTime(now.year, now.month, 1);
        final end = DateTime(now.year, now.month + 1, 0);
        return (start, end, Fmt.monthYear(now.year, now.month));
      case _Period.lastMonth:
        final lm = DateTime(now.year, now.month - 1, 1);
        final end = DateTime(now.year, now.month, 0);
        return (lm, end, Fmt.monthYear(lm.year, lm.month));
      case _Period.custom:
        final r = _custom ??
            DateTimeRange(
                start: DateTime(now.year, now.month, 1), end: now);
        return (r.start, r.end, '${Fmt.date(r.start)} – ${Fmt.date(r.end)}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = context.watch<AppState>();
    final theme = Theme.of(context);
    final cur = s.currency;
    final (start, end, label) = _range();
    final income = s.salariesBetween(start, end).fold<double>(0, (a, e) => a + e.amount);
    final spent = s.expensesBetween(start, end).fold<double>(0, (a, e) => a + e.amount);

    return Scaffold(
      appBar: AppBar(title: const Text('Reports & export')),
      body: ResponsiveCenter(
        maxWidth: 640,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
          const SectionHeader('Period'),
          SegmentedButton<_Period>(
            segments: const [
              ButtonSegment(value: _Period.thisMonth, label: Text('This month')),
              ButtonSegment(value: _Period.lastMonth, label: Text('Last month')),
              ButtonSegment(value: _Period.custom, label: Text('Custom')),
            ],
            selected: {_period},
            onSelectionChanged: (v) async {
              final p = v.first;
              if (p == _Period.custom) {
                final now = DateTime.now();
                final picked = await showDateRangePicker(
                  context: context,
                  firstDate: DateTime(2015),
                  lastDate: DateTime(now.year + 1),
                  initialDateRange: _custom,
                );
                if (picked != null) setState(() => _custom = picked);
              }
              setState(() => _period = p);
            },
          ),
          const SizedBox(height: 16),

          // Summary for the chosen period
          Card(
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 14),
                  Row(children: [
                    Expanded(child: _miniStat('Income', Fmt.currency(income, code: cur), AppTheme.positive)),
                    Expanded(child: _miniStat('Expenses', Fmt.currency(spent, code: cur), AppTheme.negative)),
                    Expanded(child: _miniStat('Savings', Fmt.currency(income - spent, code: cur),
                        income - spent >= 0 ? AppTheme.positive : AppTheme.negative)),
                  ]),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          const SectionHeader('Export'),
          _ActionTile(
            icon: Icons.picture_as_pdf,
            color: const Color(0xFFD0463B),
            title: 'PDF statement',
            subtitle: 'Preview, print, or email the statement',
            busy: _busy,
            onTap: _busy ? null : () => _sharePdf(s, start, end, label),
          ),
          const SizedBox(height: 10),
          _ActionTile(
            icon: Icons.grid_on,
            color: const Color(0xFF1565C0),
            title: 'Copy as CSV',
            subtitle: 'Copy transactions to paste into Excel / Sheets',
            onTap: () => _exportCsv(s, start, end),
          ),
          const SizedBox(height: 10),
          _ActionTile(
            icon: Icons.table_chart,
            color: const Color(0xFF1E8E5A),
            title: 'Open Excel in Google Drive',
            subtitle: 'View/edit the raw .xlsx workbook',
            onTap: () => _openExcel(s),
          ),
          const SizedBox(height: 10),
          _ActionTile(
            icon: Icons.android,
            color: const Color(0xFF3DDC84),
            title: 'Download Android app (APK)',
            subtitle: 'Install Family Finance on your phone',
            onTap: () => _open(_apkUrl, 'No download link configured yet'),
          ),
        ],
        ),
      ),
    );
  }

  Widget _miniStat(String label, String value, Color color) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w800, color: color)),
        Text(label,
            style: theme.textTheme.labelSmall
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
      ],
    );
  }

  Future<void> _sharePdf(
      AppState s, DateTime start, DateTime end, String label) async {
    setState(() => _busy = true);
    try {
      await Printing.layoutPdf(
        name: 'FamilyFinance_${label.replaceAll(' ', '_')}.pdf',
        onLayout: (_) =>
            StatementService.build(s, start: start, end: end, periodLabel: label),
      );
    } catch (e) {
      AppFeedback.error('Could not build the PDF');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Build a CSV of all income + expense rows for the period and copy it to the
  /// clipboard (no extra dependency) so it can be pasted into Excel / Sheets.
  Future<void> _exportCsv(AppState s, DateTime start, DateTime end) async {
    final rows = <List<String>>[
      ['Date', 'Type', 'Category', 'Amount', 'Payment mode', 'Notes'],
    ];
    for (final inc in s.salariesBetween(start, end)) {
      rows.add([
        Fmt.date(inc.date),
        'Income',
        inc.source,
        inc.amount.toStringAsFixed(2),
        '',
        inc.notes,
      ]);
    }
    for (final e in s.expensesBetween(start, end)) {
      rows.add([
        Fmt.date(e.date),
        'Expense',
        e.category,
        e.amount.toStringAsFixed(2),
        e.paymentMode,
        e.notes,
      ]);
    }
    if (rows.length == 1) {
      AppFeedback.error('No transactions in this period');
      return;
    }
    final csv = rows.map((r) => r.map(_csvCell).join(',')).join('\r\n');
    await Clipboard.setData(ClipboardData(text: csv));
    AppFeedback.success('CSV copied — paste into Sheets/Excel');
  }

  String _csvCell(String v) => (v.contains(',') ||
          v.contains('"') ||
          v.contains('\n') ||
          v.contains('\r'))
      ? '"${v.replaceAll('"', '""')}"'
      : v;

  Future<void> _openExcel(AppState s) async {
    final link = await s.personalFileLink();
    if (link == null) {
      AppFeedback.error('Workbook not available yet');
      return;
    }
    await _open(link, 'Could not open Drive');
  }

  Future<void> _open(String url, String errorMsg) async {
    final ok = await launchUrl(Uri.parse(url),
        mode: LaunchMode.externalApplication);
    if (!ok) AppFeedback.error(errorMsg);
  }
}

class _ActionTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;
  final bool busy;
  final VoidCallback? onTap;
  const _ActionTile({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
    this.busy = false,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(11),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.14),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: color),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: theme.textTheme.bodyLarge
                            ?.copyWith(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text(subtitle,
                        style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant)),
                  ],
                ),
              ),
              busy
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : Icon(Icons.chevron_right,
                      color: theme.colorScheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}
