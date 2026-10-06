import 'package:flutter/material.dart';

import '../../models/sql_execution.dart';

/// Selector de sub-pestañas para múltiples resultados de SELECT dentro de la
/// pestaña "Resultados" (solo se usa cuando hay más de un resultado).
class SqlResultsTabStrip extends StatelessWidget {
  const SqlResultsTabStrip({
    super.key,
    required this.results,
    required this.selectedIndex,
    required this.onSelect,
  });

  final List<SqlNamedResult> results;
  final int selectedIndex;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.6)),
        ),
      ),
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: results.length,
        separatorBuilder: (_, _) => const SizedBox(width: 4),
        itemBuilder: (context, i) {
          final selected = i == selectedIndex;
          return InkWell(
            borderRadius: BorderRadius.circular(5),
            onTap: () => onSelect(i),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: selected
                    ? cs.primaryContainer.withValues(alpha: 0.5)
                    : null,
                borderRadius: BorderRadius.circular(5),
                border: Border.all(
                  color: selected
                      ? cs.primary.withValues(alpha: 0.4)
                      : Colors.transparent,
                  width: 0.8,
                ),
              ),
              child: Text(
                'SELECT ${i + 1} · ${results[i].result.returnedRows}',
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  color: selected ? cs.primary : cs.onSurfaceVariant,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
