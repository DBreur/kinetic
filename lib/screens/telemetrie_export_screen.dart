// telemetrie_export_screen.dart: Instellingen & Data Export: sync-status
// (Supabase, Dexcom, Polar), glucosebron instellen, CSV/JSON-export met
// optionele anonimisering, en uitloggen.

import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../core/formatters.dart';
import '../models/kinetic_profile.dart';
import '../services/telemetry_export.dart';
import '../theme/kinetic_theme.dart';
import '../widgets/kinetic_widgets.dart';

class TelemetrieExportScreen extends StatelessWidget {
  const TelemetrieExportScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final store = KineticScope.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Instellingen & Data Export')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        children: [
          const _SyncStatus(),
          const SizedBox(height: 12),
          const _GlucoseSourceCard(),
          const SizedBox(height: 12),
          const _ExportCard(),
          const SizedBox(height: 12),
          KCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Eyebrow('Account', icon: Icons.person_outline),
                const SizedBox(height: 8),
                Text(store.email ?? '-', style: KText.body),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size.fromHeight(52),
                    foregroundColor: KColor.danger,
                    side: const BorderSide(color: KColor.danger),
                  ),
                  onPressed: () async {
                    final ok = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: const Text('Uitloggen?'),
                        content: const Text('Je data blijft in Supabase. Het Dexcom-wachtwoord blijft op dit toestel.'),
                        actions: [
                          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Annuleren')),
                          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Uitloggen')),
                        ],
                      ),
                    );
                    if (ok != true || !context.mounted) return;
                    Navigator.of(context).popUntil((r) => r.isFirst);
                    await store.signOut();
                  },
                  icon: const Icon(Icons.logout),
                  label: const Text('Uitloggen'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          Center(child: Text('Kinetic 2.0 • Supabase project wpexdeglubtzkdejehkj', style: KText.caption.copyWith(color: KColor.textMuted))),
        ],
      ),
    );
  }
}

class _SyncStatus extends StatelessWidget {
  const _SyncStatus();

  @override
  Widget build(BuildContext context) {
    final store = KineticScope.of(context);
    final now = store.now();
    final r = store.reading;
    String ago(DateTime? t) {
      if (t == null) return 'nog niet';
      final m = now.difference(t).inMinutes;
      return m <= 0 ? 'zojuist' : '$m min geleden';
    }

    final source = store.profile?.glucoseSource ?? GlucoseSource.dexcomShare;
    final glucoseOk = r != null && !r.isStale;
    return KCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(child: Eyebrow('Sync status', color: KColor.tealLight, icon: Icons.sync)),
              TextButton(onPressed: store.refreshAll, child: const Text('Nu synchroniseren')),
            ],
          ),
          _StatusRow(
            title: 'Supabase',
            detail: store.syncError ?? 'Gesynchroniseerd ${ago(store.lastSyncAt)}',
            ok: store.syncError == null && store.lastSyncAt != null,
          ),
          _StatusRow(
            title: source.label,
            detail: r == null
                ? (store.glucose?.message ?? 'Geen data')
                : 'Laatste meting ${ago(r.at)} • ${r.mmol.toStringAsFixed(1)} mmol/L',
            ok: glucoseOk,
          ),
          _StatusRow(
            title: 'Polar H10',
            detail: store.heartRate.isSimulated ? 'Niet gekoppeld: hartslag is een simulatie' : 'Verbonden',
            ok: !store.heartRate.isSimulated,
            warn: store.heartRate.isSimulated,
          ),
        ],
      ),
    );
  }
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({required this.title, required this.detail, required this.ok, this.warn = false});
  final String title;
  final String detail;
  final bool ok;
  final bool warn;

  @override
  Widget build(BuildContext context) {
    final color = ok ? KColor.success : (warn ? KColor.warning : KColor.danger);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: [
          Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: KText.body.copyWith(fontWeight: FontWeight.w700)),
                Text(detail, style: KText.caption),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

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
    return KCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Eyebrow('Glucosebron', color: KColor.tealLight, icon: Icons.sensors),
          const SizedBox(height: 10),
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
            TextField(controller: _dexUser, style: KText.body, decoration: const InputDecoration(labelText: 'Dexcom-gebruikersnaam')),
            const SizedBox(height: 10),
            TextField(
              controller: _dexPass,
              obscureText: true,
              style: KText.body,
              decoration: const InputDecoration(
                labelText: 'Dexcom-wachtwoord',
                hintText: 'Leeg laten = huidig wachtwoord houden',
              ),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              children: [
                KChip(label: 'Buiten de VS', selected: _server == 'shareous1.dexcom.com', onTap: () => setState(() => _server = 'shareous1.dexcom.com')),
                KChip(label: 'VS', selected: _server == 'share2.dexcom.com', onTap: () => setState(() => _server = 'share2.dexcom.com')),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Het wachtwoord staat alleen versleuteld op dit toestel, nooit in Supabase. "Delen" moet aan staan in de Dexcom-app. Dexcom Share is een niet-officiële API.',
              style: KText.caption,
            ),
          ],
          if (_source == GlucoseSource.nightscout) ...[
            TextField(controller: _nsUrl, style: KText.body, keyboardType: TextInputType.url, decoration: const InputDecoration(labelText: 'Nightscout-URL (https://)')),
            const SizedBox(height: 10),
            TextField(controller: _nsToken, obscureText: true, style: KText.body, decoration: const InputDecoration(labelText: 'API-token (optioneel)')),
          ],
          if (_source == GlucoseSource.finger)
            Text('Je logt waarden zelf via Snelle actie → Sensor Kalibratie.', style: KText.caption),
          const SizedBox(height: 14),
          BigButton(label: _saving ? 'Opslaan…' : 'Glucosebron opslaan', icon: Icons.save_outlined, height: 56, onPressed: _saving ? null : _save),
        ],
      ),
    );
  }
}

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
    return KCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Eyebrow('Data export', color: KColor.tealLight, icon: Icons.ios_share),
          const SizedBox(height: 10),
          Text('Periode', style: KText.caption),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final r in _Range.values) KChip(label: r.label, selected: _range == r, onTap: () => setState(() => _range = r)),
            ],
          ),
          const SizedBox(height: 12),
          Text('Formaat', style: KText.caption),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            children: [
              KChip(label: 'CSV (per tabel)', selected: !_json, onTap: () => setState(() => _json = false)),
              KChip(label: 'JSON', selected: _json, onTap: () => setState(() => _json = true)),
            ],
          ),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            value: _anonymize,
            onChanged: (v) => setState(() => _anonymize = v),
            title: Text('Data anonimiseren', style: KText.body.copyWith(fontWeight: FontWeight.w700)),
            subtitle: Text('Zonder id\'s, omschrijvingen en notities; tijden als "dag N uu:mm".', style: KText.caption),
          ),
          const SizedBox(height: 8),
          BigButton(
            label: _busy ? 'Bezig…' : 'Exporteren & delen',
            icon: Icons.download,
            height: 56,
            onPressed: _busy ? null : _export,
          ),
        ],
      ),
    );
  }
}
