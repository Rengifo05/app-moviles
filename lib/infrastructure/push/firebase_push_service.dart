import 'dart:async';

import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:nexo_familia/features/notifications/domain/push.dart';
import 'package:permission_handler/permission_handler.dart' as ph;

/// [PushService] con Firebase Cloud Messaging (ADR-005).
///
/// No muestra nada por su cuenta: el aviso lo pinta el sistema con el texto
/// genérico que envía `raiseSos` (sin nombres ni ubicación).
final class FirebasePushService implements PushService {
  new(this._messaging);

  final FirebaseMessaging _messaging;

  @override
  bool get isAvailable => true;

  @override
  Future<PushPermission> permission() async =>
      _map((await _messaging.getNotificationSettings()).authorizationStatus);

  @override
  Future<PushPermission> requestPermission() async =>
      _map((await _messaging.requestPermission()).authorizationStatus);

  @override
  Future<String?> token() async {
    try {
      return await _messaging.getToken();
    } on Object {
      // Sin red o sin servicios de Google: se reintenta en el próximo
      // arranque o cuando FCM avise de un token nuevo.
      return null;
    }
  }

  @override
  Future<bool> openSystemSettings() async {
    try {
      return await ph.openAppSettings();
    } on Object {
      return false;
    }
  }

  @override
  Future<void> deleteToken() async {
    try {
      await _messaging.deleteToken();
    } on Object {
      // Sin red: queda el borrado del registro, si se pudo hacer.
    }
  }

  @override
  Stream<String> get tokenRefreshes => _messaging.onTokenRefresh;

  @override
  Stream<PushOpen> get opened async* {
    final initial = await _messaging.getInitialMessage();
    final first = initial == null ? null : sosOpenOf(initial.data);
    if (first != null) yield first;
    await for (final message in FirebaseMessaging.onMessageOpenedApp) {
      if (sosOpenOf(message.data) case final open?) yield open;
    }
  }

  static PushPermission _map(AuthorizationStatus status) => switch (status) {
    AuthorizationStatus.authorized ||
    AuthorizationStatus.provisional => PushPermission.granted,
    AuthorizationStatus.denied ||
    AuthorizationStatus.deniedPermanently => PushPermission.denied,
    AuthorizationStatus.notDetermined => PushPermission.notDetermined,
  };
}

/// Datos del aviso SOS (`{type: sos, familyId, alertId}`) → alerta a abrir.
PushOpen? sosOpenOf(Map<String, dynamic> data) {
  final familyId = data['familyId'];
  final alertId = data['alertId'];
  if (data['type'] != 'sos' || familyId is! String || alertId is! String) {
    return null;
  }
  if (familyId.isEmpty || alertId.isEmpty) return null;
  return PushOpen(familyId: familyId, alertId: alertId);
}
