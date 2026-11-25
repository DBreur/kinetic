// technique_ui.dart: gedeelde bouwstenen voor de Technieken-tab (Vault,
// Systemen, Ontdekken): groepskleuren/-iconen, zoekveld, kopregel per
// sub-tab, acties (+1 rep, focus, toevoegen) en het detailvel van een
// techniek.

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/formatters.dart';
import '../../models/library.dart';
import '../../models/technique.dart';
import '../../theme/kinetic_theme.dart';
import '../../widgets/kinetic_widgets.dart';
import '../../widgets/technique_detail_widgets.dart';
import '../../widgets/video_widgets.dart';

// ------------------------------------------------------------ groepen

KTone groupTone(TechniqueGroup g) => switch (g) {
  TechniqueGroup.throws => KTone.primary,
  TechniqueGroup.striking => KTone.info,
  TechniqueGroup.submissions => KTone.purple,
  TechniqueGroup.sweeps => KTone.primary,
  TechniqueGroup.control => KTone.info,
  TechniqueGroup.defense => KTone.purple,
  TechniqueGroup.other => KTone.neutral,
};

IconData groupIcon(TechniqueGroup g) => switch (g) {
  TechniqueGroup.throws => Icons.sports_kabaddi,
  TechniqueGroup.striking => Icons.sports_mma,
  TechniqueGroup.submissions => Icons.lock_outline,
  TechniqueGroup.sweeps => Icons.swap_horiz,
  TechniqueGroup.control => Icons.push_pin_outlined,
  TechniqueGroup.defense => Icons.shield_outlined,
  TechniqueGroup.other => Icons.category_outlined,
};

/// Voorgrondkleur van een groep (iconen, tags).
Color groupColor(BuildContext context, TechniqueGroup g) => toneColors(context.k, groupTone(g)).$2;

/// Kleine groepstag bovenaan een kaart ("Throws").
class GroupTag extends StatelessWidget {
  const GroupTag(this.group, {super.key});
  final TechniqueGroup group;

  @override
  Widget build(BuildContext context) => KPill(group.label, tone: groupTone(group), dense: true);
}

/// "Beginner" / "Gevorderd" / "Expert" met niveau-icoon.
class DifficultyPill extends StatelessWidget {
  const DifficultyPill(this.difficulty, {super.key});
  final int difficulty;

  @override
  Widget build(BuildContext context) =>
      KPill(difficultyLabel(difficulty), icon: Icons.signal_cellular_alt, dense: true);
}

// ------------------------------------------------------------ kop + zoeken

/// Kop van een sub-tab: titel, ondertitel en optioneel een actieknop.
class SubTabHeader extends StatelessWidget {
  const SubTabHeader({super.key, required this.title, required this.caption, this.action});
  final String title;
  final String caption;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: context.t.headline),
              const SizedBox(height: 2),
              Text(caption, style: context.t.caption, maxLines: 2, overflow: TextOverflow.ellipsis),
            ],
          ),
        ),
        if (action != null) ...[const SizedBox(width: 12), action!],
      ],
    );
  }
}

/// Compacte primaire knop ("+ Techniek"), 48px hoog.
class HeaderButton extends StatelessWidget {
  const HeaderButton({super.key, required this.label, required this.onPressed, this.icon = Icons.add});
  final String label;
  final VoidCallback onPressed;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    return FilledButton.icon(
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 48),
        padding: const EdgeInsets.symmetric(horizontal: 16),
        backgroundColor: k.primary,
        foregroundColor: k.onPrimary,
        elevation: 0,
      ),
      onPressed: () {
        HapticFeedback.selectionClick();
        onPressed();
      },
      icon: Icon(icon, size: 20),
      label: Text(label, style: context.t.bodyStrong.copyWith(color: k.onPrimary)),
    );
  }
}

/// Zoekveld volgens de mockup: 48px, well-vlak, zoekicoon, wisknop.
class KSearchField extends StatelessWidget {
  const KSearchField({super.key, required this.controller, required this.hint, required this.onChanged});
  final TextEditingController controller;
  final String hint;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    return TextField(
      controller: controller,
      onChanged: onChanged,
      style: context.t.body,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: hint,
        prefixIcon: Icon(Icons.search, color: k.textSecondary, size: 22),
        suffixIcon: controller.text.isEmpty
            ? null
            : IconButton(
                tooltip: 'Wissen',
                icon: Icon(Icons.close, color: k.textSecondary, size: 20),
                onPressed: () {
                  controller.clear();
                  onChanged('');
                },
              ),
      ),
    );
  }
}

/// Horizontale chiprij die tot aan de schermrand doorloopt.
class ChipRow extends StatelessWidget {
  const ChipRow({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          for (var i = 0; i < children.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            children[i],
          ],
        ],
      ),
    );
  }
}

