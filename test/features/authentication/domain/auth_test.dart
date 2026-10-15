import 'package:flutter_test/flutter_test.dart';
import 'package:nexo_familia/features/authentication/domain/auth.dart';

// Correos de dominios reservados para documentación (RFC 2606).

SignUpRequest _request({
  String email = 'ana@example.com',
  String password = 'clave-segura-1',
  String displayName = 'Ana',
  bool confirmedAdult = true,
  bool acceptedPrivacyPolicy = true,
}) => SignUpRequest(
  email: email,
  password: password,
  displayName: displayName,
  confirmedAdult: confirmedAdult,
  acceptedPrivacyPolicy: acceptedPrivacyPolicy,
);

final _kebabCase = RegExp(r'^[a-z]+(-[a-z]+)*$');

void main() {
  group('AuthValidators.email', () {
    test('acepta direcciones válidas, también con espacios alrededor', () {
      for (final value in [
        'ana@example.com',
        'ana.maria+familia@example.org',
        'a@b.co',
        'ANA@EXAMPLE.COM',
        '  ana@example.com  ',
        '\tana@example.com\n',
        'ana@sub.dominio.example',
      ]) {
        expect(AuthValidators.email(value), isNull, reason: value);
      }
    });

    test('exige un valor que no sea solo espacios', () {
      for (final value in ['', ' ', '\t\n ']) {
        expect(AuthValidators.email(value), 'email-required', reason: value);
      }
    });

    test('rechaza formatos inválidos', () {
      for (final value in [
        'ana',
        'ana@',
        '@example.com',
        'ana@example',
        'ana@example.c', // Dominio de primer nivel de un solo carácter.
        'ana@@example.com',
        'ana@ex@ample.com',
        'ana maria@example.com',
        'ana@exam ple.com',
        'ana@.com',
        'ana@example.',
      ]) {
        expect(AuthValidators.email(value), 'email-invalid', reason: value);
      }
    });

    test(
      'limita la longitud a 254 caracteres sin contar espacios externos',
      () {
        // '@b.co' tiene 5 caracteres.
        final max = '${'a' * 249}@b.co';
        expect(max.length, 254);
        expect(AuthValidators.email(max), isNull);
        expect(AuthValidators.email('  $max  '), isNull);
        expect(AuthValidators.email('a$max'), 'email-invalid');
      },
    );

    test('un texto enorme pegado se rechaza sin bloquear la interfaz', () {
      // Con muchos puntos tras la arroba, la expresión regular retrocede en
      // tiempo cuadrático; si se evalúa antes del límite de longitud, 40 000
      // caracteres congelan el hilo de la interfaz durante segundos.
      final huge = 'a@${'a.' * 20000}@';
      final stopwatch = Stopwatch()..start();
      expect(AuthValidators.email(huge), 'email-invalid');
      expect(stopwatch.elapsed, lessThan(const Duration(seconds: 1)));
    });
  });

  group('AuthValidators.password', () {
    test('exige un valor', () {
      expect(AuthValidators.password(''), 'password-required');
    });

    test('exige al menos 8 caracteres (límite incluido)', () {
      expect(AuthValidators.minPasswordLength, 8);
      expect(AuthValidators.password('a' * 7), 'password-too-short');
      expect(AuthValidators.password('a' * 8), isNull);
      // Los espacios no cuentan como relleno para esquivar la longitud.
      expect(AuthValidators.password(' ' * 7), 'password-too-short');
    });

    test('rechaza una clave hecha solo de espacios', () {
      expect(AuthValidators.password(' ' * 8), 'password-too-weak');
      expect(AuthValidators.password('\t \n    \t'), 'password-too-weak');
    });

    test('no recorta la clave: los espacios internos y externos cuentan', () {
      // Recortar cambiaría la clave que el usuario eligió.
      expect(AuthValidators.password(' abc def '), isNull);
      expect(AuthValidators.password('   abcde'), isNull);
    });
  });

  group('AuthValidators.displayName', () {
    test('exige un nombre que no sea solo espacios', () {
      for (final value in ['', '   ', '\n\t']) {
        expect(
          AuthValidators.displayName(value),
          'display-name-required',
          reason: value,
        );
      }
    });

    test('admite hasta 40 caracteres tras recortar (límite incluido)', () {
      expect(AuthValidators.maxDisplayNameLength, 40);
      expect(AuthValidators.displayName('a' * 40), isNull);
      expect(AuthValidators.displayName('  ${'a' * 40}  '), isNull);
      expect(AuthValidators.displayName('a' * 41), 'display-name-too-long');
    });

    test('acepta nombres con tildes y espacios internos', () {
      expect(AuthValidators.displayName('María José Peña'), isNull);
    });
  });

  group('AuthValidators.signUp', () {
    test('una solicitud completa no tiene errores', () {
      expect(AuthValidators.signUp(_request()), isEmpty);
    });

    test('la mayoría de edad es obligatoria (decisión D5)', () {
      expect(AuthValidators.signUp(_request(confirmedAdult: false)), [
        'adult-confirmation-required',
      ]);
    });

    test('la aceptación de la política de privacidad es obligatoria', () {
      expect(AuthValidators.signUp(_request(acceptedPrivacyPolicy: false)), [
        'privacy-acceptance-required',
      ]);
    });

    test('sin mayoría de edad ni privacidad se informan ambos', () {
      expect(
        AuthValidators.signUp(
          _request(confirmedAdult: false, acceptedPrivacyPolicy: false),
        ),
        ['adult-confirmation-required', 'privacy-acceptance-required'],
      );
    });

    test('datos válidos no compensan la falta de consentimiento', () {
      // Solo hay registro con las dos casillas marcadas.
      for (final adult in [true, false]) {
        for (final privacy in [true, false]) {
          final errors = AuthValidators.signUp(
            _request(confirmedAdult: adult, acceptedPrivacyPolicy: privacy),
          );
          expect(errors.isEmpty, adult && privacy, reason: '$adult/$privacy');
        }
      }
    });

    test('acumula todos los errores en un orden estable', () {
      expect(
        AuthValidators.signUp(
          _request(
            email: '',
            password: '',
            displayName: ' ',
            confirmedAdult: false,
            acceptedPrivacyPolicy: false,
          ),
        ),
        [
          'email-required',
          'password-required',
          'display-name-required',
          'adult-confirmation-required',
          'privacy-acceptance-required',
        ],
      );
      expect(
        AuthValidators.signUp(
          _request(email: 'ana', password: 'corta', displayName: 'a' * 41),
        ),
        ['email-invalid', 'password-too-short', 'display-name-too-long'],
      );
    });

    test('los códigos son kebab-case sin dígitos', () {
      final codes = <String?>[
        AuthValidators.email(''),
        AuthValidators.email('x'),
        AuthValidators.password(''),
        AuthValidators.password('x'),
        AuthValidators.password(' ' * 8),
        AuthValidators.displayName(''),
        AuthValidators.displayName('a' * 41),
        ...AuthValidators.signUp(
          _request(confirmedAdult: false, acceptedPrivacyPolicy: false),
        ),
      ];
      for (final code in codes) {
        expect(code, matches(_kebabCase));
      }
    });
  });

  group('AuthUser', () {
    test('la igualdad compara uid, correo y nombre', () {
      const a = AuthUser(
        uid: 'u1',
        email: 'ana@example.com',
        displayName: 'Ana',
      );
      const b = AuthUser(
        uid: 'u1',
        email: 'ana@example.com',
        displayName: 'Ana',
      );
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(
        a,
        isNot(
          const AuthUser(
            uid: 'u2',
            email: 'ana@example.com',
            displayName: 'Ana',
          ),
        ),
      );
      expect(
        a,
        isNot(
          const AuthUser(
            uid: 'u1',
            email: 'otra@example.com',
            displayName: 'Ana',
          ),
        ),
      );
      expect(a, isNot(const AuthUser(uid: 'u1', email: 'ana@example.com')));
    });
  });
}
