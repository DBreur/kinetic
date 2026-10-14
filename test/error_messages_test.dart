import 'package:flutter_test/flutter_test.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:kinetic/core/error_messages.dart';

void main() {
  group('friendlyErrorMessage — AuthException', () {
    test('herkent verkeerde inloggegevens', () {
      final error = AuthApiException('Invalid login credentials');
      expect(
        friendlyErrorMessage(error),
        'E-mailadres of wachtwoord klopt niet.',
      );
    });

    test('herkent onbevestigde e-mail', () {
      final error = AuthApiException('Email not confirmed');
      expect(
        friendlyErrorMessage(error),
        'Bevestig eerst je e-mailadres via de link die je hebt gekregen.',
      );
    });

    test('herkent al bestaand account', () {
      final error = AuthApiException('User already registered');
      expect(
        friendlyErrorMessage(error),
        'Er bestaat al een account met dit e-mailadres.',
      );
    });

    test(
      'onbekende AuthException valt terug op de eigen boodschap, niet toString()',
      () {
        final error = AuthSessionMissingException();
        final result = friendlyErrorMessage(error);
        expect(result, isNot(contains('AuthSessionMissingException(')));
        expect(result, error.message);
      },
    );
  });

  group('friendlyErrorMessage — overige fouten', () {
    test('PostgrestException toont nooit de rauwe tekst', () {
      const error = PostgrestException(
        message: 'new row violates row-level security policy',
        code: '42501',
      );
      final result = friendlyErrorMessage(error);
      expect(result, isNot(contains('PostgrestException')));
      expect(result, isNot(contains('42501')));
      expect(result, genericErrorFallback);
    });

    test('gebruikt de meegegeven fallback-tekst als die is opgegeven', () {
      const error = PostgrestException(message: 'boom');
      final result = friendlyErrorMessage(
        error,
        fallback: 'Aangepaste melding.',
      );
      expect(result, 'Aangepaste melding.');
    });

    test('onbekend type levert de generieke fallback', () {
      final result = friendlyErrorMessage(Exception('iets raars'));
      expect(result, genericErrorFallback);
    });
  });
}