/// Lege staat in een kaart: icoon, tekst en optioneel een knop.
class EmptyCard extends StatelessWidget {
  const EmptyCard({super.key, required this.icon, required this.title, required this.message, this.action});
  final IconData icon;
  final String title;
  final String message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return KCard(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          IconTile(icon: icon, size: 48, color: context.k.textSecondary),
          const SizedBox(height: 12),
          Text(title, style: context.t.subtitle, textAlign: TextAlign.center),
          const SizedBox(height: 4),
          Text(message, style: context.t.body.copyWith(color: context.k.textSecondary), textAlign: TextAlign.center),
          if (action != null) ...[const SizedBox(height: 16), action!],
        ],
      ),
    );
  }
}

// ------------------------------------------------------------ vault-acties

/// Lopende acties per techniek, zodat snel dubbeltikken op een
/// bibliotheektechniek geen twee eigen kopieën maakt.
final Set<String> _pending = {};

String _pendingKey(VaultEntry e) => e.library?.id ?? e.own!.id;

Future<void> _guarded(VaultEntry e, Future<void> Function() action) async {
  final key = _pendingKey(e);
  if (!_pending.add(key)) return;
  try {
    await action();
  } finally {
    _pending.remove(key);
  }
}

/// "+1 Rep": maakt zo nodig eerst je eigen kopie van de bibliotheektechniek.
Future<void> addRep(BuildContext context, VaultEntry e) => _guarded(e, () async {
  final store = KineticScope.read(context);
  final messenger = ScaffoldMessenger.of(context);
  HapticFeedback.lightImpact();
  final wasLibrary = !e.isOwn;
  final ok = await store.addVaultReps(e);
  if (!ok) {
    showToastOn(messenger, 'Rep opslaan mislukt. Controleer je verbinding.', error: true);
  } else if (wasLibrary) {
    showToastOn(messenger, '${e.name} staat nu in je technieken • 1 rep gelogd');
  }
});

/// Zet een techniek in of uit "Focus in Sessie" (de live mat-tellers).
Future<void> toggleFocus(BuildContext context, VaultEntry e) => _guarded(e, () async {
  final store = KineticScope.read(context);
  final messenger = ScaffoldMessenger.of(context);
  HapticFeedback.selectionClick();
  final on = !e.inFocus;
  final ok = await store.toggleVaultFocus(e);
  if (!ok) {
    showToastOn(messenger, 'Focus aanpassen mislukt', error: true);
  } else {
    showToastOn(messenger, on ? '${e.name} telt mee in je volgende sessie' : '${e.name} uit focus');
  }
});

/// Neemt een bibliotheektechniek over in je eigen technieken.
Future<void> addToVault(BuildContext context, VaultEntry e) => _guarded(e, () async {
  if (e.isOwn) return;
  final store = KineticScope.read(context);
  final messenger = ScaffoldMessenger.of(context);
  HapticFeedback.selectionClick();
  final t = await store.ensureOwnTechnique(e);
  showToastOn(
    messenger,
    t == null ? 'Toevoegen mislukt. Controleer je verbinding.' : '${e.name} toegevoegd aan je technieken',
    error: t == null,
  );
});

/// Zoekt de actuele vault-regel terug (na een actie verandert de sleutel
/// van `lib:<id>` naar de eigen id).
VaultEntry? locateEntry(List<VaultEntry> vault, {String? ownId, String? libraryId}) {
  if (ownId != null) {
    for (final e in vault) {
      if (e.own?.id == ownId) return e;
    }
  }
  if (libraryId != null) {
    for (final e in vault) {
      if (e.library?.id == libraryId) return e;
    }
  }
  return null;
}

String repsLabel(int reps) => reps == 1 ? '1 rep gelogd' : '${thousands(reps)} reps gelogd';

// ------------------------------------------------------------ detailvel

/// Detailvel van een techniek: uitleg, disciplines, tags en acties.
Future<void> showTechniqueSheet(BuildContext context, VaultEntry entry) {
  return showKineticSheet<void>(
    context,
    builder: (_) => _TechniqueSheet(ownId: entry.own?.id, libraryId: entry.library?.id, fallback: entry),
  );
}

class _TechniqueSheet extends StatelessWidget {
  const _TechniqueSheet({required this.ownId, required this.libraryId, required this.fallback});
  final String? ownId;
  final String? libraryId;
  final VaultEntry fallback;

