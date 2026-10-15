import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nexo_familia/core/di/core_providers.dart';
import 'package:nexo_familia/core/failure.dart';
import 'package:nexo_familia/core/geo/geo_point.dart';
import 'package:nexo_familia/core/result.dart';
import 'package:nexo_familia/design_system/components/map/nx_list_map.dart';
import 'package:nexo_familia/design_system/components/map/nx_map.dart';
import 'package:nexo_familia/design_system/components/nx_banner.dart';
import 'package:nexo_familia/design_system/components/nx_button.dart';
import 'package:nexo_familia/design_system/components/nx_section.dart';
import 'package:nexo_familia/design_system/components/nx_state_views.dart';
import 'package:nexo_familia/design_system/components/nx_status_pill.dart';
import 'package:nexo_familia/design_system/theme/nx_theme.dart';
import 'package:nexo_familia/design_system/tokens/nx_dimens.dart';
import 'package:nexo_familia/features/authentication/presentation/auth_providers.dart';
import 'package:nexo_familia/features/common/presentation/failure_text.dart';
import 'package:nexo_familia/features/common/presentation/routes.dart';
import 'package:nexo_familia/features/common/presentation/sync_status.dart';
import 'package:nexo_familia/features/family/domain/family.dart';
import 'package:nexo_familia/features/family/presentation/family_providers.dart';
import 'package:nexo_familia/features/geofences/domain/geofence.dart';
import 'package:nexo_familia/features/geofences/presentation/geofence_providers.dart';
import 'package:nexo_familia/features/location_sharing/domain/location.dart';
import 'package:nexo_familia/features/location_sharing/presentation/location_permission_sheet.dart';
import 'package:nexo_familia/features/location_sharing/presentation/location_providers.dart';
import 'package:nexo_familia/features/location_sharing/presentation/location_text.dart';
import 'package:nexo_familia/features/location_sharing/presentation/location_view_logic.dart';
import 'package:nexo_familia/l10n/gen/app_localizations.dart';

const EdgeInsets _gutter = EdgeInsets.symmetric(horizontal: NxSpace.gutter);

