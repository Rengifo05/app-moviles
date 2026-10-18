import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nexo_familia/core/di/core_providers.dart';
import 'package:nexo_familia/core/failure.dart';
import 'package:nexo_familia/core/geo/geo_point.dart';
import 'package:nexo_familia/core/result.dart';
import 'package:nexo_familia/design_system/components/map/nx_map.dart';
import 'package:nexo_familia/design_system/components/nx_banner.dart';
import 'package:nexo_familia/design_system/components/nx_button.dart';
import 'package:nexo_familia/design_system/components/nx_section.dart';
import 'package:nexo_familia/design_system/components/nx_state_views.dart';
import 'package:nexo_familia/design_system/components/nx_status_pill.dart';
import 'package:nexo_familia/design_system/theme/nx_theme.dart';
import 'package:nexo_familia/design_system/tokens/nx_dimens.dart';
import 'package:nexo_familia/features/common/presentation/async_view.dart';
import 'package:nexo_familia/features/common/presentation/relative_time.dart';
import 'package:nexo_familia/features/common/presentation/routes.dart';
import 'package:nexo_familia/features/common/presentation/sync_status.dart';
import 'package:nexo_familia/features/family/domain/family.dart';
import 'package:nexo_familia/features/family/presentation/family_providers.dart';
import 'package:nexo_familia/features/geofences/domain/geofence.dart';
import 'package:nexo_familia/features/geofences/presentation/geofence_editor_logic.dart';
import 'package:nexo_familia/features/geofences/presentation/geofence_providers.dart';
import 'package:nexo_familia/features/geofences/presentation/geofence_text.dart';
import 'package:nexo_familia/features/geofences/presentation/geofence_widgets.dart';
import 'package:nexo_familia/features/location_sharing/presentation/location_providers.dart';
import 'package:nexo_familia/features/service_status/presentation/service_status_providers.dart';
import 'package:nexo_familia/l10n/gen/app_localizations.dart';

/// Crea una zona ([geofenceId] nulo) o edita una existente.
///
/// Solo `owner` y `admin` pueden gestionar zonas (las reglas lo vuelven a
/// validar); el resto de integrantes ve la zona en solo lectura. Nunca se
/// muestran coordenadas, y se dice con claridad que los avisos automáticos
/// de entrada y salida aún no existen (ADR-003).
class GeofenceEditorScreen extends ConsumerWidget {
  const new({super.key, this.geofenceId});

  final String? geofenceId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final familyId = ref.watch(activeFamilyIdProvider);
    final family = familyId == null
        ? const AsyncData<FamilyGroup?>(null)
        : ref.watch(activeFamilyProvider);
    final canManage = family.value?.myRole.canManage ?? false;
    final id = geofenceId;
    final title = id == null
        ? l10n.geofenceEditorNewTitle
        : canManage
        ? l10n.geofenceEditorEditTitle
        : l10n.geofenceEditorViewTitle;

    final Widget body;
    if (familyId == null) {
      body = NxMessageView(
        icon: Icons.groups_outlined,
        title: l10n.geofenceNoFamily,
        actionLabel: l10n.commonBack,
        onAction: () => _close(context),
      );
    } else {
      body = AsyncView<FamilyGroup?>(
        value: family,
        builder: (group) {
          final manager = group?.myRole.canManage ?? false;
          if (id == null) {
            return manager
                ? _GeofenceForm(familyId: familyId, isNew: true, latest: null)
                : NxMessageView(
                    icon: Icons.lock_outline,
                    title: l10n.geofenceManageOnlyTitle,
                    body: l10n.geofenceManageOnlyBody,
                    actionLabel: l10n.commonBack,
                    onAction: () => _close(context),
                  );
          }
          return AsyncView<List<Geofence>>(
            value: ref.watch(geofencesProvider(familyId)),
            onRetry: () => ref.invalidate(geofencesProvider(familyId)),
            builder: (zones) {
              final zone = zones.where((z) => z.id == id).firstOrNull;
              if (!manager) {
                return zone == null
                    ? _NotFound(onBack: () => _close(context))
                    : _GeofenceReadOnly(zone: zone);
              }
              return _GeofenceForm(
                key: ValueKey(id),
                familyId: familyId,
                isNew: false,
                latest: zone,
              );
            },
          );
        },
      );
    }

    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: SafeArea(top: false, child: body),
    );
  }
}

