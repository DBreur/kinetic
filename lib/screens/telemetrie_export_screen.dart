// telemetrie_export_screen.dart: Telemetrie & Instellingen
// (kinetic_telemetrie_export_instellingen): profiel en sync-status,
// gekoppelde sensoren (Dexcom/Polar), de glucosebron, metabole drempels,
// weergave, CSV/JSON-export met optionele anonimisering, en uitloggen.

import 'dart:async';
import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../core/formatters.dart';
import '../core/glucose_rules.dart';
import '../models/kinetic_profile.dart';
import '../services/telemetry_export.dart';
import '../state/kinetic_store.dart';
import '../theme/kinetic_theme.dart';
import '../widgets/kinetic_widgets.dart';
import '../widgets/sheets.dart';

class TelemetrieExportScreen extends StatelessWidget {
  const TelemetrieExportScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = KineticScope.of(context);
    final k = context.k;
    final r = store.reading;
    final cgmLive = r != null && store.now().difference(r.at).inMinutes < 15;
    final active = (cgmLive ? 1 : 0) + (store.heartRate.isSimulated ? 0 : 1);
    return KineticPage(
      subtitle: 'Telemetrie & Instellingen',
      body: ListView(
        padding: pagePadding(context, top: 16),
        children: [
          const _ProfileCard(),
          const SizedBox(height: 24),
          _SectionHeader(
            icon: Icons.sensors,
            title: 'Gekoppelde sensoren',
            trailing: KPill('$active actief', tone: active > 0 ? KTone.primary : KTone.neutral, dense: true),
          ),
          const _DexcomCard(),
          const SizedBox(height: 12),
          const _PolarCard(),
          const SizedBox(height: 12),
          const _GlucoseSourceCard(),
          const SizedBox(height: 24),
          const _SectionHeader(icon: Icons.tune, title: 'Metabole drempels & protocol'),
          const _ThresholdsCard(),
          const SizedBox(height: 24),
          const _SectionHeader(icon: Icons.contrast, title: 'Weergave'),
          KCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Thema', style: context.t.bodyStrong),
                const SizedBox(height: 2),
                Text('Donker is "Metabolic Combat", licht is de dagweergave.', style: context.t.caption),
                const SizedBox(height: 10),
                KSegmented<bool>(
                  options: const [(false, 'Licht'), (true, 'Donker')],
                  value: store.darkMode,
                  onChanged: (v) {
                    if (v != store.darkMode) store.toggleTheme();
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          const _SectionHeader(icon: Icons.ios_share, title: 'Data export & rapportage'),
          const _ExportCard(),
          const SizedBox(height: 24),
          const _SectionHeader(icon: Icons.person_outline, title: 'Account'),
          KCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(store.email ?? '-', style: context.t.bodyStrong),
                const SizedBox(height: 2),
                Text('Je data blijft in Supabase. Het Dexcom-wachtwoord blijft op dit toestel.', style: context.t.caption),
                const SizedBox(height: 14),
                BigButton(
                  label: 'Uitloggen',
                  icon: Icons.logout,
                  color: k.danger,
                  foreground: k.dangerInk,
                  outlined: true,
                  onPressed: () => _signOut(context),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          Center(
            child: Text(
              'Kinetic 2.0 • Supabase project wpexdeglubtzkdejehkj',
              style: context.t.caption.copyWith(color: k.textMuted),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _signOut(BuildContext context) async {
    final store = KineticScope.read(context);
    final k = context.k;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Uitloggen?'),
        content: const Text('Je data blijft in Supabase. Het Dexcom-wachtwoord blijft op dit toestel.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuleren')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: k.danger, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Uitloggen'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    Navigator.of(context).popUntil((r) => r.isFirst);
    await store.signOut();
  }
}

/// Sectiekop uit de mockup: teal icoon + uppercase label.
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.icon, required this.title, this.trailing});
  final IconData icon;
  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Icon(icon, size: 18, color: k.accent),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              title.toUpperCase(),
              style: context.t.label.copyWith(color: k.text, fontWeight: FontWeight.w700),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

String _ago(DateTime? t, DateTime now) {
  if (t == null) return 'nog niet';
  final m = now.difference(t).inMinutes;
  if (m <= 0) return 'zojuist';
  if (m < 60) return '$m min geleden';
  final h = m ~/ 60;
  if (h < 24) return '$h uur geleden';
  return shortDate(t);
}

// --------------------------------------------------------------- profiel

class _ProfileCard extends StatefulWidget {
  const _ProfileCard();

  @override
  State<_ProfileCard> createState() => _ProfileCardState();
}

class _ProfileCardState extends State<_ProfileCard> {
  bool _syncing = false;

  Future<void> _sync() async {
    final store = KineticScope.read(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _syncing = true);
    await store.refreshAll();
    if (!mounted) return;
    setState(() => _syncing = false);
    final err = store.syncError;
    showToastOn(messenger, err ?? 'Gesynchroniseerd met Supabase', error: err != null);
  }

  @override
  Widget build(BuildContext context) {
    final store = KineticScope.of(context);
    final k = context.k;
    final now = store.now();
    final ok = store.syncError == null && store.lastSyncAt != null;
    final statusColor = ok ? k.successInk : (store.syncError != null ? k.dangerInk : k.warningInk);
    final name = store.displayName.isEmpty ? 'Atleet' : store.displayName;
    return KCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              KAvatar(initials: store.initials, size: 56),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(child: Text(name, style: context.t.title, overflow: TextOverflow.ellipsis)),
                        const SizedBox(width: 8),
                        const KPill('T1D', tone: KTone.primary, dense: true),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(store.email ?? '-', style: context.t.caption, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Container(width: 8, height: 8, decoration: BoxDecoration(color: statusColor, shape: BoxShape.circle)),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(
                            ok ? 'ACTIEF GESYNCHRONISEERD' : (store.syncError != null ? 'SYNC MISLUKT' : 'NOG NIET GESYNCHRONISEERD'),
                            style: context.t.labelSm.copyWith(color: statusColor),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          KWell(
            padding: const EdgeInsets.fromLTRB(12, 4, 4, 4),
            child: Row(
              children: [
                Icon(ok ? Icons.cloud_done_outlined : Icons.cloud_off_outlined, size: 20, color: statusColor),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Supabase', style: context.t.bodyStrong),
                      Text(
                        store.syncError ?? 'Gesynchroniseerd ${_ago(store.lastSyncAt, now)}',
                        style: context.t.caption,
                      ),
                    ],
                  ),
                ),
                TextButton(
                  onPressed: _syncing ? null : _sync,
                  child: Text(_syncing ? 'Bezig…' : 'Nu synchroniseren'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// -------------------------------------------------------------- sensoren

class _DexcomCard extends StatelessWidget {
  const _DexcomCard();

  @override
  Widget build(BuildContext context) {
    final store = KineticScope.of(context);
    final k = context.k;
    final now = store.now();
    final r = store.reading;
    final source = store.profile?.glucoseSource ?? GlucoseSource.dexcomShare;
    final age = r == null ? null : now.difference(r.at).inMinutes;
    final live = age != null && age < 15;
    final title = switch (source) {
      GlucoseSource.dexcomShare => 'Dexcom G7 (CGM)',
      GlucoseSource.nightscout => 'Nightscout (CGM)',
      GlucoseSource.finger => 'Vingerprik (handmatig)',
    };
    final status = r == null
        ? (store.glucose?.message ?? 'Geen data')
        : '${live || source == GlucoseSource.finger ? 'Verbonden' : 'Verbinding kwijt'} • ${dec1(r.mmol)} mmol/L ${trendArrow(r.trend)}';
    final (tone, pill) = r == null
        ? (KTone.danger, 'Geen data')
        : live
        ? (KTone.success, 'Live')
        : source == GlucoseSource.finger
        ? (KTone.neutral, 'Handmatig')
        : (KTone.warning, 'Oud');
    return KCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconTile(icon: Icons.signal_cellular_alt, size: 44, color: k.accent),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: context.t.subtitle),
                    const SizedBox(height: 2),
                    Text(status, style: context.t.caption),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              KPill(pill, tone: tone, dot: true, dense: true),
            ],
          ),
          const SizedBox(height: 12),
          KWell(
            padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
            child: Row(
              children: [
                Icon(Icons.schedule, size: 16, color: k.textSecondary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    r == null ? 'Nog geen meting ontvangen' : 'Laatste meting ${_ago(r.at, now)} (${hhmm(r.at)})',
                    style: context.t.caption,
                  ),
                ),
                FilledButton.icon(
                  onPressed: () => showFingerstickSheet(context),
                  icon: const Icon(Icons.water_drop_outlined, size: 18),
                  label: const Text('Kalibreren'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PolarCard extends StatelessWidget {
  const _PolarCard();

  @override
  Widget build(BuildContext context) {
    final store = KineticScope.of(context);
    final k = context.k;
    final simulated = store.heartRate.isSimulated;
    return KCard(
      child: Row(
        children: [
          IconTile(icon: Icons.monitor_heart_outlined, size: 44, color: k.blue),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Polar H10 hartslagband', style: context.t.subtitle),
                const SizedBox(height: 2),
                Text(
                  simulated ? 'Niet gekoppeld: hartslag is een simulatie' : 'Verbonden • ${store.heartRateBpm} BPM',
                  style: context.t.caption,
                ),
                if (simulated) ...[
                  const SizedBox(height: 2),
                  Text('Gesimuleerde waarden worden nooit opgeslagen.', style: context.t.caption.copyWith(color: k.textMuted)),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          KPill(
            simulated ? 'Simulatie' : 'Verbonden',
            tone: simulated ? KTone.warning : KTone.success,
            dot: true,
            dense: true,
          ),
        ],
      ),
    );
  }
}

// ------------------------------------------------------------ glucosebron

class _GlucoseSourceCard extends StatefulWidget {
  const _GlucoseSourceCard();

  @override
  State<_GlucoseSourceCard> createState() => _GlucoseSourceCardState();
}

class _GlucoseSourceCardState extends State<_GlucoseSourceCard> {
  late GlucoseSource _source;
  final _dexUser = TextEditingController();
  final _dexPass = TextEditingController();
  final _nsUrl = TextEditingController();
  final _nsToken = TextEditingController();
  String _server = 'shareous1.dexcom.com';
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final p = KineticScope.read(context).profile;
    _source = p?.glucoseSource ?? GlucoseSource.dexcomShare;
    _dexUser.text = p?.dexcomUsername ?? '';
    _server = p?.dexcomServer ?? _server;
    _nsUrl.text = p?.nightscoutUrl ?? '';
    _nsToken.text = p?.nightscoutToken ?? '';
  }

  @override
  void dispose() {
    for (final c in [_dexUser, _dexPass, _nsUrl, _nsToken]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    if (_source == GlucoseSource.nightscout && _nsUrl.text.trim().isNotEmpty && !_nsUrl.text.trim().startsWith('https://')) {
      showToast(context, 'Nightscout-URL moet met https:// beginnen', error: true);
      return;
    }
    setState(() => _saving = true);
    final ok = await KineticScope.read(context).saveGlucoseSettings(
      source: _source,
      dexcomUsername: _dexUser.text,
      dexcomPassword: _dexPass.text.isEmpty ? null : _dexPass.text,
      dexcomServer: _server,
      nightscoutUrl: _nsUrl.text,
      nightscoutToken: _nsToken.text,
    );
    if (!mounted) return;
    setState(() => _saving = false);
    _dexPass.clear();
    showToast(context, ok ? 'Glucosebron opgeslagen' : 'Opslaan mislukt', error: !ok);
  }

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    return KCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.bloodtype_outlined, size: 20, color: k.accent),
              const SizedBox(width: 8),
              Expanded(child: Text('Glucosebron', style: context.t.subtitle)),
            ],
          ),
          const SizedBox(height: 4),
          Text('Waar Kinetic je glucosewaarden vandaan haalt.', style: context.t.caption),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final s in GlucoseSource.values)
                KChip(label: s.label, selected: _source == s, onTap: () => setState(() => _source = s)),
            ],
          ),
          const SizedBox(height: 14),
          if (_source == GlucoseSource.dexcomShare) ...[
            TextField(
              controller: _dexUser,
              style: context.t.body,
              decoration: const InputDecoration(labelText: 'Dexcom-gebruikersnaam', prefixIcon: Icon(Icons.person_outline)),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _dexPass,
              obscureText: true,
              style: context.t.body,
              decoration: const InputDecoration(
                labelText: 'Dexcom-wachtwoord',
                hintText: 'Leeg laten = huidig wachtwoord houden',
                prefixIcon: Icon(Icons.lock_outline),
              ),
            ),
            const SizedBox(height: 12),
            Text('Dexcom-server', style: context.t.caption),
            const SizedBox(height: 6),
            KSegmented<String>(
              options: const [('shareous1.dexcom.com', 'Buiten de VS'), ('share2.dexcom.com', 'VS')],
              value: _server == 'share2.dexcom.com' ? 'share2.dexcom.com' : 'shareous1.dexcom.com',
              onChanged: (v) => setState(() => _server = v),
            ),
            const SizedBox(height: 10),
            Text(
              'Het wachtwoord staat alleen versleuteld op dit toestel, nooit in Supabase. "Delen" moet aan staan in de Dexcom-app. Dexcom Share is een niet-officiële API.',
              style: context.t.caption,
            ),
          ],
          if (_source == GlucoseSource.nightscout) ...[
            TextField(
              controller: _nsUrl,
              style: context.t.body,
              keyboardType: TextInputType.url,
              decoration: const InputDecoration(labelText: 'Nightscout-URL (https://)', prefixIcon: Icon(Icons.link)),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _nsToken,
              obscureText: true,
              style: context.t.body,
              decoration: const InputDecoration(labelText: 'API-token (optioneel)', prefixIcon: Icon(Icons.key_outlined)),
            ),
          ],
          if (_source == GlucoseSource.finger)
            KWell(
              child: Text('Je logt waarden zelf via Snelle actie → Sensor Kalibratie.', style: context.t.caption),
            ),
          const SizedBox(height: 14),
          BigButton(
            label: _saving ? 'Opslaan…' : 'Glucosebron opslaan',
            icon: Icons.save_outlined,
            style: KButtonStyle.secondary,
            onPressed: _saving ? null : _save,
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- drempels

class _ThresholdsCard extends StatefulWidget {
  const _ThresholdsCard();

  @override
  State<_ThresholdsCard> createState() => _ThresholdsCardState();
}

class _ThresholdsCardState extends State<_ThresholdsCard> {
  late final KineticStore _store = KineticScope.read(context);
  late double _low = _store.profile?.dailyLowBelow ?? 3.9;
  late double _hyper = _store.profile?.hyperLimit ?? 10.0;
  Timer? _debounce;

  @override
  void dispose() {
    if (_debounce?.isActive ?? false) {
      _debounce!.cancel();
      // Niet synchroon notificeren terwijl de boom wordt afgebroken.
      final store = _store;
      final (low, hyper) = (_low, _hyper);
      unawaited(Future(() => store.updateThresholds(lowBelow: low, hyperLimit: hyper)));
    }
    super.dispose();
  }

  /// Snel tikken op +/- telt lokaal door; pas na een korte pauze opslaan.
  void _set({double? low, double? hyper}) {
    setState(() {
      if (low != null) _low = double.parse(low.clamp(3.0, 6.0).toStringAsFixed(1));
      if (hyper != null) _hyper = double.parse(hyper.clamp(7.0, 20.0).toStringAsFixed(1));
    });
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 700), _save);
  }

  Future<void> _save() async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = await _store.updateThresholds(lowBelow: _low, hyperLimit: _hyper);
    if (!ok) showToastOn(messenger, 'Drempels opslaan mislukt', error: true);
  }

  @override
  Widget build(BuildContext context) {
    final store = KineticScope.of(context);
    final k = context.k;
    return KCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Glucose-eenheid', style: context.t.bodyStrong),
          const SizedBox(height: 8),
          KSegmented<String>(
            options: const [('mmol', 'mmol/L'), ('mgdl', 'mg/dL')],
            value: 'mmol',
            onChanged: (v) {
              if (v == 'mgdl') showToast(context, 'Kinetic rekent in mmol/L; mg/dL wordt nog niet ondersteund.');
            },
          ),
          const SizedBox(height: 16),
          _StepperRow(
            dot: k.danger,
            title: 'Hypo-waarschuwing',
            sub: 'Waarschuwen onder deze waarde',
            value: dec1(_low),
            onMinus: _low <= 3.0 ? null : () => _set(low: _low - 0.1),
            onPlus: _low >= 6.0 ? null : () => _set(low: _low + 0.1),
          ),
          const SizedBox(height: 8),
          _StepperRow(
            dot: k.warning,
            title: 'Hyper-drempel',
            sub: 'Bovenste corridorlimiet',
            value: dec1(_hyper),
            onMinus: _hyper <= 7.0 ? null : () => _set(hyper: _hyper - 0.5),
            onPlus: _hyper >= 20.0 ? null : () => _set(hyper: _hyper + 0.5),
          ),
          const SizedBox(height: 6),
          Text(
            'Doelbereik op de mat: ${dec1(targetLow)} - ${dec1(targetHigh)} mmol/L. Hypo-alarm in de app onder ${dec1(hypoBelow)} mmol/L.',
            style: context.t.caption.copyWith(color: k.textMuted),
          ),
          const SizedBox(height: 16),
          Text('Snelle koolhydraten-noodknop', style: context.t.bodyStrong),
          const SizedBox(height: 2),
          Text('Grootte van de dextrose-knop bij een hypo of in de ronde-rust.', style: context.t.caption),
          const SizedBox(height: 8),
          KSegmented<int>(
            options: const [(10, '10g'), (15, '15g (standaard)'), (20, '20g')],
            value: store.fastCarbGrams,
            onChanged: store.setFastCarbGrams,
          ),
        ],
      ),
    );
  }
}

class _StepperRow extends StatelessWidget {
  const _StepperRow({
    required this.dot,
    required this.title,
    required this.sub,
    required this.value,
    required this.onMinus,
    required this.onPlus,
  });
  final Color dot;
  final String title;
  final String sub;
  final String value;
  final VoidCallback? onMinus;
  final VoidCallback? onPlus;

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    Widget step(IconData icon, VoidCallback? onTap) => Opacity(
      opacity: onTap == null ? 0.4 : 1,
      child: IgnorePointer(
        ignoring: onTap == null,
        child: StepButton(icon: icon, size: 48, onTap: onTap ?? () {}),
      ),
    );
    return KWell(
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      child: Row(
        children: [
          Container(width: 8, height: 8, decoration: BoxDecoration(color: dot, shape: BoxShape.circle)),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: context.t.bodyStrong),
                Text(sub, style: context.t.caption),
              ],
            ),
          ),
          const SizedBox(width: 6),
          step(Icons.remove, onMinus),
          SizedBox(
            width: 52,
            child: Text(value, textAlign: TextAlign.center, style: context.t.metricSm.copyWith(color: k.accent)),
          ),
          step(Icons.add, onPlus),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------- export

enum _Range {
  week('7 dagen', 7),
  month('30 dagen', 30),
  quarter('90 dagen', 90),
  all('Alles', null);

  const _Range(this.label, this.days);
  final String label;
  final int? days;
}

class _ExportCard extends StatefulWidget {
  const _ExportCard();

  @override
  State<_ExportCard> createState() => _ExportCardState();
}

class _ExportCardState extends State<_ExportCard> {
  _Range _range = _Range.month;
  bool _json = false;
  bool _anonymize = false;
  bool _busy = false;

  Future<void> _export() async {
    final store = KineticScope.read(context);
    setState(() => _busy = true);
    try {
      final since = _range.days == null ? null : dayStart(store.now()).subtract(Duration(days: _range.days! - 1));
      final data = await store.collectExport(since: since);
      if (data.isEmpty) {
        if (mounted) showToast(context, 'Geen data in deze periode', error: true);
        return;
      }
      final tables = buildExportTables(data, anonymize: _anonymize);
      final dir = await getTemporaryDirectory();
      final stamp = store.now().toIso8601String().substring(0, 10);
      final files = <XFile>[];
      if (_json) {
        final f = File('${dir.path}/kinetic_export_$stamp.json');
        await f.writeAsString(tablesToJson(tables, anonymize: _anonymize));
        files.add(XFile(f.path, mimeType: 'application/json'));
      } else {
        for (final e in tables.entries) {
          if (e.value.isEmpty) continue;
          final f = File('${dir.path}/kinetic_${e.key}_$stamp.csv');
          await f.writeAsString(tableToCsv(e.value));
          files.add(XFile(f.path, mimeType: 'text/csv'));
        }
      }
      await SharePlus.instance.share(ShareParams(
        files: files,
        subject: 'Kinetic telemetrie-export ($stamp)',
        text: 'Kinetic export: ${data.meals.length} maaltijden, ${data.weighIns.length} wegingen, '
            '${data.sessions.length} sessies, ${data.glucose.length} glucosewaarden${_anonymize ? ' (geanonimiseerd)' : ''}.',
      ));
    } catch (_) {
      if (mounted) showToast(context, 'Export mislukt', error: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final k = context.k;
    return KCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Trainings- & glycemisch rapport', style: context.t.subtitle),
          const SizedBox(height: 4),
          Text(
            'Maaltijden, wegingen, sessies en glucosewaarden voor je endocrinoloog, sportdiëtist of hoofdcoach.',
            style: context.t.caption,
          ),
          const SizedBox(height: 16),
          Text('EXPORTFORMAAT', style: context.t.labelSm),
          const SizedBox(height: 8),
          KSegmented<bool>(
            options: const [(false, 'CSV (per tabel)'), (true, 'JSON')],
            value: _json,
            onChanged: (v) => setState(() => _json = v),
          ),
          const SizedBox(height: 16),
          Text('TIJDSBESTEK', style: context.t.labelSm),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final r in _Range.values) KChip(label: r.label, selected: _range == r, onTap: () => setState(() => _range = r)),
            ],
          ),
          const SizedBox(height: 16),
          KWell(
            padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
            onTap: () => setState(() => _anonymize = !_anonymize),
            child: Row(
              children: [
                Icon(Icons.shield_outlined, size: 20, color: _anonymize ? k.accent : k.textSecondary),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Data anonimiseren', style: context.t.bodyStrong),
                      Text('Zonder id\'s, omschrijvingen en notities; tijden als "dag N uu:mm".', style: context.t.caption),
                    ],
                  ),
                ),
                Switch(value: _anonymize, onChanged: (v) => setState(() => _anonymize = v)),
              ],
            ),
          ),
          const SizedBox(height: 16),
          BigButton(
            label: _busy ? 'Bezig…' : 'Exporteer telemetriedata',
            icon: Icons.file_download_outlined,
            height: 56,
            onPressed: _busy ? null : _export,
          ),
        ],
      ),
    );
  }
}