/// Pestaña Mapa: últimas ubicaciones compartidas de la familia activa, el
/// estado de la propia compartición y las zonas.
///
/// Si no hay proveedor de mapas ([mapBuilderProvider] es `null`) usa la
/// lista accesible ([NxListMap]). Nunca muestra coordenadas ni dice que
/// alguien esté "seguro": solo qué tan reciente es cada ubicación.
class MapScreen extends ConsumerStatefulWidget {
  const new({super.key});

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen> {
  /// Refresca los tiempos relativos ("hace 3 min").
  static const Duration _tickEvery = Duration(seconds: 30);

  Timer? _ticker;
  AppLifecycleListener? _lifecycle;

  /// Hay una actualización en curso (incluida la explicación del permiso):
  /// evita dos envíos por toques repetidos.
  bool _inFlight = false;

  /// Se está obteniendo o enviando la ubicación (lo que ve la persona).
  bool _sending = false;

  /// Resultado del último envío; `null` si aún no hubo ninguno.
  Result<MemberLocation>? _outcome;

  /// Marcador elegido en el mapa (solo con un proveedor de mapas).
  String? _selectedMarkerId;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(_tickEvery, (_) {
      if (mounted) setState(() {});
    });
    // Al volver de los ajustes del sistema el permiso puede haber cambiado.
    _lifecycle = AppLifecycleListener(
      onResume: () => ref.invalidate(deviceLocationPermissionProvider),
    );
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _lifecycle?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final familyId = ref.watch(activeFamilyIdProvider);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.navMap)),
      body: familyId == null
          ? NxMessageView(
              icon: Icons.groups_outlined,
              title: l10n.locationNoFamily,
            )
          : _body(context, l10n, familyId),
    );
  }

  Widget _body(BuildContext context, AppLocalizations l10n, String familyId) {
    final consent = ref.watch(myConsentProvider(familyId));
    // Un resultado anterior deja de ser cierto si se deja de compartir (la
    // ubicación enviada se borró al pausar) o si cambia la familia activa.
    ref
      ..listen(myConsentProvider(familyId), (_, next) {
        if (!(next.value?.isSharing ?? false)) _clearOutcome();
      })
      ..listen(activeFamilyIdProvider, (_, _) => _clearOutcome());
    final family = _familyOf(familyId);
    final staleAfter = ref.watch(appConfigProvider).staleLocationAfter;
    final top = [
      ..._banners(l10n, consent),
      if (consent.value case final mine? when mine.isSharing)
        _shareSection(l10n, familyId, mine, family?.name),
    ];
    return NxPageBody(
      // Cada sección pone su margen lateral: la lista accesible puede ir de
      // borde a borde con texto grande.
      padding: const EdgeInsets.only(top: NxSpace.xs, bottom: NxSpace.xxl),
      children: [
        if (top.isNotEmpty)
          Padding(
            padding: _gutter,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: top,
            ),
          ),
        const SizedBox(height: NxSpace.md),
        _FamilyMap(
          familyId: familyId,
          selectedMarkerId: _selectedMarkerId,
          onMarkerTap: (id) => setState(() => _selectedMarkerId = id),
        ),
        Padding(
          padding: _gutter,
          child: _ZonesSection(
            familyId: familyId,
            canManage: family?.myRole.canManage ?? false,
          ),
        ),
        Padding(
          padding: _gutter,
          child: _Legend(staleAfter: staleAfter),
        ),
      ],
    );
  }

  FamilyGroup? _familyOf(String familyId) => ref
      .watch(myFamiliesProvider)
      .value
      ?.where((f) => f.id == familyId)
      .firstOrNull;

  List<Widget> _banners(
    AppLocalizations l10n,
    AsyncValue<SharingConsent> consent,
  ) {
    final offline = ref.watch(syncStatusProvider).value == SyncStatus.offline;
    final permission = (consent.value?.isSharing ?? false)
        ? ref.watch(deviceLocationPermissionProvider).value
        : null;
    final banners = <Widget>[
      if (offline)
        NxBanner(
          icon: Icons.cloud_off_outlined,
          message: l10n.commonOfflineBanner,
        ),
      if (consent case AsyncError() when !consent.hasValue)
        NxBanner(
          icon: Icons.error_outline,
          tone: NxTone.neutral,
          message: l10n.locationCardError,
        ),
      ...switch (consent.value?.state) {
        SharingState.notConfigured => [
          NxBanner(
            icon: Icons.location_off_outlined,
            tone: NxTone.info,
            message: l10n.locationBannerNotConfigured,
            actionLabel: l10n.locationBannerConfigure,
            onAction: _openPrivacy,
          ),
        ],
        SharingState.paused => [
          NxBanner(
            icon: Icons.pause_circle_outline,
            tone: NxTone.info,
            message: l10n.locationBannerPaused,
            actionLabel: l10n.locationBannerConfigure,
            onAction: _openPrivacy,
          ),
        ],
        SharingState.sharing || null => [
          if (permission == DeviceLocationPermission.serviceDisabled)
            NxBanner(
              icon: Icons.location_disabled_outlined,
              message: l10n.locationBannerServiceDisabled,
              actionLabel: l10n.commonOpenSettings,
              onAction: _openSettings,
            )
          else if (permission == DeviceLocationPermission.denied ||
              permission == DeviceLocationPermission.deniedForever)
            NxBanner(
              icon: Icons.location_disabled_outlined,
              message: l10n.locationBannerPermission,
              actionLabel: l10n.commonOpenSettings,
              onAction: _openSettings,
            ),
        ],
      },
    ];
    return [
      for (final (i, banner) in banners.indexed) ...[
        if (i > 0) const SizedBox(height: NxSpace.xs),
        banner,
      ],
    ];
  }

  Widget _shareSection(
    AppLocalizations l10n,
    String familyId,
    SharingConsent consent,
    String? familyName,
  ) {
    final outcome = _outcome;
    return Padding(
      padding: const EdgeInsets.only(top: NxSpace.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          NxButton(
            label: l10n.locationShareNow,
            icon: Icons.my_location,
            loading: _sending,
            onPressed: () => _shareNow(familyId, consent, familyName),
          ),
          if (outcome != null) ...[
            const SizedBox(height: NxSpace.xs),
            switch (outcome) {
              Ok(:final value) => Semantics(
                liveRegion: true,
                child: NxStatusPill(
                  icon: Icons.check_circle_outline,
                  tone: NxTone.positive,
                  label: value.isApproximate
                      ? l10n.locationShareSentApprox
                      : l10n.locationShareSent,
                ),
              ),
              Err(:final failure) => NxBanner(
                icon: Icons.error_outline,
                message: l10n.locationShareFailed(
                  locationFailureReason(l10n, failure),
                ),
                actionLabel: locationFailureNeedsSettings(failure)
                    ? l10n.commonOpenSettings
                    : l10n.commonRetry,
                onAction: locationFailureNeedsSettings(failure)
                    ? _openSettings
                    : () => _shareNow(familyId, consent, familyName),
              ),
            },
          ],
        ],
      ),
    );
  }

  Future<void> _shareNow(
    String familyId,
    SharingConsent consent,
    String? familyName,
  ) async {
    if (_inFlight) return;
    final uid = ref.read(currentUserProvider).value?.uid;
    if (uid == null) return;
    _inFlight = true;
    setState(() => _outcome = null);
    try {
      final device = ref.read(deviceLocationServiceProvider);
      // Antes del diálogo del sistema, la explicación propia: para qué, quién
      // la ve y que se puede pausar. Sin aceptarla no se pide nada.
      if (await device.permission() == DeviceLocationPermission.notDetermined) {
        if (!mounted) return;
        final accepted = await showLocationPermissionRationale(
          context,
          familyName: familyName,
        );
        if (!accepted || !mounted) return;
        await device.requestWhileInUse();
        if (!mounted) return;
        ref.invalidate(deviceLocationPermissionProvider);
      }
      setState(() => _sending = true);
      final result = await ref.read(shareMyLocationNowProvider)(
        familyId: familyId,
        uid: uid,
        consent: consent,
      );
      if (!mounted) return;
      // "Ubicación enviada" solo con la confirmación del servidor (Ok).
      setState(() => _outcome = result);
      if (result case Err(:final failure)
          when locationFailureNeedsSettings(failure)) {
        ref.invalidate(deviceLocationPermissionProvider);
      }
    } finally {
      _inFlight = false;
      if (mounted) setState(() => _sending = false);
    }
  }

  void _clearOutcome() {
    if (_outcome != null && mounted) setState(() => _outcome = null);
  }

  void _openPrivacy() => context.go(AppRoutes.privacy);

  Future<void> _openSettings() async {
    final opened = await ref
        .read(deviceLocationServiceProvider)
        .openSystemSettings();
    if (opened || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(AppLocalizations.of(context).locationSettingsNotOpened),
      ),
    );
  }
}

