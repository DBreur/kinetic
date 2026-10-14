import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:kinetic/core/error_messages.dart';
import 'package:kinetic/state/app_controller.dart';

void main() {
  group('uitkomst van "Account maken"', () {
    test('met sessie: meteen ingelogd', () {
      expect(
        registerOutcomeFor(hasSession: true, identities: const []),
        RegisterOutcome.signedIn,
      );
    });

    test('zonder sessie, nieuw account: eerst e-mail bevestigen', () {
      expect(
        registerOutcomeFor(hasSession: false, identities: const ['email']),
        RegisterOutcome.confirmEmail,
      );
      expect(
        registerOutcomeFor(hasSession: false, identities: null),
        RegisterOutcome.confirmEmail,
      );
    });

    test('zonder sessie en zonder inlogmethodes: account bestond al', () {
      expect(
        registerOutcomeFor(hasSession: false, identities: const []),
        RegisterOutcome.alreadyExists,
      );
    });
  });

  group('foutmeldingen bij inloggen/registreren', () {
    test('te veel mails verstuurd → begrijpelijke melding', () {
      expect(
        friendlyErrorMessage(const AuthException('email rate limit exceeded')),
        contains('Wacht een paar minuten'),
      );
      expect(
        friendlyErrorMessage(
          const AuthException(
            'For security purposes, you can only request this after 42 seconds.',
          ),
        ),
        contains('Wacht een paar minuten'),
      );
    });

    test('nog niet bevestigd → uitleg over de mail', () {
      expect(
        friendlyErrorMessage(const AuthException('Email not confirmed')),
        startsWith('Bevestig eerst'),
      );
    });
  });
}
