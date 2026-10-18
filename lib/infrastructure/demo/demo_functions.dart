import 'dart:convert';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';
import 'package:nexo_familia/core/clock.dart';
import 'package:nexo_familia/core/failure.dart';
import 'package:nexo_familia/core/result.dart';
import 'package:nexo_familia/infrastructure/demo/in_memory_remote_store.dart';
import 'package:nexo_familia/infrastructure/remote/remote_store.dart';

/// Reimplementación en Dart de las Cloud Functions
/// (`docs/architecture/05-api-backend.md`) sobre [InMemoryRemoteStore].
///
/// Permite usar la app de extremo a extremo sin red ni credenciales. Las
/// notificaciones push no existen en modo demostración: `notifiedCount` es
/// siempre 0 y la UI lo muestra con honestidad ("Nadie pudo ser notificado").
///
/// Cada función valida antes de escribir y aplica sus escrituras en una
/// transacción del almacén: los observadores nunca ven estados intermedios.
/// Los contadores de frecuencia se guardan aparte, antes de la transacción,
/// para que un intento rechazado también cuente.
/// Sustituye el identificador de una cuenta eliminada en la auditoría.
const deletedUser = 'deleted-user';

final class DemoFunctionsClient implements FunctionsClient {
  /// Si no se indica [clock], se usa el del almacén: así los vencimientos que
  /// calcula la función y los `serverTimestamp` salen del mismo reloj.
  new({
    required this._store,
    required this._currentUid,
    this._currentEmail,
    Clock? clock,
    math.Random? random,
  }) : _clock = clock ?? _store.clock,
       _random = random ?? math.Random.secure();

  final InMemoryRemoteStore _store;
  final String? Function() _currentUid;

  /// Correo de la sesión (en Firebase lo da Auth) para la exportación.
  final String? Function()? _currentEmail;
  final Clock _clock;
  final math.Random _random;

  static const _codeAlphabet = 'ABCDEFGHJKMNPQRSTUVWXYZ23456789';
  static const _codeLength = 10;
  static const _maxFamilyNameLength = 40;

  /// Al menos una letra o un dígito: nada de nombres invisibles.
  static final _visibleName = RegExp(r'[\p{L}\p{N}]', unicode: true);
  static const _maxFamiliesPerUser = 5;
  static const _maxMembers = 12;
  static const _maxActiveInvitations = 10;
  static const _invitationTtl = Duration(hours: 48);
  static const _maxSosPerHour = 5;
  static const _maxExportsPerHour = 3;
  static const _maxInvitationAttemptsPerHour = 10;
  static const _rateWindow = Duration(hours: 1);

  @override
  Future<Result<Json>> call(String name, Json payload) async {
    final uid = _currentUid();
    if (uid == null) return const Err(Failure.unauthenticated());
    if (_store.simulatedFailure case final failure?) return Err(failure);
    try {
      return Ok(switch (name) {
        'createFamily' => _createFamily(uid, payload),
        'createInvitation' => _createInvitation(uid, payload),
        'acceptInvitation' => _acceptInvitation(uid, payload),
        'leaveFamily' => _leaveFamily(uid, _id(payload, 'familyId')),
        'removeMember' => _removeMember(uid, payload),
        'raiseSos' => _raiseSos(uid, payload),
        'deleteAccount' => _deleteAccount(uid),
        'signOutEverywhere' => _signOutEverywhere(uid),
        'exportMyData' => _exportMyData(uid),
        _ => throw const _Reject(FailureKind.notFound, 'unknown-function'),
      });
    } on _Reject catch (r) {
      return Err(Failure(r.kind, r.reason));
    }
  }

  // --- Funciones ------------------------------------------------------------

  Json _createFamily(String uid, Json p) {
    final raw = p['name'];
    final name = raw is String ? raw.trim() : '';
    if (name.length > _maxFamilyNameLength || !_visibleName.hasMatch(name)) {
      throw const _Reject(FailureKind.validation, 'family-name-invalid');
    }
    if (_store.serverList('users/$uid/memberships').length >=
        _maxFamiliesPerUser) {
      throw const _Reject(FailureKind.rateLimited, 'too-many-families');
    }
    return _store.serverTransaction(() {
      final familyId = _newId('families');
      _store
        ..serverWrite('families/$familyId', {
          'name': name,
          'createdBy': uid,
          'createdAt': serverTimestamp,
          'memberCount': 1,
        })
        ..serverWrite('families/$familyId/members/$uid', {
          'uid': uid,
          'displayName': _displayName(uid),
          'role': 'owner',
          'joinedAt': serverTimestamp,
        })
        ..serverWrite('users/$uid/memberships/$familyId', {
          'familyId': familyId,
          'familyName': name,
          'role': 'owner',
          'joinedAt': serverTimestamp,
        });
      _writeInitialConsent(familyId, uid);
      _audit(familyId, 'createFamily', uid);
      return {'familyId': familyId};
    });
  }

