import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/providers.dart';
import '../../core/waste_catalogue.dart';
import '../../domain/entities/collection_event.dart';
import '../../domain/statistics.dart';
import '../../widgets/async_view.dart';

const _monthInitials = [
  'G',
  'F',
  'M',
  'A',
  'M',
  'G',
  'L',
  'A',
  'S',
  'O',
  'N',
  'D',
];

const _monthNames = [
  'Gennaio',
  'Febbraio',
  'Marzo',
  'Aprile',
  'Maggio',
  'Giugno',
  'Luglio',
  'Agosto',
  'Settembre',
  'Ottobre',
  'Novembre',
  'Dicembre',
];

/// Collections per month for a chosen year, plus a year-over-year comparison.
class StatisticsScreen extends ConsumerStatefulWidget {
  const StatisticsScreen({super.key, required this.houseId});

  final String houseId;

  @override
  ConsumerState<StatisticsScreen> createState() => _StatisticsScreenState();
}

class _StatisticsScreenState extends ConsumerState<StatisticsScreen> {
  late int _year = DateTime.now().year;
  int? _selectedMonth;

  @override
  Widget build(BuildContext context) {
    final years = availableYears(DateTime.now().year);
    final events = ref.watch(
      collectionsProvider((houseId: widget.houseId, year: _year)),
    );

    return Scaffold(
      appBar: AppBar(
        title: const Text('Statistiche'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/house/${widget.houseId}/waste'),
        ),
      ),
      body: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
          children: [
            _YearSelector(
              years: years,
              selected: _year,
              onSelected: (year) => setState(() {
                _year = year;
                _selectedMonth = null;
              }),
            ),
            const SizedBox(height: 20),
            AsyncView(
              value: events,
              onRetry: () => ref.invalidate(
                collectionsProvider((houseId: widget.houseId, year: _year)),
              ),
              builder: (context, list) => _YearDetail(
                breakdown: monthlyBreakdown(events: list, year: _year),
                selectedMonth: _selectedMonth,
                onMonthTap: (month) => setState(
                  () => _selectedMonth = _selectedMonth == month ? null : month,
                ),
              ),
            ),
            const SizedBox(height: 28),
            _SectionTitle('Confronto tra gli anni'),
            const SizedBox(height: 8),
            _YearComparison(houseId: widget.houseId, years: years),
          ],
        ),
      ),
    );
  }
}

class _YearSelector extends StatelessWidget {
  const _YearSelector({
    required this.years,
    required this.selected,
    required this.onSelected,
  });

  final List<int> years;
  final int selected;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    scrollDirection: Axis.horizontal,
    child: Row(
      children: [
        for (final year in years.reversed) ...[
          ChoiceChip(
            label: Text('$year'),
            selected: year == selected,
            onSelected: (_) => onSelected(year),
          ),
          const SizedBox(width: 8),
        ],
      ],
    ),
  );
}

class _YearDetail extends StatelessWidget {
  const _YearDetail({
    required this.breakdown,
    required this.selectedMonth,
    required this.onMonthTap,
  });

