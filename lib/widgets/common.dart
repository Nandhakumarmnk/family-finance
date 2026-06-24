import 'package:flutter/material.dart';

import '../utils/format.dart';

/// A tappable field that opens a date picker. Shared across forms.
class DatePickerField extends StatelessWidget {
  final DateTime date;
  final ValueChanged<DateTime> onChanged;
  final String label;
  const DatePickerField({
    super.key,
    required this.date,
    required this.onChanged,
    this.label = 'Date',
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () async {
        final picked = await showDatePicker(
          context: context,
          initialDate: date,
          firstDate: DateTime(2015),
          lastDate: DateTime(2100),
        );
        if (picked != null) onChanged(picked);
      },
      child: InputDecorator(
        decoration:
            InputDecoration(labelText: label, prefixIcon: const Icon(Icons.event)),
        child: Text(Fmt.date(date)),
      ),
    );
  }
}

/// A compact KPI tile used on the dashboard and report headers.
class StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color? color;
  final String? sub;

  const StatCard({
    super.key,
    required this.label,
    required this.value,
    required this.icon,
    this.color,
    this.sub,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = color ?? theme.colorScheme.primary;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(9),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [c.withOpacity(0.20), c.withOpacity(0.10)],
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(icon, color: c, size: 20),
                ),
                const Spacer(),
              ],
            ),
            const SizedBox(height: 10),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(
                value,
                maxLines: 1,
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.5,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
            const SizedBox(height: 3),
            Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w500,
              ),
            ),
            if (sub != null) ...[
              const SizedBox(height: 6),
              Text(sub!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall
                      ?.copyWith(color: c, fontWeight: FontWeight.w600)),
            ]
          ],
        ),
      ),
    );
  }
}

/// A titled section wrapper.
class SectionHeader extends StatelessWidget {
  final String title;
  final Widget? trailing;
  const SectionHeader(this.title, {super.key, this.trailing});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
      child: Row(
        children: [
          Text(title,
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.bold)),
          const Spacer(),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// Empty-state placeholder.
class EmptyState extends StatelessWidget {
  final IconData icon;
  final String message;
  const EmptyState({super.key, required this.icon, required this.message});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: theme.colorScheme.outlineVariant),
            const SizedBox(height: 12),
            Text(message,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.outline)),
          ],
        ),
      ),
    );
  }
}

/// Month + year picker row used on dashboard & reports.
class PeriodPicker extends StatelessWidget {
  final int year;
  final int month;
  final List<int> years;
  final ValueChanged<int> onYear;
  final ValueChanged<int> onMonth;
  final bool showMonth;

  const PeriodPicker({
    super.key,
    required this.year,
    required this.month,
    required this.years,
    required this.onYear,
    required this.onMonth,
    this.showMonth = true,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        if (showMonth)
          Expanded(
            child: DropdownButtonFormField<int>(
              value: month,
              decoration: const InputDecoration(labelText: 'Month'),
              items: List.generate(12, (i) => i + 1)
                  .map((m) => DropdownMenuItem(
                        value: m,
                        child: Text(_monthName(m)),
                      ))
                  .toList(),
              onChanged: (v) => v == null ? null : onMonth(v),
            ),
          ),
        if (showMonth) const SizedBox(width: 12),
        Expanded(
          child: DropdownButtonFormField<int>(
            value: years.contains(year) ? year : years.first,
            decoration: const InputDecoration(labelText: 'Year'),
            items: years
                .map((y) => DropdownMenuItem(value: y, child: Text('$y')))
                .toList(),
            onChanged: (v) => v == null ? null : onYear(v),
          ),
        ),
      ],
    );
  }

  static String _monthName(int m) {
    const names = [
      'January', 'February', 'March', 'April', 'May', 'June',
      'July', 'August', 'September', 'October', 'November', 'December'
    ];
    return names[m - 1];
  }
}