/// Vuelve a la pantalla anterior (o al mapa si se abrió directamente).
void _close(BuildContext context) {
  if (context.canPop()) {
    context.pop();
  } else {
    context.go(AppRoutes.map);
  }
}

class _NotFound extends StatelessWidget {
  const new({required this.onBack});

  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return NxMessageView(
      icon: Icons.wrong_location_outlined,
      title: l10n.geofenceNotFoundTitle,
      body: l10n.geofenceNotFoundBody,
      actionLabel: l10n.commonBack,
      onAction: onBack,
    );
  }
}

enum _Busy { saving, deleting }

class _GeofenceForm extends ConsumerStatefulWidget {
  const new({
    required this.familyId,
    required this.isNew,
    required this.latest,
    super.key,
  });

  final String familyId;
  final bool isNew;

  /// Al editar: la zona tal como está ahora en la caché (`null` si ya no
  /// existe). Puede cambiar mientras se edita si otro integrante la
  /// modifica.
  final Geofence? latest;

  @override
  ConsumerState<_GeofenceForm> createState() => _GeofenceFormState();
}

class _GeofenceFormState extends ConsumerState<_GeofenceForm> {
  final _name = TextEditingController();
  final GlobalKey _topKey = GlobalKey();
  final GlobalKey _nameKey = GlobalKey();
  final GlobalKey _centerKey = GlobalKey();
  final GlobalKey _errorKey = GlobalKey();
  final GlobalKey _saveKey = GlobalKey();

  /// Versión de la zona que se está editando (control de concurrencia).
  Geofence? _base;
  double _radius = GeofenceRules.defaultRadiusMeters;
  ZoneCenter? _center;

  String? _nameError;
  bool _showCenterError = false;
  String? _formError;

  /// El servidor rechazó el cambio por conflicto de versión.
  bool _conflict = false;

  /// Último problema al obtener la ubicación actual (nulo si no hay).
  LocateOutcome? _locateIssue;
  bool _locating = false;
  _Busy? _busy;