  Json _createInvitation(String uid, Json p) {
    final familyId = _id(p, 'familyId');
    final role = _roleOf(familyId, uid);
    if (role != 'owner' && role != 'admin') {
      throw const _Reject(FailureKind.permissionDenied, 'not-allowed');
    }
    final now = _clock.now();
    final active = _store
        .serverList('invitations')
        .map(_store.serverRead)
        .nonNulls
        .where((i) => i['familyId'] == familyId && _isUsable(i, now))
        .length;
    if (active >= _maxActiveInvitations) {
      throw const _Reject(FailureKind.rateLimited, 'too-many-invitations');
    }
    // Solo se guarda el hash; ante una colisión (improbable) se genera otro.
    String code;
    String hash;
    do {
      code = _newCode();
      hash = _hash(code);
    } while (_store.serverRead('invitations/$hash') != null);
    final expiresAt = now.add(_invitationTtl);
    return _store.serverTransaction(() {
      _store.serverWrite('invitations/$hash', {
        'familyId': familyId,
        'createdBy': uid,
        'createdAt': serverTimestamp,
        'expiresAt': expiresAt,
        'expireAt': expiresAt.add(const Duration(days: 7)),
        'maxUses': 1,
        'uses': 0,
        'status': 'active',
      });
      _audit(familyId, 'createInvitation', uid);
      return {
        'invitationId': hash.substring(0, 12),
        'code': code,
        // El contrato fija milisegundos desde la época (UTC).
        'expiresAt': expiresAt.millisecondsSinceEpoch,
        'maxUses': 1,
      };
    });
  }

  Json _acceptInvitation(String uid, Json p) {
    // El intento cuenta aunque luego falle: es lo que frena la fuerza bruta.
    _rateLimit(uid, 'acceptInvitation', _maxInvitationAttemptsPerHour);
    final code = _requiredString(
      p,
      'code',
    ).toUpperCase().replaceAll(RegExp(r'[\s-]'), '');
    return _store.serverTransaction(() {
      final path = 'invitations/${_hash(code)}';
      final invitation = _store.serverRead(path);
      // Inexistente, vencida, agotada, revocada o de una familia borrada:
      // siempre el mismo motivo, para no confirmar si el código existe.
      if (invitation == null || !_isUsable(invitation, _clock.now())) {
        throw const _Reject(FailureKind.notFound, 'invitation-invalid');
      }
      final familyId = invitation['familyId']! as String;
      final family = _store.serverRead('families/$familyId');
      if (family == null) {
        throw const _Reject(FailureKind.notFound, 'invitation-invalid');
      }
      if (_roleOf(familyId, uid) != null) {
        throw const _Reject(FailureKind.conflict, 'already-member');
      }
      final count = family['memberCount']! as int;
      if (count >= _maxMembers) {
        throw const _Reject(FailureKind.rateLimited, 'family-full');
      }
      final uses = (invitation['uses']! as int) + 1;
      _store
        ..serverWrite(path, {
          ...invitation,
          'uses': uses,
          'status': uses >= (invitation['maxUses']! as int)
              ? 'exhausted'
              : 'active',
        })
        ..serverWrite('families/$familyId', {
          ...family,
          'memberCount': count + 1,
        })
        ..serverWrite('families/$familyId/members/$uid', {
          'uid': uid,
          'displayName': _displayName(uid),
          'role': 'member',
          'joinedAt': serverTimestamp,
        })
        ..serverWrite('users/$uid/memberships/$familyId', {
          'familyId': familyId,
          'familyName': family['name'],
          'role': 'member',
          'joinedAt': serverTimestamp,
        });
      _writeInitialConsent(familyId, uid);
      _event(familyId, {
        'type': 'membership',
        'actorUid': uid,
        'change': 'joined',
      });
      _audit(familyId, 'acceptInvitation', uid);
      return {'familyId': familyId};
    });
  }

