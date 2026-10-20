import 'package:nexo_familia/core/clock.dart';
import 'package:nexo_familia/core/failure.dart';
import 'package:nexo_familia/core/geo/geo_point.dart';
import 'package:nexo_familia/core/id_generator.dart';
import 'package:nexo_familia/core/result.dart';
import 'package:nexo_familia/features/geofences/domain/geofence.dart';
import 'package:nexo_familia/infrastructure/backend_paths.dart';
import 'package:nexo_familia/infrastructure/remote/remote_store.dart';
import 'package:nexo_familia/infrastructure/remote_json.dart';
import 'package:nexo_familia/infrastructure/sync/document_cache.dart';

/// Códigos de fallo propios de las zonas (la interfaz los traduce).
abstract final class GeofenceFailureCodes {
  /// La familia ya tiene `GeofenceRules.maxPerFamily` zonas.
  static const limit = 'geofence-limit';

  /// Otro integrante cambió la zona desde que se abrió para editarla.
  static const conflict = 'geofence-conflict';

  /// La zona ya no existe (otro integrante la eliminó).
  static const notFound = 'geofence-not-found';
}

/// Datos de un intento de creación; si se repite igual, es un reintento.
typedef _CreateAttempt = ({
  String familyId,
  String uid,
  String name,
  GeoPoint center,
  double radiusMeters,
});

/// Zonas de una familia (`families/{f}/geofences/{id}`).
///
/// Lee de la caché local (reflejada por `RemoteMirror`). Crea con la
/// Function `createGeofence`, que aplica el máximo de zonas por familia (las
/// reglas no pueden contar documentos); edita y elimina directo en el
/// almacén remoto: las reglas exigen ser `owner` o `admin`, un nombre y un
/// radio válidos, la versión anterior + 1 y conservar `createdBy` (contrato:
/// `docs/architecture/05-api-backend.md`).
///
/// No usa la bandeja de salida: la edición necesita la respuesta del
/// servidor para detectar conflictos de versión y permisos, y la interfaz
/// solo confirma después de un `Ok`. Sin conexión `commit` falla rápido
/// (fallo transitorio) y no se sabe si el servidor alcanzó a aplicarlo, así
/// que los reintentos son idempotentes:
/// * crear: el mismo intento reutiliza el id, y `createGeofence` devuelve la
///   zona existente sin contarla dos veces;
/// * editar: si la zona ya tiene exactamente el contenido y la versión que
///   se iban a escribir, el cambio ya se aplicó y se da por bueno;
/// * eliminar: borrar algo que ya no existe no cambia nada.
///
/// Nunca registra coordenadas.
final class GeofenceRepositoryImpl implements GeofenceRepository {
  new({
    required this._remote,
    required this._functions,
    required this._cache,
    required this._currentUid,
    required this._clock,
    required this._ids,
  });

  final RemoteStore _remote;
  final FunctionsClient _functions;
  final DocumentCache _cache;
  final String? Function() _currentUid;
  final Clock _clock;
  final IdGenerator _ids;

  /// Último intento de creación sin confirmar (fallo transitorio).
  ({_CreateAttempt attempt, String id})? _unconfirmedCreate;

  @override
  Stream<List<Geofence>> watchGeofences(String familyId) => _cache
      .watchCollection(BackendPaths.geofences(familyId))
      .map(
        (docs) =>
            docs.map((d) => _geofence(familyId, d.id, d.data)).nonNulls.toList()
              ..sort(_byName),
      );

  @override
  Future<Result<Geofence>> create({
    required String familyId,
    required String name,
    required GeoPoint center,
    required double radiusMeters,
  }) async {
    final errors = GeofenceRules.validate(
      name: name,
      radiusMeters: radiusMeters,
    );
    if (errors.isNotEmpty) return Err(Failure.validation(errors.first));
    final uid = _currentUid();
    if (uid == null) return const Err(Failure.unauthenticated());
    final trimmed = name.trim();
    final attempt = (
      familyId: familyId,
      uid: uid,
      name: trimmed,
      center: center,
      radiusMeters: radiusMeters,
    );
    final id = switch (_unconfirmedCreate) {
      (attempt: final previous, :final id) when previous == attempt => id,
      _ => _ids.newId(),
    };
    // El servidor aplica el límite; comprobarlo antes con lo ya sincronizado
    // da la respuesta sin esperar a la red (sin contar la propia zona si un
    // intento anterior sí llegó al servidor).
    final existing = await _cache
        .watchCollection(BackendPaths.geofences(familyId))
        .first;
    if (existing.where((d) => d.id != id).length >=
        GeofenceRules.maxPerFamily) {
      return const Err(Failure.validation(GeofenceFailureCodes.limit));
    }
    final geofence = Geofence(
      id: id,
      familyId: familyId,
      name: trimmed,
      center: center,
      radiusMeters: radiusMeters,
      createdBy: uid,
      version: 1,
      updatedAt: _clock.now(),
    );
    final written = switch (await _functions.call(
      BackendFunctions.createGeofence,
      {
        'familyId': familyId,
        'geofenceId': id,
        'name': trimmed,
        'lat': center.latitude,
        'lng': center.longitude,
        'radiusM': radiusMeters,
      },
    )) {
      Ok() => const Ok<void>(null),
      Err(failure: Failure(code: 'too-many-geofences')) => const Err<void>(
        Failure.validation(GeofenceFailureCodes.limit),
      ),
      Err(:final failure) => Err<void>(failure),
    };
    _unconfirmedCreate = switch (written) {
      Err(:final failure) when failure.isTransient => (
        attempt: attempt,
        id: id,
      ),
      _ => null,
    };
    return written.map((_) => geofence);
  }

