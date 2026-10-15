import 'package:flutter_test/flutter_test.dart';
import 'package:nexo_familia/features/settings/domain/preferences.dart';

void main() {
  group('AppPreferences', () {
    test('por defecto: sin onboarding, sin familia activa y con detalles', () {
      const preferences = AppPreferences();
      expect(preferences.onboardingCompleted, isFalse);
      expect(preferences.activeFamilyId, isNull);
      expect(preferences.hideNotificationDetails, isFalse);
    });
  });

  group('AppPreferences.copyWith', () {
    const original = AppPreferences(
      onboardingCompleted: true,
      activeFamilyId: 'f1',
      hideNotificationDetails: true,
    );

    test('sin argumentos conserva todos los campos', () {
      final copy = original.copyWith();
      expect(copy.onboardingCompleted, isTrue);
      expect(copy.activeFamilyId, 'f1');
      expect(copy.hideNotificationDetails, isTrue);
    });

    test('activeFamilyId ausente conserva la familia activa', () {
      final copy = original.copyWith(hideNotificationDetails: false);
      expect(copy.activeFamilyId, 'f1');
      expect(copy.hideNotificationDetails, isFalse);
    });

    test('activeFamilyId nulo explícito borra la familia activa', () {
      final copy = original.copyWith(activeFamilyId: () => null);
      expect(copy.activeFamilyId, isNull);
      // El resto no cambia.
      expect(copy.onboardingCompleted, isTrue);
      expect(copy.hideNotificationDetails, isTrue);
    });

    test('activeFamilyId con valor la reemplaza', () {
      expect(
        original.copyWith(activeFamilyId: () => 'f2').activeFamilyId,
        'f2',
      );
      expect(
        const AppPreferences()
            .copyWith(activeFamilyId: () => 'f3')
            .activeFamilyId,
        'f3',
      );
    });

    test('borrar una familia ya vacía la deja vacía', () {
      final copy = const AppPreferences().copyWith(activeFamilyId: () => null);
      expect(copy.activeFamilyId, isNull);
    });

    test('cambia los indicadores sin tocar la familia activa', () {
      final copy = original.copyWith(
        onboardingCompleted: false,
        hideNotificationDetails: false,
      );
      expect(copy.onboardingCompleted, isFalse);
      expect(copy.hideNotificationDetails, isFalse);
      expect(copy.activeFamilyId, 'f1');
    });

    test('no modifica las preferencias originales', () {
      final copy = original.copyWith(
        onboardingCompleted: false,
        activeFamilyId: () => null,
        hideNotificationDetails: false,
      );
      expect(copy.activeFamilyId, isNull);
      expect(original.onboardingCompleted, isTrue);
      expect(original.activeFamilyId, 'f1');
      expect(original.hideNotificationDetails, isTrue);
    });
  });
}
