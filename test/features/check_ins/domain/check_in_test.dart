import 'package:flutter_test/flutter_test.dart';
import 'package:nexo_familia/features/check_ins/domain/check_in.dart';

void main() {
  group('CheckInRules.message', () {
    test('el mensaje es opcional', () {
      expect(CheckInRules.message(null), isNull);
      expect(CheckInRules.message(''), isNull);
      expect(CheckInRules.message('   '), isNull);
    });

    test('admite hasta 140 caracteres (límite incluido)', () {
      expect(CheckInRules.maxMessageLength, 140);
      expect(CheckInRules.message('Llegué al colegio'), isNull);
      expect(CheckInRules.message('a' * 140), isNull);
      expect(CheckInRules.message('a' * 141), 'check-in-message-too-long');
    });

    test('los espacios externos no cuentan para el límite', () {
      expect(CheckInRules.message('   ${'a' * 140}   '), isNull);
      expect(CheckInRules.message('\n${'a' * 140}\t'), isNull);
      expect(
        CheckInRules.message('  ${'a' * 141}  '),
        'check-in-message-too-long',
      );
    });

    test('los espacios internos sí cuentan', () {
      expect(CheckInRules.message('a ' * 70), isNull); // 139 tras recortar.
      expect(
        CheckInRules.message('${'a ' * 70}a'),
        'check-in-message-too-long',
      );
    });

    test('el código es kebab-case sin dígitos', () {
      expect(
        CheckInRules.message('a' * 141),
        matches(RegExp(r'^[a-z]+(-[a-z]+)*$')),
      );
    });
  });

  test('los tipos de check-in coinciden con el contrato del backend', () {
    expect(CheckInKind.values.map((k) => k.name), ['ok', 'needHelp']);
  });
}