  final MonthlyBreakdown breakdown;
  final int? selectedMonth;
  final ValueChanged<int> onMonthTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (breakdown.isEmpty) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              Icon(
                Icons.insights_outlined,
                size: 36,
                color: theme.colorScheme.outline,
              ),
              const SizedBox(height: 12),
              Text(
                'Nessuna raccolta registrata nel ${breakdown.year}',
                style: theme.textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    final types = breakdown.typesPresent;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${breakdown.total}',
                      style: theme.textTheme.displaySmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        breakdown.total == 1
                            ? 'raccolta nel ${breakdown.year}'
                            : 'raccolte nel ${breakdown.year}',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Text('Andamento mensile', style: theme.textTheme.labelLarge),
                const SizedBox(height: 12),
                _MonthlyChart(
                  breakdown: breakdown,
                  types: types,
                  selectedMonth: selectedMonth,
                  onMonthTap: onMonthTap,
                ),
                if (selectedMonth != null) ...[
                  const SizedBox(height: 16),
                  _MonthDetail(breakdown: breakdown, month: selectedMonth!),
                ],
                const SizedBox(height: 20),
                const Divider(),
                const SizedBox(height: 12),
                Text('Totale per tipo', style: theme.textTheme.labelLarge),
                const SizedBox(height: 12),
                for (final type in types) ...[
                  _TypeRow(
                    type: type,
                    count: breakdown.totalForType(type),
                    total: breakdown.total,
                  ),
                  const SizedBox(height: 10),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// A stacked column per month, each segment coloured by waste type.
class _MonthlyChart extends StatelessWidget {
  const _MonthlyChart({
    required this.breakdown,
    required this.types,
    required this.selectedMonth,
    required this.onMonthTap,
  });

  final MonthlyBreakdown breakdown;
  final List<WasteType> types;
  final int? selectedMonth;
  final ValueChanged<int> onMonthTap;

  static const _chartHeight = 130.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final peak = breakdown.peakMonthTotal;

    return Column(
      children: [
        SizedBox(
          height: _chartHeight + 26,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              for (var month = 0; month < 12; month++)
                Expanded(
                  child: _MonthColumn(
                    month: month,
                    counts: breakdown.byMonth[month],
                    total: breakdown.totalForMonth(month),
                    peak: peak,
                    types: types,
                    isSelected: selectedMonth == month,
                    chartHeight: _chartHeight,
                    onTap: () => onMonthTap(month),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'Tocca un mese per il dettaglio',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }
}

class _MonthColumn extends StatelessWidget {
  const _MonthColumn({
    required this.month,
    required this.counts,
    required this.total,
    required this.peak,
    required this.types,
    required this.isSelected,
    required this.chartHeight,
    required this.onTap,
  });

  final int month;
  final Map<WasteType, int> counts;
  final int total;
  final int peak;
  final List<WasteType> types;
  final bool isSelected;
  final double chartHeight;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // A bar for a month with collections is never shorter than 4px, so a
    // single collection stays visible next to a busy month.
    final barHeight = total == 0
        ? 3.0
        : (total / peak * chartHeight).clamp(4.0, chartHeight);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 1.5),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            if (total > 0)
              Text(
                '$total',
                style: theme.textTheme.labelSmall?.copyWith(
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              )
            else
              const SizedBox(height: 12),
            const SizedBox(height: 2),
            Container(
              height: barHeight,
              decoration: BoxDecoration(
                color: total == 0
                    ? theme.colorScheme.surfaceContainerHighest
                    : null,
                borderRadius: BorderRadius.circular(3),
              ),
              child: total == 0
                  ? null
                  : ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: Column(
                        children: [
                          for (final type in types)
                            if ((counts[type] ?? 0) > 0)
                              Expanded(
                                flex: counts[type]!,
                                child: Container(
                                  width: double.infinity,
                                  color: type.colorFor(theme.brightness),
                                ),
                              ),
                        ],
                      ),
                    ),
            ),
            const SizedBox(height: 4),
            Text(
              _monthInitials[month],
              style: theme.textTheme.labelSmall?.copyWith(
                fontSize: 10,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected
                    ? theme.colorScheme.primary
                    : theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MonthDetail extends StatelessWidget {
  const _MonthDetail({required this.breakdown, required this.month});

  final MonthlyBreakdown breakdown;
  final int month;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final counts = breakdown.byMonth[month];
    final total = breakdown.totalForMonth(month);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${_monthNames[month]} ${breakdown.year}',
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          if (total == 0)
            Text('Nessuna raccolta.', style: theme.textTheme.bodySmall)
          else
            Wrap(
              spacing: 12,
              runSpacing: 6,
              children: [
                for (final type in WasteType.values)
                  if ((counts[type] ?? 0) > 0)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          type.icon,
                          size: 16,
                          color: type.colorFor(theme.brightness),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          '${type.label}: ${counts[type]}',
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
              ],
            ),
        ],
      ),
    );
  }
}

class _TypeRow extends StatelessWidget {
  const _TypeRow({
    required this.type,
    required this.count,
    required this.total,
  });

  final WasteType type;
  final int count;
  final int total;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = type.colorFor(theme.brightness);
    final share = total == 0 ? 0.0 : count / total;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(type.icon, size: 16, color: color),
            const SizedBox(width: 8),
            Expanded(child: Text(type.label, style: theme.textTheme.bodySmall)),
            Text(
              '$count · ${(share * 100).round()}%',
              style: theme.textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: LinearProgressIndicator(
            value: share,
            minHeight: 5,
            backgroundColor: theme.colorScheme.surfaceContainerHighest,
            valueColor: AlwaysStoppedAnimation(color),
          ),
        ),
      ],
    );
  }
}

/// Totals for each of the last few years side by side.
///
/// Each year is a separate query, so they arrive independently; a year that is
/// still loading shows a muted bar rather than a misleading zero.
class _YearComparison extends ConsumerWidget {
  const _YearComparison({required this.houseId, required this.years});

  final String houseId;
  final List<int> years;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    final totals = [
      for (final year in years.reversed)
        _totalFor(
          year,
          ref.watch(collectionsProvider((houseId: houseId, year: year))),
        ),
    ];
    final peak = peakYearTotal(totals);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            for (final entry in totals) ...[
              _YearBar(total: entry, peak: peak),
              if (entry != totals.last) const SizedBox(height: 14),
            ],
            const SizedBox(height: 12),
            Text(
              'Ultimi ${years.length} anni',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  YearTotal _totalFor(int year, AsyncValue<List<CollectionEvent>> events) {
    final list = events.value;
    return YearTotal(
      year: year,
      byType: list == null
          ? const {}
          : _countByType(list.where((e) => e.date.year == year)),
      isLoaded: list != null,
    );
  }

  Map<WasteType, int> _countByType(Iterable<CollectionEvent> events) {
    final counts = <WasteType, int>{};
    for (final event in events) {
      counts.update(event.type, (v) => v + 1, ifAbsent: () => 1);
    }
    return counts;
  }
}

class _YearBar extends StatelessWidget {
  const _YearBar({required this.total, required this.peak});

  final YearTotal total;
  final int peak;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      children: [
        SizedBox(
          width: 42,
          child: Text(
            '${total.year}',
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              if (!total.isLoaded) {
                return Container(
                  height: 22,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(5),
                  ),
                );
              }
              final width = total.total == 0
                  ? 0.0
                  : (total.total / peak * constraints.maxWidth).clamp(
                      6.0,
                      constraints.maxWidth,
                    );
              return Align(
                alignment: Alignment.centerLeft,
                child: Container(
                  height: 22,
                  width: width,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(5),
                    color: total.total == 0
                        ? theme.colorScheme.surfaceContainerHighest
                        : null,
                  ),
                  child: total.total == 0
                      ? null
                      : ClipRRect(
                          borderRadius: BorderRadius.circular(5),
                          child: Row(
                            children: [
                              for (final type in WasteType.values)
                                if ((total.byType[type] ?? 0) > 0)
                                  Expanded(
                                    flex: total.byType[type]!,
                                    child: Container(
                                      color: type.colorFor(theme.brightness),
                                    ),
                                  ),
                            ],
                          ),
                        ),
                ),
              );
            },
          ),
        ),
        SizedBox(
          width: 38,
          child: Text(
            total.isLoaded ? '${total.total}' : '–',
            textAlign: TextAlign.end,
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: Theme.of(
      context,
    ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
  );
}
