// positions.dart — vaste posities voor de techniekkaart (zie
// technique_map_screen.dart): elke techniek verbindt twee van deze posities
// via zijn `transition`-veld (bv. "Staand -> Grond boven"). Puur, UI-los en
// makkelijk te testen — net als lib/core/training_streak.dart.

import 'dart:math' as math;
import 'dart:ui';

import '../models/technique.dart';
import '../theme/kinetic_theme.dart';

/// De vaste posities op de kaart, in weergave-/canvasvolgorde. "Striking"
/// is staand op slagafstand (combat sambo: van slaan naar een takedown). Dit zijn
/// de enige geldige "van"-kanten van een transitie — je kunt wel ergens
/// vertrekken vanuit een positie, maar niet vanuit een afgeronde score (zie
/// [kOutcomes]).
const kPositions = [
  'Striking',
  'Staand',
  'Clinch',
  'Grond boven',
  'Grond onder',
  'Klem',
];

/// Afgeronde scores — een worp of afwerking die de uitwisseling meteen
/// beëindigt (bv. een ippon) in plaats van door te gaan naar grondwerk.
/// Alleen geldig als "naar"-kant van een transitie, nooit als "van".
const kOutcomes = ['Takedown', 'Submission'];

/// Alle knopen op de kaart: de posities plus de twee afgeronde scores —
/// gebruikt voor het tekenen/hit-testen van de kaart en voor de "naar"-kant
/// van de transitiekiezer (de "van"-kant gebruikt alleen [kPositions]).
const kAllNodes = [...kPositions, ...kOutcomes];

/// Specifiekere grondposities, los van de kaart zelf — optioneel te kiezen
/// bij een techniek die naar "Submission" gaat, zodat je bv. kunt vastleggen
/// dat een bepaalde afwerking vanuit half guard werkt en een andere vanuit
/// mount. Geen eigen knopen op de kaart: puur een extra, los label.
const kGroundPositions = [
  'Mount',
  'Side control',
  'Half guard',
  'Guard',
  'North-South',
  'Back control',
  'Knee on belly',
  'Turtle',
];

/// Referentiegrootte van het kaartvlak — alles schaalt hiervandaan naar de
/// werkelijke schermbreedte (zie [positionOffset]/[nodeRect]).
const double kMapWidth = 340;
const double kMapHeight = 480;

const Map<String, Offset> _basePositions = {
  // Striking (slagafstand) bovenaan, apart, zodat de lijnen naar Staand,
  // Clinch en Takedown vrij blijven van de andere knopen.
  'Striking': Offset(170, 45),
  'Staand': Offset(70, 135),
  'Clinch': Offset(270, 135),
  'Grond boven': Offset(70, 245),
  'Grond onder': Offset(270, 245),
  'Klem': Offset(170, 335),
  'Takedown': Offset(90, 435),
  'Submission': Offset(250, 435),
};

/// Positie van een knooppunt-middelpunt, geschaald naar [canvasSize] (die
/// zelf de verhouding van [kMapWidth]/[kMapHeight] aanhoudt).
Offset positionOffset(String position, Size canvasSize) {
  final base = _basePositions[position];
  if (base == null) return Offset.zero;
  final scale = canvasSize.width / kMapWidth;
  return Offset(base.dx * scale, base.dy * scale);
}

/// Rechthoek van een knooppunt (100×44 bij volledige grootte), geschaald
/// naar [canvasSize] — gedeeld tussen tekenen en hit-testen zodat ze nooit
/// uit elkaar kunnen lopen.
Rect nodeRect(String position, Size canvasSize) {
  final scale = canvasSize.width / kMapWidth;
  final center = positionOffset(position, canvasSize);
  return Rect.fromCenter(center: center, width: 100 * scale, height: 44 * scale);
}

/// Normaliseert een los getypte positienaam (hoofdletters/spaties) naar een
/// exacte entry in [kAllNodes], of null als die niet bestaat. Of de "van"-kant
/// daarbij wel een echte positie is (geen afgeronde score) wordt niet hier
/// maar door de kiezers in de UI afgedwongen — de parser zelf is bewust
/// soepel, zodat ook oudere/afwijkende data nog steeds parseert.
String? _matchPosition(String raw) {
  final cleaned = raw.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  for (final p in kAllNodes) {
    if (p.toLowerCase() == cleaned) return p;
  }
  return null;
}

/// Van/naar-paar uit een `transition`-string. Accepteert `->`, `→` en `>`
/// als scheidingsteken, negeert spaties/hoofdletters. Geeft null bij een
/// lege string, een onbekende positie, of een string zonder scheidingsteken.
({String from, String to})? parseTransition(String raw) {
  final trimmed = raw.trim();
  if (trimmed.isEmpty) return null;
  final normalized = trimmed.replaceAll('→', '->');
  final parts = normalized.split(RegExp(r'->|>'));
  if (parts.length != 2) return null;
  final from = _matchPosition(parts[0]);
  final to = _matchPosition(parts[1]);
  if (from == null || to == null) return null;
  return (from: from, to: to);
}

/// Of een techniek op de kaart hoort — normaal via een geldige kaart-
/// transitie, maar categorie "Submission" alleen is ook genoeg: dan weet je
/// al dat hij bij het Submission-knooppunt hoort, ook zonder dat je ook nog
/// een vertrekpositie hebt ingevuld.
bool isOnMap(Technique t) =>
    parseTransition(t.transition) != null || t.category == 'Submission';

/// Of een techniek "aankomt" bij [position] — via een geldige transitie, of
/// (voor het Submission-knooppunt specifiek) via de categorie alleen, zodat
/// een Submission-techniek zonder transitie toch meetelt bij dat knooppunt.
bool arrivesAt(Technique t, String position) {
  final parsed = parseTransition(t.transition);
  if (parsed != null) return parsed.to == position;
  return position == 'Submission' && t.category == 'Submission';
}

