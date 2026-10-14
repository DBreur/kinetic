import 'package:flutter/material.dart';

import '../core/formatters.dart';
import '../core/positions.dart';
import '../core/combination_sort.dart';
import '../core/technique_sort.dart';
import '../models/combination.dart';
import '../models/glucose.dart';
import '../models/technique.dart';
import '../models/training_session.dart';
import '../repositories/combination_repository.dart';
import '../repositories/session_repository.dart';
import '../repositories/technique_repository.dart';
import '../services/background_glucose_service.dart';
import '../services/finger_reminder_service.dart';
import '../models/agenda.dart';
import '../services/glucose_provider.dart';
import '../services/notification_router.dart';
import '../services/system_bars.dart';
import '../state/app_controller.dart';
import '../state/live_session_controller.dart';
import '../state/mat_session_controller.dart';
import '../state/strength_session_controller.dart';
import '../theme/kinetic_theme.dart';
import '../widgets/empty_state.dart';
import '../widgets/ground_position_tags.dart';
import '../widgets/kinetic.dart';
import 'combination_detail_screen.dart';
import 'combination_view_screen.dart';
import 'exercise_progress_list_screen.dart';
import 'food_log_screen.dart';
import 'insights_screen.dart';
import 'mat_mode_screen.dart';
import 'agenda_screen.dart';
import 'now_screen.dart';
import 'profile_screen.dart';
import 'session_detail_screen.dart';
import 'settings_screen.dart';
import 'strength_mode_screen.dart';
import 'technique_detail_screen.dart';
import 'technique_edit_screen.dart';
import 'technique_map_screen.dart';
import 'training_library_screen.dart';

class ShellScreen extends StatefulWidget {
  const ShellScreen({super.key, required this.controller});

  final AppController controller;

  @override
  State<ShellScreen> createState() => _ShellScreenState();
}