  /// Saca a [uid] de la familia. Si [removedBy] no es null, es una expulsión
  /// hecha por esa persona.
  Json _leaveFamily(String uid, String familyId, {String? removedBy}) =>
      _store.serverTransaction(() {
        final member = _store.serverRead('families/$familyId/members/$uid');
        final family = _store.serverRead('families/$familyId');
        if (member == null || family == null) {
          throw const _Reject(FailureKind.notFound, 'not-member');
        }
        _store
          ..serverDelete('families/$familyId/members/$uid')
          ..serverDelete('users/$uid/memberships/$familyId')
          ..serverDelete('families/$familyId/locations/$uid')
          ..serverDelete('families/$familyId/consents/$uid');
        final remaining = _store
            .serverList('families/$familyId/members')
            .map(_store.serverRead)
            .nonNulls
            .toList();
        if (remaining.isEmpty) {
          _store.serverDeleteTree('families/$familyId');
          return <String, Object?>{};
        }
        if (member['role'] == 'owner') _promoteOldest(familyId, remaining);
        _store.serverWrite('families/$familyId', {
          ...family,
          'memberCount': remaining.length,
        });
        final actor = removedBy ?? uid;
        _event(familyId, {
          'type': 'membership',
          'actorUid': actor,
          'change': removedBy == null ? 'left' : 'removed',
          if (removedBy != null) 'targetUid': uid,
        });
        _audit(
          familyId,
          removedBy == null ? 'leaveFamily' : 'removeMember',
          actor,
          target: removedBy == null ? null : uid,
        );
        return <String, Object?>{};
      });

  /// El integrante más antiguo pasa a `owner`; a igual antigüedad decide el
  /// uid, para que el resultado sea determinista.
  void _promoteOldest(String familyId, List<Json> remaining) {
    remaining.sort((a, b) {
      final byAge = (a['joinedAt']! as DateTime).compareTo(
        b['joinedAt']! as DateTime,
      );
      return byAge != 0
          ? byAge
          : (a['uid']! as String).compareTo(b['uid']! as String);
    });
    final heir = remaining.first;
    final heirUid = heir['uid']! as String;
    _store
      ..serverWrite('families/$familyId/members/$heirUid', {
        ...heir,
        'role': 'owner',
      })
      ..serverWrite('users/$heirUid/memberships/$familyId', {
        ...?_store.serverRead('users/$heirUid/memberships/$familyId'),
        'role': 'owner',
      });
  }

  Json _removeMember(String uid, Json p) {
    final familyId = _id(p, 'familyId');
    final target = _id(p, 'uid');
    final callerRole = _roleOf(familyId, uid);
    final targetRole = _roleOf(familyId, target);
    final allowed =
        target != uid &&
        targetRole != null &&
        (callerRole == 'owner' ||
            (callerRole == 'admin' && targetRole == 'member'));
    if (!allowed) {
      throw const _Reject(FailureKind.permissionDenied, 'not-allowed');
    }
    return _leaveFamily(target, familyId, removedBy: uid);
  }

  Json _raiseSos(String uid, Json p) {
    final familyId = _id(p, 'familyId');
    final alertId = _id(p, 'alertId');
    if (_roleOf(familyId, uid) == null) {
      throw const _Reject(FailureKind.permissionDenied, 'not-member');
    }
    final path = 'families/$familyId/emergencies/$alertId';
    final existing = _store.serverRead(path);
    if (existing != null) {
      if (existing['uid'] != uid) {
        throw const _Reject(FailureKind.permissionDenied, 'not-allowed');
      }
      // Reintento: se devuelve lo guardado sin volver a notificar ni contar.
      return {
        'alertId': alertId,
        'notifiedCount': existing['notifiedCount'],
        'alreadyExisted': true,
      };
    }
    _rateLimit(uid, 'raiseSos', _maxSosPerHour);
    // Como en las Functions: la ubicación sigue el consentimiento VIGENTE.
    final consent = _store.serverRead('families/$familyId/consents/$uid');
    final location = _shareable(
      _sosLocation(p),
      consent?['state'],
      consent?['precision'],
    );
    return _store.serverTransaction(() {
      _store.serverWrite(path, {
        'uid': uid,
        'createdAt': serverTimestamp,
        ...?location,
        // Sin push en modo demostración: nadie recibe la notificación.
        'notifiedCount': 0,
        'acks': <String, Object?>{},
        'resolvedAt': null,
        'expireAt': _clock.now().add(const Duration(days: 90)),
      });
      // El evento y la auditoría nunca llevan coordenadas.
      _event(familyId, {'type': 'sos', 'actorUid': uid, 'alertId': alertId});
      _audit(familyId, 'raiseSos', uid);
      return {'alertId': alertId, 'notifiedCount': 0, 'alreadyExisted': false};
    });
  }