/// Categorie zoals getoond in het tabblad Technieken: een al bestaande
/// handmatige categorie (niet leeg, niet "Overig") blijft leidend; anders
/// wordt ze afgeleid — een afgeronde score (zie [kOutcomes]) geeft direct
/// "Takedown"/"Submission", anders de positie waar de techniek vertrekt.
String effectiveCategory(Technique t) {
  if (t.category.isNotEmpty && t.category != 'Overig') return t.category;
  final parsed = parseTransition(t.transition);
  if (parsed == null) return 'Overig';
  if (parsed.to == 'Takedown' || parsed.to == 'Submission') return parsed.to;
  return (parsed.from == 'Staand' ||
          parsed.from == 'Clinch' ||
          parsed.from == 'Striking')
      ? 'Staand'
      : 'Grondwerk';
}

/// Beheersingsscore van één techniek: de rating (0-5) van de meest recente
/// beoordeelde [TechniqueUpdate], of 0 als er nooit een rating > 0 was.
double masteryScore(Technique t) {
  TechniqueUpdate? latest;
  for (final u in t.updates) {
    if (u.rating > 0 && (latest == null || u.at.isAfter(latest.at))) {
      latest = u;
    }
  }
  return (latest?.rating ?? 0).toDouble();
}

/// Kleur voor een beheersingsscore (0-5): ★4-5 beheerst, ★3 bezig, ★1-2
/// zwak, 0 (nooit beoordeeld) grijs/transparant — nooit amber/rood, die
/// kleuren zijn uitsluitend voor glucose.
Color colorForMasteryScore(double score) {
  if (score <= 0) return const Color(0x33FFFFFF); // wit 20%
  if (score >= 4) return AppColor.greenBright;
  if (score >= 3) return AppColor.teal;
  return AppColor.teal.withValues(alpha: .5);
}

/// Alle technieken met eenzelfde van/naar-positiepaar, met afgeleide
/// statistieken voor de verbindingslijn op de kaart.
class ConnectionStats {
  final String from;
  final String to;
  final List<Technique> techniques;
  const ConnectionStats({
    required this.from,
    required this.to,
    required this.techniques,
  });

  /// Gestippeld als geen enkele techniek op deze verbinding ooit een
  /// rating > 0 heeft gekregen.
  bool get everRated =>
      techniques.any((t) => t.updates.any((u) => u.rating > 0));

  double get averageMastery {
    if (techniques.isEmpty) return 0;
    final total = techniques.fold<double>(0, (sum, t) => sum + masteryScore(t));
    return total / techniques.length;
  }

  Color get color => colorForMasteryScore(averageMastery);

  /// Lijndikte: 2px + 1px per techniek, nooit dikker dan 6px.
  double get strokeWidth => math.min(6, 2 + techniques.length).toDouble();
}

/// Groepeert technieken met een geldige transitie per positiepaar. Technieken
/// zonder parsebare transitie (leeg of onbekende positie) horen hier niet
/// bij — die komen op de kaart in de "Niet op de kaart"-lijst.
List<ConnectionStats> groupConnections(List<Technique> techniques) {
  final byKey = <String, List<Technique>>{};
  for (final t in techniques) {
    final parsed = parseTransition(t.transition);
    if (parsed == null) continue;
    byKey.putIfAbsent('${parsed.from}||${parsed.to}', () => []).add(t);
  }
  return byKey.entries.map((e) {
    final parts = e.key.split('||');
    return ConnectionStats(from: parts[0], to: parts[1], techniques: e.value);
  }).toList();
}

/// Parametrisch snijpunt (Liang-Barsky) van het lijnstuk [from]→[to] met de
/// rand van [rect] — [to] moet binnen [rect] liggen (het is het middelpunt
/// van het doelknooppunt). Geeft het entry-punt (waar de lijn de rand
/// binnenkomt), of null als het lijnstuk de rand nooit kruist.
double? _entryParameter(Offset from, Offset to, Rect rect) {
  final dx = to.dx - from.dx;
  final dy = to.dy - from.dy;
  double t0 = 0.0;
  double t1 = 1.0;

  bool clip(double p, double q) {
    if (p == 0) return q >= 0;
    final r = q / p;
    if (p < 0) {
      if (r > t1) return false;
      if (r > t0) t0 = r;
    } else {
      if (r < t0) return false;
      if (r < t1) t1 = r;
    }
    return true;
  }

  if (!clip(-dx, from.dx - rect.left)) return null;
  if (!clip(dx, rect.right - from.dx)) return null;
  if (!clip(-dy, from.dy - rect.top)) return null;
  if (!clip(dy, rect.bottom - from.dy)) return null;
  return t0;
}

/// Het punt waar de richtingsstip van een verbinding moet komen: op de rand
/// van het doelknooppunt ([targetRect], middelpunt [to]), [pullBack] pixels
/// terug richting [from] — geen vast percentage van de lijn, maar de echte
/// rand-kruising.
Offset arrowAnchorPoint(
  Offset from,
  Offset to,
  Rect targetRect, {
  double pullBack = 8,
}) {
  final t = _entryParameter(from, to, targetRect) ?? 1.0;
  final edgePoint = Offset(
    from.dx + (to.dx - from.dx) * t,
    from.dy + (to.dy - from.dy) * t,
  );
  final dir = to - from;
  final length = dir.distance;
  if (length == 0) return edgePoint;
  final unit = Offset(dir.dx / length, dir.dy / length);
  return edgePoint - unit * pullBack;
}
