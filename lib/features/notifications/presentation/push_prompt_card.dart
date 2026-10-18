import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexo_familia/design_system/components/nx_banner.dart';
import 'package:nexo_familia/design_system/components/nx_status_pill.dart';
import 'package:nexo_familia/design_system/tokens/nx_dimens.dart';
import 'package:nexo_familia/features/notifications/domain/push.dart';
import 'package:nexo_familia/features/notifications/presentation/notifications_providers.dart';
import 'package:nexo_familia/l10n/gen/app_localizations.dart';

/// Pide el permiso de avisos EN CONTEXTO, explicando antes para qué sirve
/// (ADR-005). Sin servicio de avisos o con el permiso concedido no ocupa
/// espacio. Con el permiso denegado lo dice: las alertas SOS no llegarán con
/// la app cerrada.
class PushPromptCard extends ConsumerStatefulWidget {
  const new({super.key});

  @override
  ConsumerState<PushPromptCard> createState() => _PushPromptCardState();
}

class _PushPromptCardState extends ConsumerState<PushPromptCard> {
  bool _asking = false;

  /// Al volver a la app (por ejemplo, desde los ajustes del sistema) se
  /// relee el permiso: si ahora está concedido, se registra el teléfono.
  late final AppLifecycleListener _lifecycle;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onResume: () => unawaited(_recheck()));
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  Future<void> _recheck() async {
    if (!mounted || !ref.read(pushServiceProvider).isAvailable) return;
    ref.invalidate(pushPermissionProvider);
    try {
      if (await ref.read(pushPermissionProvider.future) ==
          PushPermission.granted) {
        await ref.read(pushRegistrationProvider).sync();
      }
    } on Object {
      // Se reintenta en la próxima vuelta a la app o al iniciar sesión.
    }
  }

  void _openSettings() =>
      unawaited(ref.read(pushServiceProvider).openSystemSettings());

  Future<void> _activate() async {
    if (_asking) return;
    setState(() => _asking = true);
    try {
      final granted =
          await ref.read(pushServiceProvider).requestPermission() ==
          PushPermission.granted;
      if (granted) await ref.read(pushRegistrationProvider).sync();
    } on Object {
      // El diálogo del sistema falló: el botón vuelve a estar disponible.
    } finally {
      if (mounted) {
        ref.invalidate(pushPermissionProvider);
        setState(() => _asking = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!ref.watch(pushServiceProvider).isAvailable) {
      return const SizedBox.shrink();
    }
    final l10n = AppLocalizations.of(context);
    final banner = switch (ref.watch(pushPermissionProvider).value) {
      PushPermission.notDetermined => NxBanner(
        icon: Icons.notifications_active_outlined,
        tone: NxTone.info,
        message: l10n.pushPromptMessage,
        actionLabel: l10n.pushPromptAction,
        onAction: _asking ? null : _activate,
      ),
      PushPermission.denied => NxBanner(
        icon: Icons.notifications_off_outlined,
        message: l10n.pushDeniedMessage,
        actionLabel: l10n.commonOpenSettings,
        onAction: _openSettings,
      ),
      PushPermission.granted || null => null,
    };
    if (banner == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(bottom: NxSpace.sm),
      child: banner,
    );
  }
}