class _ShellScreenState extends State<ShellScreen>
    with WidgetsBindingObserver {
  int _tab = 0;
  int _trainSegment = 0;
  final _foodKey = GlobalKey<FoodLogScreenState>();

  /// De actieve sambo-sessie, ook als MatModeScreen zelf niet in beeld is —
  /// zie mat_session_controller.dart. Null zolang er geen sessie loopt.
  MatSessionController? _liveMat;

  /// Zelfde principe als [_liveMat], maar voor een live krachttraining — zie
  /// strength_session_controller.dart.
  StrengthSessionController? _liveStrength;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.controller.addListener(_syncBackgroundWatcher);
    _syncBackgroundWatcher();
    NotificationRouter.pendingStart.addListener(_onStartRequest);
    // Geopend via een melding terwijl de app dicht was?
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await NotificationRouter.checkLaunchDetails();
      _onStartRequest();
    });
  }

  /// Geplande trainingen die in deze sessie van de app al gestart zijn —
  /// zodat de "Start nu"-kaart daarna niet opnieuw verschijnt.
  final Set<String> _startedPlanned = {};

  void _onStartRequest() {
    final request = NotificationRouter.pendingStart.value;
    if (request == null || !mounted) return;
    NotificationRouter.pendingStart.value = null;
    if (request.startNow) {
      _startPlanned(request.trainingId, request.kind, request.title);
    } else {
      setState(() => _tab = KineticTab.today.index);
    }
  }

  /// Start de sessie die bij een geplande training hoort: mat-sessie bij
  /// sambo, krachttraining bij kracht — met de geplande titel.
  Future<void> _startPlanned(
    String id,
    TrainingKind kind,
    String title,
  ) async {
    if (id.isNotEmpty) setState(() => _startedPlanned.add(id));
    final reading = widget.controller.cachedGlucose?.reading;
    if (kind == TrainingKind.kracht) {
      await _startOrResumeStrength(initialReading: reading, title: title);
    } else {
      await _startOrResumeMat(initialReading: reading, title: title);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Android kan de balken terugzetten terwijl de app op de achtergrond
    // stond — bij terugkomst de gekozen stand opnieuw toepassen.
    if (state == AppLifecycleState.resumed) SystemBars.reapply();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    NotificationRouter.pendingStart.removeListener(_onStartRequest);
    widget.controller.removeListener(_syncBackgroundWatcher);
    super.dispose();
  }

  /// Start of stopt de achtergrondbewaking van de dagelijkse ondergrens en de
  /// vingerprik-herinnering zodra het profiel verandert (bv. alarm uit,
  /// overschakelen naar vingerprik) — zie background_glucose_service.dart en
  /// finger_reminder_service.dart.
  void _syncBackgroundWatcher() {
    BackgroundGlucoseWatcher.instance.sync(widget.controller);
    FingerReminderService.instance.sync(widget.controller.profile);
    SystemBars.setAlwaysHidden(
      widget.controller.profile?.hideSystemBars ?? false,
    );
  }

  /// Start een nieuwe sambo-sessie, of heropent de lopende als er al één
  /// actief is (dan wordt [initialReading] genegeerd).
  Future<bool?> _startOrResumeMat({
    required GlucoseReading? initialReading,
    String title = 'Combat sambo',
  }) async {
    final existing = _liveMat;
    if (existing != null) return _openMat(existing);
    final profile = widget.controller.profile;
    final provider = profile == null ? null : await resolveGlucoseProvider(profile);
    final ctrl = MatSessionController(
      title: title,
      appController: widget.controller,
      contextOf: () => context,
      provider: provider,
      initialReading: initialReading,
    );
    return _openMat(ctrl);
  }

  Future<bool?> _openMat(MatSessionController ctrl) async {
    setState(() => _liveMat = ctrl);
    final result = await Navigator.of(context, rootNavigator: true).push<bool>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => MatModeScreen(controller: ctrl),
      ),
    );
    // null == geminimaliseerd (naar een ander tabblad), sessie blijft actief.
    // true/false == echt afgerond (opgeslagen of weggegooid).
    if (result != null && mounted) {
      setState(() => _liveMat = null);
      ctrl.dispose();
    }
    return result;
  }

  /// Start een nieuwe krachttraining, of heropent de lopende als er al één
  /// actief is (dan worden [initialReading]/[planned] genegeerd).
  Future<bool?> _startOrResumeStrength({
    required GlucoseReading? initialReading,
    String title = 'Krachttraining',
    List<ExerciseEntry> planned = const [],
    List<Circuit> plannedCircuits = const [],
  }) async {
    final existing = _liveStrength;
    if (existing != null) return _openStrength(existing);
    final profile = widget.controller.profile;
    final provider = profile == null ? null : await resolveGlucoseProvider(profile);
    final ctrl = StrengthSessionController(
      title: title,
      appController: widget.controller,
      contextOf: () => context,
      provider: provider,
      initialReading: initialReading,
      planned: planned,
      plannedCircuits: plannedCircuits,
    );
    return _openStrength(ctrl);
  }

  Future<bool?> _openStrength(StrengthSessionController ctrl) async {
    setState(() => _liveStrength = ctrl);
    final result = await Navigator.of(context, rootNavigator: true).push<bool>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => StrengthModeScreen(controller: ctrl),
      ),
    );
    // null == geminimaliseerd (naar een ander tabblad), sessie blijft actief.
    // true/false == echt afgerond (opgeslagen of weggegooid).
    if (result != null && mounted) {
      setState(() => _liveStrength = null);
      ctrl.dispose();
    }
    return result;
  }

  void _go(KineticTab tab) => setState(() => _tab = tab.index);

  Future<void> _openProfile() async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => ProfileScreen(
          controller: widget.controller,
          onOpenSettings: _openSettings,
        ),
      ),
    );
    if (mounted) setState(() {});
  }

  Future<void> _openSettings() async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => SettingsScreen(controller: widget.controller),
      ),
    );
    if (mounted) setState(() {});
  }

  static const _sections = ['Vandaag', 'Train', 'Eten', 'Biometrie', 'Agenda'];

  @override
  Widget build(BuildContext context) {
    // Geen IndexedStack: elke keer dat je een tab opent bouwt hij opnieuw
    // op en haalt hij verse sessies op. Bij dit datavolume (persoonlijk
    // gebruik) weegt dat niet op tegen state die na een opgeslagen sessie
    // stil zou blijven staan.
    final body = switch (KineticTab.values[_tab]) {
      KineticTab.today => NowScreen(
        alreadyStartedPlanned: _startedPlanned,
        sessionRunning: _liveMat != null || _liveStrength != null,
        onStartPlanned: (t) => _startPlanned(t.id, t.kind, t.displayTitle),
        controller: widget.controller,
        openMatSession: _startOrResumeMat,
        openStrengthSession: _startOrResumeStrength,
        onNavigate: _go,
        onOpenSettings: _openSettings,
      ),
      KineticTab.train => _TrainHub(
        controller: widget.controller,
        segment: _trainSegment,
        onSegment: (v) => setState(() => _trainSegment = v),
      ),
      KineticTab.food => FoodLogScreen(key: _foodKey, controller: widget.controller),
      KineticTab.biometrics => InsightsScreen(controller: widget.controller),
      KineticTab.agenda => AgendaScreen(controller: widget.controller),
    };
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            ValueListenableBuilder<GlucoseSnapshot?>(
              valueListenable: widget.controller.glucose,
              builder: (context, glucose, _) => KTopBar(
                section: _sections[_tab],
                glucose: glucose,
                avatarUrl: widget.controller.profile?.avatarUrl ?? '',
                initials: widget.controller.initials,
                onProfile: _openProfile,
                onSettings: _openSettings,
                trailing: KineticTab.values[_tab] == KineticTab.food
                    ? PopupMenuButton<bool>(
                        tooltip: 'Exporteren',
                        padding: EdgeInsets.zero,
                        icon: const Icon(
                          Icons.ios_share,
                          color: AppColor.inkMuted,
                          size: 22,
                        ),
                        onSelected: (pdf) =>
                            _foodKey.currentState?.exportLog(pdf),
                        itemBuilder: (_) => const [
                          PopupMenuItem(
                            value: true,
                            child: Text('Exporteer als PDF'),
                          ),
                          PopupMenuItem(
                            value: false,
                            child: Text('Exporteer als CSV'),
                          ),
                        ],
                      )
                    : null,
              ),
            ),
            if (_liveMat != null)
              _LiveSessionBar(
                controller: _liveMat!,
                onTap: () => _openMat(_liveMat!),
              ),
            if (_liveStrength != null)
              _LiveSessionBar(
                controller: _liveStrength!,
                onTap: () => _openStrength(_liveStrength!),
              ),
            Expanded(child: body),
          ],
        ),
      ),
      bottomNavigationBar: DecoratedBox(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: AppColor.line)),
        ),
        child: NavigationBar(
          selectedIndex: _tab,
          onDestinationSelected: (i) => setState(() => _tab = i),
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.track_changes),
              label: 'Vandaag',
            ),
            NavigationDestination(
              icon: Icon(Icons.sports_mma_outlined),
              selectedIcon: Icon(Icons.sports_mma),
              label: 'Train',
            ),
            NavigationDestination(
              icon: Icon(Icons.restaurant_outlined),
              selectedIcon: Icon(Icons.restaurant),
              label: 'Eten',
            ),
            NavigationDestination(
              icon: Icon(Icons.monitor_heart_outlined),
              selectedIcon: Icon(Icons.monitor_heart),
              label: 'Biometrie',
            ),
            NavigationDestination(
              icon: Icon(Icons.event_outlined),
              selectedIcon: Icon(Icons.event),
              label: 'Agenda',
            ),
          ],
        ),
      ),
    );
  }
}

/// Train-tab: schakelt tussen trainingslogboek en technieken.
class _TrainHub extends StatelessWidget {
  const _TrainHub({
    required this.controller,
    required this.segment,
    required this.onSegment,
  });

  final AppController controller;
  final int segment;
  final ValueChanged<int> onSegment;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpace.gutter,
            4,
            AppSpace.gutter,
            0,
          ),
          child: KSegmented<int>(
            options: const [
              (0, 'Trainingen', Icons.sports_mma_outlined),
              (1, 'Technieken', Icons.sports_martial_arts_outlined),
            ],
            selected: segment,
            onChanged: onSegment,
          ),
        ),
        Expanded(
          child: segment == 0
              ? TrainingScreen(controller: controller)
              : TechniquesScreen(controller: controller),
        ),
      ],
    );
  }
}

/// Permanente balk die op elk tabblad zichtbaar blijft zolang een sambo- of
/// krachtsessie op de achtergrond doorloopt — tik erop om hem weer te openen.
class _LiveSessionBar extends StatelessWidget {
  const _LiveSessionBar({required this.controller, required this.onTap});

