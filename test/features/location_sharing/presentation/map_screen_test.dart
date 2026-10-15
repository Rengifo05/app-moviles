import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexo_familia/core/failure.dart';
import 'package:nexo_familia/core/result.dart';
import 'package:nexo_familia/design_system/components/map/nx_list_map.dart';
import 'package:nexo_familia/design_system/components/map/nx_map.dart';
import 'package:nexo_familia/features/common/presentation/sync_status.dart';
import 'package:nexo_familia/features/family/domain/family.dart';
import 'package:nexo_familia/features/location_sharing/domain/location.dart';
import 'package:nexo_familia/features/location_sharing/presentation/location_providers.dart';
import 'package:nexo_familia/features/location_sharing/presentation/map_screen.dart';

import 'location_test_support.dart';

const _nbsp = '\u00A0';

/// Desplaza la página (el primer desplazable) hasta que [finder] se vea.
Future<void> scrollTo(WidgetTester tester, Finder finder, double delta) =>
    tester.scrollUntilVisible(
      finder,
      delta,
      scrollable: find.byType(Scrollable).first,
    );

void main() {
  late FakeLocationRepository repository;
  late FakeDeviceLocation device;

  setUp(() {
    repository = FakeLocationRepository(locations: sampleLocations());
    device = FakeDeviceLocation();
  });

  Future<void> pumpMap(
    WidgetTester tester, {
    List<FamilyMember>? members,
    MemberRole myRole = MemberRole.owner,
    SyncStatus sync = SyncStatus.live,
    String? activeFamilyId = familyId,
    NxMapBuilder? mapBuilder,
  }) async {
    tester.view
      ..physicalSize = const Size(390, 844) * 3
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      locationTestApp(
        overrides: [
          ...locationOverrides(
            repository: repository,
            device: device,
            members: members,
            myRole: myRole,
            sync: sync,
            activeFamilyId: activeFamilyId,
            zones: [zone('z1', 'Casa'), zone('z2', 'Colegio', radius: 400)],
          ),
          if (mapBuilder != null)
            mapBuilderProvider.overrideWithValue(mapBuilder),
        ],
        home: const MapScreen(),
      ),
    );
    await settle(tester);
  }

  group('lista accesible', () {
    testWidgets('muestra el estado de cada ubicación sin coordenadas', (
      tester,
    ) async {
      await pumpMap(tester);

      expect(find.byType(NxListMap), findsOneWidget);
      expect(find.text('Luis'), findsOneWidget);
      expect(
        find.text('Ubicación actualizada hace 3${_nbsp}min'),
        findsOneWidget,
      );
      expect(
        find.text(
          'Sin actualización reciente. Última ubicación hace 3${_nbsp}h',
        ),
        findsOneWidget,
      );
      expect(
        find.text(
          'Ubicación aproximada (±1${_nbsp}km) actualizada '
          'hace 10${_nbsp}min',
        ),
        findsOneWidget,
      );
      // Nunca coordenadas ni promesas de seguridad.
      expect(find.textContaining('4.6'), findsNothing);
      expect(find.textContaining('-74'), findsNothing);
      expect(find.textContaining('segur'), findsNothing);
      expect(find.textContaining('a salvo'), findsNothing);
    });

    testWidgets('el lector de pantalla anuncia nombre y estado', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await pumpMap(tester);
      expect(
        find.bySemanticsLabel(
          RegExp('Luis.*Ubicación actualizada hace 3.min', dotAll: true),
        ),
        findsOneWidget,
      );
      semantics.dispose();
    });

    testWidgets('lista a quienes no tienen ubicación publicada', (
      tester,
    ) async {
      await pumpMap(
        tester,
        members: [...sampleMembers, member('pedro', 'Pedro')],
      );
      expect(find.text('Sin ubicación compartida'), findsOneWidget);
      expect(find.text('Pedro'), findsOneWidget);
    });

    testWidgets('ignora ubicaciones de quien ya no es integrante', (
      tester,
    ) async {
      repository = FakeLocationRepository(
        locations: [
          ...sampleLocations(),
          locationOf('ex', const Duration(minutes: 1)),
        ],
      );
      await pumpMap(tester);
      final list = tester.widget<NxListMap>(find.byType(NxListMap));
      expect(list.data.markers.map((m) => m.id), ['luis', 'marta', 'sofia']);
    });

    testWidgets('mi ubicación aparece primero como "Tú"', (tester) async {
      repository = FakeLocationRepository(
        locations: [
          ...sampleLocations(),
          locationOf(myUid, const Duration(minutes: 1)),
        ],
      );
      await pumpMap(tester);
      final list = tester.widget<NxListMap>(find.byType(NxListMap));
      final first = list.data.markers.first;
      expect(first.id, myUid);
      expect(first.label, 'Tú');
      expect(first.isSelf, isTrue);
    });

    testWidgets('los tiempos se actualizan solos', (tester) async {
      await pumpMap(tester);
      expect(
        find.text('Ubicación actualizada hace 3${_nbsp}min'),
        findsOneWidget,
      );
      // El reloj de la prueba es fijo: solo se comprueba que el temporizador
      // vuelve a construir sin errores.
      await tester.pump(const Duration(seconds: 31));
      expect(tester.takeException(), isNull);
    });
  });

  group('con proveedor de mapas', () {
    testWidgets('recibe marcadores completos, tonos y zonas', (tester) async {
      NxMapData? received;
      await pumpMap(
        tester,
        mapBuilder: (context, data) {
          received = data;
          return const SizedBox.expand();
        },
      );

      expect(find.byType(NxListMap), findsNothing);
      final data = received!;
      final byId = {for (final m in data.markers) m.id: m};
      expect(
        byId['luis']!.semanticsLabel,
        'Luis. Ubicación actualizada hace 3${_nbsp}min',
      );
      expect(byId['luis']!.tone, NxMarkerTone.recent);
      expect(byId['marta']!.tone, NxMarkerTone.stale);
      expect(
        byId['marta']!.semanticsLabel,
        'Marta. Sin actualización reciente. Última ubicación '
        'hace 3${_nbsp}h',
      );
      expect(byId['sofia']!.isApproximate, isTrue);
      expect(byId['sofia']!.semanticsLabel, contains('aproximada'));
      expect(data.zones.map((z) => z.name), ['Casa', 'Colegio']);
      expect(data.initialCenter, isNotNull);
    });
  });

  group('avisos', () {
    testWidgets('sin configurar: invita a configurar y no ofrece enviar', (
      tester,
    ) async {
      repository = FakeLocationRepository(state: SharingState.notConfigured);
      await pumpMap(tester);

      expect(
        find.text('Aún no compartes tu ubicación con esta familia.'),
        findsOneWidget,
      );
      expect(find.text('Actualizar mi ubicación'), findsNothing);

      await tester.tap(find.text('Configurar'));
      await settle(tester);
      expect(find.text('ruta: privacidad'), findsOneWidget);
    });

    testWidgets('en pausa: lo dice y ofrece configurar', (tester) async {
      repository = FakeLocationRepository(state: SharingState.paused);
      await pumpMap(tester);
      expect(
        find.text('Tu ubicación está en pausa para esta familia.'),
        findsOneWidget,
      );
      expect(find.text('Configurar'), findsOneWidget);
      expect(find.text('Actualizar mi ubicación'), findsNothing);
    });

    testWidgets('permiso denegado: abre los ajustes', (tester) async {
      device.current = DeviceLocationPermission.deniedForever;
      await pumpMap(tester);
      expect(
        find.text(
          'La app no tiene permiso para usar la ubicación de este teléfono.',
        ),
        findsOneWidget,
      );
      await tester.tap(find.text('Abrir ajustes'));
      await settle(tester);
      expect(device.settingsOpened, 1);
    });

    testWidgets('si no se pueden abrir los ajustes, lo dice', (tester) async {
      device
        ..current = DeviceLocationPermission.denied
        ..settingsResult = false;
      await pumpMap(tester);
      await tester.tap(find.text('Abrir ajustes'));
      await settle(tester);
      expect(
        find.text('No pudimos abrir los ajustes. Ábrelos desde tu teléfono.'),
        findsOneWidget,
      );
    });

    testWidgets('servicio de ubicación apagado', (tester) async {
      device.current = DeviceLocationPermission.serviceDisabled;
      await pumpMap(tester);
      expect(
        find.text('La ubicación de este teléfono está apagada.'),
        findsOneWidget,
      );
      expect(find.text('Abrir ajustes'), findsOneWidget);
    });

    testWidgets('sin compartir, el permiso del sistema no se menciona', (
      tester,
    ) async {
      repository = FakeLocationRepository(state: SharingState.paused);
      device.current = DeviceLocationPermission.deniedForever;
      await pumpMap(tester);
      expect(find.text('Abrir ajustes'), findsNothing);
    });

    testWidgets('sin conexión', (tester) async {
      await pumpMap(tester, sync: SyncStatus.offline);
      expect(
        find.text('Sin conexión. Mostramos los últimos datos guardados.'),
        findsOneWidget,
      );
    });

    testWidgets('sin familia activa', (tester) async {
      await pumpMap(tester, activeFamilyId: null);
      expect(
        find.text('Crea una familia o únete a una para ver el mapa.'),
        findsOneWidget,
      );
    });
  });

  group('Actualizar mi ubicación', () {
    Finder shareButton() => find.text('Actualizar mi ubicación');

    testWidgets('con permiso, envía y solo entonces dice "Ubicación enviada"', (
      tester,
    ) async {
      repository.publishGate = Completer<void>();
      await pumpMap(tester);

      await tester.tap(shareButton());
      await tester.pump();
      await tester.pump();
      expect(find.text('Ubicación enviada'), findsNothing);

      repository.publishGate!.complete();
      await settle(tester);
      expect(find.text('Ubicación enviada'), findsOneWidget);
      expect(repository.published.single.uid, myUid);
      expect(device.requests, 0);
    });

    testWidgets('al pausar, el "Ubicación enviada" anterior desaparece', (
      tester,
    ) async {
      await pumpMap(tester);
      await tester.tap(shareButton());
      await settle(tester);
      expect(find.text('Ubicación enviada'), findsOneWidget);

      final sharing = repository.consent.value;
      repository.consent.value = sharing.copyWith(state: SharingState.paused);
      await settle(tester);
      repository.consent.value = sharing;
      await settle(tester);

      expect(shareButton(), findsOneWidget);
      expect(find.text('Ubicación enviada'), findsNothing);
    });

    testWidgets('sin decidir: explica antes de pedir el permiso', (
      tester,
    ) async {
      device.current = DeviceLocationPermission.notDetermined;
      await pumpMap(tester);

      await tester.tap(shareButton());
      await settle(tester);
      expect(find.text('Así usamos tu ubicación'), findsOneWidget);
      expect(
        find.text('Solo la ven los integrantes de Familia Rojas.'),
        findsOneWidget,
      );
      expect(
        find.text('Puedes pausarla cuando quieras en Ajustes, Privacidad.'),
        findsOneWidget,
      );
      expect(device.requests, 0);

      await tester.tap(find.text('Continuar'));
      await settle(tester);
      expect(device.requests, 1);
      expect(repository.published, hasLength(1));
      expect(find.text('Ubicación enviada'), findsOneWidget);
    });

    testWidgets('"Ahora no" no pide el permiso ni envía nada', (tester) async {
      device.current = DeviceLocationPermission.notDetermined;
      await pumpMap(tester);

      await tester.tap(shareButton());
      await settle(tester);
      await tester.tap(find.text('Ahora no'));
      await settle(tester);

      expect(device.requests, 0);
      expect(repository.published, isEmpty);
      expect(find.text('Ubicación enviada'), findsNothing);
    });

    testWidgets('si niega el permiso, lo dice con su acción', (tester) async {
      device
        ..current = DeviceLocationPermission.notDetermined
        ..afterRequest = DeviceLocationPermission.denied;
      await pumpMap(tester);

      await tester.tap(shareButton());
      await settle(tester);
      await tester.tap(find.text('Continuar'));
      await settle(tester);

      expect(repository.published, isEmpty);
      expect(
        find.text(
          'No se envió tu ubicación. La app no tiene permiso para usar tu '
          'ubicación.',
        ),
        findsOneWidget,
      );
      expect(find.text('Ubicación enviada'), findsNothing);
      // Acción del resultado y del aviso de permiso.
      expect(find.text('Abrir ajustes'), findsNWidgets(2));
    });

    testWidgets('sin conexión: no se envió, con opción de reintentar', (
      tester,
    ) async {
      repository.publishResult = const Err(networkFailure);
      await pumpMap(tester);

      await tester.tap(shareButton());
      await settle(tester);
      expect(
        find.text(
          'No se envió tu ubicación. No hay conexión. Revisa tu red e '
          'inténtalo de nuevo.',
        ),
        findsOneWidget,
      );
      expect(find.text('Ubicación enviada'), findsNothing);

      repository.publishResult = const Ok(null);
      await tester.tap(find.text('Reintentar'));
      await settle(tester);
      expect(find.text('Ubicación enviada'), findsOneWidget);
      expect(repository.published, hasLength(2));
    });

    testWidgets('sin lectura del GPS: error específico', (tester) async {
      device.fix = const Err(Failure.unavailable('location-unavailable'));
      await pumpMap(tester);
      await tester.tap(shareButton());
      await settle(tester);
      expect(
        find.textContaining('No pudimos obtener tu ubicación.'),
        findsOneWidget,
      );
      expect(repository.published, isEmpty);
    });

    testWidgets('el servidor la rechaza: lo explica', (tester) async {
      repository.publishResult = const Err(Failure.permissionDenied());
      await pumpMap(tester);
      await tester.tap(shareButton());
      await settle(tester);
      expect(find.textContaining('El servidor no la aceptó.'), findsOneWidget);
    });

    testWidgets('con precisión aproximada lo indica al enviar', (tester) async {
      repository = FakeLocationRepository(
        locations: sampleLocations(),
        precision: LocationPrecision.approximate,
      );
      await pumpMap(tester);
      await tester.tap(shareButton());
      await settle(tester);
      expect(find.text('Ubicación aproximada enviada'), findsOneWidget);
      expect(repository.published.single.isApproximate, isTrue);
    });

    testWidgets('dos toques seguidos envían una sola vez', (tester) async {
      repository.publishGate = Completer<void>();
      await pumpMap(tester);
      // El segundo toque llega antes de que el botón se muestre ocupado.
      await tester.tap(shareButton());
      await tester.tap(shareButton(), warnIfMissed: false);
      await tester.pump();
      repository.publishGate!.complete();
      await settle(tester);
      expect(repository.published, hasLength(1));
    });
  });

  group('zonas', () {
    testWidgets('owner o admin pueden crear una zona', (tester) async {
      await pumpMap(tester);
      await scrollTo(tester, find.text('Nueva zona'), 200);
      await tester.tap(find.text('Nueva zona'));
      await settle(tester);
      expect(find.text('ruta: nueva zona'), findsOneWidget);
    });

    testWidgets('un integrante no ve "Nueva zona"', (tester) async {
      await pumpMap(tester, myRole: MemberRole.member);
      await scrollTo(tester, find.text('Casa'), 200);
      expect(find.text('Nueva zona'), findsNothing);
    });

    testWidgets('tocar una zona la abre', (tester) async {
      await pumpMap(tester, myRole: MemberRole.member);
      await scrollTo(tester, find.text('Colegio'), 200);
      expect(find.text('Radio de 400${_nbsp}m'), findsOneWidget);
      await tester.tap(find.text('Colegio'));
      await settle(tester);
      expect(find.text('ruta: zona z2'), findsOneWidget);
    });
  });

  testWidgets('leyenda accesible con el umbral configurado', (tester) async {
    await pumpMap(tester);
    await scrollTo(
      tester,
      find.text(
        'Cada teléfono reporta su propia ubicación, que puede no ser '
        'exacta.',
      ),
      200,
    );
    expect(find.text('Cómo leer el mapa'), findsOneWidget);
    expect(
      find.text('Actualizada: la ubicación tiene 30${_nbsp}min o menos.'),
      findsOneWidget,
    );
  });

  testWidgets('al 200 % no hay desbordes en ningún estado', (tester) async {
    tester.view
      ..physicalSize = const Size(390, 844) * 3
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    device.current = DeviceLocationPermission.deniedForever;
    await tester.pumpWidget(
      locationTestApp(
        overrides: locationOverrides(
          repository: repository,
          device: device,
          sync: SyncStatus.offline,
          members: [...sampleMembers, member('pedro', 'Pedro Pablo')],
          zones: [zone('z1', 'Casa de los abuelos en el campo')],
        ),
        home: const MapScreen(),
        textScale: 2,
      ),
    );
    await settle(tester);
    repository.publishResult = const Err(networkFailure);
    await tester.ensureVisible(find.text('Actualizar mi ubicación'));
    await settle(tester);
    await tester.tap(find.text('Actualizar mi ubicación'));
    await settle(tester);
    await tester.drag(find.byType(Scrollable).first, const Offset(0, -3000));
    await settle(tester);
    expect(tester.takeException(), isNull);
  });
}