/// Mapa (o su lista accesible) con los integrantes que comparten ubicación,
/// seguido de quienes no tienen una ubicación publicada.
class _FamilyMap extends ConsumerWidget {
  const new({
    required this.familyId,
    required this.selectedMarkerId,
    required this.onMarkerTap,
  });

  final String familyId;
  final String? selectedMarkerId;
  final ValueChanged<String> onMarkerTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final builder = ref.watch(mapBuilderProvider);
    final locations = ref.watch(familyLocationsProvider(familyId));
    final members = ref.watch(familyMembersProvider(familyId));
    final myUid = ref.watch(currentUserProvider).value?.uid;
    final now = ref.watch(clockProvider).now();
    final staleAfter = ref.watch(appConfigProvider).staleLocationAfter;

    final loaded = (locations.value, members.value);
    if (loaded case (final locs?, final people?)) {
      final entries = matchFamilyLocations(
        locations: locs,
        members: people,
        myUid: myUid,
      );
      List<NxMapMarker> markers({required bool forList}) => [
        for (final entry in entries.located)
          _marker(
            l10n,
            entry,
            now: now,
            staleAfter: staleAfter,
            forList: forList,
          ),
      ];
      final Widget map;
      if (builder == null) {
        // Con texto grande la lista va de borde a borde: cada píxel de ancho
        // ahorra líneas en sus filas.
        final framed = MediaQuery.textScalerOf(context).scale(1) <= 1.3;
        map = Padding(
          padding: framed ? _gutter : EdgeInsets.zero,
          child: _ListMap(markers: markers(forList: true), framed: framed),
        );
      } else {
        final zones = ref.watch(geofencesProvider(familyId)).value ?? const [];
        map = Container(
          height: _mapHeight(context),
          padding: _gutter,
          child: ClipRRect(
            borderRadius: NxRadius.lgAll,
            child: builder(
              context,
              NxMapData(
                markers: markers(forList: false),
                zones: [for (final zone in zones) _zone(zone)],
                selectedMarkerId: selectedMarkerId,
                onMarkerTap: onMarkerTap,
                initialCenter: _initialCenter(entries, zones),
              ),
            ),
          ),
        );
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          map,
          if (entries.withoutLocation.isNotEmpty)
            Padding(
              padding: _gutter,
              child: _WithoutLocation(
                names: [
                  for (final member in entries.withoutLocation)
                    locationMemberName(l10n, member, isSelf: false),
                ],
              ),
            ),
        ],
      );
    }
    final error = locations.error ?? members.error;
    return Container(
      height: _mapHeight(context),
      padding: _gutter,
      child: NxSurface(
        padding: EdgeInsets.zero,
        child: error == null
            ? NxLoadingView(label: l10n.commonLoading)
            : NxMessageView(
                icon: Icons.error_outline,
                title: failureMessage(
                  l10n,
                  error is Failure ? error : Failure.unexpected('map', error),
                ),
                actionLabel: l10n.commonRetry,
                onAction: () => ref
                  ..invalidate(familyLocationsProvider(familyId))
                  ..invalidate(familyMembersProvider(familyId)),
              ),
      ),
    );
  }

  /// Alto del mapa del proveedor (y de los estados de carga y error).
  static double _mapHeight(BuildContext context) =>
      (MediaQuery.sizeOf(context).height * 0.45).clamp(240, 480);

  /// En la lista, el nombre ya es el título de la fila y el estado su
  /// subtítulo: repetir el nombre solo alargaría cada fila (el lector de
  /// pantalla anuncia ambos). En el mapa del proveedor el marcador necesita
  /// la descripción completa ("Ana. Ubicación actualizada hace 3 min").
  static NxMapMarker _marker(
    AppLocalizations l10n,
    LocatedMember entry, {
    required DateTime now,
    required Duration staleAfter,
    required bool forList,
  }) {
    final status = locationStatusOf(
      entry.location,
      now: now,
      staleAfter: staleAfter,
    );
    final name = locationMemberName(l10n, entry.member, isSelf: entry.isSelf);
    return NxMapMarker(
      id: entry.member.uid,
      label: name,
      point: entry.location.point,
      tone: switch (status.freshness) {
        LocationFreshness.recent => NxMarkerTone.recent,
        LocationFreshness.stale => NxMarkerTone.stale,
      },
      semanticsLabel: forList
          ? locationStatusText(l10n, status, now: now)
          : locationMarkerDescription(
              l10n,
              name: name,
              status: status,
              now: now,
            ),
      isSelf: entry.isSelf,
      isApproximate: status.isApproximate,
    );
  }

  static NxMapZone _zone(Geofence zone) => NxMapZone(
    id: zone.id,
    name: zone.name,
    center: zone.center,
    radiusMeters: zone.radiusMeters,
  );

  static GeoPoint? _initialCenter(
    FamilyMapEntries entries,
    List<Geofence> zones,
  ) => entries.located.firstOrNull?.location.point ?? zones.firstOrNull?.center;
}

