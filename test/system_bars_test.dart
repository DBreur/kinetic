import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:kinetic/models/app_profile.dart';
import 'package:kinetic/services/system_bars.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final modes = <String>[];

  setUp(() {
    modes.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'SystemChrome.setEnabledSystemUIMode') {
            modes.add(call.arguments as String);
          }
          return null;
        });
  });

  test('live sessie verbergt, sluiten zet terug', () async {
    await SystemBars.setAlwaysHidden(false);
    modes.clear();
    await SystemBars.enterSession();
    expect(modes.last, 'SystemUiMode.immersive');
    await SystemBars.exitSession();
    expect(modes.last, 'SystemUiMode.edgeToEdge');
  });

  test('sessie sluiten overschrijft "altijd verbergen" niet', () async {
    await SystemBars.setAlwaysHidden(true);
    await SystemBars.enterSession();
    await SystemBars.exitSession();
    expect(SystemBars.hidden, isTrue);
    expect(modes.last, 'SystemUiMode.immersive');
    await SystemBars.setAlwaysHidden(false);
    expect(modes.last, 'SystemUiMode.edgeToEdge');
  });

  test('meer keer sluiten dan openen blijft netjes op 0', () async {
    await SystemBars.exitSession();
    await SystemBars.exitSession();
    await SystemBars.enterSession();
    expect(SystemBars.hidden, isTrue);
    await SystemBars.exitSession();
    expect(SystemBars.hidden, isFalse);
  });

  test('instelling staat in het profiel, standaard uit', () {
    expect(AppProfile.defaults('u').hideSystemBars, isFalse);
    final p = AppProfile.defaults('u').copyWith(hideSystemBars: true);
    expect(AppProfile.fromJson(p.toJson()).hideSystemBars, isTrue);
  });
}