  @override
  Widget build(BuildContext context) {
    final store = KineticScope.of(context);
    final k = context.k;
    final e = locateEntry(store.vault, ownId: ownId, libraryId: libraryId) ?? fallback;
    final lib = e.library;
    final own = e.own;
    final mastery = e.masteryPercent;
    final goal = own?.learningGoal.trim() ?? '';
    final transition = (own?.transition.trim().isNotEmpty ?? false) ? own!.transition.trim() : (lib?.transition.trim() ?? '');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            GroupTag(e.group),
            if (e.difficulty != null) DifficultyPill(e.difficulty!),
            if (e.isOwn)
              const KPill('In je vault', tone: KTone.success, icon: Icons.check, dense: true)
            else
              const KPill('Bibliotheek', icon: Icons.local_library_outlined, dense: true),
            if (e.inFocus) const KPill('In focus', tone: KTone.primary, icon: Icons.center_focus_strong, dense: true),
          ],
        ),
        const SizedBox(height: 12),
        Text(e.name, style: context.t.headline),
        if (e.subtitle.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(e.subtitle, style: context.t.caption),
        ],
        const SizedBox(height: 16),
        if (e.isOwn) ...[
          Row(
            children: [
              Expanded(
                child: MetricTile(
                  label: 'Herhalingen',
                  value: thousands(e.loggedReps),
                  sub: 'reps gelogd',
                  icon: Icons.repeat,
                  inWell: true,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: MetricTile(
                  label: 'Mastery Index',
                  value: mastery == null ? '—' : '$mastery%',
                  sub: mastery == null ? 'Nog niet beoordeeld' : 'Laatste 5 beoordelingen',
                  icon: Icons.insights,
                  valueColor: mastery == null ? k.textMuted : k.accent,
                  inWell: true,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
        ],
        if (own == null && e.description.isNotEmpty) ...[
          _SheetSection(
            icon: Icons.insights,
            label: 'Uitleg',
            child: Text(e.description, style: context.t.body.copyWith(color: k.textSecondary)),
          ),
          const SizedBox(height: 8),
        ],
        if (goal.isNotEmpty) ...[
          _SheetSection(icon: Icons.flag_outlined, label: 'Doel', child: Text(goal, style: context.t.body)),
          const SizedBox(height: 8),
        ],
        if (transition.isNotEmpty) ...[
          _SheetSection(icon: Icons.trending_flat, label: 'Overgang', child: Text(transition, style: context.t.body)),
          const SizedBox(height: 8),
        ],
        if (lib?.strikeCode != null) ...[
          _SheetSection(icon: Icons.tag, label: 'Telcode', child: Text(lib!.strikeCode!, style: context.t.bodyStrong)),
          const SizedBox(height: 8),
        ],
        if (own != null) ...[
          const SizedBox(height: 8),
          TechniqueDetails(techniqueId: own.id),
          const SizedBox(height: 8),
        ] else if ((lib?.videoUrls ?? const []).isNotEmpty) ...[
          const SizedBox(height: 8),
          const DetailHeader(icon: Icons.ondemand_video, title: "Video's"),
          VideoList(urls: lib!.videoUrls),
          Text("Voeg de techniek toe aan je vault om eigen video's, notities en beoordelingen te maken.", style: context.t.caption),
          const SizedBox(height: 8),
        ],
        if (e.disciplines.isNotEmpty) ...[
          const SizedBox(height: 8),
          const Eyebrow('Disciplines'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [for (final d in e.disciplines) KPill(disciplineLabel(d), dense: true)],
          ),
        ],
        if ((lib?.tags ?? const []).isNotEmpty) ...[
          const SizedBox(height: 16),
          const Eyebrow('Tags'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [for (final t in lib!.tags) KPill('#$t', dense: true)],
          ),
        ],
        const SizedBox(height: 20),
        FocusToggleRow(entry: e, inWell: true),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: e.isOwn
                  ? BigButton(
                      label: '+1 Rep',
                      icon: Icons.repeat,
                      style: KButtonStyle.secondary,
                      onPressed: () => addRep(context, e),
                    )
                  : BigButton(
                      label: 'Toevoegen',
                      icon: Icons.add,
                      onPressed: () => addToVault(context, e),
                    ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: BigButton(
                label: 'Sluiten',
                style: KButtonStyle.ghost,
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _SheetSection extends StatelessWidget {
  const _SheetSection({required this.icon, required this.label, required this.child});
  final IconData icon;
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return KWell(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: context.k.accent),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label.toUpperCase(), style: context.t.labelSm),
                const SizedBox(height: 4),
                child,
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// De "Focus in Sessie"-schakelaar: tekst, icoon én switch, zodat de
/// status nooit alleen uit kleur blijkt.
class FocusToggleRow extends StatelessWidget {
  const FocusToggleRow({super.key, required this.entry, this.inWell = false});
  final VaultEntry entry;
  final bool inWell;

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    final on = entry.inFocus;
    final row = Row(
      children: [
        Icon(on ? Icons.center_focus_strong : Icons.center_focus_weak, size: 22, color: on ? k.accent : k.textSecondary),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Focus in Sessie', style: context.t.bodyStrong.copyWith(color: on ? k.accent : k.text)),
              if (on || inWell)
                Text(
                  on ? 'Telt mee op de live mat' : 'Niet in je volgende sessie',
                  style: context.t.caption,
                ),
            ],
          ),
        ),
        ExcludeSemantics(
          child: Switch(value: on, onChanged: (_) => toggleFocus(context, entry)),
        ),
      ],
    );
    return Semantics(
      toggled: on,
      button: true,
      label: 'Focus in Sessie',
      child: Material(
        color: inWell ? (on ? k.primaryTint : k.well) : const Color(0x00000000),
        borderRadius: BorderRadius.circular(KRadius.md),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => toggleFocus(context, entry),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: inWell ? 56 : 52),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: inWell ? 12 : 0, vertical: 4),
              child: row,
            ),
          ),
        ),
      ),
    );
  }
}