/// Lista accesible ([NxListMap]) que ocupa exactamente el alto de su
/// contenido: así la página se desplaza como una sola pieza, sin una lista
/// con desplazamiento propio dentro de otra (incómodo con texto grande).
class _ListMap extends StatelessWidget {
  const new({required this.markers, required this.framed});

  final List<NxMapMarker> markers;

  /// Con marco (superficie con borde) o de borde a borde.
  final bool framed;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final list = NxListMap(
      // Las zonas van en su propia sección, donde se pueden abrir.
      data: NxMapData(markers: markers, zones: const []),
      strings: NxListMapStrings(
        title: l10n.locationListTitle,
        emptyMarkers: l10n.locationListEmpty,
        zonesTitle: l10n.locationZonesTitle,
        radiusLabel: (meters) => l10n.locationZoneRadius(meters.round()),
      ),
      scrollable: false,
    );
    return framed ? NxSurface(padding: EdgeInsets.zero, child: list) : list;
  }
}

class _WithoutLocation extends StatelessWidget {
  const new({required this.names});

  final List<String> names;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final c = context.nx;
    return Padding(
      padding: const EdgeInsets.only(top: NxSpace.md),
      child: MergeSemantics(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.location_off_outlined,
              color: c.inkMuted,
              size: nxScaledIcon(context, NxSize.iconMd),
            ),
            const SizedBox(width: NxSpace.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.locationNotSharedTitle,
                    style: context.text.titleSmall,
                  ),
                  Text(
                    names.join(', '),
                    style: context.text.bodyMedium?.copyWith(color: c.inkMuted),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ZonesSection extends ConsumerWidget {
  const new({required this.familyId, required this.canManage});

  final String familyId;

  /// Solo owner y admin crean zonas (el servidor lo vuelve a validar).
  final bool canManage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l10n = AppLocalizations.of(context);
    final muted = context.text.bodyMedium?.copyWith(color: context.nx.inkMuted);
    final zones = ref.watch(geofencesProvider(familyId));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        NxSectionHeader(
          title: l10n.locationZonesTitle,
          action: canManage
              ? TextButton.icon(
                  onPressed: () => context.push(AppRoutes.newZone),
                  style: TextButton.styleFrom(
                    minimumSize: const Size(
                      NxSize.minTouchTarget,
                      NxSize.minTouchTarget,
                    ),
                    foregroundColor: context.nx.secondary,
                    textStyle: context.text.labelLarge,
                    iconSize: nxScaledIcon(context, NxSize.iconSm),
                  ),
                  icon: const Icon(Icons.add),
                  label: Text(l10n.locationZonesNew),
                )
              : null,
        ),
        ...switch (zones) {
          AsyncValue(value: final list?) when list.isEmpty => [
            Text(l10n.locationZonesEmpty, style: muted),
          ],
          AsyncValue(value: final list?) => [
            for (final zone in list)
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.trip_origin),
                title: Text(zone.name),
                subtitle: Text(
                  l10n.locationZoneRadius(zone.radiusMeters.round()),
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => context.push(AppRoutes.zone(zone.id)),
              ),
          ],
          AsyncError() => [Text(l10n.locationZonesError, style: muted)],
          _ => const <Widget>[],
        },
      ],
    );
  }
}

/// Leyenda de estados: el color nunca va solo, cada estado tiene ícono y
/// texto.
class _Legend extends StatelessWidget {
  const new({required this.staleAfter});

  final Duration staleAfter;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final minutes = staleAfter.inMinutes;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        NxSectionHeader(title: l10n.locationLegendTitle),
        _LegendRow(
          icon: Icons.location_on_outlined,
          text: l10n.locationLegendRecent(minutes),
        ),
        _LegendRow(
          icon: Icons.history_toggle_off,
          text: l10n.locationLegendStale(minutes),
        ),
        _LegendRow(icon: Icons.blur_circular, text: l10n.locationLegendApprox),
        _LegendRow(icon: Icons.info_outline, text: l10n.locationLegendReported),
      ],
    );
  }
}

class _LegendRow extends StatelessWidget {
  const new({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: NxSpace.xxs + 2),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ExcludeSemantics(
          child: Icon(
            icon,
            color: context.nx.inkMuted,
            size: nxScaledIcon(context, NxSize.iconMd),
          ),
        ),
        const SizedBox(width: NxSpace.sm),
        Expanded(child: Text(text, style: context.text.bodyMedium)),
      ],
    ),
  );
}
