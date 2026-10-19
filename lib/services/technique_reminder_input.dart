// technique_reminder_input.dart — haalt je technieken op voor de
// techniek-herinneringen in de agenda-meldingen (namen en "oefenen bij de
// eerstvolgende training"), samen met de instellingen uit je profiel.

import '../repositories/technique_repository.dart';
import '../state/app_controller.dart';
import 'agenda_notification_service.dart';

Future<TechniqueReminderInput?> loadTechniqueReminderInput(
  AppController controller,
) async {
  final profile = controller.profile;
  final client = controller.client;
  final userId = controller.user?.id;
  if (profile == null || client == null || userId == null) return null;
  if (!profile.techniqueRemindersEnabled) {
    return const TechniqueReminderInput(names: {}, enabled: false);
  }
  try {
    final techniques = await TechniqueRepository(client).listForUser(userId);
    return TechniqueReminderInput(
      names: {for (final t in techniques) t.id: t.name},
      practiceNextIds: [
        for (final t in techniques)
          if (t.practiceNext) t.id,
      ],
      withSound: profile.techniqueReminderSound,
      defaultReminders: profile.techniqueReminderDefaults,
    );
  } catch (_) {
    return null;
  }
}
