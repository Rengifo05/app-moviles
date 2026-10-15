import 'package:flutter_test/flutter_test.dart';
import 'package:nexo_familia/core/text.dart';
import 'package:nexo_familia/features/authentication/domain/auth.dart';
import 'package:nexo_familia/features/family/domain/family.dart';
import 'package:nexo_familia/features/geofences/domain/geofence.dart';

void main() {
  group('hasVisibleContent', () {
    test('acepta letras de cualquier idioma, dígitos y emoji con letras', () {
      expect(hasVisibleContent('Ñandú'), isTrue);
      expect(hasVisibleContent('Casa 2'), isTrue);
      expect(hasVisibleContent('7'), isTrue);
      expect(hasVisibleContent('Mamá 🙂'), isTrue);
    });

    test('rechaza espacios, signos y caracteres invisibles', () {
      expect(hasVisibleContent(''), isFalse);
      expect(hasVisibleContent('   '), isFalse);
      expect(hasVisibleContent('​​'), isFalse);
      expect(hasVisibleContent(' ﻿'), isFalse);
      expect(hasVisibleContent('---'), isFalse);
      expect(hasVisibleContent('🙂'), isFalse);
    });
  });

  test('los validadores tratan un nombre invisible como vacío', () {
    expect(FamilyRules.familyName('​'), 'family-name-required');
    expect(AuthValidators.displayName('​ '), 'display-name-required');
    expect(
      GeofenceRules.validate(name: '﻿', radiusMeters: 200),
      contains('geofence-name-required'),
    );
    expect(FamilyRules.familyName('Familia Gómez'), isNull);
  });
}
