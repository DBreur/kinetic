// telemetry_sheet.dart: de pulsknop in de top bar. Snel overzicht van de
// live sensoren (Dexcom en, als die aan staat, Polar) met de meest gebruikte
// acties, zonder van pagina te wisselen.

import 'package:material_ui/material_ui.dart';

import '../theme/kinetic_theme.dart';
import 'kinetic_widgets.dart';
import 'sheets.dart';
import 'telemetry_widgets.dart';

Future<void> showTelemetrySheet(BuildContext context) =>
    showKineticSheet<void>(context, builder: (_) => _TelemetrySheet(outer: context));

class _TelemetrySheet extends StatelessWidget {
  const _TelemetrySheet({required this.outer});

  /// De pagina eronder: de sheet is weg voordat de volgende opent.
  final BuildContext outer;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Live telemetrie', style: context.t.headline),
        const SizedBox(height: 12),
        const TelemetryRow(),
        const SizedBox(height: 16),
        BigButton(
          label: 'Vingerprik vergelijken',
          icon: Icons.water_drop_outlined,
          style: KButtonStyle.secondary,
          fitLabel: true,
          onPressed: () {
            Navigator.of(context).pop();
            showFingerstickSheet(outer);
          },
        ),
        const SizedBox(height: 10),
        BigButton(
          label: 'Sensoren & instellingen',
          icon: Icons.sensors,
          style: KButtonStyle.ghost,
          fitLabel: true,
          onPressed: () {
            final nav = Navigator.of(context);
            nav.pop();
            nav.pushNamed('/telemetrie-export');
          },
        ),
      ],
    );
  }
}
