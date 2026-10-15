// Conformidad de DemoFunctionsClient con docs/architecture/05-api-backend.md.
// Todos los datos son sintéticos: nombres inventados y coordenadas ficticias.
import 'dart:convert';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexo_familia/core/failure.dart';
import 'package:nexo_familia/core/result.dart';
import 'package:nexo_familia/infrastructure/demo/demo_functions.dart';
import 'package:nexo_familia/infrastructure/demo/in_memory_remote_store.dart';
import 'package:nexo_familia/infrastructure/remote/remote_store.dart';

import '../../helpers/fakes.dart';

const _notAllowed = Err<Json>(
  Failure(FailureKind.permissionDenied, 'not-allowed'),
);
const _invitationInvalid = Err<Json>(
  Failure(FailureKind.notFound, 'invitation-invalid'),
);
const _rateLimited = Err<Json>(
  Failure(FailureKind.rateLimited, 'rate-limited'),
);

const _alphabet = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
final _kebabCase = RegExp(r'^[a-z]+(-[a-z]+)*$');

String _sha256(String code) => sha256.convert(utf8.encode(code)).toString();

/// `Ok` compara su valor con `==`, que en los mapas es identidad; aquí se
/// compara el contenido.
Matcher _isOk(Json expected) =>
    isA<Ok<Json>>().having((r) => r.value, 'value', expected);

/// Todos los textos de un valor JSON, incluidas las claves de los mapas.
Iterable<String> _texts(Object? value) sync* {
  switch (value) {
    case final Map<String, Object?> map:
      for (final MapEntry(:key, :value) in map.entries) {
        yield key;
        yield* _texts(value);
      }
    case final List<Object?> list:
      for (final item in list) {
        yield* _texts(item);
      }
    case null:
      break;
    default:
      yield value.toString();
  }
}

