import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexo_familia/core/failure.dart';
import 'package:nexo_familia/core/result.dart';
import 'package:nexo_familia/features/common/presentation/routes.dart';
import 'package:nexo_familia/features/common/presentation/sync_status.dart';
import 'package:nexo_familia/features/family/domain/family.dart';
import 'package:nexo_familia/features/location_sharing/domain/location.dart';
import 'package:nexo_familia/features/service_status/domain/service_status.dart';

import 'geofence_test_support.dart';

Finder _button(String label) => find.widgetWithText(TextButton, label);

/// La lista se construye de forma perezosa: se desplaza hasta el botón
/// antes de leerlo.
Future<bool> _enabled(WidgetTester tester, String label) async {
  await tester.scrollUntilVisible(
    _button(label),
    200,
    scrollable: find.byType(Scrollable).first,
  );
  return tester.widget<TextButton>(_button(label)).onPressed != null;
}

Future<void> _scrollToTop(WidgetTester tester) async {
  await tester.drag(find.byType(Scrollable).first, const Offset(0, 4000));
  await pumpFrames(tester);
}

Future<void> _enterName(WidgetTester tester, String name) async {
  await _scrollToTop(tester);
  await tester.enterText(find.byType(TextField), name);
  await pumpFrames(tester, frames: 3);
}

Future<void> _useMyLocation(WidgetTester tester) =>
    scrollAndTap(tester, _button('Usar mi ubicación actual'));

Future<void> _save(WidgetTester tester, {String label = 'Guardar zona'}) =>
    scrollAndTap(tester, _button(label));