/// Bottom sheet met één tekstveld (naam) en een bevestigknop.
Future<String?> askName(
  BuildContext context, {
  required String title,
  required String hint,
  required String confirm,
  String initial = '',
  String? subtitle,
}) {
  return showKineticSheet<String>(
    context,
    builder: (_) => _NameSheet(title: title, hint: hint, confirm: confirm, initial: initial, subtitle: subtitle),
  );
}

class _NameSheet extends StatefulWidget {
  const _NameSheet({required this.title, required this.hint, required this.confirm, required this.initial, this.subtitle});
  final String title;
  final String hint;
  final String confirm;
  final String initial;
  final String? subtitle;

  @override
  State<_NameSheet> createState() => _NameSheetState();
}

class _NameSheetState extends State<_NameSheet> {
  late final _ctrl = TextEditingController(text: widget.initial);

  @override
  void initState() {
    super.initState();
    _ctrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  void _done() {
    final v = _ctrl.text.trim();
    if (v.isNotEmpty) Navigator.of(context).pop(v);
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(widget.title, style: context.t.headline),
        if (widget.subtitle != null) ...[
          const SizedBox(height: 4),
          Text(widget.subtitle!, style: context.t.caption),
        ],
        const SizedBox(height: 16),
        TextField(
          controller: _ctrl,
          autofocus: true,
          maxLength: 80,
          textCapitalization: TextCapitalization.sentences,
          style: context.t.body,
          decoration: InputDecoration(labelText: 'Naam', hintText: widget.hint),
          onSubmitted: (_) => _done(),
        ),
        const SizedBox(height: 8),
        BigButton(label: widget.confirm, onPressed: _ctrl.text.trim().isEmpty ? null : _done),
      ],
    );
  }
}

/// Bevestiging voor iets dat niet terug te draaien is.
Future<bool> confirmDelete(BuildContext context, {required String title, required String message}) async {
  final k = context.k;
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuleren')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: k.danger, foregroundColor: Colors.white),
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('Verwijderen'),
        ),
      ],
    ),
  );
  return ok ?? false;
}

/// Uitklapbare groepskop (accordeon) voor Vault en Ontdekken.
class GroupHeader extends StatelessWidget {
  const GroupHeader({
    super.key,
    required this.group,
    required this.count,
    required this.focusCount,
    required this.expanded,
    required this.onTap,
  });
  final TechniqueGroup group;
  final int count;
  final int focusCount;
  final bool expanded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    return Semantics(
      button: true,
      expanded: expanded,
      child: KCard(
        padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
        onTap: onTap,
        child: Row(
          children: [
            IconTile(icon: groupIcon(group), size: 40, color: groupColor(context, group)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(group.label, style: context.t.subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
                  const SizedBox(height: 2),
                  Text(
                    focusCount > 0 ? '${group.description} • $focusCount in focus' : group.description,
                    style: context.t.caption,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            CountBadge(count: count, highlight: focusCount > 0),
            const SizedBox(width: 4),
            AnimatedRotation(
              turns: expanded ? 0.5 : 0,
              duration: const Duration(milliseconds: 180),
              child: Icon(Icons.expand_more, color: k.textSecondary, size: 26),
            ),
          ],
        ),
      ),
    );
  }
}

class CountBadge extends StatelessWidget {
  const CountBadge({super.key, required this.count, required this.highlight});
  final int count;
  final bool highlight;

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    return Container(
      constraints: const BoxConstraints(minWidth: 32),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: highlight ? k.primaryTint : k.well,
        borderRadius: BorderRadius.circular(KRadius.full),
      ),
      child: Text(
        '$count',
        style: context.t.caption.copyWith(
          color: highlight ? k.accent : k.textSecondary,
          fontWeight: FontWeight.w700,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}