  @override
  Future<Result<Geofence>> update(Geofence updated) async {
    final errors = GeofenceRules.validate(
      name: updated.name,
      radiusMeters: updated.radiusMeters,
    );
    if (errors.isNotEmpty) return Err(Failure.validation(errors.first));
    if (_currentUid() == null) return const Err(Failure.unauthenticated());
    final cached = await _cache
        .watchDoc(BackendPaths.geofences(updated.familyId), updated.id)
        .first;
    if (cached == null) {
      return const Err(Failure.notFound(GeofenceFailureCodes.notFound));
    }
    final next = Geofence(
      id: updated.id,
      familyId: updated.familyId,
      name: updated.name.trim(),
      center: updated.center,
      radiusMeters: updated.radiusMeters,
      // Las reglas exigen conservar el autor original.
      createdBy:
          RemoteJson.string(cached.data['createdBy']) ?? updated.createdBy,
      version: updated.version + 1,
      updatedAt: _clock.now(),
    );
    if (RemoteJson.integer(cached.data['version']) != updated.version) {
      // Reintento de un cambio que sí llegó al servidor: ya está aplicado.
      return _isApplied(cached.data, next)
          ? Ok(next)
          : const Err(Failure.conflict(GeofenceFailureCodes.conflict));
    }
    final written = await _remote.commit([
      RemoteWrite.put(
        BackendPaths.geofence(next.familyId, next.id),
        _document(next),
      ),
    ]);
    return switch (written) {
      Ok() => Ok(next),
      Err(:final failure) => await _explainRejectedUpdate(next, failure),
    };
  }

  @override
  Future<VoidResult> delete(Geofence geofence) => _remote.commit([
    RemoteWrite.remove(BackendPaths.geofence(geofence.familyId, geofence.id)),
  ]);

  /// Si la caché estaba desactualizada, las reglas rechazan la escritura
  /// con `permission-denied` (la versión no es la anterior + 1, o la zona
  /// ya no existe y una "actualización" sería una creación con versión
  /// distinta de 1); una transacción con contención termina en `conflict`.
  /// Se consulta el servidor para decir la causa real en lugar de "no
  /// tienes permiso".
  Future<Result<Geofence>> _explainRejectedUpdate(
    Geofence next,
    Failure failure,
  ) async {
    if (failure.kind != FailureKind.permissionDenied &&
        failure.kind != FailureKind.conflict) {
      return Err(failure);
    }
    final current = await _remote.getDoc(
      BackendPaths.geofence(next.familyId, next.id),
    );
    return switch (current) {
      Ok(value: null) => const Err(
        Failure.notFound(GeofenceFailureCodes.notFound),
      ),
      Ok(value: final RemoteDoc doc) when _isApplied(doc.data, next) => Ok(
        next,
      ),
      Ok(value: final RemoteDoc doc)
          when RemoteJson.integer(doc.data['version']) != next.version - 1 =>
        const Err(Failure.conflict(GeofenceFailureCodes.conflict)),
      _ => Err(failure),
    };
  }

  /// El documento ya tiene la versión y el contenido de [next].
  static bool _isApplied(Json data, Geofence next) =>
      RemoteJson.integer(data['version']) == next.version &&
      RemoteJson.string(data['name']) == next.name &&
      RemoteJson.number(data['lat']) == next.center.latitude &&
      RemoteJson.number(data['lng']) == next.center.longitude &&
      RemoteJson.number(data['radiusM']) == next.radiusMeters;

  static Json _document(Geofence g) => {
    'name': g.name,
    'lat': g.center.latitude,
    'lng': g.center.longitude,
    'radiusM': g.radiusMeters,
    'createdBy': g.createdBy,
    'version': g.version,
    'updatedAt': serverTimestamp,
  };

  /// `null` si el documento no cumple el contrato: se ignora en lugar de
  /// dibujar una zona inventada.
  Geofence? _geofence(String familyId, String id, Json data) {
    final name = RemoteJson.string(data['name']);
    final lat = RemoteJson.number(data['lat']);
    final lng = RemoteJson.number(data['lng']);
    final radius = RemoteJson.number(data['radiusM']);
    final version = RemoteJson.integer(data['version']);
    if (name == null ||
        lat == null ||
        lng == null ||
        radius == null ||
        version == null) {
      return null;
    }
    final center = GeoPoint.tryCreate(lat, lng);
    if (center == null) return null;
    return Geofence(
      id: id,
      familyId: familyId,
      name: name,
      center: center,
      radiusMeters: radius,
      createdBy: RemoteJson.string(data['createdBy']) ?? '',
      version: version,
      // Mientras el servidor no fija la hora (escritura local pendiente),
      // la mejor estimación es "ahora".
      updatedAt: RemoteJson.date(data['updatedAt']) ?? _clock.now(),
    );
  }

  static int _byName(Geofence a, Geofence b) {
    final byName = a.name.toLowerCase().compareTo(b.name.toLowerCase());
    return byName != 0 ? byName : a.id.compareTo(b.id);
  }
}
