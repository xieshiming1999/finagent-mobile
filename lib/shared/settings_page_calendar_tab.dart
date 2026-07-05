import 'package:flutter/material.dart';

import 'i18n/app_localizations.dart';
import 'trading_calendar.dart';

class TradingCalendarTab extends StatelessWidget {
  const TradingCalendarTab({
    super.key,
    required this.store,
    required this.calendarMonth,
    required this.calendarFetching,
    required this.onRefresh,
    required this.onMonthChanged,
    required this.onDayTap,
  });

  final TradingCalendarStore? store;
  final DateTime calendarMonth;
  final bool calendarFetching;
  final VoidCallback onRefresh;
  final ValueChanged<DateTime> onMonthChanged;
  final ValueChanged<CalendarDay> onDayTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context);
    if (store == null) {
      return Center(
        child: Text(
          l10n.calendarNotLoaded,
          style: TextStyle(color: cs.onSurface.withValues(alpha: 0.5)),
        ),
      );
    }

    final days = store!.getMonthDays(calendarMonth.year, calendarMonth.month);
    final monthLabel = l10n.tradingCalendarMonthLabel(
      calendarMonth.year,
      calendarMonth.month,
    );
    final weekdayHeaders = l10n.tradingCalendarWeekdayHeaders;
    final firstWeekday = days.isNotEmpty ? days.first.date.weekday : 1;
    final padStart = firstWeekday - 1;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            Text(
              l10n.tradingCalendar,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: cs.primary,
              ),
            ),
            const Spacer(),
            if (calendarFetching)
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            else
              FilledButton.icon(
                onPressed: onRefresh,
                icon: const Icon(Icons.sync, size: 16),
                label: Text(l10n.refresh),
              ),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          store!.lastFetched != null
              ? l10n.tradingCalendarStatus(
                  store!.lastFetched!,
                  store!.tradingDayCount,
                )
              : l10n.weekendFallbackRule,
          style: TextStyle(
            fontSize: 11,
            color: cs.onSurface.withValues(alpha: 0.4),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            IconButton(
              icon: const Icon(Icons.chevron_left, size: 20),
              onPressed: () => onMonthChanged(
                DateTime(calendarMonth.year, calendarMonth.month - 1),
              ),
            ),
            GestureDetector(
              onTap: () => onMonthChanged(
                DateTime(DateTime.now().year, DateTime.now().month),
              ),
              child: Text(
                monthLabel,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  color: cs.onSurface,
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.chevron_right, size: 20),
              onPressed: () => onMonthChanged(
                DateTime(calendarMonth.year, calendarMonth.month + 1),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: weekdayHeaders
              .map(
                (h) => Expanded(
                  child: Center(
                    child: Text(
                      h,
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                        color: cs.onSurface.withValues(alpha: 0.5),
                      ),
                    ),
                  ),
                ),
              )
              .toList(),
        ),
        const SizedBox(height: 4),
        ...List.generate(((padStart + days.length) / 7).ceil(), (week) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Row(
              children: List.generate(7, (col) {
                final idx = week * 7 + col - padStart;
                if (idx < 0 || idx >= days.length) {
                  return const Expanded(child: SizedBox(height: 36));
                }
                return Expanded(child: _buildCalendarCell(days[idx], cs));
              }),
            ),
          );
        }),
        const SizedBox(height: 12),
        Row(
          children: [
            _legendDot(Colors.green, l10n.tradingDay),
            const SizedBox(width: 12),
            _legendDot(Colors.grey, l10n.nonTradingDay),
            const SizedBox(width: 12),
            _legendDot(Colors.orange, l10n.manualOverride),
          ],
        ),
        const SizedBox(height: 4),
        Text(
          l10n.tapDayToggle,
          style: TextStyle(
            fontSize: 11,
            color: cs.onSurface.withValues(alpha: 0.4),
          ),
        ),
      ],
    );
  }

  Widget _buildCalendarCell(CalendarDay day, ColorScheme cs) {
    final isToday = _isToday(day.date);
    final bgColor = day.isTrading
        ? Colors.green.withValues(alpha: 0.15)
        : cs.surfaceContainerHighest.withValues(alpha: 0.3);
    final borderColor = day.isOverride
        ? Colors.orange
        : (isToday ? cs.primary : Colors.transparent);
    return GestureDetector(
      onTap: () => onDayTap(day),
      child: Container(
        height: 36,
        margin: const EdgeInsets.all(1),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: borderColor, width: isToday ? 1.5 : 1),
        ),
        child: Center(
          child: Text(
            '${day.date.day}',
            style: TextStyle(
              fontSize: 12,
              fontWeight: isToday ? FontWeight.bold : FontWeight.normal,
              color: day.isTrading
                  ? Colors.green
                  : cs.onSurface.withValues(alpha: 0.4),
            ),
          ),
        ),
      ),
    );
  }

  Widget _legendDot(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(3),
            border: Border.all(color: color, width: 0.5),
          ),
        ),
        const SizedBox(width: 4),
        Text(label, style: const TextStyle(fontSize: 10)),
      ],
    );
  }

  bool _isToday(DateTime d) {
    final now = DateTime.now();
    return d.year == now.year && d.month == now.month && d.day == now.day;
  }
}
