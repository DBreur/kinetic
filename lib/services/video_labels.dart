// video_labels.dart — eigen namen voor video's ("Instap", "Detail grip")
// in plaats van "Video 1, 2, …". Eén map van link → naam per gebruiker,
// bewaard in het profiel (profiles.video_labels), zodat een naam overal
// meekomt waar dezelfde video staat: technieken, combinaties, oefeningen,
// circuits en tijdens een sessie. Net als SystemBars een kleine statische
// dienst, zodat de videolijsten geen AppController nodig hebben.

import 'package:flutter/foundation.dart';

class VideoLabels {
  VideoLabels._();

  static final ValueNotifier<Map<String, String>> labels = ValueNotifier(
    const {},
  );

  static Future<void> Function(Map<String, String>)? _persist;

  /// Zet de namen uit het profiel en hoe wijzigingen bewaard worden — wordt
  /// door AppController aangeroepen telkens als het profiel verandert.
  static void attach(
    Map<String, String> fromProfile,
    Future<void> Function(Map<String, String>)? persist,
  ) {
    _persist = persist;
    if (!mapEquals(labels.value, fromProfile)) {
      labels.value = Map.unmodifiable(fromProfile);
    }
  }

  static String _key(String url) => url.trim();

  /// De eigen naam van een video, of null als die er niet is.
  static String? labelOf(String url) => labels.value[_key(url)];

  /// Eigen naam, anders "Video 2" (op basis van de plek in de lijst).
  static String titleFor(String url, int index) =>
      labelOf(url) ?? 'Video ${index + 1}';

  /// Zet (of wist, bij een lege naam) de naam van een video en bewaart hem.
  static Future<void> setLabel(String url, String label) async {
    final next = Map<String, String>.of(labels.value);
    final trimmed = label.trim();
    if (trimmed.isEmpty) {
      next.remove(_key(url));
    } else {
      next[_key(url)] = trimmed;
    }
    labels.value = Map.unmodifiable(next);
    await _persist?.call(next);
  }
}