  final LiveSessionController controller;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final e = controller.elapsed;
        final mm = e.inMinutes.toString().padLeft(2, '0');
        final ss = (e.inSeconds % 60).toString().padLeft(2, '0');
        final color = glucoseColor(glucoseStateFor(controller.glucoseMmol));
        return Material(
          color: AppColor.surface,
          child: InkWell(
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: AppColor.line)),
              ),
              child: Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      controller.isPaused
                          ? '${controller.title} · gepauzeerd'
                          : '${controller.title} · $mm:$ss',
                      style: AppText.bodyStrong.copyWith(fontSize: 13),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${mmolText(controller.glucoseMmol)} mmol/L',
                    style: AppText.caption,
                  ),
                  const SizedBox(width: 6),
                  const Icon(
                    Icons.chevron_right,
                    size: 18,
                    color: AppColor.inkFaint,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

// ───────────────────────── gedeelde laadstatus ──────────────────────────────

/// Haalt de sessies van de ingelogde gebruiker op. Elke tab die dit nodig
/// heeft roept dit zelf aan — bij dit datavolume weegt een aparte fetch per
/// tab niet op tegen de complexiteit van gedeelde state tussen tabs.
class _SessionsLoader extends StatefulWidget {
  const _SessionsLoader({required this.controller, required this.builder});

  final AppController controller;
  final Widget Function(
    BuildContext context,
    SessionRepository repo,
    List<TrainingSession> sessions,
    bool loading,
    VoidCallback reload,
  )
  builder;

  @override
  State<_SessionsLoader> createState() => _SessionsLoaderState();
}

class _SessionsLoaderState extends State<_SessionsLoader> {
  late final SessionRepository _repo;
  List<TrainingSession> _sessions = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _repo = SessionRepository(widget.controller.client!);
    _load();
  }

  Future<void> _load() async {
    final userId = widget.controller.user?.id;
    if (userId == null) return;
    setState(() => _loading = true);
    try {
      final sessions = await _repo.listForUser(userId);
      if (mounted) setState(() => _sessions = sessions);
    } catch (_) {
      // Lijst blijft leeg/oud; pull-to-refresh laat het opnieuw proberen.
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) =>
      widget.builder(context, _repo, _sessions, _loading, _load);
}

// ───────────────────────── Training ─────────────────────────────────────────

class TrainingScreen extends StatefulWidget {
  const TrainingScreen({super.key, required this.controller});

  final AppController controller;

  @override
  State<TrainingScreen> createState() => _TrainingScreenState();
}

class _TrainingScreenState extends State<TrainingScreen> {
  String _filter = 'Sambo';
  bool _searching = false;
  String _query = '';
  final _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _toggleSearch() {
    setState(() {
      _searching = !_searching;
      if (!_searching) {
        _query = '';
        _searchController.clear();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return _SessionsLoader(
      controller: widget.controller,
      builder: (context, repo, sessions, loading, reload) {
        final query = _query.trim().toLowerCase();
        final filtered = sessions.where((s) {
          if (_filter == 'Sambo' && s.kind != SessionKind.sambo) return false;
          if (_filter == 'Kracht' && s.kind != SessionKind.kracht) {
            return false;
          }
          if (query.isEmpty) return true;
          return s.title.toLowerCase().contains(query) ||
              dutchShortDate(s.startedAt).toLowerCase().contains(query);
        }).toList();
        final totalMinutes = sessions.fold<int>(
          0,
          (n, s) => n + s.durationMinutes,
        );

        return Scaffold(
          backgroundColor: AppColor.bg,
          body: RefreshIndicator(
            onRefresh: () async => reload(),
            child: ListView(
              padding: const EdgeInsets.only(bottom: 24),
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
                  child: _searching
                      ? Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _searchController,
                                autofocus: true,
                                style: AppText.bodyStrong,
                                onChanged: (v) => setState(() => _query = v),
                                decoration: InputDecoration(
                                  isDense: true,
                                  hintText: 'Zoek op naam of datum',
                                  hintStyle: AppText.body.copyWith(
                                    color: AppColor.inkGhost,
                                  ),
                                  border: InputBorder.none,
                                ),
                              ),
                            ),
                            IconButton(
                              onPressed: _toggleSearch,
                              icon: const Icon(
                                Icons.close,
                                color: AppColor.inkMuted,
                              ),
                            ),
                          ],
                        )
                      : Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Trainingen', style: AppText.title),
                                  const SizedBox(height: 6),
                                  Text(
                                    '${sessions.length} sessies · $totalMinutes min totaal',
                                    style: AppText.caption,
                                  ),
                                ],
                              ),
                            ),
                            IconButton(
                              onPressed: () => Navigator.push<void>(
                                context,
                                MaterialPageRoute(
                                  builder: (_) => ExerciseProgressListScreen(
                                    controller: widget.controller,
                                  ),
                                ),
                              ),
                              icon: const Icon(
                                Icons.show_chart,
                                color: AppColor.inkMuted,
                              ),
                              tooltip: 'Voortgang',
                            ),
                            IconButton(
                              onPressed: _toggleSearch,
                              icon: const Icon(
                                Icons.search,
                                color: AppColor.inkMuted,
                              ),
                            ),
                          ],
                        ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: SegmentedButton<String>(
                    showSelectedIcon: false,
                    segments: const [
                      ButtonSegment(value: 'Sambo', label: Text('Sambo')),
                      ButtonSegment(value: 'Kracht', label: Text('Kracht')),
                    ],
                    selected: {_filter},
                    onSelectionChanged: (v) =>
                        setState(() => _filter = v.first),
                  ),
                ),
                // Schema's, circuits en oefeningen horen bij krachttraining.
                if (_filter == 'Kracht')
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                  child: Row(
                    children: [
                      for (final (tab, icon, label) in const [
                        (LibraryTab.templates, Icons.view_list_outlined, "Schema's"),
                        (LibraryTab.circuits, Icons.loop, 'Circuits'),
                        (LibraryTab.exercises, Icons.fitness_center, 'Oefeningen'),
                      ]) ...[
                        if (tab != LibraryTab.templates) const SizedBox(width: 8),
                        Expanded(
                          child: KCard(
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            onTap: () => Navigator.push<void>(
                              context,
                              MaterialPageRoute(
                                builder: (_) => TrainingLibraryScreen(
                                  controller: widget.controller,
                                  initialTab: tab,
                                ),
                              ),
                            ),
                            child: Column(
                              children: [
                                Icon(icon, size: 20, color: AppColor.slate),
                                const SizedBox(height: 4),
                                Text(label, style: AppText.caption.copyWith(
                                  color: AppColor.ink,
                                )),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 6),
                if (!loading && filtered.isEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 30, 20, 0),
                    child: query.isNotEmpty
                        ? Text(
                            'Geen trainingen gevonden voor "$_query".',
                            style: AppText.caption,
                          )
                        : EmptyState(
                            icon: Icons.fitness_center_outlined,
                            message:
                                'Nog geen ${_filter.toLowerCase()}trainingen '
                                'opgeslagen. Start er een vanaf "Vandaag".',
                          ),
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                  child: Column(
                    children: [
                      for (final s in filtered)
                        _TrainingCard(
                          session: s,
                          onTap: () async {
                            final changed = await Navigator.push<bool>(
                              context,
                              MaterialPageRoute(
                                builder: (_) => SessionDetailScreen(
                                  session: s,
                                  repository: repo,
                                  controller: widget.controller,
                                ),
                              ),
                            );
                            if (changed == true) reload();
                          },
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _TrainingCard extends StatelessWidget {
  const _TrainingCard({required this.session, required this.onTap});

  final TrainingSession session;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final count = session.kind == SessionKind.sambo
        ? '${session.blocks.length} blokken'
        : '${session.exercises.length} oefeningen';
    final range = session.glucoseSeries.length >= 2
        ? '${mmolText(session.firstMmol!)} -> ${mmolText(session.lastMmol!)}'
        : '—';
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColor.surface,
          borderRadius: BorderRadius.circular(AppRadius.lg),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(session.title, style: AppText.bodyStrong),
                  const SizedBox(height: 2),
                  Text(
                    '${dutchShortDate(session.startedAt)} · $count',
                    style: AppText.caption,
                  ),
                ],
              ),
            ),
            Text(
              range,
              style: AppText.caption.copyWith(
                color: session.hadDip
                    ? AppColor.amberBright
                    : AppColor.greenBright,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ───────────────────────── Technieken ───────────────────────────────────────

class _TechniqueStat implements TechniqueSortable {
  _TechniqueStat({required this.name, required this.meta});

  @override
  final String name;
  final String meta;
  Technique? technique;
  int count = 0;
  int lastRating = 0;
  @override
  DateTime? lastDate;
  final List<TechniqueOccurrence> occurrences = [];

  @override
  bool get favorite => technique?.favorite ?? false;
  String get transition => technique?.transition ?? '';
  @override
  LearningStatus get learningStatus =>
      technique?.learningStatus ?? LearningStatus.none;
  DateTime? get plannedFor => technique?.plannedFor;
  String get learningGoal => technique?.learningGoal ?? '';
  @override
  DateTime? get createdAt => technique?.createdAt;
  List<String> get groundPositions => technique?.groundPositions ?? const [];

  /// Categorie voor het filteren — via dezelfde afleiding als de kaart voor
  /// een echte catalogustechniek, anders de ruwe categorie uit de meta-regel
  /// van een sessie-only techniek (nog niet aan de catalogus toegevoegd).
  String get category {
    final t = technique;
    if (t != null) return effectiveCategory(t);
    final first = meta.split(' · ').first;
    return first.isNotEmpty ? first : 'Overig';
  }
}

class TechniquesScreen extends StatefulWidget {
  const TechniquesScreen({super.key, required this.controller});

  final AppController controller;

  @override
  State<TechniquesScreen> createState() => _TechniquesScreenState();
}

enum _TechniquesView { techniques, combinations }


/// Vaste, begrensde verzameling categorieën om op te filteren — de vier
/// handmatige (zie kBlockCategories) plus de twee die de kaart afleidt uit
/// een transitie (Staand/Grondwerk) als er geen handmatige categorie is.
const _kFilterCategories = [
  'Takedown',
  'Submission',
  'Strike',
  'Staand',
  'Grondwerk',
  'Overig',
];

/// Resultaat van [_SortFilterSheet] — alleen gezet als op "Toepassen"
/// getikt is (anders blijft de huidige sortering/filtering ongewijzigd).
class _SortFilterResult {
  const _SortFilterResult({
    required this.sort,
    required this.categories,
    required this.statuses,
    required this.groundPositions,
    required this.onlyUnrated,
  });
  final TechniqueSort sort;
  final Set<String> categories;
  final Set<LearningStatus> statuses;
  final Set<String> groundPositions;
  final bool onlyUnrated;
}

class _TechniquesScreenState extends State<TechniquesScreen> {
  late final SessionRepository _sessionRepo;
  late final TechniqueRepository _techniqueRepo;
  late final CombinationRepository _comboRepo;
  List<TrainingSession> _sessions = [];
  List<Technique> _techniques = [];
  List<Combination> _combos = [];
  bool _comboFavOnly = false;
  ComboType? _comboType;
  ComboSort _comboSort = ComboSort.az;
  bool _loading = true;
  bool _searching = false;
  String _query = '';
  final _searchController = TextEditingController();
  _TechniquesView _view = _TechniquesView.techniques;
  TechniqueSort _sort = TechniqueSort.nameAsc;
  Set<String> _categoryFilter = {};
  Set<LearningStatus> _statusFilter = {};
  Set<String> _positionFilter = {};
  bool _onlyUnrated = false;

  bool get _filtersActive =>
      _categoryFilter.isNotEmpty ||
      _statusFilter.isNotEmpty ||
      _positionFilter.isNotEmpty ||
      _onlyUnrated;

  @override
  void initState() {
    super.initState();
    _sessionRepo = SessionRepository(widget.controller.client!);
    _techniqueRepo = TechniqueRepository(widget.controller.client!);
    _comboRepo = CombinationRepository(widget.controller.client!);
    _load();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _toggleSearch() {
    setState(() {
      _searching = !_searching;
      if (!_searching) {
        _query = '';
        _searchController.clear();
      }
    });
  }

  Future<void> _openSortFilterSheet() async {
    final result = await showModalBottomSheet<_SortFilterResult>(
      context: context,
      isScrollControlled: true,
      backgroundColor: AppColor.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppRadius.sheet),
        ),
      ),
      builder: (ctx) => _SortFilterSheet(
        initialSort: _sort,
        initialCategories: _categoryFilter,
        initialStatuses: _statusFilter,
        initialGroundPositions: _positionFilter,
        initialOnlyUnrated: _onlyUnrated,
      ),
    );
    if (result == null || !mounted) return;
    setState(() {
      _sort = result.sort;
      _categoryFilter = result.categories;
      _statusFilter = result.statuses;
      _positionFilter = result.groundPositions;
      _onlyUnrated = result.onlyUnrated;
    });
  }

  Future<void> _toggleFavorite(_TechniqueStat stat) async {
    final userId = widget.controller.user?.id;
    if (userId == null) return;
    try {
      if (stat.technique != null) {
        final updated = await _techniqueRepo.updateContent(
          stat.technique!.copyWith(favorite: !stat.technique!.favorite),
        );
        setState(() => stat.technique = updated);
      } else {
        final category = stat.meta.split(' · ').first.isNotEmpty
            ? stat.meta.split(' · ').first
            : 'Overig';
        final created = await _techniqueRepo.create(
          Technique(
            id: '',
            name: stat.name,
            category: category,
            favorite: true,
          ),
          userId,
        );
        setState(() {
          stat.technique = created;
          _techniques = [..._techniques, created];
        });
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Favoriet markeren is niet gelukt. Probeer opnieuw.'),
          ),
        );
      }
    }
  }

  Future<void> _load() async {
    final userId = widget.controller.user?.id;
    if (userId == null) return;
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        _sessionRepo.listForUser(userId),
        _techniqueRepo.listForUser(userId),
        _comboRepo.listForUser(userId),
      ]);
      if (mounted) {
        setState(() {
          _sessions = results[0] as List<TrainingSession>;
          _techniques = results[1] as List<Technique>;
          _combos = results[2] as List<Combination>;
        });
      }
    } catch (_) {
      // Lijst blijft leeg/oud; pull-to-refresh laat het opnieuw proberen.
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Bestaande combinatie: eerst bekijken (met ster en "Aanpassen"), net als
  /// een techniek. Nieuwe combinatie: meteen het bewerkscherm.
  Future<void> _openCombo([Combination? combo]) async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => combo == null
            ? CombinationDetailScreen(
                repository: _comboRepo,
                userId: widget.controller.user!.id,
                existingTechniques: _techniques,
              )
            : CombinationViewScreen(
                repository: _comboRepo,
                userId: widget.controller.user!.id,
                combination: combo,
                existingTechniques: _techniques,
              ),
      ),
    );
    if (changed == true) _load();
  }

  Future<void> _toggleComboFavorite(Combination combo) async {
    try {
      final updated = await _comboRepo.setFavorite(combo.id, !combo.favorite);
      if (!mounted) return;
      setState(() {
        _combos = [
          for (final c in _combos) c.id == updated.id ? updated : c,
        ];
      });
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Favoriet opslaan is niet gelukt.')),
        );
      }
    }
  }

  Future<void> _openTechnique(_TechniqueStat stat) async {
    final technique = stat.technique;
    // Nog geen eigen catalogusregel (alleen uit sessiegeschiedenis bekend) —
    // er is dan nog niets te bekijken, dus meteen naar het aanmaken/
    // aanpassen, net als bij een gloednieuwe techniek.
    if (technique == null) {
      final result = await Navigator.push<TechniqueEditResult>(
        context,
        MaterialPageRoute(
          builder: (_) => TechniqueEditScreen(
            repository: _techniqueRepo,
            userId: widget.controller.user!.id,
            initialName: stat.name,
            initialCategory: stat.meta.split(' · ').first.isNotEmpty
                ? stat.meta.split(' · ').first
                : 'Takedown',
          ),
        ),
      );
      if (result?.technique != null) _load();
      return;
    }
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => TechniqueDetailScreen(
          repository: _techniqueRepo,
          userId: widget.controller.user!.id,
          technique: technique,
          sessionOccurrences: stat.occurrences
              .where((o) => o.fromSession)
              .toList(),
        ),
      ),
    );
    if (changed == true) _load();
  }

  Future<void> _openMap() async {
    final changed = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => TechniqueMapScreen(
          repository: _techniqueRepo,
          userId: widget.controller.user!.id,
          techniques: _techniques,
        ),
      ),
    );
    if (changed == true) _load();
  }

  Future<void> _addTechnique() async {
    final result = await Navigator.push<TechniqueEditResult>(
      context,
      MaterialPageRoute(
        builder: (_) => TechniqueEditScreen(
          repository: _techniqueRepo,
          userId: widget.controller.user!.id,
        ),
      ),
    );
    if (result?.technique != null) _load();
  }

  @override
  Widget build(BuildContext context) {
    final byName = <String, _TechniqueStat>{};
    for (final s in _sessions.where((s) => s.kind == SessionKind.sambo)) {
      for (final b in s.blocks.where(
        (b) => b.covered && b.kind == BlockKind.technique,
      )) {
        final stat = byName.putIfAbsent(
          b.name,
          () => _TechniqueStat(name: b.name, meta: b.meta),
        );
        stat.count += 1;
        stat.occurrences.add(
          TechniqueOccurrence(
            date: s.startedAt,
            rating: b.rating,
            note: b.note,
            fromSession: true,
          ),
        );
        if (stat.lastDate == null || s.startedAt.isAfter(stat.lastDate!)) {
          stat.lastDate = s.startedAt;
          stat.lastRating = b.rating;
        }
      }
    }
    for (final t in _techniques) {
      final stat = byName.putIfAbsent(
        t.name,
        () => _TechniqueStat(name: t.name, meta: t.category),
      );
      stat.technique = t;
      stat.count += t.updates.length;
      for (final u in t.updates) {
        stat.occurrences.add(
          TechniqueOccurrence(date: u.at, rating: u.rating, note: u.note),
        );
        if (stat.lastDate == null || u.at.isAfter(stat.lastDate!)) {
          stat.lastDate = u.at;
          stat.lastRating = u.rating;
        }
      }
    }
    final query = _query.trim().toLowerCase();
    final techniques = byName.values
        .where((t) => query.isEmpty || t.name.toLowerCase().contains(query))
        .where(
          (t) =>
              _categoryFilter.isEmpty || _categoryFilter.contains(t.category),
        )
        .where(
          (t) => _statusFilter.isEmpty || _statusFilter.contains(t.learningStatus),
        )
        .where(
          (t) =>
              _positionFilter.isEmpty ||
              t.groundPositions.any(_positionFilter.contains),
        )
        .where((t) => !_onlyUnrated || t.lastRating == 0)
        .toList();
    // Favorieten staan altijd bovenaan, ongeacht de gekozen sortering — zie
    // sortTechniques in lib/core/technique_sort.dart.
    sortTechniques(techniques, _sort);
    final unrated = techniques.where((t) => t.lastRating == 0).length;
    final learning = techniques
        .where((t) => t.learningStatus == LearningStatus.learning)
        .toList();
    final planned = techniques.where((t) => t.plannedFor != null).toList()
      ..sort((a, b) => a.plannedFor!.compareTo(b.plannedFor!));

    final combos = sortAndFilterCombos(
      _combos,
      query: query,
      onlyFavorites: _comboFavOnly,
      type: _comboType,
      sort: _comboSort,
    );

    return Scaffold(
      backgroundColor: AppColor.bg,
      floatingActionButton: FloatingActionButton(
        onPressed: _view == _TechniquesView.techniques
            ? _addTechnique
            : () => _openCombo(),
        child: const Icon(Icons.add),
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 24),
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
              child: _searching
                  ? Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _searchController,
                            autofocus: true,
                            style: AppText.bodyStrong,
                            onChanged: (v) => setState(() => _query = v),
                            decoration: InputDecoration(
                              isDense: true,
                              hintText: 'Zoek op naam',
                              hintStyle: AppText.body.copyWith(
                                color: AppColor.inkGhost,
                              ),
                              border: InputBorder.none,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: _toggleSearch,
                          icon: const Icon(
                            Icons.close,
                            color: AppColor.inkMuted,
                          ),
                        ),
                      ],
                    )
                  : Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Technieken', style: AppText.title),
                              const SizedBox(height: 6),
                              Text(
                                '${techniques.length} vastgelegd · $unrated nog niet beoordeeld',
                                style: AppText.caption,
                              ),
                            ],
                          ),
                        ),
                        OutlinedButton.icon(
                          onPressed: () => _openMap(),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColor.tealBright,
                            side: const BorderSide(color: AppColor.teal),
                            minimumSize: const Size(0, 36),
                            padding: const EdgeInsets.symmetric(horizontal: 14),
                          ),
                          icon: const Icon(Icons.hub_outlined, size: 16),
                          label: const Text('Kaart'),
                        ),
                        if (_view == _TechniquesView.techniques)
                          Stack(
                            clipBehavior: Clip.none,
                            children: [
                              IconButton(
                                onPressed: _openSortFilterSheet,
                                icon: const Icon(
                                  Icons.tune,
                                  color: AppColor.inkMuted,
                                ),
                              ),
                              if (_filtersActive)
                                Positioned(
                                  right: 6,
                                  top: 6,
                                  child: Container(
                                    width: 8,
                                    height: 8,
                                    decoration: const BoxDecoration(
                                      color: AppColor.tealBright,
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        IconButton(
                          onPressed: _toggleSearch,
                          icon: const Icon(
                            Icons.search,
                            color: AppColor.inkMuted,
                          ),
                        ),
                      ],
                    ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: SegmentedButton<_TechniquesView>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(
                    value: _TechniquesView.techniques,
                    label: Text(
                      'Technieken',
                      softWrap: false,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  ButtonSegment(
                    value: _TechniquesView.combinations,
                    label: Text(
                      'Combinaties',
                      softWrap: false,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
                selected: {_view},
                onSelectionChanged: (v) => setState(() => _view = v.first),
              ),
            ),
            const SizedBox(height: 6),
            if (_view == _TechniquesView.techniques) ...[
              if (learning.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 10, 20, 8),
                  child: Text('BEZIG MET LEREN', style: AppText.overline),
                ),
                SizedBox(
                  height: 86,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    children: [
                      for (final t in learning)
                        _LearningCard(stat: t, onTap: () => _openTechnique(t)),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
              ],
              if (planned.isNotEmpty) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                  child: Text('PLANNING', style: AppText.overline),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
                  child: Column(
                    children: [
                      for (final t in planned)
                        _PlanningRow(stat: t, onTap: () => _openTechnique(t)),
                    ],
                  ),
                ),
              ],
              if (!_loading && techniques.isEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                  child: query.isNotEmpty
                      ? Text(
                          'Geen technieken gevonden voor "$_query".',
                          style: AppText.caption,
                        )
                      : const EmptyState(
                          icon: Icons.sports_martial_arts_outlined,
                          message:
                              'Nog geen technieken vastgelegd. Tik op + om '
                              'er zelf een toe te voegen, of beoordeel er '
                              'een tijdens een mat-sessie.',
                        ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 80),
                child: Column(
                  children: [
                    for (final t in techniques)
                      _TechniqueTile(
                        stat: t,
                        onTap: () => _openTechnique(t),
                        onToggleFavorite: () => _toggleFavorite(t),
                      ),
                  ],
                ),
              ),
            ] else ...[
              _ComboFilterBar(
                onlyFavorites: _comboFavOnly,
                type: _comboType,
                sort: _comboSort,
                onFavorites: (v) => setState(() => _comboFavOnly = v),
                onType: (v) => setState(() => _comboType = v),
                onSort: (v) => setState(() => _comboSort = v),
              ),
              if (!_loading && combos.isEmpty && _comboFavOnly)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                  child: Text(
                    'Nog geen favoriete combinaties. Tik op de ster bij een combinatie.',
                    style: AppText.caption,
                  ),
                )
              else if (!_loading && combos.isEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
                  child: query.isNotEmpty
                      ? Text(
                          'Geen combinaties gevonden voor "$_query".',
                          style: AppText.caption,
                        )
                      : const EmptyState(
                          icon: Icons.call_merge,
                          message:
                              'Nog geen combinaties vastgelegd. Tik op + om '
                              'er een te maken uit meerdere technieken.',
                        ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 80),
                child: Column(
                  children: [
                    for (final c in combos)
                      _CombinationTile(
                        combo: c,
                        onTap: () => _openCombo(c),
                        onToggleFavorite: () => _toggleComboFavorite(c),
                      ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Kleurkoppel (achtergrond/tekst) voor een leerstatus-badge — bewust
/// teal/groen/grijs, nooit amber/rood (dat is voorbehouden aan glucose).
(Color, Color)? _learningBadgeColors(LearningStatus status) => switch (status) {
  LearningStatus.learning => (AppColor.tealWash, AppColor.tealBright),
  LearningStatus.mastered => (AppColor.greenWash, AppColor.greenBright),
  LearningStatus.planned => (Colors.white.withValues(alpha: .08), AppColor.inkMuted),
  LearningStatus.none => null,
};

String? _learningBadgeText(_TechniqueStat stat) {
  switch (stat.learningStatus) {
    case LearningStatus.learning:
      return 'Bezig';
    case LearningStatus.mastered:
      return 'Beheerst';
    case LearningStatus.planned:
      return stat.plannedFor != null
          ? 'Gepland · ${dutchShortDate(stat.plannedFor!)}'
          : 'Gepland';
    case LearningStatus.none:
      return null;
  }
}

class _LearningStatusBadge extends StatelessWidget {
  const _LearningStatusBadge({required this.stat});
  final _TechniqueStat stat;

  @override
  Widget build(BuildContext context) {
    final colors = _learningBadgeColors(stat.learningStatus);
    final text = _learningBadgeText(stat);
    if (colors == null || text == null) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: colors.$1,
        borderRadius: BorderRadius.circular(99),
      ),
      child: Text(
        text,
        style: AppText.caption.copyWith(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: colors.$2,
        ),
      ),
    );
  }
}

/// Horizontale kaart in de "Bezig met leren"-sectie bovenaan het tabblad.
class _LearningCard extends StatelessWidget {
  const _LearningCard({required this.stat, required this.onTap});
  final _TechniqueStat stat;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: Container(
        width: 170,
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColor.surface,
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border(left: BorderSide(color: AppColor.teal, width: 2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              stat.name,
              style: AppText.bodyStrong,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            Text(
              stat.learningGoal.isNotEmpty
                  ? stat.learningGoal
                  : stat.lastRating > 0
                  ? 'Laatste: ${'★' * stat.lastRating}'
                  : 'Nog niet beoordeeld',
              style: AppText.caption,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}

/// Rij in de "Planning"-sectie bovenaan het tabblad.
class _PlanningRow extends StatelessWidget {
  const _PlanningRow({required this.stat, required this.onTap});
  final _TechniqueStat stat;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: AppColor.surface,
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                stat.name,
                style: AppText.bodyStrong,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              planningLabel(stat.plannedFor!),
              style: AppText.caption.copyWith(color: AppColor.inkMuted),
            ),
            const SizedBox(width: 6),
            const Icon(Icons.chevron_right, size: 18, color: AppColor.inkFaint),
          ],
        ),
      ),
    );
  }
}

/// Bottom sheet om de technieklijst te sorteren en filteren — levert pas een
/// resultaat op "Toepassen"; "Wissen" reset alleen het formulier hieronder.
class _SortFilterSheet extends StatefulWidget {
  const _SortFilterSheet({
    required this.initialSort,
    required this.initialCategories,
    required this.initialStatuses,
    required this.initialGroundPositions,
    required this.initialOnlyUnrated,
  });

  final TechniqueSort initialSort;
  final Set<String> initialCategories;
  final Set<LearningStatus> initialStatuses;
  final Set<String> initialGroundPositions;
  final bool initialOnlyUnrated;

  @override
  State<_SortFilterSheet> createState() => _SortFilterSheetState();
}

class _SortFilterSheetState extends State<_SortFilterSheet> {
  late TechniqueSort _sort;
  late Set<String> _categories;
  late Set<LearningStatus> _statuses;
  late Set<String> _groundPositions;
  late bool _onlyUnrated;

  @override
  void initState() {
    super.initState();
    _sort = widget.initialSort;
    _categories = Set.of(widget.initialCategories);
    _statuses = Set.of(widget.initialStatuses);
    _groundPositions = Set.of(widget.initialGroundPositions);
    _onlyUnrated = widget.initialOnlyUnrated;
  }

  String _statusLabel(LearningStatus s) =>
      s == LearningStatus.none ? 'Geen leerstatus' : s.label;

  Widget _chip(String label, bool selected, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(99),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? AppColor.tealWash : AppColor.surfaceRaised,
          borderRadius: BorderRadius.circular(99),
        ),
        child: Text(
          label,
          style: AppText.caption.copyWith(
            fontWeight: FontWeight.w600,
            color: selected ? AppColor.tealBright : AppColor.inkMuted,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          18,
          20,
          20 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('Sorteren & filteren', style: AppText.cardTitle),
                  TextButton(
                    onPressed: () => setState(() {
                      _sort = TechniqueSort.nameAsc;
                      _categories = {};
                      _statuses = {};
                      _groundPositions = {};
                      _onlyUnrated = false;
                    }),
                    child: const Text('Wissen'),
                  ),
                ],
              ),
              Text(
                'Favoriete technieken staan altijd bovenaan.',
                style: AppText.caption,
              ),
              const SizedBox(height: 14),
              Text('SORTEREN', style: AppText.overline),
              const SizedBox(height: 4),
              for (final s in TechniqueSort.values)
                InkWell(
                  onTap: () => setState(() => _sort = s),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      children: [
                        Icon(
                          _sort == s
                              ? Icons.radio_button_checked
                              : Icons.radio_button_unchecked,
                          size: 18,
                          color: _sort == s
                              ? AppColor.tealBright
                              : AppColor.inkFaint,
                        ),
                        const SizedBox(width: 10),
                        Text(s.label, style: AppText.body),
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 10),
              Text('CATEGORIE', style: AppText.overline),
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final c in _kFilterCategories)
                    _chip(
                      c,
                      _categories.contains(c),
                      () => setState(() {
                        if (!_categories.remove(c)) {
                          _categories.add(c);
                        } else if (c == 'Submission') {
                          // Submission uitgezet: de positiefilter erop
                          // heeft dan geen betekenis meer.
                          _groundPositions = {};
                        }
                      }),
                    ),
                ],
              ),
              if (_categories.contains('Submission')) ...[
                const SizedBox(height: 20),
                Text('POSITIE (BIJ SUBMISSION)', style: AppText.overline),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final p in kGroundPositions)
                      _chip(
                        p,
                        _groundPositions.contains(p),
                        () => setState(() {
                          if (!_groundPositions.remove(p)) {
                            _groundPositions.add(p);
                          }
                        }),
                      ),
                  ],
                ),
              ],
              const SizedBox(height: 20),
              Text('LEERSTATUS', style: AppText.overline),
              const SizedBox(height: 10),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final s in LearningStatus.values)
                    _chip(
                      _statusLabel(s),
                      _statuses.contains(s),
                      () => setState(() {
                        if (!_statuses.remove(s)) _statuses.add(s);
                      }),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              InkWell(
                onTap: () => setState(() => _onlyUnrated = !_onlyUnrated),
                borderRadius: BorderRadius.circular(AppRadius.md),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    children: [
                      Checkbox(
                        value: _onlyUnrated,
                        activeColor: AppColor.tealBright,
                        onChanged: (v) =>
                            setState(() => _onlyUnrated = v ?? false),
                      ),
                      Expanded(
                        child: Text(
                          'Alleen nog niet beoordeeld',
                          style: AppText.body,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => Navigator.pop(
                  context,
                  _SortFilterResult(
                    sort: _sort,
                    categories: _categories,
                    statuses: _statuses,
                    groundPositions: _groundPositions,
                    onlyUnrated: _onlyUnrated,
                  ),
                ),
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
                child: const Text('Toepassen'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TechniqueTile extends StatelessWidget {
  const _TechniqueTile({
    required this.stat,
    required this.onTap,
    required this.onToggleFavorite,
  });
  final _TechniqueStat stat;
  final VoidCallback onTap;
  final VoidCallback onToggleFavorite;

  @override
  Widget build(BuildContext context) {
    final stars = stat.lastRating > 0
        ? '★' * stat.lastRating + '☆' * (5 - stat.lastRating)
        : 'nog niet beoordeeld';
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 13),
        decoration: BoxDecoration(
          color: AppColor.surface,
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                InkWell(
                  onTap: onToggleFavorite,
                  borderRadius: BorderRadius.circular(99),
                  child: Padding(
                    padding: const EdgeInsets.all(6),
                    child: Icon(
                      stat.favorite ? Icons.star : Icons.star_border,
                      size: 20,
                      color: stat.favorite
                          ? AppColor.amberBright
                          : AppColor.inkFaint,
                    ),
                  ),
                ),
                const SizedBox(width: 2),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(stat.name, style: AppText.bodyStrong),
                      const SizedBox(height: 3),
                      Text(
                        stat.transition.isNotEmpty
                            ? '${stat.transition} · ${stat.count}× · laatst ${stat.lastDate != null ? dutchShortDate(stat.lastDate!) : ''}'
                            : '${stat.count}× · laatst ${stat.lastDate != null ? dutchShortDate(stat.lastDate!) : ''}',
                        style: AppText.caption,
                      ),
                      if (stat.learningStatus != LearningStatus.none) ...[
                        const SizedBox(height: 5),
                        _LearningStatusBadge(stat: stat),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    stars,
                    textAlign: TextAlign.end,
                    overflow: TextOverflow.ellipsis,
                    style: AppText.caption.copyWith(
                      color: stat.lastRating > 0
                          ? AppColor.amberBright
                          : AppColor.inkFaint,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                const Icon(
                  Icons.chevron_right,
                  size: 18,
                  color: AppColor.inkFaint,
                ),
              ],
            ),
            if (stat.groundPositions.isNotEmpty) ...[
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.only(left: 34),
                child: GroundPositionTags(positions: stat.groundPositions),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _CombinationTile extends StatelessWidget {
  const _CombinationTile({
    required this.combo,
    required this.onTap,
    required this.onToggleFavorite,
  });
  final Combination combo;
  final VoidCallback onTap;
  final VoidCallback onToggleFavorite;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.fromLTRB(4, 8, 14, 8),
        decoration: BoxDecoration(
          color: AppColor.surface,
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: Row(
          children: [
            IconButton(
              tooltip: combo.favorite ? 'Geen favoriet meer' : 'Favoriet',
              onPressed: onToggleFavorite,
              icon: Icon(
                combo.favorite ? Icons.star : Icons.star_border,
                size: 20,
                color: combo.favorite ? AppColor.amberBright : AppColor.inkFaint,
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(combo.name, style: AppText.bodyStrong),
                  const SizedBox(height: 3),
                  Text(
                    combo.techniques.isEmpty
                        ? '${combo.type.label} · Nog geen technieken'
                        : '${combo.type.label} · ${combo.techniques.join(' → ')}',
                    style: AppText.caption,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            const Icon(Icons.chevron_right, size: 18, color: AppColor.inkFaint),
          ],
        ),
      ),
    );
  }
}

/// Filterregel boven de combinaties: favorieten, type en A–Z / Z–A.
class _ComboFilterBar extends StatelessWidget {
  const _ComboFilterBar({
    required this.onlyFavorites,
    required this.type,
    required this.sort,
    required this.onFavorites,
    required this.onType,
    required this.onSort,
  });

  final bool onlyFavorites;
  final ComboType? type;
  final ComboSort sort;
  final ValueChanged<bool> onFavorites;
  final ValueChanged<ComboType?> onType;
  final ValueChanged<ComboSort> onSort;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 44,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(20, 6, 20, 0),
        children: [
          FilterChip(
            avatar: Icon(
              onlyFavorites ? Icons.star : Icons.star_border,
              size: 16,
              color: AppColor.amberBright,
            ),
            label: const Text('Favorieten'),
            selected: onlyFavorites,
            showCheckmark: false,
            onSelected: onFavorites,
          ),
          const SizedBox(width: 6),
          for (final t in <ComboType?>[null, ...ComboType.values]) ...[
            ChoiceChip(
              label: Text(t?.label ?? 'Alle'),
              selected: type == t,
              showCheckmark: false,
              onSelected: (_) => onType(t),
            ),
            const SizedBox(width: 6),
          ],
          ActionChip(
            avatar: const Icon(Icons.sort_by_alpha, size: 16),
            label: Text(sort == ComboSort.az ? 'A–Z' : 'Z–A'),
            onPressed: () =>
                onSort(sort == ComboSort.az ? ComboSort.za : ComboSort.az),
          ),
        ],
      ),
    );
  }
}
