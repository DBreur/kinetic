// onboarding_screen.dart
//
// Het eerste scherm van Kinetic. Draait één keer, vóór de tabbalk bestaat.
// Drie stappen in een PageView; na de laatste stap pushReplacement naar de shell.
//
// Let op: dit scherm heeft GEEN AppBar. De balk bovenin is een voortgangsbalk,
// gewoon een Row van drie Containers. Zie de notitie onderaan dit bestand.

import 'package:flutter/material.dart';
import '../core/formatters.dart';
import '../models/app_profile.dart';
import '../services/dexcom_credentials.dart';
import '../services/dexcom_share_service.dart';
import '../state/app_controller.dart';
import '../theme/kinetic_theme.dart';
import '../widgets/kinetic.dart';

class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key, required this.controller});

  final AppController controller;

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  int _step = 0; // 0, 1, 2
  late GlucoseSource _source;
  late double _trainingLimit;
  late bool _breakSilentMode;
  late final TextEditingController _dexcomUsername;
  late final TextEditingController _dexcomPassword;
  late String _dexcomServer;
  bool _testingDexcom = false;
  String? _dexcomTestResult;

  @override
  void initState() {
    super.initState();
    final profile = widget.controller.profile!;
    _source = profile.glucoseSource;
    _trainingLimit = profile.trainingLimit;
    _breakSilentMode = profile.breakSilentMode;
    _dexcomUsername = TextEditingController(text: profile.dexcomUsername);
    _dexcomPassword = TextEditingController();
    _dexcomServer = profile.dexcomServer;
  }

  @override
  void dispose() {
    _dexcomUsername.dispose();
    _dexcomPassword.dispose();
    super.dispose();
  }

  Future<void> _testDexcomConnection() async {
    final username = _dexcomUsername.text.trim();
    final password = _dexcomPassword.text.trim();
    if (username.isEmpty || password.isEmpty) {
      setState(
        () => _dexcomTestResult = 'Vul gebruikersnaam en wachtwoord in.',
      );
      return;
    }
    setState(() {
      _testingDexcom = true;
      _dexcomTestResult = null;
    });
    final snapshot = await DexcomShareService(
      username: username,
      password: password,
      server: _dexcomServer,
    ).fetch(count: 1);
    if (!mounted) return;
    setState(() {
      _testingDexcom = false;
      _dexcomTestResult = snapshot.reading != null
          ? 'Verbonden · laatste meting ${relativeDutch(snapshot.reading!.at)}'
          : (snapshot.message ?? 'Verbinding mislukt.');
    });
  }

  Future<void> _next() async {
    if (_step == 2) {
      if (_source == GlucoseSource.dexcomShare) {
        // Los geprobeerd: een mislukte secure-storage-schrijfactie mag het
        // afronden van de onboarding niet blokkeren.
        try {
          final password = _dexcomPassword.text.trim();
          if (password.isEmpty) {
            await DexcomCredentials.delete();
          } else {
            await DexcomCredentials.write(password);
          }
        } catch (_) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Dexcom-wachtwoord kon niet veilig worden opgeslagen. Je '
                  'kan dit later opnieuw proberen in Instellingen.',
                ),
              ),
            );
          }
        }
      }
      final profile = widget.controller.profile!;
      await widget.controller.saveProfile(
        profile.copyWith(
          glucoseSource: _source,
          trainingLimit: _trainingLimit,
          breakSilentMode: _breakSilentMode,
          dexcomUsername: _dexcomUsername.text,
          dexcomServer: _dexcomServer,
          onboardingCompleted: true,
        ),
      );
    } else {
      setState(() => _step++);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColor.bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _ProgressBar(step: _step),
              const SizedBox(height: AppSpace.lg),
              Expanded(
                child: switch (_step) {
                  0 => const _StepIntro(),
                  1 => _StepSource(
                    value: _source,
                    onChanged: (v) => setState(() {
                      _source = v;
                      _dexcomTestResult = null;
                    }),
                    dexcomUsername: _dexcomUsername,
                    dexcomPassword: _dexcomPassword,
                    dexcomServer: _dexcomServer,
                    onDexcomServerChanged: (v) =>
                        setState(() => _dexcomServer = v),
                    testingDexcom: _testingDexcom,
                    dexcomTestResult: _dexcomTestResult,
                    onTestDexcom: _testDexcomConnection,
                  ),
                  _ => _StepAlarm(
                    value: _trainingLimit,
                    onChanged: (v) => setState(() => _trainingLimit = v),
                    breakSilentMode: _breakSilentMode,
                    onBreakSilentModeChanged: (v) =>
                        setState(() => _breakSilentMode = v),
                  ),
                },
              ),
              AnimatedBuilder(
                animation: widget.controller,
                builder: (context, _) => FilledButton(
                  onPressed: widget.controller.busy ? null : _next,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(56),
                  ),
                  child: Text(
                    widget.controller.busy
                        ? 'Opslaan...'
                        : (_step == 2 ? 'Klaar - open Kinetic' : 'Volgende'),
                  ),
                ),
              ),
              if (widget.controller.authError != null) ...[
                const SizedBox(height: 10),
                Text(
                  widget.controller.authError!,
                  style: AppText.caption.copyWith(color: AppColor.redBright),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ── Voortgangsbalk ──────────────────────────────────────────────────────────

class _ProgressBar extends StatelessWidget {
  const _ProgressBar({required this.step});
  final int step;

  static const _labels = ['Intro', 'Glucosebron', 'Alarm'];

  @override
  Widget build(BuildContext context) {
    final pct = ((step + 1) / 3 * 100).round();
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColor.surface,
        borderRadius: BorderRadius.circular(AppRadius.xl),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: KLabel(
                  'Stap ${step + 1} van 3: ${_labels[step]}',
                  color: AppColor.ice,
                ),
              ),
              KLabel('$pct%', color: AppColor.ink),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.chip),
            child: LinearProgressIndicator(
              value: (step + 1) / 3,
              minHeight: 6,
              backgroundColor: AppColor.bgDeep,
              valueColor: const AlwaysStoppedAnimation(AppColor.coral),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              for (var i = 0; i < 3; i++) ...[
                if (i > 0) const SizedBox(width: 6),
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: i == step ? AppColor.surfaceRaised : AppColor.bgDeep,
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                    ),
                    child: Text(
                      '0${i + 1} ${_labels[i]}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppText.caption.copyWith(
                        color: i == step
                            ? AppColor.coralSoft
                            : (i < step ? AppColor.ice : AppColor.inkMuted),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

// ── Stap 1: wat is dit ──────────────────────────────────────────────────────

class _StepIntro extends StatelessWidget {
  const _StepIntro();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        const KLogo(size: 64),
        const SizedBox(height: AppSpace.lg),
        Text(
          'KINETIC',
          style: AppText.display.copyWith(fontSize: 40, letterSpacing: 2),
        ),
        const SizedBox(height: 14),
        Text(
          'Je glucose en je sambo-training in één logboek. Zodat je na afloop '
          'weet wat er gebeurde — en tijdens de training weet wanneer je moet stoppen.',
          textAlign: TextAlign.center,
          style: AppText.bodyLarge.copyWith(color: AppColor.inkMuted),
        ),
      ],
    );
  }
}

// ── Stap 2: bron van de glucosedata ─────────────────────────────────────────

class _StepSource extends StatelessWidget {
  const _StepSource({
    required this.value,
    required this.onChanged,
    required this.dexcomUsername,
    required this.dexcomPassword,
    required this.dexcomServer,
    required this.onDexcomServerChanged,
    required this.testingDexcom,
    required this.dexcomTestResult,
    required this.onTestDexcom,
  });
  final GlucoseSource value;
  final ValueChanged<GlucoseSource> onChanged;
  final TextEditingController dexcomUsername;
  final TextEditingController dexcomPassword;
  final String dexcomServer;
  final ValueChanged<String> onDexcomServerChanged;
  final bool testingDexcom;
  final String? dexcomTestResult;
  final VoidCallback onTestDexcom;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Waar komt je glucose vandaan?',
            style: AppText.display.copyWith(fontSize: 30),
          ),
          const SizedBox(height: AppSpace.xl - 2),
          _SourceCard(
            title: 'Dexcom G7',
            body:
                'Rechtstreeks via je Dexcom-account. Waardes komen elke 5 '
                'minuten binnen, alarmen werken automatisch.',
            selected: value == GlucoseSource.dexcomShare,
            onTap: () => onChanged(GlucoseSource.dexcomShare),
          ),
          if (value == GlucoseSource.dexcomShare) ...[
            const SizedBox(height: 10),
            TextField(
              controller: dexcomUsername,
              style: AppText.body,
              decoration: InputDecoration(
                labelText: 'Dexcom-gebruikersnaam',
                filled: true,
                fillColor: AppColor.surface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: dexcomPassword,
              obscureText: true,
              style: AppText.body,
              decoration: InputDecoration(
                labelText: 'Dexcom-wachtwoord',
                filled: true,
                fillColor: AppColor.surface,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
              ),
            ),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(
                  value: 'shareous1.dexcom.com',
                  label: Text(
                    'Buiten de VS',
                    softWrap: false,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                ButtonSegment(value: 'share2.dexcom.com', label: Text('VS')),
              ],
              selected: {dexcomServer},
              onSelectionChanged: (v) => onDexcomServerChanged(v.first),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: testingDexcom ? null : onTestDexcom,
              child: Text(
                testingDexcom ? 'Verbinding testen...' : 'Verbinding testen',
              ),
            ),
            if (dexcomTestResult != null) ...[
              const SizedBox(height: 6),
              Text(dexcomTestResult!, style: AppText.caption),
            ],
            const SizedBox(height: 6),
            Text(
              'Zet "Delen" aan in de Dexcom-app. Geen officiële koppeling — '
              'kan enkele minuten achterlopen.',
              style: AppText.caption.copyWith(fontSize: 10),
            ),
          ],
          const SizedBox(height: AppSpace.sm + 2),
          _SourceCard(
            title: 'Nightscout',
            body:
                'Libre of Dexcom via een Nightscout-site. Waardes komen elke '
                '5 minuten binnen, alarmen werken automatisch.',
            selected: value == GlucoseSource.nightscout,
            onTap: () => onChanged(GlucoseSource.nightscout),
          ),
          const SizedBox(height: AppSpace.sm + 2),
          _SourceCard(
            title: 'Vingerprik',
            body:
                'Je voert zelf in. Kinetic herinnert je eraan voor en na de training.',
            selected: value == GlucoseSource.finger,
            onTap: () => onChanged(GlucoseSource.finger),
          ),
          const SizedBox(height: AppSpace.lg),
          Text(
            'Je kunt dit later altijd nog aanpassen in Instellingen.',
            style: AppText.caption.copyWith(color: AppColor.inkFaint),
          ),
        ],
      ),
    );
  }
}