  /// Como en las Functions, sin sesiones remotas que revocar: borra los
  /// dispositivos registrados para avisos.
  Json _signOutEverywhere(String uid) => _store.serverTransaction(() {
    _store.serverList('users/$uid/devices').forEach(_store.serverDelete);
    // Las invitaciones activas que creó se revocan.
    for (final path in _store.serverList('invitations')) {
      final invitation = _store.serverRead(path)!;
      if (invitation['createdBy'] == uid && invitation['status'] == 'active') {
        _store.serverWrite(path, {...invitation, 'status': 'revoked'});
      }
    }
    return <String, Object?>{};
  });

  /// Igual que `functions/src/export.ts`: los datos de la persona en todas
  /// sus familias, sin tokens ni datos de otras personas.
  Json _exportMyData(String uid) {
    _rateLimit(uid, 'exportMyData', _maxExportsPerHour);
    Json? read(String path) => _store.serverRead(path);
    String familyOf(String path) => path.split('/')[1];
    Json without(Json data, Set<String> keys) => {
      for (final MapEntry(:key, :value) in data.entries)
        if (!keys.contains(key)) key: value,
    };
    final families = _store.serverList('families');
    final events = [
      for (final family in families)
        for (final path in _store.serverList('$family/events'))
          if (read(path)!['actorUid'] == uid) path,
    ];
    final emergencies = [
      for (final family in families)
        for (final path in _store.serverList('$family/emergencies'))
          if (read(path)!['uid'] == uid) path,
    ];
    return _plain({
          'schema': 'nexo-familia/export@1',
          'generatedAt': _clock.now().toUtc(),
          'data': {
            'account': {
              'uid': uid,
              'email': _currentEmail?.call(),
              'createdAt': null,
            },
            'profile': read('users/$uid'),
            'devices': [
              for (final path in _store.serverList('users/$uid/devices'))
                {
                  'platform': read(path)!['platform'],
                  'updatedAt': read(path)!['updatedAt'],
                },
            ],
            'families': [
              for (final path in _store.serverList('users/$uid/memberships'))
                {
                  'familyId': path.split('/').last,
                  'name': read('families/${path.split('/').last}')?['name'],
                  'member': read(
                    'families/${path.split('/').last}/members/$uid',
                  ),
                  'sharingConsent': read(
                    'families/${path.split('/').last}/consents/$uid',
                  ),
                  'lastLocation': read(
                    'families/${path.split('/').last}/locations/$uid',
                  ),
                },
            ],
            'events': [
              for (final path in events)
                {
                  'familyId': familyOf(path),
                  'id': path.split('/').last,
                  ...without(read(path)!, const {
                    'actorUid',
                    'targetUid',
                    'expireAt',
                  }),
                },
            ],
            'emergencies': [
              for (final path in emergencies)
                {
                  'familyId': familyOf(path),
                  'id': path.split('/').last,
                  ...without(read(path)!, const {
                    'uid',
                    'acks',
                    'expireAt',
                    'notifyStartedAt',
                  }),
                  'acknowledgements':
                      (read(path)!['acks'] as Map?)?.length ?? 0,
                },
            ],
          },
        })!
        as Json;
  }

  /// Como JSON: fechas en ISO 8601 (UTC).
  static Object? _plain(Object? value) => switch (value) {
    final DateTime date => date.toUtc().toIso8601String(),
    final Map<Object?, Object?> map => {
      for (final MapEntry(:key, :value) in map.entries) '$key': _plain(value),
    },
    final List<Object?> list => [for (final v in list) _plain(v)],
    _ => value,
  };