void main() {
  final l10n = esL10n;

  group('nueva zona', () {
    testWidgets(
      'sin mapa: centro con la ubicación actual, guardar y volver al mapa',
      (tester) async {
        final env = GeofenceTestEnv();
        await pumpGeofenceApp(tester, env);

        expect(find.text('Nueva zona'), findsOneWidget);
        expect(find.text(l10n.geofenceMapUnavailable), findsOneWidget);
        expect(find.text('Aún no has elegido el centro.'), findsOneWidget);
        expect(find.text('Radio: 200 m'), findsOneWidget);
        expect(find.text(l10n.geofenceVisibilityNote), findsOneWidget);
        expect(
          find.text(
            'Los avisos automáticos de entrada y salida aún no están '
            'disponibles en esta versión.',
          ),
          findsOneWidget,
        );
        expect(find.byKey(const Key('fake-map-pick')), findsNothing);

        await _useMyLocation(tester);
        expect(find.text('Centro elegido · precisión ±12 m'), findsOneWidget);
        // Nunca se muestran coordenadas.
        expect(find.textContaining('-40'), findsNothing);
        expect(find.textContaining('-30'), findsNothing);

        await _enterName(tester, '  Colegio  ');
        await _save(tester);

        final call = env.repository.createCalls.single;
        expect(call.familyId, familyId);
        expect(call.name, 'Colegio');
        expect(call.radiusMeters, 200);
        expect(call.center, syntheticCenter);
        expect(find.text('stub:${AppRoutes.map}'), findsOneWidget);
        expect(find.text('Zona guardada'), findsOneWidget);
      },
    );

    testWidgets('valida nombre y centro antes de guardar', (tester) async {
      final env = GeofenceTestEnv();
      await pumpGeofenceApp(tester, env);

      await _save(tester);
      expect(find.text('Escribe un nombre para la zona.'), findsOneWidget);
      expect(
        find.text('Elige el centro de la zona para poder guardarla.'),
        findsOneWidget,
      );
      expect(env.repository.createCalls, isEmpty);

      await _enterName(tester, 'Casa');
      await _useMyLocation(tester);
      expect(
        find.text('Elige el centro de la zona para poder guardarla.'),
        findsNothing,
      );
    });

    testWidgets('el radio se mueve de 50 en 50 y se anuncia', (tester) async {
      final env = GeofenceTestEnv();
      await pumpGeofenceApp(tester, env);
      final handle = tester.ensureSemantics();

      final slider = find.byType(Slider);
      expect(
        find.semantics.byValue('Radio: 200 m').evaluate().single,
        isSemantics(
          value: 'Radio: 200 m',
          increasedValue: 'Radio: 250 m',
          decreasedValue: 'Radio: 150 m',
          isSlider: true,
          isEnabled: true,
          hasIncreaseAction: true,
          hasDecreaseAction: true,
        ),
      );
      // La pista arranca en 100 m; el centro equivale a 1050 m (paso 50).
      await tester.tap(slider);
      await pumpFrames(tester);
      expect(find.text('Radio: 1050 m'), findsOneWidget);

      await _enterName(tester, 'Casa');
      await _useMyLocation(tester);
      await _save(tester);
      expect(env.repository.createCalls.single.radiusMeters, 1050);
      handle.dispose();
    });

    testWidgets('un integrante sin rol de gestión no puede crear zonas', (
      tester,
    ) async {
      await pumpGeofenceApp(tester, GeofenceTestEnv(role: MemberRole.member));
      expect(find.text(l10n.geofenceManageOnlyTitle), findsOneWidget);
      expect(find.byType(TextField), findsNothing);

      await tester.tap(_button('Atrás'));
      await pumpFrames(tester);
      expect(find.text('stub:${AppRoutes.map}'), findsOneWidget);
    });

    testWidgets('sin familia activa lo explica', (tester) async {
      await pumpGeofenceApp(tester, GeofenceTestEnv(activeFamilyId: null));
      expect(find.text(l10n.geofenceNoFamily), findsOneWidget);
    });

    testWidgets('límite de zonas', (tester) async {
      final env = GeofenceTestEnv();
      env.repository.createResult = const Err(
        Failure.validation('geofence-limit'),
      );
      await pumpGeofenceApp(tester, env);
      await _enterName(tester, 'Casa');
      await _useMyLocation(tester);
      await _save(tester);

      expect(find.text(l10n.geofenceErrorLimit(10)), findsOneWidget);
      expect(find.text('stub:${AppRoutes.map}'), findsNothing);
    });

    testWidgets('el servidor rechaza a quien no gestiona la familia', (
      tester,
    ) async {
      final env = GeofenceTestEnv();
      env.repository.createResult = const Err(Failure.permissionDenied());
      await pumpGeofenceApp(tester, env);
      await _enterName(tester, 'Casa');
      await _useMyLocation(tester);
      await _save(tester);
      expect(find.text(l10n.geofenceErrorNotAllowed), findsOneWidget);
    });

    testWidgets(
      'sin confirmación del servidor no dice que se guardó ni culpa a otro',
      (tester) async {
        final env = GeofenceTestEnv();
        await pumpGeofenceApp(tester, env);
        await _enterName(tester, 'Casa');
        await _useMyLocation(tester);
        for (final failure in const [
          Failure.unavailable('timeout'),
          Failure.conflict(),
        ]) {
          env.repository.createResult = Err(failure);
          await _save(tester);
          expect(find.text(l10n.geofenceErrorUnconfirmed), findsOneWidget);
          expect(find.text(l10n.geofenceErrorConflict), findsNothing);
          expect(find.text('Zona guardada'), findsNothing);
          expect(find.text('stub:${AppRoutes.map}'), findsNothing);
        }
        // Reintentar con éxito.
        env.repository.createResult = null;
        await _save(tester);
        expect(env.repository.createCalls, hasLength(3));
        expect(find.text('stub:${AppRoutes.map}'), findsOneWidget);
      },
    );

    testWidgets('mientras guarda no se puede volver a enviar', (tester) async {
      final env = GeofenceTestEnv();
      final gate = env.repository.gate = Completer<void>();
      await pumpGeofenceApp(tester, env);
      await _enterName(tester, 'Casa');
      await _useMyLocation(tester);
      await _save(tester);

      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(await _enabled(tester, 'Usar mi ubicación actual'), isFalse);
      gate.complete();
      await pumpFrames(tester);
      expect(env.repository.createCalls, hasLength(1));
      expect(find.text('stub:${AppRoutes.map}'), findsOneWidget);
    });

    testWidgets('sin conexión no deja guardar y lo dice', (tester) async {
      await pumpGeofenceApp(
        tester,
        GeofenceTestEnv(syncStatus: SyncStatus.offline),
      );
      expect(find.text(l10n.geofenceOfflineBanner), findsOneWidget);
      expect(await _enabled(tester, 'Guardar zona'), isFalse);
    });
  });

  group('ubicación actual', () {
    testWidgets('explica antes de pedir el permiso; "Ahora no" no pide nada', (
      tester,
    ) async {
      final env = GeofenceTestEnv(
        device: FakeDeviceLocationService(
          permissionState: DeviceLocationPermission.notDetermined,
        ),
      );
      await pumpGeofenceApp(tester, env);

      await _useMyLocation(tester);
      expect(find.text(l10n.geofenceLocationRationaleTitle), findsOneWidget);
      expect(find.text(l10n.geofenceLocationRationaleVisible), findsOneWidget);
      await tester.tap(_button('Ahora no'));
      await pumpFrames(tester);
      expect(env.device.requests, 0);
      expect(find.text('Aún no has elegido el centro.'), findsOneWidget);

      await _useMyLocation(tester);
      await tester.tap(_button('Continuar'));
      await pumpFrames(tester);
      expect(env.device.requests, 1);
      expect(find.text('Centro elegido · precisión ±12 m'), findsOneWidget);
    });

    testWidgets('si no concede el permiso, lo dice sin insistir', (
      tester,
    ) async {
      final env = GeofenceTestEnv(
        device: FakeDeviceLocationService(
          permissionState: DeviceLocationPermission.notDetermined,
          onRequest: DeviceLocationPermission.denied,
        ),
      );
      await pumpGeofenceApp(tester, env);
      await _useMyLocation(tester);
      await tester.tap(_button('Continuar'));
      await pumpFrames(tester);
      expect(find.text(l10n.geofenceLocationDeclined), findsOneWidget);
      expect(env.device.requests, 1);
    });

    testWidgets('denegado para siempre: ofrece abrir los ajustes', (
      tester,
    ) async {
      final env = GeofenceTestEnv(
        device: FakeDeviceLocationService(
          permissionState: DeviceLocationPermission.deniedForever,
        ),
      );
      await pumpGeofenceApp(tester, env);
      await _useMyLocation(tester);
      expect(find.text(l10n.geofenceLocationBlocked), findsOneWidget);

      await scrollAndTap(tester, _button('Abrir ajustes'));
      expect(env.device.settingsOpened, 1);
      // Si no se pudieron abrir, se dice tal cual.
      expect(find.text(l10n.geofenceSettingsNotOpened), findsOneWidget);
    });

    testWidgets('servicio apagado', (tester) async {
      await pumpGeofenceApp(
        tester,
        GeofenceTestEnv(
          device: FakeDeviceLocationService(
            permissionState: DeviceLocationPermission.serviceDisabled,
          ),
        ),
      );
      await _useMyLocation(tester);
      expect(find.text(l10n.geofenceLocationServiceOff), findsOneWidget);
    });

    testWidgets('sin lectura: reintentar', (tester) async {
      final env = GeofenceTestEnv(
        device: FakeDeviceLocationService(
          fix: const Err(Failure.unavailable('location-unavailable')),
        ),
      );
      await pumpGeofenceApp(tester, env);
      await _useMyLocation(tester);
      expect(find.text(l10n.geofenceLocationUnavailable), findsOneWidget);

      env.device.fix = Ok(sampleFix(accuracyMeters: 240));
      await scrollAndTap(tester, _button('Reintentar'));
      expect(find.text(l10n.geofenceLocationUnavailable), findsNothing);
      expect(find.text('Centro elegido · precisión ±240 m'), findsOneWidget);
      expect(find.text(l10n.geofenceCenterLowAccuracy), findsOneWidget);
    });
  });

  group('con mapa', () {
    testWidgets('elegir el centro tocando el mapa', (tester) async {
      final env = GeofenceTestEnv(mapBuilder: fakeMapBuilder);
      await pumpGeofenceApp(tester, env);

      expect(find.text(l10n.geofenceMapUnavailable), findsNothing);
      expect(find.text(l10n.geofenceMapHint), findsOneWidget);
      expect(find.text('map zones=0 radius=null pick=true'), findsOneWidget);

      await scrollAndTap(tester, find.byKey(const Key('fake-map-pick')));
      expect(find.text('Centro elegido en el mapa'), findsOneWidget);
      expect(find.text('map zones=1 radius=200 pick=true'), findsOneWidget);

      await _enterName(tester, 'Parque');
      await _save(tester);
      expect(env.repository.createCalls.single.center, syntheticPicked);
    });
  });

  group('editar', () {
    String location() => AppRoutes.zone('z1');

    testWidgets('precarga la zona y guarda desde su versión', (tester) async {
      final env = GeofenceTestEnv();
      await pumpGeofenceApp(tester, env, location: location());

      expect(find.text('Editar zona'), findsOneWidget);
      expect(find.text('Casa'), findsOneWidget);
      expect(find.text('Radio: 300 m'), findsOneWidget);
      expect(find.text('Se mantiene el centro guardado'), findsOneWidget);

      await _enterName(tester, 'Casa de la abuela');
      await _save(tester, label: 'Guardar cambios');

      final sent = env.repository.updateCalls.single;
      expect(sent.id, 'z1');
      expect(sent.version, 2);
      expect(sent.name, 'Casa de la abuela');
      expect(sent.radiusMeters, 300);
      expect(sent.center, syntheticCenter);
      expect(sent.createdBy, 'marta');
      expect(find.text('stub:${AppRoutes.map}'), findsOneWidget);
    });

    testWidgets('conflicto al guardar: avisa y permite ver la versión actual', (
      tester,
    ) async {
      final env = GeofenceTestEnv();
      env.repository.updateResult = const Err(
        Failure.conflict('geofence-conflict'),
      );
      await pumpGeofenceApp(tester, env, location: location());
      await _enterName(tester, 'Mi versión');
      await _save(tester, label: 'Guardar cambios');

      expect(
        find.text(
          'Otro integrante cambió esta zona. Revisa la versión actual.',
        ),
        findsOneWidget,
      );
      expect(find.text('stub:${AppRoutes.map}'), findsNothing);

      // Llega la versión del otro integrante.
      env.repository.zones.value = [
        sampleZone(name: 'Casa (nueva)', radiusMeters: 500, version: 3),
      ];
      await pumpFrames(tester);
      await tester.tap(_button('Ver versión actual'));
      await pumpFrames(tester);
      await _scrollToTop(tester);
      expect(find.text('Casa (nueva)'), findsOneWidget);
      expect(find.text('Radio: 500 m'), findsOneWidget);
      expect(find.text(l10n.geofenceErrorConflict), findsNothing);

      env.repository.updateResult = null;
      await _save(tester, label: 'Guardar cambios');
      expect(env.repository.updateCalls.last.version, 3);
    });

    testWidgets('avisa si otro integrante la cambia mientras se edita', (
      tester,
    ) async {
      final env = GeofenceTestEnv();
      await pumpGeofenceApp(tester, env, location: location());
      expect(find.text(l10n.geofenceErrorConflict), findsNothing);

      env.repository.zones.value = [sampleZone(version: 3)];
      await pumpFrames(tester);
      expect(find.text(l10n.geofenceErrorConflict), findsOneWidget);
    });

    testWidgets('si la eliminan mientras se edita, no deja guardar', (
      tester,
    ) async {
      final env = GeofenceTestEnv();
      await pumpGeofenceApp(tester, env, location: location());
      env.repository.zones.value = const [];
      await pumpFrames(tester);
      expect(find.text(l10n.geofenceErrorNotFound), findsOneWidget);
      expect(await _enabled(tester, 'Guardar cambios'), isFalse);
      expect(await _enabled(tester, 'Eliminar zona'), isFalse);
    });

    testWidgets('en pausa por el equipo lo dice y no deja guardar ni '
        'eliminar', (tester) async {
      final env = GeofenceTestEnv(
        serviceFlags: const ServiceFlags(geofenceEditingEnabled: false),
      );
      await pumpGeofenceApp(tester, env, location: location());
      expect(find.text(l10n.geofenceEditingPausedByService), findsOneWidget);
      expect(await _enabled(tester, 'Guardar cambios'), isFalse);
      expect(await _enabled(tester, 'Eliminar zona'), isFalse);
    });

    testWidgets('eliminar pide confirmación', (tester) async {
      final env = GeofenceTestEnv();
      await pumpGeofenceApp(tester, env, location: location());

      await scrollAndTap(tester, _button('Eliminar zona'));
      expect(find.text('¿Eliminar la zona «Casa»?'), findsOneWidget);
      expect(find.text(l10n.geofenceDeleteBody), findsOneWidget);
      await tester.tap(_button('Cancelar'));
      await pumpFrames(tester);
      expect(env.repository.deleteCalls, isEmpty);

      await scrollAndTap(tester, _button('Eliminar zona'));
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: _button('Eliminar zona'),
        ),
      );
      await pumpFrames(tester);
      // Sin falsos avisos mientras la caché refleja el borrado.
      env.repository.zones.value = const [];
      await pumpFrames(tester);
      expect(env.repository.deleteCalls.single.id, 'z1');
      expect(find.text('stub:${AppRoutes.map}'), findsOneWidget);
      expect(find.text('Zona eliminada'), findsOneWidget);
    });

    testWidgets('si eliminar falla, lo dice y sigue en la pantalla', (
      tester,
    ) async {
      final env = GeofenceTestEnv();
      env.repository.deleteResult = const Err(Failure.network());
      await pumpGeofenceApp(tester, env, location: location());
      await scrollAndTap(tester, _button('Eliminar zona'));
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: _button('Eliminar zona'),
        ),
      );
      await pumpFrames(tester);
      expect(find.text(l10n.geofenceErrorUnconfirmed), findsOneWidget);
      expect(find.text('stub:${AppRoutes.map}'), findsNothing);
    });

    testWidgets('una zona que no existe', (tester) async {
      await pumpGeofenceApp(
        tester,
        GeofenceTestEnv(),
        location: AppRoutes.zone('otra'),
      );
      expect(find.text(l10n.geofenceNotFoundTitle), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
    });

    testWidgets('quien no gestiona la familia la ve en solo lectura', (
      tester,
    ) async {
      await pumpGeofenceApp(
        tester,
        GeofenceTestEnv(role: MemberRole.member),
        location: location(),
      );
      expect(find.text('Zona'), findsOneWidget);
      expect(find.text('Casa'), findsOneWidget);
      expect(find.text('Modificada hace 3 días'), findsOneWidget);
      expect(find.text('Radio: 300 m'), findsOneWidget);
      expect(find.text(l10n.geofenceReadOnlyNote), findsOneWidget);
      expect(find.text(l10n.geofenceMapUnavailableReadOnly), findsOneWidget);
      expect(find.text(l10n.geofenceAlertsUnavailableNote), findsOneWidget);
      expect(find.byType(TextField), findsNothing);
      expect(find.byType(Slider), findsNothing);
      expect(_button('Guardar cambios'), findsNothing);
      expect(_button('Eliminar zona'), findsNothing);
    });

    testWidgets('en solo lectura con mapa, el mapa no permite elegir', (
      tester,
    ) async {
      await pumpGeofenceApp(
        tester,
        GeofenceTestEnv(role: MemberRole.admin, mapBuilder: fakeMapBuilder),
        location: location(),
      );
      // Un admin sí gestiona.
      expect(find.byType(TextField), findsOneWidget);

      await pumpGeofenceApp(
        tester,
        GeofenceTestEnv(role: MemberRole.member, mapBuilder: fakeMapBuilder),
        location: location(),
      );
      expect(find.text('map zones=1 radius=300 pick=false'), findsOneWidget);
    });
  });

  group('texto al 200 %: los errores se llevan a la vista', () {
    bool onScreen(WidgetTester tester, Finder finder) =>
        finder.hitTestable().evaluate().isNotEmpty;

    testWidgets('nombre vacío: sube hasta el campo', (tester) async {
      final env = GeofenceTestEnv();
      await pumpGeofenceApp(tester, env, textScale: 2);
      await _useMyLocation(tester);
      await _save(tester);
      await pumpFrames(tester);
      expect(
        onScreen(tester, find.text('Escribe un nombre para la zona.')),
        isTrue,
      );
    });

    testWidgets('conflicto: sube hasta el aviso', (tester) async {
      final env = GeofenceTestEnv();
      env.repository.updateResult = const Err(
        Failure.conflict('geofence-conflict'),
      );
      await pumpGeofenceApp(
        tester,
        env,
        location: AppRoutes.zone('z1'),
        textScale: 2,
      );
      await _save(tester, label: 'Guardar cambios');
      await pumpFrames(tester);
      expect(onScreen(tester, find.text(l10n.geofenceErrorConflict)), isTrue);
      expect(onScreen(tester, _button('Ver versión actual')), isTrue);
    });

    testWidgets('límite: muestra el error junto al botón', (tester) async {
      final env = GeofenceTestEnv();
      env.repository.createResult = const Err(
        Failure.validation('geofence-limit'),
      );
      await pumpGeofenceApp(tester, env, textScale: 2);
      await _enterName(tester, 'Casa');
      await _useMyLocation(tester);
      await _save(tester);
      await pumpFrames(tester);
      expect(onScreen(tester, find.text(l10n.geofenceErrorLimit(10))), isTrue);
    });
  });

  group('texto al 200 %', () {
    for (final (name, location, role) in [
      ('nueva', AppRoutes.newZone, MemberRole.owner),
      ('editar', AppRoutes.zone('z1'), MemberRole.owner),
      ('solo lectura', AppRoutes.zone('z1'), MemberRole.member),
    ]) {
      testWidgets('$name: sin desbordes', (tester) async {
        final env = GeofenceTestEnv(
          role: role,
          device: FakeDeviceLocationService(
            permissionState: DeviceLocationPermission.deniedForever,
          ),
        );
        await pumpGeofenceApp(tester, env, location: location, textScale: 2);
        if (role == MemberRole.owner) {
          // Con los avisos y errores a la vista: es lo que más crece.
          env.repository.updateResult = const Err(
            Failure.conflict('geofence-conflict'),
          );
          await _enterName(tester, '');
          await _useMyLocation(tester);
          await _save(
            tester,
            label: location == AppRoutes.newZone
                ? 'Guardar zona'
                : 'Guardar cambios',
          );
          expect(find.text('stub:${AppRoutes.map}'), findsNothing);
          await tester.drag(
            find.byType(Scrollable).first,
            const Offset(0, -3000),
          );
          await pumpFrames(tester);
        }
        expect(tester.takeException(), isNull);
      });
    }
  });
}