  /// Ya se guardó o eliminó y la pantalla se está cerrando: los cambios
  /// que llegan de la caché no deben mostrar avisos.
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    _load(widget.latest);
  }

  @override
  void didUpdateWidget(_GeofenceForm oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Abierta antes de que la caché tuviera la zona: se carga al llegar.
    if (!widget.isNew && _base == null && widget.latest != null) {
      _load(widget.latest);
    }
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _load(Geofence? zone) {
    _base = zone;
    _conflict = false;
    _formError = null;
    _nameError = null;
    _showCenterError = false;
    if (zone == null) return;
    _name.text = zone.name;
    _radius = clampGeofenceRadius(zone.radiusMeters);
    _center = SavedCenter(zone.center);
  }

  /// Lleva [key] a la vista tras el próximo fotograma (errores y avisos que
  /// pueden quedar fuera de la pantalla, sobre todo con texto grande),
  /// hacia arriba o hacia abajo según haga falta.
  ///
  /// La lista se construye de forma perezosa: si [key] está tan arriba que
  /// aún no existe, salta al inicio y lo intenta otra vez. Puede hacer
  /// falta más de un salto: al construir lo que faltaba, la lista corrige
  /// sus posiciones estimadas y el desplazamiento.
  void _reveal(GlobalKey key, {int attempt = 0}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final target = key.currentContext;
      if (target != null && target.mounted) {
        final duration = NxMotion.of(target, NxMotion.medium);
        // Cada política desplaza en un solo sentido y solo si hace falta:
        // como mucho una de las dos actúa.
        for (final policy in const [
          ScrollPositionAlignmentPolicy.keepVisibleAtStart,
          ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
        ]) {
          Scrollable.ensureVisible(
            target,
            duration: duration,
            curve: NxMotion.standard,
            alignmentPolicy: policy,
          );
        }
        return;
      }
      final position = _scrollPosition();
      if (position == null || attempt >= 3) return;
      position.jumpTo(position.minScrollExtent);
      _reveal(key, attempt: attempt + 1);
    });
  }

  /// Posición de desplazamiento de la página, a partir de cualquier
  /// elemento ya construido.
  ScrollPosition? _scrollPosition() {
    for (final key in [_saveKey, _errorKey, _centerKey, _nameKey, _topKey]) {
      final element = key.currentContext;
      if (element != null && element.mounted) {
        return Scrollable.maybeOf(element)?.position;
      }
    }
    return null;
  }

  Future<void> _useMyLocation() async {
    if (_locating) return;
    final locator = ref.read(zoneCenterLocatorProvider);
    setState(() {
      _locating = true;
      _locateIssue = null;
    });
    var outcome = await locator.locate();
    if (!mounted) return;
    if (outcome is LocateNeedsPermission) {
      setState(() => _locating = false);
      if (!await showGeofenceLocationRationale(context)) return;
      if (!mounted) return;
      setState(() => _locating = true);
      outcome = await locator.requestAndLocate();
      if (!mounted) return;
    }
    setState(() {
      _locating = false;
      if (outcome case Located(:final center)) {
        _center = center;
        _showCenterError = false;
      } else {
        _locateIssue = outcome;
      }
    });
  }

  Future<void> _openSettings() async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppLocalizations.of(context);
    final opened = await ref
        .read(zoneCenterLocatorProvider)
        .openSystemSettings();
    if (!opened) {
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.geofenceSettingsNotOpened)),
      );
    }
  }

  void _pickOnMap(GeoPoint point) => setState(() {
    _center = MapPickedCenter(point);
    _showCenterError = false;
    _locateIssue = null;
  });

  Future<void> _save() async {
    if (_busy != null) return;
    final l10n = AppLocalizations.of(context);
    final codes = validateGeofenceDraft(
      name: _name.text,
      radiusMeters: _radius,
      center: _center,
    );
    final nameCode = codes.where((c) => c.startsWith('geofence-name-'));
    setState(() {
      _nameError = nameCode.isEmpty
          ? null
          : geofenceValidationMessage(l10n, nameCode.first);
      _showCenterError = codes.contains(GeofenceEditorCodes.centerRequired);
      _formError = codes.contains(GeofenceCodes.radiusOutOfRange)
          ? geofenceValidationMessage(l10n, GeofenceCodes.radiusOutOfRange)
          : null;
    });
    if (codes.isNotEmpty) {
      _reveal(
        _nameError != null
            ? _nameKey
            : _showCenterError
            ? _centerKey
            : _errorKey,
      );
      return;
    }

    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      _busy = _Busy.saving;
      _conflict = false;
    });
    final result = await ref
        .read(geofenceActionsProvider)
        .save(
          familyId: widget.familyId,
          original: widget.isNew ? null : _base,
          name: _name.text,
          center: _center!.point,
          radiusMeters: _radius,
        );
    if (!mounted) return;
    switch (result) {
      case Ok():
        _closing = true;
        messenger.showSnackBar(SnackBar(content: Text(l10n.geofenceSaved)));
        _close(context);
      case Err(:final failure):
        _showFailure(l10n, failure);
    }
  }

  Future<void> _delete() async {
    final base = _base;
    if (base == null || _busy != null) return;
    final l10n = AppLocalizations.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await confirmGeofenceDelete(
      context,
      widget.latest?.name ?? base.name,
    );
    if (!confirmed || !mounted) return;
    setState(() {
      _busy = _Busy.deleting;
      _formError = null;
    });
    final result = await ref.read(geofenceActionsProvider).delete(base);
    if (!mounted) return;
    switch (result) {
      case Ok():
        _closing = true;
        messenger.showSnackBar(SnackBar(content: Text(l10n.geofenceDeleted)));
        _close(context);
      case Err(:final failure):
        _showFailure(l10n, failure);
    }
  }

  void _showFailure(AppLocalizations l10n, Failure failure) {
    // Solo el conflicto de versión confirmado por el repositorio; otros
    // conflictos (p. ej. una transacción que no se completó) se informan
    // como cambio sin confirmar.
    final isConflict = failure.code == GeofenceCodes.conflict;
    final isName =
        failure.kind == FailureKind.validation &&
        failure.code.startsWith('geofence-name-');
    setState(() {
      _busy = null;
      if (isConflict) {
        _conflict = true;
      } else if (isName) {
        _nameError = geofenceFailureMessage(l10n, failure);
      } else {
        _formError = geofenceFailureMessage(l10n, failure);
      }
    });
    _reveal(
      isConflict
          ? _topKey
          : isName
          ? _nameKey
          : _errorKey,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final base = _base;
    if (!widget.isNew && base == null) {
      return _NotFound(onBack: () => _close(context));
    }
    final latest = widget.latest;
    final offline = ref.watch(syncStatusProvider).value == SyncStatus.offline;
    final mapBuilder = ref.watch(mapBuilderProvider);
    final deletedRemotely = !widget.isNew && latest == null && !_closing;
    final changedRemotely =
        !widget.isNew &&
        !_closing &&
        latest != null &&
        latest.version != base!.version;
    final busy = _busy != null;
    final paused = !ref
        .watch(currentServiceFlagsProvider)
        .geofenceEditingEnabled;
    final canSubmit = !offline && !deletedRemotely && !busy && !paused;

    return NxPageBody(
      children: [
        SizedBox(key: _topKey, height: NxSpace.xs),
        if (paused) ...[
          NxBanner(
            icon: Icons.pause_circle_outline,
            message: l10n.geofenceEditingPausedByService,
          ),
          const SizedBox(height: NxSpace.sm),
        ],
        if (offline) ...[
          NxBanner(
            icon: Icons.cloud_off_outlined,
            message: l10n.geofenceOfflineBanner,
          ),
          const SizedBox(height: NxSpace.sm),
        ],
        if (deletedRemotely) ...[
          NxBanner(
            icon: Icons.wrong_location_outlined,
            message: l10n.geofenceErrorNotFound,
          ),
          const SizedBox(height: NxSpace.sm),
        ] else if (changedRemotely || _conflict) ...[
          NxBanner(
            icon: Icons.sync_problem_outlined,
            message: l10n.geofenceErrorConflict,
            actionLabel: latest == null ? null : l10n.geofenceLoadCurrent,
            onAction: latest == null
                ? null
                : () => setState(() {
                    _load(latest);
                    _locateIssue = null;
                  }),
          ),
          const SizedBox(height: NxSpace.sm),
        ],
        const SizedBox(height: NxSpace.xs),
        TextField(
          key: _nameKey,
          controller: _name,
          enabled: !busy,
          maxLength: GeofenceRules.maxNameLength,
          textCapitalization: TextCapitalization.sentences,
          textInputAction: TextInputAction.done,
          onTapOutside: (_) => FocusScope.of(context).unfocus(),
          decoration: InputDecoration(
            labelText: l10n.geofenceNameLabel,
            hintText: l10n.geofenceNameHint,
            errorText: _nameError,
            errorMaxLines: 3,
          ),
        ),
        const SizedBox(height: NxSpace.md),
        GeofenceRadiusField(
          meters: _radius,
          onChanged: busy ? null : (v) => setState(() => _radius = v),
        ),
        NxSectionHeader(key: _centerKey, title: l10n.geofenceCenterTitle),
        if (mapBuilder != null) ...[
          GeofenceMapBox(builder: mapBuilder, data: _mapData(l10n, base, busy)),
          const SizedBox(height: NxSpace.xs),
          Text(l10n.geofenceMapHint, style: context.text.bodySmall),
        ],
        GeofenceCenterStatus(center: _center, showError: _showCenterError),
        if (_locateIssue case final issue?) ...[
          const SizedBox(height: NxSpace.xs),
          _locateBanner(l10n, issue, hasMap: mapBuilder != null),
        ],
        const SizedBox(height: NxSpace.sm),
        NxButton(
          label: l10n.geofenceUseMyLocation,
          icon: Icons.my_location,
          variant: NxButtonVariant.secondary,
          loading: _locating,
          onPressed: busy ? null : _useMyLocation,
        ),
        if (mapBuilder == null) ...[
          const SizedBox(height: NxSpace.xs),
          GeofenceNote(
            icon: Icons.map_outlined,
            text: l10n.geofenceMapUnavailable,
          ),
        ],
        const SizedBox(height: NxSpace.sm),
        GeofenceNote(
          icon: Icons.groups_outlined,
          text: l10n.geofenceVisibilityNote,
        ),
        GeofenceNote(
          icon: Icons.notifications_off_outlined,
          text: l10n.geofenceAlertsUnavailableNote,
        ),
        // El aviso de arriba ya dice que la zona no existe.
        if (_formError case final error?
            when !(deletedRemotely && error == l10n.geofenceErrorNotFound)) ...[
          const SizedBox(height: NxSpace.sm),
          NxBanner(key: _errorKey, icon: Icons.error_outline, message: error),
        ],
        const SizedBox(height: NxSpace.lg),
        NxButton(
          key: _saveKey,
          label: widget.isNew ? l10n.geofenceSaveNew : l10n.geofenceSaveChanges,
          loading: _busy == _Busy.saving,
          onPressed: canSubmit ? _save : null,
        ),
        if (!widget.isNew) ...[
          const SizedBox(height: NxSpace.sm),
          NxButton(
            label: l10n.geofenceDelete,
            icon: Icons.delete_outline,
            variant: NxButtonVariant.destructive,
            loading: _busy == _Busy.deleting,
            onPressed: canSubmit ? _delete : null,
          ),
        ],
      ],
    );
  }

  NxMapData _mapData(AppLocalizations l10n, Geofence? base, bool busy) {
    final center = _center;
    final name = _name.text.trim();
    return NxMapData(
      markers: const [],
      zones: [
        if (center != null)
          NxMapZone(
            id: base?.id ?? 'draft',
            name: name.isEmpty ? l10n.geofenceEditorNewTitle : name,
            center: center.point,
            radiusMeters: _radius,
          ),
      ],
      onPickPoint: busy ? null : _pickOnMap,
      pickedPoint: center?.point,
      initialCenter: center?.point,
    );
  }

  Widget _locateBanner(
    AppLocalizations l10n,
    LocateOutcome issue, {
    required bool hasMap,
  }) => switch (issue) {
    LocateDeclined() => NxBanner(
      icon: Icons.location_disabled_outlined,
      message: hasMap
          ? l10n.geofenceLocationDeclinedWithMap
          : l10n.geofenceLocationDeclined,
    ),
    LocateBlocked() => NxBanner(
      icon: Icons.location_disabled_outlined,
      message: l10n.geofenceLocationBlocked,
      actionLabel: l10n.commonOpenSettings,
      onAction: _openSettings,
    ),
    LocateServiceOff() => NxBanner(
      icon: Icons.location_off_outlined,
      message: l10n.geofenceLocationServiceOff,
      actionLabel: l10n.commonOpenSettings,
      onAction: _openSettings,
    ),
    LocateUnavailable() || LocateNeedsPermission() || Located() => NxBanner(
      icon: Icons.gps_not_fixed,
      message: l10n.geofenceLocationUnavailable,
      actionLabel: l10n.commonRetry,
      onAction: _useMyLocation,
    ),
  };
}