class _SourceCard extends StatelessWidget {
  const _SourceCard({
    required this.title,
    required this.body,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String body;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.xl),
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: selected ? AppColor.greenWash : AppColor.surface,
          borderRadius: BorderRadius.circular(AppRadius.xl),
          border: Border.all(
            color: selected ? AppColor.green : AppColor.line,
            width: 1.5,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: AppText.bodyStrong.copyWith(fontSize: 15)),
            const SizedBox(height: 5),
            Text(body, style: AppText.caption.copyWith(fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

// ── Stap 3: alarmgrens ──────────────────────────────────────────────────────

class _StepAlarm extends StatelessWidget {
  const _StepAlarm({
    required this.value,
    required this.onChanged,
    required this.breakSilentMode,
    required this.onBreakSilentModeChanged,
  });
  final double value;
  final ValueChanged<double> onChanged;
  final bool breakSilentMode;
  final ValueChanged<bool> onBreakSilentModeChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Wanneer moet Kinetic alarm slaan?',
          style: AppText.display.copyWith(fontSize: 30),
        ),
        const SizedBox(height: AppSpace.xl - 2),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: AppColor.surface,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('ONDERGRENS TIJDENS TRAINING', style: AppText.overline),
              const SizedBox(height: 14),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    mmolText(value),
                    style: AppText.display.copyWith(
                      fontSize: 52,
                      color: AppColor.redBright,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text('mmol/L', style: AppText.caption.copyWith(fontSize: 13)),
                ],
              ),
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  activeTrackColor: AppColor.red,
                  inactiveTrackColor: AppColor.line,
                  thumbColor: AppColor.ink,
                  trackHeight: 4,
                  overlayShape: SliderComponentShape.noOverlay,
                ),
                child: Slider(
                  value: value,
                  min: 4.0,
                  max: 6.5,
                  divisions: 25,
                  onChanged: onChanged,
                ),
              ),
              Text(
                'Hoger dan je normale grens van 3,9 — tijdens inspanning zakt je '
                'waarde sneller dan de sensor laat zien.',
                style: AppText.caption.copyWith(fontSize: 12),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpace.md + 2),
        Container(
          padding: const EdgeInsets.all(15),
          decoration: BoxDecoration(
            color: const Color(0x14FF4D4D),
            borderRadius: BorderRadius.circular(AppRadius.lg),
            border: Border.all(color: const Color(0x33FF4D4D)),
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Alarm doorbreekt stille modus en gaat over het vergrendelscherm heen.',
                  style: AppText.caption.copyWith(fontSize: 12),
                ),
              ),
              const SizedBox(width: AppSpace.md),
              Switch(
                value: breakSilentMode,
                onChanged: onBreakSilentModeChanged,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── NOTITIE OVER DE BALK BOVENIN ────────────────────────────────────────────
//
// Geen enkel scherm in Uchivo gebruikt een gewone AppBar. Per scherm:
//
// Onboarding      → geen balk. De streepjes zijn _ProgressBar hierboven.
//
// Nu / Training / → een Row of Column binnen de body, boven de scrollende
// Technieken /      inhoud. Wil je dat de titel wegschuift bij scrollen, gebruik
// Inzicht           dan CustomScrollView met SliverAppBar(
//                     backgroundColor: AppColor.bg, elevation: 0,
//                     largeTitle-achtige opbouw via flexibleSpace).
//                   Wil je dat hij blijft staan: gewoon een Container boven de
//                   ListView, met een Divider(color: AppColor.lineSoft) eronder.
//
// Sessie- en      → AppBar mág hier, want het is een gepushte pagina met een
// techniekdetail,   terugknop. Zet dan wel:
// instellingen        AppBar(backgroundColor: AppColor.bg, elevation: 0,
//                            scrolledUnderElevation: 0,
//                            titleTextStyle: AppText.bodyStrong.copyWith(fontSize: 14))
//                   Anders krijg je Material's standaard lichtblauwe tint.
//
// Mat-modus       → de gekleurde glucosebalk is GEEN AppBar maar een Container
//                   met een achtergrondkleur die meebeweegt met je waarde
//                   (groen → amber → rood). Dat kan een AppBar niet netjes,
//                   en je wil er geen terugknop in.