  Json _deleteAccount(String uid) => _store.serverTransaction(() {
    for (final path in _store.serverList('users/$uid/memberships')) {
      final familyId = path.split('/').last;
      if (_roleOf(familyId, uid) != null &&
          _store.serverRead('families/$familyId') != null) {
        _leaveFamily(uid, familyId);
      } else {
        // Restos inconsistentes (sin integrante o sin familia): se limpian
        // sin impedir el borrado de la cuenta.
        _store
          ..serverDelete(path)
          ..serverDelete('families/$familyId/members/$uid')
          ..serverDelete('families/$familyId/locations/$uid')
          ..serverDelete('families/$familyId/consents/$uid');
      }
    }
    // Como en las Functions: la limpieza alcanza TODAS las familias,
    // también aquellas de las que ya había salido.
    for (final path in _store.serverList('families')) {
      _scrubFamily(uid, path.split('/').last);
    }
    for (final path in _store.serverList('invitations')) {
      if (_store.serverRead(path)!['createdBy'] == uid) {
        _store.serverDelete(path);
      }
    }
    // Perfil con todas sus subcolecciones y los contadores de frecuencia.
    _store
      ..serverDeleteTree('users/$uid')
      ..serverDelete('rateLimits/$uid');
    return <String, Object?>{};
  });

  /// Como en las Functions: lo que la cuenta eliminada deja en una familia.
  /// Sus check-ins y eventos de zona se borran ya; sus alertas se conservan
  /// sin coordenadas hasta su retención; la auditoría y `createdBy` (familia
  /// y zonas, que suben de versión) se anonimizan.
  void _scrubFamily(String uid, String familyId) {
    final familyPath = 'families/$familyId';
    final family = _store.serverRead(familyPath);
    if (family != null && family['createdBy'] == uid) {
      _store.serverWrite(familyPath, {...family, 'createdBy': deletedUser});
    }
    for (final path in _store.serverList('$familyPath/geofences')) {
      final zone = _store.serverRead(path)!;
      if (zone['createdBy'] == uid) {
        _store.serverWrite(path, {
          ...zone,
          'createdBy': deletedUser,
          'version': ((zone['version'] as num?) ?? 0).toInt() + 1,
        });
      }
    }
    for (final path in _store.serverList('families/$familyId/events')) {
      final event = _store.serverRead(path)!;
      if (event['actorUid'] == uid &&
          (event['type'] == 'checkIn' || event['type'] == 'geofence')) {
        _store.serverDelete(path);
      }
    }
    for (final path in _store.serverList('families/$familyId/emergencies')) {
      final alert = _store.serverRead(path)!;
      if (alert['uid'] == uid) {
        _store.serverWrite(path, {
          for (final MapEntry(:key, :value) in alert.entries)
            if (key != 'lat' && key != 'lng' && key != 'accuracyM') key: value,
        });
      }
    }
    for (final path in _store.serverList('families/$familyId/audit')) {
      final entry = _store.serverRead(path)!;
      if (entry['actorUid'] == uid || entry['targetUid'] == uid) {
        _store.serverWrite(path, {
          ...entry,
          if (entry['actorUid'] == uid) 'actorUid': deletedUser,
          if (entry['targetUid'] == uid) 'targetUid': deletedUser,
        });
      }
    }
  }

  // --- Utilidades -----------------------------------------------------------

  void _writeInitialConsent(String familyId, String uid) {
    _store.serverWrite('families/$familyId/consents/$uid', {
      'state': 'notConfigured',
      'precision': 'exact',
      'updatedAt': serverTimestamp,
    });
  }

  /// Si una invitación aún puede usarse en el instante [now].
  static bool _isUsable(Json invitation, DateTime now) =>
      invitation['status'] == 'active' &&
      (invitation['expiresAt']! as DateTime).isAfter(now) &&
      (invitation['uses']! as int) < (invitation['maxUses']! as int);

  /// Coordenadas opcionales del SOS. Si llegan mal formadas o fuera de rango
  /// se descartan en lugar de rechazar la alerta: un SOS nunca debe fallar
  /// por la ubicación.
  static Json? _sosLocation(Json p) {
    final lat = p['lat'];
    final lng = p['lng'];
    if (lat is! num || lng is! num) return null;
    if (!lat.isFinite || !lng.isFinite || lat.abs() > 90 || lng.abs() > 180) {
      return null;
    }
    final accuracy = p['accuracyM'];
    return {
      'lat': lat.toDouble(),
      'lng': lng.toDouble(),
      if (accuracy is num && accuracy.isFinite && accuracy >= 0)
        'accuracyM': accuracy.toDouble(),
    };
  }

