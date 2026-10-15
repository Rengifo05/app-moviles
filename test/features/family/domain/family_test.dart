import 'package:flutter_test/flutter_test.dart';
import 'package:nexo_familia/features/family/domain/family.dart';

void main() {
  group('MemberRole.canManage', () {
    test('solo owner y admin gestionan la familia', () {
      expect(MemberRole.owner.canManage, isTrue);
      expect(MemberRole.admin.canManage, isTrue);
      expect(MemberRole.member.canManage, isFalse);
      expect(MemberRole.values.where((r) => r.canManage).toSet(), {
        MemberRole.owner,
        MemberRole.admin,
      });
    });

    test('los nombres coinciden con el contrato del backend', () {
      expect(MemberRole.values.map((r) => r.name), [
        'owner',
        'admin',
        'member',
      ]);
    });
  });

  group('FamilyRules.familyName', () {
    test('exige un nombre que no sea solo espacios', () {
      for (final value in ['', '  ', '\t\n']) {
        expect(FamilyRules.familyName(value), 'family-name-required');
      }
    });

    test('admite de 1 a 40 caracteres tras recortar', () {
      expect(FamilyRules.maxNameLength, 40);
      expect(FamilyRules.familyName('C'), isNull);
      expect(FamilyRules.familyName('Casa Peña'), isNull);
      expect(FamilyRules.familyName('a' * 40), isNull);
      expect(FamilyRules.familyName('   ${'a' * 40}   '), isNull);
      expect(FamilyRules.familyName('a' * 41), 'family-name-too-long');
    });
  });

  group('FamilyRules: alfabeto de los códigos', () {
    test('coincide con el contrato del backend', () {
      expect(FamilyRules.codeAlphabet, 'ABCDEFGHJKMNPQRSTUVWXYZ23456789');
      expect(FamilyRules.codeLength, 10);
      expect(FamilyRules.maxMembers, 12);
    });

    test('no tiene caracteres ambiguos ni repetidos', () {
      const alphabet = FamilyRules.codeAlphabet;
      for (final ambiguous in ['0', 'O', '1', 'I', 'L']) {
        expect(alphabet, isNot(contains(ambiguous)));
      }
      expect(alphabet.split('').toSet(), hasLength(alphabet.length));
      expect(alphabet, matches(RegExp(r'^[A-Z2-9]+$')));
      // Todas las letras y cifras salvo las cinco ambiguas.
      expect(alphabet.length, 26 + 10 - 5);
    });
  });

  group('FamilyRules.normalizeCode', () {
    test('acepta el código tal cual y con el formato de presentación', () {
      expect(FamilyRules.normalizeCode('ABCDEFGHJK'), 'ABCDEFGHJK');
      expect(FamilyRules.normalizeCode('ABCDE-FGHJK'), 'ABCDEFGHJK');
    });

    test('pasa las minúsculas a mayúsculas', () {
      expect(FamilyRules.normalizeCode('abcde-fghjk'), 'ABCDEFGHJK');
      expect(FamilyRules.normalizeCode('AbCdE fGhJk'), 'ABCDEFGHJK');
    });

    test('ignora espacios y guiones en cualquier posición', () {
      for (final input in [
        '  ABCDE-FGHJK  ',
        'AB CD-EF GH-JK',
        'A-B-C-D-E-F-G-H-J-K',
        '--ABCDEFGHJK--',
        'ABCDE\tFGHJK\n',
        'ABCDE FGHJK', // Espacio de no separación (al copiar y pegar).
        'ABCDE　FGHJK', // Espacio ideográfico.
      ]) {
        expect(FamilyRules.normalizeCode(input), 'ABCDEFGHJK', reason: input);
      }
    });

    test('acepta los guiones tipográficos que insertan teclados y apps', () {
      for (final dash in [
        '‐', // Guion.
        '‑', // Guion de no separación.
        '‒', // Guion de cifras.
        '–', // Raya corta (en dash).
        '—', // Raya (em dash).
        '―', // Barra horizontal.
        '−', // Signo menos.
      ]) {
        expect(
          FamilyRules.normalizeCode('ABCDE${dash}FGHJK'),
          'ABCDEFGHJK',
          reason: 'U+${dash.codeUnitAt(0).toRadixString(16)}',
        );
      }
    });

    test(
      'rechaza los caracteres ambiguos 0, O, 1, I y L en cualquier caja',
      () {
        for (final ambiguous in ['0', 'O', 'o', '1', 'I', 'i', 'L', 'l']) {
          final input = 'ABCDEFGHJ$ambiguous';
          expect(FamilyRules.normalizeCode(input), isNull, reason: input);
        }
      },
    );

    test('exige exactamente 10 caracteres sin contar separadores', () {
      expect(FamilyRules.normalizeCode(''), isNull);
      expect(FamilyRules.normalizeCode('   --  '), isNull);
      expect(FamilyRules.normalizeCode('ABCDEFGHJ'), isNull);
      expect(FamilyRules.normalizeCode('ABCDE-FGHJ'), isNull);
      expect(FamilyRules.normalizeCode('ABCDEFGHJKM'), isNull);
      expect(FamilyRules.normalizeCode('ABCDE-FGHJK-M'), isNull);
    });

    test('rechaza símbolos y caracteres fuera del alfabeto', () {
      for (final input in [
        'ABCDE_FGHJK',
        'ABCDE.FGHJK',
        'ABCDEFGHJ!',
        'ABCDEFGHJÑ',
        'ABCDEFGH🙂', // Ocupa dos unidades UTF-16: 10 en total.
        'ＡＢＣＤＥＦＧＨＪＫ', // Letras de ancho completo.
      ]) {
        expect(FamilyRules.normalizeCode(input), isNull, reason: input);
      }
    });

    test('no convierte letras no ASCII en letras del alfabeto', () {
      // 'ſ' (s larga) pasa a 'S' con toUpperCase y 'ß' a 'SS' en web: un texto
      // que no es un código no debe aceptarse como tal.
      expect(FamilyRules.normalizeCode('ABCDEFGHJſ'), isNull);
      expect(FamilyRules.normalizeCode('ABCDEFGHß'), isNull);
      expect(FamilyRules.normalizeCode('ABCDEFGHJı'), isNull);
    });

    test('acepta todos los caracteres del alfabeto en ambas cajas', () {
      // 31 caracteres + 9 de relleno = 4 códigos de 10.
      const all = '${FamilyRules.codeAlphabet}ABCDEFGHJ';
      for (var i = 0; i < all.length; i += 10) {
        final code = all.substring(i, i + 10);
        expect(FamilyRules.normalizeCode(code), code);
        expect(FamilyRules.normalizeCode(code.toLowerCase()), code);
      }
    });
  });

  group('FamilyRules.formatCode', () {
    test('separa un código de 10 caracteres en dos grupos de 5', () {
      expect(FamilyRules.formatCode('ABCDEFGHJK'), 'ABCDE-FGHJK');
    });

    test('deja intacto lo que no tiene la longitud de un código', () {
      for (final value in ['', 'ABCDE', 'ABCDEFGHJ', 'ABCDEFGHJKM']) {
        expect(FamilyRules.formatCode(value), value);
      }
    });

    test('formatear y normalizar es reversible', () {
      const codes = ['ABCDEFGHJK', '23456789ZY', 'MNPQRSTUVW'];
      for (final code in codes) {
        final formatted = FamilyRules.formatCode(code);
        expect(formatted, hasLength(11));
        expect(FamilyRules.normalizeCode(formatted), code);
        expect(FamilyRules.normalizeCode(formatted.toLowerCase()), code);
      }
    });
  });
}
