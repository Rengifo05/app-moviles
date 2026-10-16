import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexo_familia/app/router.dart';
import 'package:nexo_familia/app/session.dart';
import 'package:nexo_familia/app/session_providers.dart';
import 'package:nexo_familia/features/notifications/presentation/notifications_providers.dart';
import 'package:nexo_familia/features/settings/presentation/settings_providers.dart';

/// Conecta los avisos con la sesión (ADR-005):
/// * con sesión, registra este dispositivo (si hay permiso);
/// * cuando FCM renueva el token, cambia el registro;
/// * al tocar un aviso SOS, activa esa familia y abre Inicio, donde se ve la
///   alerta con "Lo vi".
final pushBindingProvider = Provider<void>((ref) {
  final service = ref.watch(pushServiceProvider);
  if (!service.isAvailable) return;
  final registration = ref.watch(pushRegistrationProvider);
  ref.listen(sessionProvider, (_, session) {
    switch (session) {
      case SessionReady() || NeedsFamily():
        unawaited(registration.sync());
      case SignedOut():
        registration.forget();
      case SessionLoading() || NeedsOnboarding():
        break;
    }
  }, fireImmediately: true);
  final refreshes = service.tokenRefreshes.listen(
    (token) => unawaited(registration.onTokenRefresh(token)),
  );
  final opens = service.opened.listen((open) async {
    // Si la familia no es de esta cuenta, la sesión la ignora y sigue con la
    // activa (`sessionProvider` solo acepta familias propias).
    try {
      await ref
          .read(preferencesRepositoryProvider)
          .update((p) => p.copyWith(activeFamilyId: () => open.familyId));
    } on Object {
      // Sin poder guardar la preferencia igual se abre Inicio.
    }
    ref.read(routerProvider).go(AppRoutes.home);
  });
  ref.onDispose(() {
    unawaited(refreshes.cancel());
    unawaited(opens.cancel());
  });
});
