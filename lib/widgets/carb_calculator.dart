// carb_calculator.dart — klein rekenmachientje voor koolhydraten in het
// eetlogboek: begint met wat er al ingevuld staat, dan + en − (bv. "45 + 12
// − 8"), en "Overnemen" zet de uitkomst terug in het veld. De insuline
// rekent daarna gewoon opnieuw.

import 'package:flutter/material.dart';

import '../core/formatters.dart' show carbsText;
import '../theme/kinetic_theme.dart';

/// Rekent een som met + en − uit ("45 + 12,5 − 8"). Komma of punt als
/// decimaalteken. Null bij een ongeldige som; de uitkomst is nooit negatief.
double? evaluateCarbSum(String expression) {
  final cleaned = expression
      .replaceAll(' ', '')
      .replaceAll('−', '-')
      .replaceAll(',', '.');
  if (cleaned.isEmpty) return 0;
  final match = RegExp(r'^[+-]?\d*\.?\d+([+-]\d*\.?\d+)*$').hasMatch(cleaned);
  if (!match) return null;
  var total = 0.0;
  for (final m in RegExp(r'[+-]?\d*\.?\d+').allMatches(cleaned)) {
    total += double.parse(m.group(0)!);
  }
  return total < 0 ? 0 : total;
}

/// Opent het rekenmachientje met [start] als beginwaarde. Geeft de uitkomst
/// terug bij "Overnemen", of null bij annuleren.
Future<double?> showCarbCalculator(BuildContext context, double start) {
  return showModalBottomSheet<double>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _CarbCalculator(start: start),
  );
}

class _CarbCalculator extends StatefulWidget {
  const _CarbCalculator({required this.start});

  final double start;

  @override
  State<_CarbCalculator> createState() => _CarbCalculatorState();
}

class _CarbCalculatorState extends State<_CarbCalculator> {
  late String _expr = widget.start > 0 ? carbsText(widget.start) : '';

  bool get _endsWithOperator => _expr.endsWith(' + ') || _expr.endsWith(' − ');

  void _tap(String key) {
    setState(() {
      switch (key) {
        case 'C':
          _expr = '';
        case '⌫':
          if (_endsWithOperator) {
            _expr = _expr.substring(0, _expr.length - 3);
          } else if (_expr.isNotEmpty) {
            _expr = _expr.substring(0, _expr.length - 1);
          }
        case '+':
        case '−':
          if (_expr.isEmpty) return;
          // Twee keer een teken: het laatste geldt.
          if (_endsWithOperator) _expr = _expr.substring(0, _expr.length - 3);
          _expr += ' $key ';
        case ',':
          final last = _expr.split(' ').last;
          if (last.contains(',')) return;
          _expr += last.isEmpty ? '0,' : ',';
        default:
          _expr += key;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final result = evaluateCarbSum(
      _endsWithOperator ? _expr.substring(0, _expr.length - 3) : _expr,
    );
    final insets = MediaQuery.of(context);
    Widget key(String label, {Color? color}) => Expanded(
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: SizedBox(
          height: 52,
          child: FilledButton.tonal(
            onPressed: () => _tap(label),
            style: FilledButton.styleFrom(
              minimumSize: const Size(0, 52),
              backgroundColor: color ?? AppColor.surfaceHigh,
              foregroundColor: AppColor.ink,
              textStyle: AppText.title,
            ),
            child: Text(label),
          ),
        ),
      ),
    );
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(16, 16, 16, 12 + insets.padding.bottom),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Koolhydraten rekenen', style: AppText.cardTitle),
            const SizedBox(height: 12),
            Text(
              _expr.isEmpty ? '0' : _expr,
              textAlign: TextAlign.right,
              style: AppText.body.copyWith(color: AppColor.inkMuted),
            ),
            Text(
              result == null ? '—' : '${carbsText(result)} g',
              textAlign: TextAlign.right,
              style: AppText.metric.copyWith(fontSize: 34),
            ),
            const SizedBox(height: 8),
            for (final row in const [
              ['7', '8', '9', '⌫'],
              ['4', '5', '6', '−'],
              ['1', '2', '3', '+'],
              ['C', '0', ','],
            ])
              Row(
                children: [
                  for (final k in row)
                    key(
                      k,
                      color: k == '+' || k == '−'
                          ? AppColor.coralWash
                          : (k == 'C' || k == '⌫'
                                ? AppColor.surfaceMuted
                                : null),
                    ),
                  if (row.length == 3)
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.all(4),
                        child: FilledButton(
                          onPressed: result == null
                              ? null
                              : () => Navigator.pop(context, result),
                          style: FilledButton.styleFrom(
                            minimumSize: const Size(0, 52),
                          ),
                          child: const Text('OK'),
                        ),
                      ),
                    ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