/// Zona vista por quien no puede gestionarla: sin campos editables.
class _GeofenceReadOnly extends ConsumerWidget {
  const new({required this.zone});

  final Geofence zone;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final now = ref.watch(clockProvider).now();
    final mapBuilder = ref.watch(mapBuilderProvider);
    return NxPageBody(
      children: [
        const SizedBox(height: NxSpace.md),
        Semantics(
          header: true,
          child: Text(zone.name, style: context.text.headlineSmall),
        ),
        const SizedBox(height: NxSpace.xxs),
        Text(
          l10n.geofenceUpdatedAgo(relativeTime(l10n, zone.updatedAt, now)),
          style: context.text.bodyMedium?.copyWith(color: context.nx.inkMuted),
        ),
        const SizedBox(height: NxSpace.md),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: NxStatusPill(
            label: l10n.geofenceRadiusValue(zone.radiusMeters.round()),
            icon: Icons.radio_button_checked,
          ),
        ),
        if (mapBuilder != null) ...[
          const SizedBox(height: NxSpace.md),
          GeofenceMapBox(
            builder: mapBuilder,
            data: NxMapData(
              markers: const [],
              zones: [
                NxMapZone(
                  id: zone.id,
                  name: zone.name,
                  center: zone.center,
                  radiusMeters: zone.radiusMeters,
                ),
              ],
              initialCenter: zone.center,
            ),
          ),
        ],
        const SizedBox(height: NxSpace.lg),
        GeofenceNote(icon: Icons.lock_outline, text: l10n.geofenceReadOnlyNote),
        if (mapBuilder == null)
          GeofenceNote(
            icon: Icons.map_outlined,
            text: l10n.geofenceMapUnavailableReadOnly,
          ),
        GeofenceNote(
          icon: Icons.groups_outlined,
          text: l10n.geofenceVisibilityNote,
        ),
        GeofenceNote(
          icon: Icons.notifications_off_outlined,
          text: l10n.geofenceAlertsUnavailableNote,
        ),
      ],
    );
  }
}
