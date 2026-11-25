// technieken_screen.dart: de Technieken-tab met drie sub-tabs:
//  - Technieken: de Technique Vault (alle eigen + bibliotheektechnieken,
//    accordeons per groep, +1 Rep en "Focus in Sessie" voor de live mat);
//  - Combo's: combinaties van technieken in volgorde;
//  - Systemen: flow-grafen van posities en technieken;
//  - Ontdekken: de gedeelde bibliotheek doorzoeken en overnemen.
// De shell levert de top bar en de navigatie; dit scherm alleen de inhoud.

import 'package:material_ui/material_ui.dart';

import '../theme/kinetic_theme.dart';
import '../widgets/kinetic_widgets.dart';
import 'techniques/combinations_view.dart';
import 'techniques/discover_view.dart';
import 'techniques/systems_view.dart';
import 'techniques/vault_view.dart';

enum TechniekenTab { vault, combos, systems, discover }

class TechniekenScreen extends StatefulWidget {
  const TechniekenScreen({super.key, this.initialTab = TechniekenTab.vault});
  final TechniekenTab initialTab;

  @override
  State<TechniekenScreen> createState() => _TechniekenScreenState();
}

class _TechniekenScreenState extends State<TechniekenScreen> {
  late TechniekenTab _tab = widget.initialTab;

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    return ColoredBox(
      color: k.canvas,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: KSegmented<TechniekenTab>(
              options: const [
                (TechniekenTab.vault, 'Technieken'),
                (TechniekenTab.combos, "Combo's"),
                (TechniekenTab.systems, 'Systemen'),
                (TechniekenTab.discover, 'Ontdekken'),
              ],
              value: _tab,
              onChanged: (t) {
                FocusScope.of(context).unfocus();
                setState(() => _tab = t);
              },
            ),
          ),
          Expanded(
            child: IndexedStack(
              index: _tab.index,
              children: const [VaultView(), CombinationsView(), SystemsView(), DiscoverView()],
            ),
          ),
        ],
      ),
    );
  }
}