  /// Sin compartir no se guarda nada; con una precisión distinta de
  /// "exacta", rejilla de 0,01° y precisión declarada de al menos 1 km.
  static Json? _shareable(Json? location, Object? state, Object? precision) {
    if (location == null || state != 'sharing') return null;
    if (precision == 'exact') return location;
    double snap(Object? degrees) =>
        ((degrees! as double) * 100).roundToDouble() / 100 + 0.0;
    final accuracy = (location['accuracyM'] as double?) ?? 0;
    return {
      'lat': snap(location['lat']),
      'lng': snap(location['lng']),
      'accuracyM': accuracy < 1000 ? 1000.0 : accuracy,
    };
  }

  String? _roleOf(String familyId, String uid) =>
      _store.serverRead('families/$familyId/members/$uid')?['role'] as String?;

  /// Como en las Functions: sin un nombre de perfil válido, "Integrante".
  String _displayName(String uid) =>
      switch (_store.serverRead('users/$uid')?['displayName']) {
        final String name when name.isNotEmpty => name,
        _ => 'Integrante',
      };

  void _event(String familyId, Json data) {
    final days = data['type'] == 'sos' ? 90 : 30;
    final events = 'families/$familyId/events';
    _store.serverWrite('$events/${_newId(events)}', {
      ...data,
      'createdAt': serverTimestamp,
      'expireAt': _clock.now().add(Duration(days: days)),
    });
  }

  void _audit(String familyId, String action, String actor, {String? target}) {
    if (_store.serverRead('families/$familyId') == null) return;
    final audit = 'families/$familyId/audit';
    _store.serverWrite('$audit/${_newId(audit)}', {
      'action': action,
      'actorUid': actor,
      'targetUid': ?target,
      'createdAt': serverTimestamp,
      'expireAt': _clock.now().add(const Duration(days: 180)),
    });
  }

  /// Ventana deslizante de una hora por usuario y operación. Registra el
  /// intento (fuera de cualquier transacción) o lanza `rate-limited`.
  void _rateLimit(String uid, String key, int maxPerHour) {
    final path = 'rateLimits/$uid';
    final now = _clock.now();
    final data = _store.serverRead(path) ?? {};
    final recent = ((data[key] as List<Object?>?) ?? const [])
        .cast<DateTime>()
        .where((t) => now.difference(t) < _rateWindow)
        .toList();
    if (recent.length >= maxPerHour) {
      throw const _Reject(FailureKind.rateLimited, 'rate-limited');
    }
    _store.serverWrite(path, {
      ...data,
      key: [...recent, now],
    });
  }

  String _newCode() => List.generate(
    _codeLength,
    (_) => _codeAlphabet[_random.nextInt(_codeAlphabet.length)],
  ).join();

  /// ID nuevo en [collection]. Como los IDs automáticos de Firestore, nunca
  /// coincide con un documento existente: con un `Random` con semilla, dos
  /// clientes sobre el mismo almacén generan la misma secuencia.
  String _newId(String collection) {
    String id;
    do {
      id = List.generate(
        20,
        (_) => 'abcdefghijklmnopqrstuvwxyz0123456789'[_random.nextInt(36)],
      ).join();
    } while (_store.serverRead('$collection/$id') != null);
    return id;
  }

  static String _hash(String code) =>
      sha256.convert(utf8.encode(code)).toString();

  /// Texto obligatorio; si falta: `<campo>-required` (en kebab-case).
  static String _requiredString(Json p, String key) {
    final value = p[key];
    if (value is! String || value.isEmpty) {
      throw _Reject(FailureKind.validation, '${_kebab(key)}-required');
    }
    return value;
  }

  /// Identificador que se usa como segmento de ruta: no puede contener `/`
  /// ni ser `.`, `..` o `__…__` (reservados en Firestore).
  static String _id(Json p, String key) {
    final value = _requiredString(p, key);
    if (value.contains('/') ||
        value == '.' ||
        value == '..' ||
        RegExp(r'^__.*__$').hasMatch(value)) {
      throw _Reject(FailureKind.validation, '${_kebab(key)}-invalid');
    }
    return value;
  }

  static String _kebab(String key) =>
      key.replaceAllMapped(RegExp('[A-Z]'), (m) => '-${m[0]!.toLowerCase()}');
}

final class _Reject implements Exception {
  const new(this.kind, this.reason);

  final FailureKind kind;
  final String reason;
}
