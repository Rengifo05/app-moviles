import 'package:nexo_familia/core/failure.dart';
import 'package:nexo_familia/core/geo/geo_point.dart';
import 'package:nexo_familia/core/result.dart';
import 'package:nexo_familia/features/location_sharing/domain/location.dart';
import 'package:nexo_familia/infrastructure/backend_paths.dart';
import 'package:nexo_familia/infrastructure/remote/remote_store.dart';
import 'package:nexo_familia/infrastructure/remote_json.dart';
import 'package:nexo_familia/infrastructure/sync/document_cache.dart';

/// Consentimiento y última ubicación de cada integrante.
///
/// Lee de la caché local (reflejada por `RemoteMirror`) y escribe directo
/// en el almacén remoto con lotes atómicos; las reglas de Firestore validan
/// la autorización (contrato: `docs/architecture/05-api-backend.md`).
///
/// Nunca registra coordenadas.
final class LocationRepositoryImpl implements LocationRepository {
  new({required this._remote, required this._cache, required this._currentUid});

  final RemoteStore _remote;
  final DocumentCache _cache;
  final String? Function() _currentUid;

  /// Mayor `accuracyM` aceptado: las reglas exigen `0 <= accuracyM < 100000`.
  static const double _maxAccuracyMeters = 99999;

  /// La precisión declarada de una ubicación aproximada no puede ser mejor
  /// que su redondeo (≈ 1 km).
  static const double _approximateAccuracyMeters = 1000;

  @override
  Stream<List<MemberLocation>> watchFamilyLocations(String familyId) => _cache
      .watchCollection(BackendPaths.locations(familyId))
      .map(
        (docs) =>
            docs.map((d) => _location(d.id, d.data)).nonNulls.toList()
              ..sort((a, b) => a.uid.compareTo(b.uid)),
      );

  @override
  Stream<SharingConsent> watchMyConsent(String familyId) {
    final uid = _currentUid();
    if (uid == null) return Stream.error(const Failure.unauthenticated());
    return _cache
        .watchDoc(BackendPaths.consents(familyId), uid)
        .map(
          (doc) => doc == null
              // Sin documento equivale a no haber decidido: no se comparte.
              ? SharingConsent.initial(familyId: familyId, uid: uid)
              : _consent(familyId, uid, doc.data),
        );
  }

  @override
  Future<VoidResult> updateConsent(SharingConsent consent) async {
    final uid = _currentUid();
    if (uid == null) return const Err(Failure.unauthenticated());
    // Nadie puede cambiar la decisión de otra persona (amenaza 9).
    if (consent.uid != uid) {
      return const Err(Failure.permissionDenied('not-own-consent'));
    }
    final familyId = consent.familyId;
    return await _remote.commit([
      RemoteWrite.merge(BackendPaths.consent(familyId, uid), {
        'state': _stateValue(consent.state),
        'precision': _precisionValue(consent.precision),
        'updatedAt': serverTimestamp,
      }),
      // Dejar de compartir borra la ubicación publicada en la misma
      // operación (amenaza 5): o se aplican las dos escrituras o ninguna.
      if (!consent.isSharing)
        RemoteWrite.remove(BackendPaths.location(familyId, uid)),
    ]);
  }

  @override
  Future<VoidResult> publishMyLocation(
    String familyId,
    MemberLocation location,
  ) async {
    final uid = _currentUid();
    if (uid == null) return const Err(Failure.unauthenticated());
    if (location.uid != uid) {
      return const Err(Failure.permissionDenied('not-own-location'));
    }
    // Defensa en profundidad: aunque el caso de uso ya redondeó, una
    // ubicación aproximada nunca sale del dispositivo con más detalle.
    // `approximate()` es canónico, así que repetirlo no cambia nada.
    final point = location.isApproximate
        ? location.point.approximate()
        : location.point;
    return await _remote.commit([
      RemoteWrite.put(BackendPaths.location(familyId, uid), {
        'lat': point.latitude,
        'lng': point.longitude,
        'accuracyM': _accuracyFor(location),
        'capturedAt': location.capturedAt.toUtc(),
        'receivedAt': serverTimestamp,
        'approximate': location.isApproximate,
      }),
    ]);
  }

  /// Precisión dentro del rango que aceptan las reglas (de 0 a menos de
  /// 100 000 m).
  static double _accuracyFor(MemberLocation location) {
    final raw = location.accuracyMeters;
    final accuracy = raw.isFinite && raw >= 0
        ? (raw > _maxAccuracyMeters ? _maxAccuracyMeters : raw)
        : _maxAccuracyMeters;
    return location.isApproximate && accuracy < _approximateAccuracyMeters
        ? _approximateAccuracyMeters
        : accuracy;
  }

  /// `null` si el documento no cumple el contrato (coordenadas fuera de
  /// rango, campos ausentes o de otro tipo): se ignora en lugar de mostrar
  /// una ubicación inventada.
  static MemberLocation? _location(String uid, Json data) {
    final lat = RemoteJson.number(data['lat']);
    final lng = RemoteJson.number(data['lng']);
    final accuracy = RemoteJson.number(data['accuracyM']);
    final capturedAt = RemoteJson.date(data['capturedAt']);
    if (lat == null || lng == null || accuracy == null || capturedAt == null) {
      return null;
    }
    if (accuracy < 0) return null;
    final point = GeoPoint.tryCreate(lat, lng);
    if (point == null) return null;
    return MemberLocation(
      uid: uid,
      point: point,
      accuracyMeters: accuracy,
      capturedAt: capturedAt,
      receivedAt: RemoteJson.date(data['receivedAt']),
      isApproximate: data['approximate'] == true,
    );
  }

  static SharingConsent _consent(String familyId, String uid, Json data) =>
      SharingConsent(
        familyId: familyId,
        uid: uid,
        // Un estado desconocido se trata como "no decidido": nunca como
        // compartir.
        state: switch (data['state']) {
          'sharing' => SharingState.sharing,
          'paused' => SharingState.paused,
          _ => SharingState.notConfigured,
        },
        // Una precisión desconocida se trata como la que menos revela.
        precision: switch (data['precision']) {
          'exact' => LocationPrecision.exact,
          _ => LocationPrecision.approximate,
        },
        updatedAt: RemoteJson.date(data['updatedAt']),
      );

  static String _stateValue(SharingState state) => switch (state) {
    SharingState.notConfigured => 'notConfigured',
    SharingState.sharing => 'sharing',
    SharingState.paused => 'paused',
  };

  static String _precisionValue(LocationPrecision precision) =>
      switch (precision) {
        LocationPrecision.exact => 'exact',
        LocationPrecision.approximate => 'approximate',
      };
}