void main() {
  late FakeClock clock;
  late InMemoryRemoteStore store;
  late DemoFunctionsClient functions;
  String? session;

  DemoFunctionsClient newClient(InMemoryRemoteStore target) =>
      DemoFunctionsClient(
        store: target,
        currentUid: () => session,
        random: math.Random(7),
      );

  setUp(() {
    clock = FakeClock();
    store = InMemoryRemoteStore(clock: clock);
    session = null;
    // Sin `clock`: debe usar el del almacén.
    functions = newClient(store);
    for (final (uid, name) in [
      ('ana', 'Ana Prueba'),
      ('bruno', 'Bruno Prueba'),
      ('carla', 'Carla Prueba'),
    ]) {
      store.serverWrite('users/$uid', {'displayName': name});
    }
  });

  tearDown(() => store.dispose());

  // --- Ayudas ---------------------------------------------------------------

  Future<Result<Json>> callAs(
    String uid,
    String name, [
    Json payload = const {},
  ]) {
    session = uid;
    return functions.call(name, payload);
  }

  Future<Json> ok(Future<Result<Json>> call) async {
    final result = await call;
    expect(result.isOk, isTrue, reason: '$result');
    return result.valueOrNull!;
  }

  Future<String> createFamily(
    String owner, [
    String name = 'Casa Prueba',
  ]) async {
    final result = await ok(callAs(owner, 'createFamily', {'name': name}));
    return result['familyId']! as String;
  }

  Future<String> invite(String familyId, String by) async {
    final result = await ok(
      callAs(by, 'createInvitation', {'familyId': familyId}),
    );
    return result['code']! as String;
  }

  Future<Result<Json>> accept(String uid, String code) =>
      callAs(uid, 'acceptInvitation', {'code': code});

  /// Familia de [owner] a la que se unen [members] en orden, un minuto
  /// después cada uno (salvo que [gap] diga otra cosa).
  Future<String> familyOf(
    String owner,
    List<String> members, {
    Duration gap = const Duration(minutes: 1),
  }) async {
    final familyId = await createFamily(owner);
    for (final uid in members) {
      clock.advance(gap);
      await ok(accept(uid, await invite(familyId, owner)));
    }
    return familyId;
  }

  /// Cambia un rol directamente en el servidor (el contrato aún no tiene una
  /// función para ello).
  void setRole(String familyId, String uid, String role) {
    for (final path in [
      'families/$familyId/members/$uid',
      'users/$uid/memberships/$familyId',
    ]) {
      store.serverWrite(path, {...?store.serverRead(path), 'role': role});
    }
  }

  List<Json> docsIn(String collection) =>
      store.serverList(collection).map(store.serverRead).nonNulls.toList();

  List<Json> eventsOf(String familyId, String type) => [
    for (final e in docsIn('families/$familyId/events'))
      if (e['type'] == type) e,
  ];

  List<Json> auditsOf(String familyId, String action) => [
    for (final a in docsIn('families/$familyId/audit'))
      if (a['action'] == action) a,
  ];

  String? roleOf(String familyId, String uid) =>
      store.serverRead('families/$familyId/members/$uid')?['role'] as String?;

  // --- Pruebas --------------------------------------------------------------

  group('llamadas', () {
    test('sin sesión responde unauthenticated en cualquier función y no '
        'escribe nada', () async {
      final familyId = await createFamily('ana');
      session = null;
      final before = store.snapshot;
      for (final (name, payload) in <(String, Json)>[
        ('createFamily', {'name': 'Otra'}),
        ('createInvitation', {'familyId': familyId}),
        ('acceptInvitation', {'code': 'ABCDEFGHJK'}),
        ('leaveFamily', {'familyId': familyId}),
        ('removeMember', {'familyId': familyId, 'uid': 'ana'}),
        ('raiseSos', {'familyId': familyId, 'alertId': 'alerta-1'}),
        ('deleteAccount', {}),
        ('signOutEverywhere', {}),
        ('noExiste', {}),
      ]) {
        expect(
          await functions.call(name, payload),
          const Err<Json>(Failure.unauthenticated()),
          reason: name,
        );
      }
      expect(store.snapshot, before);
    });

    test('una función desconocida responde unknown-function', () async {
      expect(
        await callAs('ana', 'borrarTodo'),
        const Err<Json>(Failure(FailureKind.notFound, 'unknown-function')),
      );
    });

    test('con simulatedFailure devuelve ese fallo sin escribir nada', () async {
      const failure = Failure.unavailable();
      store.simulatedFailure = failure;
      final before = store.snapshot;
      expect(
        await callAs('ana', 'createFamily', {'name': 'Casa'}),
        const Err<Json>(failure),
      );
      expect(store.snapshot, before);
    });

    test('rechaza datos mal formados con códigos en kebab-case', () async {
      final familyId = await createFamily('ana');
      final cases = <(String, Json, String)>[
        ('leaveFamily', {}, 'family-id-required'),
        ('leaveFamily', {'familyId': 3}, 'family-id-required'),
        ('leaveFamily', {'familyId': ''}, 'family-id-required'),
        ('leaveFamily', {'familyId': '$familyId/x/y'}, 'family-id-invalid'),
        ('leaveFamily', {'familyId': '..'}, 'family-id-invalid'),
        ('createInvitation', {'familyId': '__x__'}, 'family-id-invalid'),
        ('removeMember', {'familyId': familyId}, 'uid-required'),
        (
          'raiseSos',
          {'familyId': familyId, 'alertId': 'a/b'},
          'alert-id-invalid',
        ),
        ('raiseSos', {'familyId': familyId}, 'alert-id-required'),
        ('acceptInvitation', {}, 'code-required'),
      ];
      for (final (name, payload, code) in cases) {
        final failure = (await callAs('ana', name, payload)).failureOrNull;
        expect(failure, Failure(FailureKind.validation, code), reason: name);
        expect(failure!.code, matches(_kebabCase));
      }
    });

    test('con la misma semilla genera los mismos identificadores y '
        'códigos', () async {
      final otherStore = InMemoryRemoteStore(clock: FakeClock());
      final other = newClient(otherStore);
      session = 'ana';
      final a = await ok(functions.call('createFamily', {'name': 'Casa'}));
      final b = await ok(other.call('createFamily', {'name': 'Casa'}));
      expect(a, b);
      final codeA = await ok(functions.call('createInvitation', a));
      final codeB = await ok(other.call('createInvitation', b));
      expect(codeA['code'], codeB['code']);
      await otherStore.dispose();
    });

    test('un ID generado nunca reemplaza un documento existente, aunque '
        'varios clientes compartan semilla y almacén', () async {
      final familyId = await createFamily('ana');
      final code = await invite(familyId, 'ana');
      // Mismo Random(7) que `functions`: generan la misma secuencia de IDs.
      session = 'bruno';
      await ok(newClient(store).call('acceptInvitation', {'code': code}));
      session = 'carla';
      final own = await ok(
        newClient(store).call('createFamily', {'name': 'Casa Carla'}),
      );

      expect(own['familyId'], isNot(familyId));
      expect(store.serverRead('families/$familyId'), {
        'name': 'Casa Prueba',
        'createdBy': 'ana',
        'createdAt': clock.now(),
        'memberCount': 2,
      });
      expect(roleOf(familyId, 'carla'), isNull);
      for (final action in [
        'createFamily',
        'createInvitation',
        'acceptInvitation',
      ]) {
        expect(auditsOf(familyId, action), hasLength(1), reason: action);
      }
    });

    test('con un reloj explícito, las fechas que calcula la función lo '
        'usan', () async {
      final ownClock = FakeClock(DateTime.utc(2030, 6));
      final client = DemoFunctionsClient(
        store: store,
        currentUid: () => 'ana',
        clock: ownClock,
        random: math.Random(1),
      );
      final created = await ok(client.call('createFamily', {'name': 'Casa'}));
      final invitation = await ok(client.call('createInvitation', created));
      expect(
        invitation['expiresAt'],
        DateTime.utc(
          2030,
          6,
        ).add(const Duration(hours: 48)).millisecondsSinceEpoch,
      );
    });
  });

  group('createFamily', () {
    test('crea exactamente la familia, el integrante owner, la membresía, el '
        'consentimiento notConfigured y la auditoría', () async {
      final before = store.snapshot.keys.toSet();
      final now = clock.now();
      final familyId = await createFamily('ana');

      expect(familyId, matches(RegExp(r'^[a-z0-9]{20}$')));
      final auditPath = store.serverList('families/$familyId/audit').single;
      expect(store.snapshot.keys.toSet().difference(before), {
        'families/$familyId',
        'families/$familyId/members/ana',
        'users/ana/memberships/$familyId',
        'families/$familyId/consents/ana',
        auditPath,
      });
      expect(store.serverRead('families/$familyId'), {
        'name': 'Casa Prueba',
        'createdBy': 'ana',
        'createdAt': now,
        'memberCount': 1,
      });
      expect(store.serverRead('families/$familyId/members/ana'), {
        'uid': 'ana',
        'displayName': 'Ana Prueba',
        'role': 'owner',
        'joinedAt': now,
      });
      expect(store.serverRead('users/ana/memberships/$familyId'), {
        'familyId': familyId,
        'familyName': 'Casa Prueba',
        'role': 'owner',
        'joinedAt': now,
      });
      expect(store.serverRead('families/$familyId/consents/ana'), {
        'state': 'notConfigured',
        'precision': 'exact',
        'updatedAt': now,
      });
      expect(store.serverRead(auditPath), {
        'action': 'createFamily',
        'actorUid': 'ana',
        'createdAt': now,
        'expireAt': now.add(const Duration(days: 180)),
      });
    });

    test('recorta el nombre y acepta de 1 a 40 caracteres con al menos una '
        'letra o un dígito', () async {
      for (final (input, stored) in [
        ('  Casa Prueba  ', 'Casa Prueba'),
        ('A', 'A'),
        ('7', '7'),
        ('Ñandú 🙂', 'Ñandú 🙂'),
        ('x' * 40, 'x' * 40),
        (' ${'y' * 40} ', 'y' * 40),
      ]) {
        final familyId = await createFamily('bruno', input);
        expect(store.serverRead('families/$familyId')!['name'], stored);
        await ok(callAs('bruno', 'leaveFamily', {'familyId': familyId}));
      }
    });

    test('rechaza con family-name-invalid un nombre vacío, de solo espacios, '
        'sin letras ni dígitos, de más de 40 caracteres o que no es '
        'texto', () async {
      final before = store.snapshot;
      for (final payload in <Json>[
        {'name': ''},
        {'name': '   '},
        {'name': '---'},
        // Espacio de ancho cero: no se recorta, pero no se ve.
        {'name': '\u200B'},
        {'name': '🙂🙂'},
        {'name': 'x' * 41},
        {},
        {'name': null},
        {'name': 42},
      ]) {
        expect(
          await callAs('ana', 'createFamily', payload),
          const Err<Json>(
            Failure(FailureKind.validation, 'family-name-invalid'),
          ),
          reason: '$payload',
        );
      }
      expect(store.snapshot, before);
    });

    test('sin perfil, o con un nombre vacío o que no es texto, el integrante '
        'se llama "Integrante"', () async {
      store
        ..serverWrite('users/vacio', {'displayName': ''})
        ..serverWrite('users/numerico', {'displayName': 42});
      for (final uid in ['sin-perfil', 'vacio', 'numerico']) {
        final familyId = await createFamily(uid);
        expect(
          store.serverRead('families/$familyId/members/$uid')!['displayName'],
          'Integrante',
          reason: uid,
        );
      }
    });

    test('admite como máximo 5 familias por usuario, contando aquellas a las '
        'que se unió por invitación', () async {
      for (var i = 0; i < 4; i++) {
        await createFamily('ana');
      }
      final joined = await createFamily('bruno');
      await ok(accept('ana', await invite(joined, 'bruno')));
      expect(store.serverList('users/ana/memberships'), hasLength(5));

      final families = store.serverList('families').length;
      expect(
        await callAs('ana', 'createFamily', {'name': 'Sexta'}),
        const Err<Json>(Failure(FailureKind.rateLimited, 'too-many-families')),
      );
      expect(store.serverList('families'), hasLength(families));

      await ok(callAs('ana', 'leaveFamily', {'familyId': joined}));
      await createFamily('ana', 'Sexta');
    });
  });

  group('createInvitation', () {
    test('el owner y un admin pueden invitar; un member o alguien ajeno '
        'reciben not-allowed', () async {
      final familyId = await familyOf('ana', ['bruno', 'carla']);
      setRole(familyId, 'bruno', 'admin');

      await invite(familyId, 'ana');
      await invite(familyId, 'bruno');
      for (final uid in ['carla', 'dario']) {
        expect(
          await callAs(uid, 'createInvitation', {'familyId': familyId}),
          _notAllowed,
          reason: uid,
        );
      }
      expect(
        await callAs('ana', 'createInvitation', {'familyId': 'no-existe'}),
        _notAllowed,
      );
    });

    test('el código tiene 10 caracteres del alfabeto sin caracteres '
        'ambiguos', () async {
      final familyId = await createFamily('ana');
      final codes = <String>{};
      for (var round = 0; round < 5; round++) {
        for (var i = 0; i < 10; i++) {
          codes.add(await invite(familyId, 'ana'));
        }
        // Al vencer las anteriores se pueden crear 10 más.
        clock.advance(const Duration(hours: 48));
      }
      expect(codes, hasLength(50));
      for (final code in codes) {
        expect(code, matches(RegExp('^[$_alphabet]{10}\$')));
        expect(code, isNot(matches(RegExp('[ILO01]'))));
      }
    });

    test('guarda solo el hash SHA-256: el código en claro no aparece en '
        'ningún documento del almacén', () async {
      final familyId = await createFamily('ana');
      final result = await ok(
        callAs('ana', 'createInvitation', {'familyId': familyId}),
      );
      final code = result['code']! as String;

      expect(store.serverRead('invitations/${_sha256(code)}'), isNotNull);
      expect(store.serverList('invitations'), ['invitations/${_sha256(code)}']);
      final snapshot = store.snapshot;
      for (final MapEntry(:key, :value) in snapshot.entries) {
        expect(key, isNot(contains(code)));
        for (final text in _texts(value)) {
          expect(text, isNot(contains(code)), reason: key);
          expect(text.toUpperCase(), isNot(contains(code)), reason: key);
        }
      }
      expect(result['invitationId'], isNot(contains(code)));
    });

    test('guarda los campos del contrato: vence a las 48 h, admite un uso y '
        'devuelve expiresAt en milisegundos', () async {
      final familyId = await createFamily('ana');
      clock.advance(const Duration(minutes: 3));
      final now = clock.now();
      final result = await ok(
        callAs('ana', 'createInvitation', {'familyId': familyId}),
      );
      final code = result['code']! as String;
      final expiresAt = now.add(const Duration(hours: 48));

      expect(result, {
        'invitationId': _sha256(code).substring(0, 12),
        'code': code,
        'expiresAt': expiresAt.millisecondsSinceEpoch,
        'maxUses': 1,
      });
      expect(store.serverRead('invitations/${_sha256(code)}'), {
        'familyId': familyId,
        'createdBy': 'ana',
        'createdAt': now,
        'expiresAt': expiresAt,
        'expireAt': expiresAt.add(const Duration(days: 7)),
        'maxUses': 1,
        'uses': 0,
        'status': 'active',
      });
      expect(auditsOf(familyId, 'createInvitation').single, {
        'action': 'createInvitation',
        'actorUid': 'ana',
        'createdAt': now,
        'expireAt': now.add(const Duration(days: 180)),
      });
    });

    test('admite como máximo 10 invitaciones activas por familia', () async {
      final familyId = await createFamily('ana');
      final other = await createFamily('bruno');
      final codes = [
        for (var i = 0; i < 10; i++) await invite(familyId, 'ana'),
      ];

      const tooMany = Err<Json>(
        Failure(FailureKind.rateLimited, 'too-many-invitations'),
      );
      expect(
        await callAs('ana', 'createInvitation', {'familyId': familyId}),
        tooMany,
      );
      expect(store.serverList('invitations'), hasLength(10));
      // Las de otra familia no cuentan.
      await invite(other, 'bruno');

      // Una invitación agotada deja de estar activa.
      await ok(accept('carla', codes.first));
      await invite(familyId, 'ana');
      expect(
        await callAs('ana', 'createInvitation', {'familyId': familyId}),
        tooMany,
      );

      // Las vencidas tampoco cuentan.
      clock.advance(const Duration(hours: 48));
      await invite(familyId, 'ana');
    });
  });

  group('acceptInvitation', () {
    test('une a la persona como member y escribe los documentos del '
        'contrato', () async {
      final familyId = await createFamily('ana');
      final code = await invite(familyId, 'ana');
      clock.advance(const Duration(minutes: 5));
      final now = clock.now();

      expect(await accept('bruno', code), _isOk({'familyId': familyId}));

      expect(store.serverRead('families/$familyId/members/bruno'), {
        'uid': 'bruno',
        'displayName': 'Bruno Prueba',
        'role': 'member',
        'joinedAt': now,
      });
      expect(store.serverRead('users/bruno/memberships/$familyId'), {
        'familyId': familyId,
        'familyName': 'Casa Prueba',
        'role': 'member',
        'joinedAt': now,
      });
      expect(store.serverRead('families/$familyId/consents/bruno'), {
        'state': 'notConfigured',
        'precision': 'exact',
        'updatedAt': now,
      });
      expect(store.serverRead('families/$familyId')!['memberCount'], 2);
      expect(store.serverRead('invitations/${_sha256(code)}'), {
        'familyId': familyId,
        'createdBy': 'ana',
        'createdAt': now.subtract(const Duration(minutes: 5)),
        'expiresAt': now.add(
          const Duration(hours: 48) - const Duration(minutes: 5),
        ),
        'expireAt': now.add(
          const Duration(hours: 48, days: 7) - const Duration(minutes: 5),
        ),
        'maxUses': 1,
        'uses': 1,
        'status': 'exhausted',
      });
      expect(eventsOf(familyId, 'membership').single, {
        'type': 'membership',
        'actorUid': 'bruno',
        'change': 'joined',
        'createdAt': now,
        'expireAt': now.add(const Duration(days: 30)),
      });
      expect(auditsOf(familyId, 'acceptInvitation').single, {
        'action': 'acceptInvitation',
        'actorUid': 'bruno',
        'createdAt': now,
        'expireAt': now.add(const Duration(days: 180)),
      });
    });

    test('acepta el código con guiones, espacios y minúsculas', () async {
      final familyId = await createFamily('ana');
      for (final (uid, format) in [
        ('bruno', (String c) => '${c.substring(0, 5)}-${c.substring(5)}'),
        ('carla', (String c) => ' ${c.toLowerCase().split('').join(' ')} '),
      ]) {
        final code = await invite(familyId, 'ana');
        expect(
          await accept(uid, format(code)),
          _isOk({'familyId': familyId}),
          reason: uid,
        );
      }
    });

    test('un código inexistente, vencido, agotado, revocado o de una familia '
        'borrada responde siempre invitation-invalid', () async {
      final familyId = await familyOf('ana', ['bruno']);
      final exhausted = await invite(familyId, 'ana');
      await ok(accept('carla', exhausted));
      final revoked = await invite(familyId, 'ana');
      store.serverWrite('invitations/${_sha256(revoked)}', {
        ...?store.serverRead('invitations/${_sha256(revoked)}'),
        'status': 'revoked',
      });
      final solo = await createFamily('elena');
      final orphan = await invite(solo, 'elena');
      await ok(callAs('elena', 'leaveFamily', {'familyId': solo}));
      final expired = await invite(familyId, 'ana');

      // Primero los que no dependen del vencimiento.
      final results = <String, Result<Json>>{
        'inexistente': await accept('dario', 'ZZZZZZZZZZ'),
        'mal formado': await accept('dario', 'hola'),
        'agotado': await accept('dario', exhausted),
        'revocado': await accept('dario', revoked),
        'familia borrada': await accept('dario', orphan),
      };
      clock.advance(const Duration(hours: 48));
      results['vencido'] = await accept('dario', expired);
      for (final MapEntry(:key, :value) in results.entries) {
        expect(value, _invitationInvalid, reason: key);
      }
      expect(results.values.toSet(), hasLength(1));
      expect(store.serverRead('families/$familyId/members/dario'), isNull);
    });

    test('vence exactamente a las 48 h', () async {
      final familyId = await createFamily('ana');
      final first = await invite(familyId, 'ana');
      final second = await invite(familyId, 'ana');

      clock.advance(const Duration(hours: 48) - const Duration(seconds: 1));
      expect((await accept('bruno', first)).isOk, isTrue);
      clock.advance(const Duration(seconds: 1));
      expect(await accept('carla', second), _invitationInvalid);
    });

    test('already-member no consume la invitación', () async {
      final familyId = await familyOf('ana', ['bruno']);
      final code = await invite(familyId, 'ana');
      for (final uid in ['ana', 'bruno']) {
        expect(
          await accept(uid, code),
          const Err<Json>(Failure(FailureKind.conflict, 'already-member')),
          reason: uid,
        );
      }
      final invitation = store.serverRead('invitations/${_sha256(code)}')!;
      expect(invitation['uses'], 0);
      expect(invitation['status'], 'active');
      expect(store.serverRead('families/$familyId')!['memberCount'], 2);
      expect((await accept('carla', code)).isOk, isTrue);
    });

    test(
      'family-full con 12 integrantes, sin consumir la invitación',
      () async {
        final members = [for (var i = 1; i < 12; i++) 'persona-$i'];
        final familyId = await familyOf('ana', members);
        expect(store.serverList('families/$familyId/members'), hasLength(12));
        expect(store.serverRead('families/$familyId')!['memberCount'], 12);

        final code = await invite(familyId, 'ana');
        expect(
          await accept('persona-12', code),
          const Err<Json>(Failure(FailureKind.rateLimited, 'family-full')),
        );
        expect(store.serverRead('families/$familyId')!['memberCount'], 12);
        expect(
          store.serverRead('families/$familyId/members/persona-12'),
          isNull,
        );
        expect(store.serverRead('invitations/${_sha256(code)}')!['uses'], 0);

        // Al liberarse un hueco, la misma invitación vuelve a servir.
        await ok(callAs('persona-1', 'leaveFamily', {'familyId': familyId}));
        expect((await accept('persona-12', code)).isOk, isTrue);
      },
    );

    test('admite como máximo 10 intentos por hora por usuario, también los '
        'fallidos y los exitosos', () async {
      final familyId = await createFamily('ana');
      final valid = await invite(familyId, 'ana');
      final other = await createFamily('carla');

      // 9 intentos fallidos y 1 exitoso: 10 en la ventana.
      for (var i = 0; i < 9; i++) {
        expect(await accept('bruno', 'ZZZZZZZZZZ'), _invitationInvalid);
      }
      await ok(accept('bruno', await invite(other, 'carla')));

      expect(await accept('bruno', valid), _rateLimited);
      // El límite es por usuario.
      expect(await accept('dario', 'ZZZZZZZZZZ'), _invitationInvalid);

      clock.advance(const Duration(minutes: 59, seconds: 59));
      expect(await accept('bruno', valid), _rateLimited);
      expect(store.serverRead('families/$familyId/members/bruno'), isNull);

      clock.advance(const Duration(seconds: 1));
      expect(await accept('bruno', valid), _isOk({'familyId': familyId}));
    });
  });

  group('leaveFamily', () {
    test('borra integrante, membresía, ubicación y consentimiento y registra '
        'el evento left', () async {
      final familyId = await familyOf('ana', ['bruno', 'carla']);
      store.serverWrite('families/$familyId/locations/bruno', {
        'lat': 1.2345,
        'lng': -2.3456,
        'accuracyM': 20.0,
      });
      clock.advance(const Duration(hours: 1));
      final now = clock.now();

      expect(
        await callAs('bruno', 'leaveFamily', {'familyId': familyId}),
        _isOk({}),
      );

      for (final path in [
        'families/$familyId/members/bruno',
        'users/bruno/memberships/$familyId',
        'families/$familyId/locations/bruno',
        'families/$familyId/consents/bruno',
      ]) {
        expect(store.serverRead(path), isNull, reason: path);
      }
      expect(store.serverRead('families/$familyId')!['memberCount'], 2);
      expect(roleOf(familyId, 'ana'), 'owner');
      expect(roleOf(familyId, 'carla'), 'member');
      expect(store.serverRead('families/$familyId/consents/carla'), isNotNull);
      expect(store.serverRead('users/bruno'), isNotNull);
      expect(eventsOf(familyId, 'membership').last, {
        'type': 'membership',
        'actorUid': 'bruno',
        'change': 'left',
        'createdAt': now,
        'expireAt': now.add(const Duration(days: 30)),
      });
      expect(auditsOf(familyId, 'leaveFamily').single, {
        'action': 'leaveFamily',
        'actorUid': 'bruno',
        'createdAt': now,
        'expireAt': now.add(const Duration(days: 180)),
      });
    });

    test('si sale el owner, el integrante más antiguo pasa a owner', () async {
      // zoe es más antigua que bruno aunque su uid sea mayor.
      final familyId = await familyOf('ana', ['zoe', 'bruno']);
      await ok(callAs('ana', 'leaveFamily', {'familyId': familyId}));

      expect(roleOf(familyId, 'zoe'), 'owner');
      expect(
        store.serverRead('users/zoe/memberships/$familyId')!['role'],
        'owner',
      );
      expect(roleOf(familyId, 'bruno'), 'member');
      expect(
        store.serverRead('users/bruno/memberships/$familyId')!['role'],
        'member',
      );
      expect(store.serverRead('families/$familyId')!['memberCount'], 2);
    });

    test('a igual antigüedad hereda el uid menor', () async {
      final familyId = await familyOf('ana', [
        'zoe',
        'bruno',
      ], gap: Duration.zero);
      await ok(callAs('ana', 'leaveFamily', {'familyId': familyId}));
      expect(roleOf(familyId, 'bruno'), 'owner');
      expect(roleOf(familyId, 'zoe'), 'member');
    });

    test('si sale el último integrante se borra la familia con todas sus '
        'subcolecciones', () async {
      final familyId = await createFamily('ana');
      final other = await createFamily('bruno');
      await ok(
        callAs('ana', 'raiseSos', {'familyId': familyId, 'alertId': 'sos-1'}),
      );
      store
        ..serverWrite('families/$familyId/geofences/g1', {'name': 'Zona'})
        ..serverWrite('families/$familyId/locations/ana', {
          'lat': 1.0,
          'lng': 2.0,
        });

      expect(
        await callAs('ana', 'leaveFamily', {'familyId': familyId}),
        _isOk({}),
      );

      final leftovers = store.snapshot.keys.where(
        (k) => k == 'families/$familyId' || k.startsWith('families/$familyId/'),
      );
      expect(leftovers, isEmpty);
      expect(store.serverRead('users/ana/memberships/$familyId'), isNull);
      expect(store.serverRead('families/$other'), isNotNull);
      expect(roleOf(other, 'bruno'), 'owner');
    });

    test('quien no es miembro recibe not-member', () async {
      final familyId = await createFamily('ana');
      final before = store.snapshot;
      for (final id in [familyId, 'no-existe']) {
        expect(
          await callAs('bruno', 'leaveFamily', {'familyId': id}),
          const Err<Json>(Failure(FailureKind.notFound, 'not-member')),
        );
      }
      expect(store.snapshot, before);
    });
  });

  group('removeMember', () {
    // owner: ana · admins: bruno, berta · members: carla, camilo.
    Future<String> rolesFamily() async {
      final familyId = await familyOf('ana', [
        'bruno',
        'berta',
        'carla',
        'camilo',
      ]);
      setRole(familyId, 'bruno', 'admin');
      setRole(familyId, 'berta', 'admin');
      return familyId;
    }

    const cases = [
      ('owner', 'ana', 'admin', 'bruno', true),
      ('owner', 'ana', 'member', 'carla', true),
      ('owner', 'ana', 'sí mismo', 'ana', false),
      ('admin', 'bruno', 'member', 'carla', true),
      ('admin', 'bruno', 'otro admin', 'berta', false),
      ('admin', 'bruno', 'owner', 'ana', false),
      ('admin', 'bruno', 'sí mismo', 'bruno', false),
      ('member', 'carla', 'otro member', 'camilo', false),
      ('member', 'carla', 'admin', 'bruno', false),
      ('member', 'carla', 'owner', 'ana', false),
      ('member', 'carla', 'sí mismo', 'carla', false),
      ('ajeno', 'dario', 'member', 'carla', false),
      ('owner', 'ana', 'ajeno', 'dario', false),
    ];
    for (final (callerRole, caller, targetRole, target, allowed) in cases) {
      test('$callerRole expulsa a $targetRole: '
          '${allowed ? 'permitido' : 'not-allowed'}', () async {
        final familyId = await rolesFamily();
        final before = store.snapshot;
        final result = await callAs(caller, 'removeMember', {
          'familyId': familyId,
          'uid': target,
        });
        if (allowed) {
          expect(result, _isOk({}));
          expect(roleOf(familyId, target), isNull);
          expect(store.serverRead('families/$familyId')!['memberCount'], 4);
        } else {
          expect(result, _notAllowed);
          expect(store.snapshot, before);
        }
      });
    }

    test('borra lo mismo que leaveFamily y registra el evento removed con '
        'targetUid', () async {
      final familyId = await familyOf('ana', ['bruno', 'carla']);
      store.serverWrite('families/$familyId/locations/carla', {
        'lat': 3.0,
        'lng': 4.0,
      });
      clock.advance(const Duration(hours: 2));
      final now = clock.now();

      await ok(
        callAs('ana', 'removeMember', {'familyId': familyId, 'uid': 'carla'}),
      );

      for (final path in [
        'families/$familyId/members/carla',
        'users/carla/memberships/$familyId',
        'families/$familyId/locations/carla',
        'families/$familyId/consents/carla',
      ]) {
        expect(store.serverRead(path), isNull, reason: path);
      }
      expect(store.serverRead('families/$familyId')!['memberCount'], 2);
      expect(eventsOf(familyId, 'membership').last, {
        'type': 'membership',
        'actorUid': 'ana',
        'change': 'removed',
        'targetUid': 'carla',
        'createdAt': now,
        'expireAt': now.add(const Duration(days: 30)),
      });
      expect(auditsOf(familyId, 'removeMember').single, {
        'action': 'removeMember',
        'actorUid': 'ana',
        'targetUid': 'carla',
        'createdAt': now,
        'expireAt': now.add(const Duration(days: 180)),
      });
    });
  });

  group('raiseSos', () {
    late String familyId;

    setUp(() async {
      familyId = await familyOf('ana', ['bruno']);
      clock.advance(const Duration(hours: 1));
    });

    Future<Result<Json>> sos(
      String uid,
      String alertId, [
      Json extra = const {},
    ]) => callAs(uid, 'raiseSos', {
      'familyId': familyId,
      'alertId': alertId,
      ...extra,
    });

    test('crea la alerta del contrato con notifiedCount 0 y un evento sos sin '
        'coordenadas', () async {
      final now = clock.now();
      expect(
        await sos('ana', 'alerta-1', {
          'lat': 1.5,
          'lng': -2.25,
          'accuracyM': 30,
        }),
        _isOk({
          'alertId': 'alerta-1',
          'notifiedCount': 0,
          'alreadyExisted': false,
        }),
      );
      expect(store.serverRead('families/$familyId/emergencies/alerta-1'), {
        'uid': 'ana',
        'createdAt': now,
        'lat': 1.5,
        'lng': -2.25,
        'accuracyM': 30.0,
        'notifiedCount': 0,
        'acks': <String, Object?>{},
        'resolvedAt': null,
        'expireAt': now.add(const Duration(days: 90)),
      });
      expect(eventsOf(familyId, 'sos').single, {
        'type': 'sos',
        'actorUid': 'ana',
        'alertId': 'alerta-1',
        'createdAt': now,
        'expireAt': now.add(const Duration(days: 90)),
      });
      expect(auditsOf(familyId, 'raiseSos').single, {
        'action': 'raiseSos',
        'actorUid': 'ana',
        'createdAt': now,
        'expireAt': now.add(const Duration(days: 180)),
      });
    });

    test('sin coordenadas no guarda campos de ubicación', () async {
      await ok(sos('ana', 'alerta-1'));
      final alert = store.serverRead(
        'families/$familyId/emergencies/alerta-1',
      )!;
      expect(
        alert.keys.toSet().intersection({'lat', 'lng', 'accuracyM'}),
        isEmpty,
      );
    });

    test('acepta coordenadas enteras y descarta las inválidas sin rechazar la '
        'alerta', () async {
      final cases = <String, (Json, Json)>{
        'enteras': (
          {'lat': 2, 'lng': 3, 'accuracyM': 10},
          {'lat': 2.0, 'lng': 3.0, 'accuracyM': 10.0},
        ),
        'precisión negativa': (
          {'lat': 2.0, 'lng': 3.0, 'accuracyM': -1},
          {'lat': 2.0, 'lng': 3.0},
        ),
        'latitud fuera de rango': ({'lat': 91.0, 'lng': 3.0}, {}),
        'longitud fuera de rango': ({'lat': 2.0, 'lng': -180.5}, {}),
        'solo latitud': ({'lat': 2.0}, {}),
        'no numérica': ({'lat': '2.0', 'lng': '3.0'}, {}),
        'NaN': ({'lat': double.nan, 'lng': 3.0}, {}),
      };
      var n = 0;
      for (final MapEntry(key: name, value: (input, stored)) in cases.entries) {
        final alertId = 'alerta-${n++}';
        expect((await sos('ana', alertId, input)).isOk, isTrue, reason: name);
        final alert = store.serverRead(
          'families/$familyId/emergencies/$alertId',
        )!;
        expect(
          {
            for (final key in ['lat', 'lng', 'accuracyM'])
              if (alert.containsKey(key)) key: alert[key],
          },
          stored,
          reason: name,
        );
        // Evita el límite de 5 por hora entre casos.
        clock.advance(const Duration(hours: 1));
      }
    });

    test('es idempotente por alertId: devuelve lo guardado sin duplicar '
        'eventos ni contar para el límite', () async {
      await ok(sos('ana', 'alerta-1', {'lat': 1.0, 'lng': 1.0}));
      final stored = store.serverRead(
        'families/$familyId/emergencies/alerta-1',
      );
      for (var i = 0; i < 10; i++) {
        clock.advance(const Duration(seconds: 1));
        expect(
          await sos('ana', 'alerta-1', {'lat': 9.0, 'lng': 9.0}),
          _isOk({
            'alertId': 'alerta-1',
            'notifiedCount': 0,
            'alreadyExisted': true,
          }),
        );
      }
      expect(
        store.serverRead('families/$familyId/emergencies/alerta-1'),
        stored,
      );
      expect(eventsOf(familyId, 'sos'), hasLength(1));
      expect(auditsOf(familyId, 'raiseSos'), hasLength(1));

      // Los reintentos no consumieron el cupo: caben 4 alertas nuevas más.
      for (var i = 2; i <= 5; i++) {
        await ok(sos('ana', 'alerta-$i'));
      }
      expect(await sos('ana', 'alerta-6'), _rateLimited);
    });

    test('un alertId de otra persona responde not-allowed y no toca la '
        'alerta', () async {
      await ok(sos('ana', 'alerta-1'));
      final before = store.snapshot;
      expect(await sos('bruno', 'alerta-1'), _notAllowed);
      expect(store.snapshot, before);
    });

    test('admite como máximo 5 por hora por usuario', () async {
      for (var i = 1; i <= 5; i++) {
        await ok(sos('ana', 'alerta-$i'));
      }
      expect(await sos('ana', 'alerta-6'), _rateLimited);
      expect(
        store.serverRead('families/$familyId/emergencies/alerta-6'),
        isNull,
      );
      expect(eventsOf(familyId, 'sos'), hasLength(5));
      // El límite es por usuario.
      await ok(sos('bruno', 'alerta-b'));

      clock.advance(const Duration(minutes: 59, seconds: 59));
      expect(await sos('ana', 'alerta-6'), _rateLimited);
      clock.advance(const Duration(seconds: 1));
      await ok(sos('ana', 'alerta-6'));
    });

    test('quien no es miembro recibe permission-denied y no consume '
        'cupo', () async {
      final before = store.snapshot;
      for (final id in [familyId, 'no-existe']) {
        final result = await callAs('carla', 'raiseSos', {
          'familyId': id,
          'alertId': 'alerta-1',
        });
        expect(
          result,
          const Err<Json>(Failure(FailureKind.permissionDenied, 'not-member')),
        );
      }
      expect(store.snapshot, before);
    });
  });

  group('signOutEverywhere', () {
    test('revoca las invitaciones activas que creó', () async {
      final familyId = await createFamily('ana');
      final code =
          (await ok(
                callAs('ana', 'createInvitation', {'familyId': familyId}),
              ))['code']!
              as String;
      expect(await callAs('ana', 'signOutEverywhere'), _isOk({}));
      expect(
        await callAs('bruno', 'acceptInvitation', {'code': code}),
        const Err<Json>(Failure(FailureKind.notFound, 'invitation-invalid')),
      );
    });

    test('borra solo los dispositivos de avisos de quien la llama', () async {
      store
        ..serverWrite('users/ana', {'displayName': 'Ana'})
        ..serverWrite('users/ana/devices/d1', {'platform': 'android'})
        ..serverWrite('users/ana/devices/d2', {'platform': 'ios'})
        ..serverWrite('users/bruno/devices/b1', {'platform': 'ios'});
      expect(await callAs('ana', 'signOutEverywhere'), _isOk({}));
      expect(store.serverList('users/ana/devices'), isEmpty);
      expect(store.serverRead('users/ana'), isNotNull);
      expect(store.serverRead('users/bruno/devices/b1'), isNotNull);
    });
  });

  group('deleteAccount', () {
    test('sale de todas sus familias y borra el perfil con sus '
        'subcolecciones', () async {
      final alone = await createFamily('ana');
      final shared = await familyOf('ana', ['bruno']);
      final foreign = await familyOf('carla', ['ana']);
      await ok(
        callAs('ana', 'raiseSos', {'familyId': shared, 'alertId': 's1'}),
      );
      store
        ..serverWrite('users/ana/devices/d1', {'platform': 'android'})
        ..serverWrite('users/ana/private/notificationPrefs', {'sos': true});

      expect(await callAs('ana', 'deleteAccount'), _isOk({}));

      expect(
        store.snapshot.keys.where(
          (k) => k == 'users/ana' || k.startsWith('users/ana/'),
        ),
        isEmpty,
      );
      expect(store.serverRead('rateLimits/ana'), isNull);
      expect(store.serverRead('families/$alone'), isNull);
      expect(roleOf(shared, 'ana'), isNull);
      expect(roleOf(shared, 'bruno'), 'owner');
      expect(store.serverRead('families/$shared')!['memberCount'], 1);
      expect(roleOf(foreign, 'ana'), isNull);
      expect(store.serverRead('families/$foreign')!['memberCount'], 1);
      expect(store.serverRead('users/bruno'), isNotNull);
      expect(store.serverRead('users/carla'), isNotNull);
    });

    test('borra sus check-ins, quita coordenadas de sus alertas y anonimiza '
        'la auditoría', () async {
      final familyId = await familyOf('carla', ['ana']);
      await ok(
        callAs('ana', 'raiseSos', {
          'familyId': familyId,
          'alertId': 's1',
          'lat': 1.5,
          'lng': 2.5,
          'accuracyM': 10,
        }),
      );
      final events = 'families/$familyId/events';
      store
        ..serverWrite('$events/c1', {
          'type': 'checkIn',
          'actorUid': 'ana',
          'message': 'Llegué',
        })
        ..serverWrite('$events/g1', {
          'type': 'geofence',
          'actorUid': 'ana',
          'geofenceName': 'Colegio',
        })
        ..serverWrite('$events/c2', {'type': 'checkIn', 'actorUid': 'carla'});

      expect(await callAs('ana', 'deleteAccount'), _isOk({}));

      expect(store.serverRead('$events/c1'), isNull);
      expect(store.serverRead('$events/g1'), isNull);
      expect(store.serverRead('$events/c2'), isNotNull);
      final alert = store.serverRead('families/$familyId/emergencies/s1')!;
      expect(alert['uid'], 'ana');
      expect(alert.keys, isNot(contains('lat')));
      expect(alert.keys, isNot(contains('accuracyM')));
      final audit = [
        for (final path in store.serverList('families/$familyId/audit'))
          store.serverRead(path)!,
      ];
      expect(
        audit.expand((a) => [a['actorUid'], a['targetUid']]),
        allOf(isNot(contains('ana')), contains(deletedUser)),
      );
      expect(store.snapshot.toString(), isNot(contains('Llegué')));
      expect(store.snapshot.toString(), isNot(contains('Colegio')));
    });

    test('limpia también las familias de las que ya había salido, anonimiza '
        'createdBy y borra sus invitaciones', () async {
      final familyId = await familyOf('ana', ['bruno']);
      final events = 'families/$familyId/events';
      store
        ..serverWrite('$events/c1', {
          'type': 'checkIn',
          'actorUid': 'bruno',
          'message': 'Llegué',
        })
        ..serverWrite('families/$familyId/geofences/g1', {
          'name': 'Casa',
          'createdBy': 'bruno',
          'version': 1,
        })
        ..serverWrite('invitations/inv-bruno', {
          'familyId': familyId,
          'createdBy': 'bruno',
          'status': 'active',
        });
      await ok(callAs('bruno', 'leaveFamily', {'familyId': familyId}));

      expect(await callAs('bruno', 'deleteAccount'), _isOk({}));

      expect(store.serverRead('$events/c1'), isNull);
      expect(store.serverRead('families/$familyId/geofences/g1'), {
        'name': 'Casa',
        'createdBy': deletedUser,
        'version': 2,
      });
      expect(store.serverRead('invitations/inv-bruno'), isNull);
      expect(store.snapshot.toString(), isNot(contains('Llegué')));
    });

    test('una membresía huérfana no impide borrar la cuenta', () async {
      store.serverWrite('users/ana/memberships/fantasma', {
        'familyId': 'fantasma',
      });
      expect(await callAs('ana', 'deleteAccount'), _isOk({}));
      expect(store.serverRead('users/ana/memberships/fantasma'), isNull);
      expect(store.serverRead('users/ana'), isNull);
    });
  });

  group('atomicidad', () {
    test('los observadores ven cada función como un único cambio, sin estados '
        'intermedios', () async {
      final familyId = await familyOf('ana', ['bruno', 'carla']);
      final snapshots = <List<RemoteDoc>>[];
      final subscription = store
          .watchCollection('families/$familyId/members')
          .listen(snapshots.add);
      await Future<void>.delayed(Duration.zero);
      expect(snapshots, hasLength(1));

      await ok(callAs('ana', 'leaveFamily', {'familyId': familyId}));
      await Future<void>.delayed(Duration.zero);

      expect(snapshots, hasLength(2));
      final owners = [
        for (final doc in snapshots.last)
          if (doc.data['role'] == 'owner') doc.id,
      ];
      expect(owners, ['bruno']);
      await subscription.cancel();
    });
  });
}
