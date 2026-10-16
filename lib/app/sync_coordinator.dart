import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:nexo_familia/app/session.dart';
import 'package:nexo_familia/core/failure.dart';
import 'package:nexo_familia/core/logging/safe_logger.dart';
import 'package:nexo_familia/infrastructure/backend_paths.dart';
import 'package:nexo_familia/infrastructure/remote/remote_store.dart';
import 'package:nexo_familia/infrastructure/sync/document_cache.dart';
import 'package:nexo_familia/infrastructure/sync/outbox.dart';
import 'package:nexo_familia/infrastructure/sync/remote_mirror.dart';

/// Colecciones de una familia que se reflejan localmente (ADR-004).
List<MirrorSpec> familyMirrorSpecs(String familyId) => [
  MirrorSpec(BackendPaths.members(familyId)),
  MirrorSpec(BackendPaths.consents(familyId)),
  MirrorSpec(BackendPaths.locations(familyId)),
  MirrorSpec(BackendPaths.geofences(familyId)),
  MirrorSpec(
    BackendPaths.events(familyId),
    query: const RemoteQuery(
      orderBy: 'createdAt',
      descending: true,
      limit: 100,
    ),
  ),
  MirrorSpec(
    BackendPaths.emergencies(familyId),
    query: const RemoteQuery(orderBy: 'createdAt', descending: true, limit: 20),
  ),
];

/// Decide qué se sincroniza y cuándo:
/// * escuchas remotas solo con sesión iniciada **y** la app en primer plano
///   (costo y batería, ver `03-costos.md`);
/// * solo la familia activa. Cambiar de familia detiene la escucha de la
///   anterior pero conserva su copia: al volver a ella sin conexión se ven
///   los últimos datos guardados, no un estado vacío presentado como cierto;
/// * las familias que ya no están entre tus membresías (saliste o te
///   quitaron) se purgan de la copia local y de la bandeja de salida, en
///   cuanto las membresías llegan del servidor;
/// * al cerrar sesión se purga todo.
final class SyncCoordinator with WidgetsBindingObserver {
  new({
    required this._mirror,
    required this._outbox,
    required this._cache,
    required this._outboxStore,
    this._logger,
  });

  final RemoteMirror _mirror;
  final OutboxProcessor _outbox;
  final DocumentCache _cache;
  final OutboxStore _outboxStore;
  final SafeLogger? _logger;

  String? _uid;
  String? _familyId;
  bool _foreground = true;
  final Set<String> _scopes = {};
  Future<void> _pending = Future.value();
  StreamSubscription<void>? _membershipsSub;
  StreamSubscription<void>? _statusSub;

  /// Aplica un nuevo estado de sesión.
  void onSession(SessionState session) {
    final (uid, familyId) = switch (session) {
      SessionReady(:final user, :final familyId) => (user.uid, familyId),
      NeedsFamily(:final user) => (user.uid, null),
      _ => (null, null),
    };
    final signedOut = _uid != null && uid == null;
    if (uid != _uid) _watchMemberships(uid);
    _uid = uid;
    _familyId = familyId;
    _enqueue(() async {
      if (signedOut) await _purge();
      await _apply();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _enqueue(_apply);
  }

  /// Serializa los cambios para que no se solapen arranques y paradas. Un
  /// paso que falla se registra y NO impide los siguientes (p. ej. la purga
  /// al cerrar sesión debe ejecutarse aunque falle un arranque anterior).
  void _enqueue(Future<void> Function() step) {
    _pending = _pending.then((_) async {
      try {
        await step();
      } on Object catch (error) {
        _logger?.error(
          'sync.coordinator_step_failed',
          fields: {'feature': 'sync'},
          failure: error is Failure ? error : null,
        );
      }
    });
  }

  /// Espera a que terminen los cambios en curso (útil en pruebas).
  Future<void> get settled => _pending;

  Future<void> _apply() async {
    final uid = _uid;
    if (uid == null || !_foreground) {
      await _stopAll();
      _outbox.stop();
      return;
    }
    final wanted = <String, List<MirrorSpec>>{
      DocumentCache.userScope: [MirrorSpec(BackendPaths.memberships(uid))],
    };
    final familyId = _familyId;
    if (familyId != null) wanted[familyId] = familyMirrorSpecs(familyId);
    // Un ámbito que deja de interesar (otra familia activa) solo se detiene,
    // esperando las escrituras en curso. Si además ya no es tu familia, lo
    // purga _purgeFormerFamilies.
    for (final scope in _scopes.difference(wanted.keys.toSet()).toList()) {
      await _mirror.stop(scope);
      _scopes.remove(scope);
    }
    for (final MapEntry(key: scope, value: specs) in wanted.entries) {
      _mirror.start(scope, specs);
      _scopes.add(scope);
    }
    await _outbox.start();
  }

  /// Vigila las membresías y el estado del espejo para purgar las familias
  /// de las que ya no eres integrante.
  void _watchMemberships(String? uid) {
    unawaited(_membershipsSub?.cancel());
    unawaited(_statusSub?.cancel());
    _membershipsSub = null;
    _statusSub = null;
    if (uid == null) return;
    void check(Object? _) => _enqueue(_purgeFormerFamilies);
    _membershipsSub = _cache
        .watchCollection(BackendPaths.memberships(uid))
        .listen(check, onError: (_) {});
    _statusSub = _mirror.status.listen(check);
  }

  /// Purga la copia local y la bandeja de salida de las familias que ya no
  /// están entre las membresías. Solo con membresías confirmadas por el
  /// servidor en esta ejecución: sin conexión no se borra nada por error.
  Future<void> _purgeFormerFamilies() async {
    final uid = _uid;
    if (uid == null) return;
    final user = _mirror.statusOf(DocumentCache.userScope);
    if (user.connection != MirrorConnection.live || user.lastSyncedAt == null) {
      return;
    }
    final docs = await _cache
        .watchCollection(BackendPaths.memberships(uid))
        .first;
    final current = {for (final doc in docs) doc.id};
    for (final scope in await _cache.scopes()) {
      if (scope == DocumentCache.userScope || current.contains(scope)) continue;
      await _mirror.stop(scope);
      _scopes.remove(scope);
      await _cache.clearScope(scope);
    }
    for (final entry in await _outboxStore.watch().first) {
      if (!current.contains(entry.familyId)) {
        await _outboxStore.remove(entry.id);
      }
    }
  }

  Future<void> _stopAll() async {
    await _mirror.stopAll();
    _scopes.clear();
  }

  /// Al cerrar sesión: sin copia local de familias ni operaciones pendientes
  /// de la cuenta anterior (no deben enviarse con otra sesión).
  Future<void> _purge() async {
    _outbox.stop();
    await _stopAll();
    await _cache.clearAll();
    for (final entry in await _outboxStore.watch().first) {
      await _outboxStore.remove(entry.id);
    }
  }

  Future<void> dispose() async {
    await _membershipsSub?.cancel();
    await _statusSub?.cancel();
    await _pending;
    await _stopAll();
    _outbox.stop();
  }
}
