import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/design.dart';
import '../../app/providers.dart';
import '../../app/theme.dart';
import '../../core/waste_catalogue.dart';
import '../../domain/entities/collection_event.dart';
import '../../domain/statistics.dart';
import '../../widgets/async_view.dart';
import '../../widgets/waste_badges.dart';

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

    return GlassScaffold(
      appBar: AppBar(
        title: const Text('Statistiche'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.go('/house/${widget.houseId}/waste'),
        ),
      ),
      body: (context) => SafeArea(
        top: false,
        child: ListView(
          padding: glassListPadding(context, bottom: 32),
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
            const SizedBox(height: AppSpacing.sectionGap),
            const _SectionTitle('Confronto tra gli anni'),
            const SizedBox(height: 12),
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
    // Newest first. Chronological order reads more naturally, but it put the
    // year you are actually looking at — the current one — last, off the right
    // edge of the screen and half cut off, so the screen opened on a selection
    // you could not see.
    child: Row(
      children: [
        for (final year in years) ...[
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
          padding: const EdgeInsets.all(28),
          child: Column(
            children: [
              Icon(
                Icons.insights_outlined,
                size: 40,
                color: theme.colorScheme.outline,
              ),
              const SizedBox(height: 14),
              Text(
                'Nessuna raccolta registrata nel ${breakdown.year}',
                style: theme.textTheme.bodyLarge,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      );
    }

    final types = breakdown.typesPresent;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.cardPadding),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _TotalHeadline(breakdown: breakdown),
                const SizedBox(height: 22),
                Text('Andamento mensile', style: theme.textTheme.titleSmall),
                const SizedBox(height: 14),
                _MonthlyChart(
                  breakdown: breakdown,
                  types: types,
                  selectedMonth: selectedMonth,
                  onMonthTap: onMonthTap,
                ),
                const SizedBox(height: 14),
                _Legend(types: types),
                if (selectedMonth != null) ...[
                  const SizedBox(height: 16),
                  _MonthDetail(breakdown: breakdown, month: selectedMonth!),
                ],
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.rowGap),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.cardPadding),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Totale per tipo', style: theme.textTheme.titleSmall),
                const SizedBox(height: 16),
                for (final type in types) ...[
                  _TypeRow(
                    type: type,
                    count: breakdown.totalForType(type),
                    total: breakdown.total,
                  ),
                  if (type != types.last) const SizedBox(height: 16),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// The year's total, with the monthly average underneath it.
class _TotalHeadline extends StatelessWidget {
  const _TotalHeadline({required this.breakdown});

  final MonthlyBreakdown breakdown;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final average = breakdown.total / 12;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${breakdown.total}',
                style: theme.textTheme.displaySmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.primary,
                  height: 1.1,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                breakdown.total == 1
                    ? 'raccolta nel ${breakdown.year}'
                    : 'raccolte nel ${breakdown.year}',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        // Pushed into its own block so a long system font size wraps the words
        // instead of colliding with the headline figure beside it.
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                average.toStringAsFixed(1).replaceAll('.', ','),
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              Text(
                'al mese',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
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

  static const _chartHeight = 150.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final peak = breakdown.peakMonthTotal;

    return Column(
      children: [
        Row(
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
        const SizedBox(height: 8),
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
    // A month with collections is never shorter than 6px, so a single
    // collection stays visible next to a busy month.
    final barHeight = total == 0
        ? 4.0
        : (total / peak * chartHeight).clamp(6.0, chartHeight);
    const radius = BorderRadius.vertical(
      top: Radius.circular(5),
      bottom: Radius.circular(2),
    );

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.chip),
      child: Container(
        decoration: BoxDecoration(
          // The selected month is lifted by a tint behind the whole column
          // rather than by recolouring the bar, which would fight the stack's
          // own colours and hide which types made it up.
          color: isSelected
              ? theme.colorScheme.primary.withValues(alpha: 0.10)
              : null,
          borderRadius: BorderRadius.circular(AppRadius.chip),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: 16,
              child: total == 0
                  ? null
                  : FittedBox(
                      child: Text(
                        '$total',
                        style: theme.textTheme.labelSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: isSelected
                              ? theme.colorScheme.primary
                              : theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
            ),
            const SizedBox(height: 4),
            SizedBox(
              height: chartHeight,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Container(
                    height: barHeight,
                    decoration: BoxDecoration(
                      color: total == 0
                          ? theme.colorScheme.surfaceContainerHighest
                          : null,
                      borderRadius: radius,
                    ),
                    child: total == 0
                        ? null
                        : ClipRRect(
                            borderRadius: radius,
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
                ],
              ),
            ),
            const SizedBox(height: 6),
            FittedBox(
              child: Text(
                _monthInitials[month],
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  color: isSelected
                      ? theme.colorScheme.primary
                      : theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Which colour in the stack is which type.
///
/// The chart is the one place in the app where a waste type appears as a bare
/// band of colour with no icon next to it, so the key has to be spelled out
/// somewhere — and it uses the same tiles as everywhere else.
class _Legend extends StatelessWidget {
  const _Legend({required this.types});

  final List<WasteType> types;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Wrap(
      spacing: 14,
      runSpacing: 8,
      children: [
        for (final type in types)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              WasteAvatar(type: type, size: 20),
              const SizedBox(width: 6),
              Text(
                type.label,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
      ],
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
    const padding = 14.0;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(padding),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
        borderRadius: BorderRadius.circular(
          AppRadius.concentric(AppRadius.card, AppSpacing.cardPadding),
        ),
        border: Border.all(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${_monthNames[month]} ${breakdown.year}',
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 10),
          if (total == 0)
            Text('Nessuna raccolta.', style: theme.textTheme.bodyMedium)
          else
            Wrap(
              spacing: 14,
              runSpacing: 8,
              children: [
                for (final type in WasteType.values)
                  if ((counts[type] ?? 0) > 0)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        WasteAvatar(type: type, size: 22),
                        const SizedBox(width: 6),
                        Text(
                          '${type.label}: ${counts[type]}',
                          style: theme.textTheme.bodyMedium,
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
    final color = wasteColor(context, type);
    final share = total == 0 ? 0.0 : count / total;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            WasteAvatar(type: type, size: 28),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                type.label,
                style: theme.textTheme.bodyLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            Text(
              '$count · ${(share * 100).round()}%',
              style: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: share,
            minHeight: 7,
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
        padding: const EdgeInsets.all(AppSpacing.cardPadding),
        child: Column(
          children: [
            for (final entry in totals) ...[
              _YearBar(total: entry, peak: peak),
              if (entry != totals.last) const SizedBox(height: 16),
            ],
            const SizedBox(height: 14),
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

  static const _barHeight = 26.0;
  static final _radius = BorderRadius.circular(7);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Row(
      children: [
        SizedBox(
          width: 48,
          child: Text(
            '${total.year}',
            style: theme.textTheme.labelLarge?.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              if (!total.isLoaded) {
                return Container(
                  height: _barHeight,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest,
                    borderRadius: _radius,
                  ),
                );
              }
              final width = total.total == 0
                  ? 0.0
                  : (total.total / peak * constraints.maxWidth).clamp(
                      8.0,
                      constraints.maxWidth,
                    );
              return Stack(
                children: [
                  // The track makes an empty or short year legible as a share
                  // of the best one, instead of a stub floating in white space.
                  Container(
                    height: _barHeight,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest
                          .withValues(alpha: 0.5),
                      borderRadius: _radius,
                    ),
                  ),
                  if (total.total > 0)
                    ClipRRect(
                      borderRadius: _radius,
                      child: SizedBox(
                        height: _barHeight,
                        width: width,
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
                ],
              );
            },
          ),
        ),
        SizedBox(
          width: 44,
          child: Text(
            total.isLoaded ? '${total.total}' : '–',
            textAlign: TextAlign.end,
            style: theme.textTheme.labelLarge?.copyWith(
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
