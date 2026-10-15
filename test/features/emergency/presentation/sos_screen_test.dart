import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexo_familia/core/failure.dart';
import 'package:nexo_familia/core/result.dart';
import 'package:nexo_familia/design_system/components/nx_hold_button.dart';
import 'package:nexo_familia/features/common/presentation/sync_status.dart';
import 'package:nexo_familia/features/emergency/domain/emergency.dart';
import 'package:nexo_familia/features/emergency/domain/sos_codes.dart';
import 'package:nexo_familia/features/emergency/presentation/sos_screen.dart';
import 'package:nexo_familia/features/location_sharing/domain/location.dart';

import '../../../helpers/fakes.dart';
import 'sos_test_support.dart';

void main() {
  late FakeClock clock;
  late FakeEmergencyRepository repository;
  late FakeDialer dialer;

  setUp(() {
    clock = FakeClock(testNow);
    repository = FakeEmergencyRepository();
    dialer = FakeDialer();
  });

  Future<void> pumpSos(
    WidgetTester tester, {
    String emergencyNumber = '123',
    SharingState sharing = SharingState.sharing,
    LocationPrecision precision = LocationPrecision.exact,
    SyncStatus sync = SyncStatus.live,
    String? activeFamilyId = familyId,
  }) async {
    await tester.pumpWidget(
      sosTestApp(
        overrides: sosOverrides(
          repository: repository,
          clock: clock,
          dialer: dialer,
          emergencyNumber: emergencyNumber,
          sharing: sharing,
          precision: precision,
          sync: sync,
          activeFamilyId: activeFamilyId,
        ),
        home: const SosScreen(),
      ),
    );
    await settle(tester);
  }

  group('estado inicial', () {
    testWidgets('explica qué pasará y ofrece llamar al 123', (tester) async {
      await pumpSos(tester);
      expect(find.text('¿Necesitas ayuda urgente?'), findsOneWidget);
      expect(
        find.text(
          'Avisaremos a los integrantes de tu familia con tu ubicación si la '
          'compartes. Nexo Familia no contacta a los servicios de emergencia.',
        ),
        findsOneWidget,
      );
      expect(find.byType(NxHoldButton), findsOneWidget);
      expect(find.text('Mantén presionado 2 segundos'), findsOneWidget);
      expect(find.text('Llamar al 123'), findsOneWidget);
      expect(
        find.text(
          'Se incluirá tu ubicación si el teléfono la obtiene a tiempo.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('sin compartir ubicación avisa que irá sin ella', (
      tester,
    ) async {
      await pumpSos(tester, sharing: SharingState.paused);
      expect(
        find.text(
          'No compartes tu ubicación con esta familia: la alerta irá sin ella.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('sin conexión explica que se guardará y se enviará después', (
      tester,
    ) async {
      await pumpSos(tester, sync: SyncStatus.offline);
      expect(
        find.textContaining('Sin conexión. Si envías una alerta'),
        findsOne,
      );
    });

    testWidgets('sin familia no se puede enviar, pero sí llamar', (
      tester,
    ) async {
      await pumpSos(tester, activeFamilyId: null);
      expect(find.byType(NxHoldButton), findsNothing);
      expect(find.textContaining('primero debes crear una familia'), findsOne);
      expect(find.text('Llamar al 123'), findsOneWidget);
    });
  });

  group('activación', () {
    testWidgets('un toque corto no activa nada', (tester) async {
      await pumpSos(tester);
      await tester.tap(holdButtonLabel);
      await elapse(tester, clock, const Duration(seconds: 8));
      expect(find.text('La alerta se enviará en'), findsNothing);
      expect(find.byType(NxHoldButton), findsOneWidget);
      expect(repository.raised, isEmpty);
    });

    testWidgets('soltar antes de 2 s no activa', (tester) async {
      await pumpSos(tester);
      await holdSos(
        tester,
        clock,
        duration: const Duration(milliseconds: 1500),
      );
      await elapse(tester, clock, const Duration(seconds: 8));
      expect(find.text('La alerta se enviará en'), findsNothing);
      expect(repository.raised, isEmpty);
    });

    testWidgets('mantener pulsado inicia la cuenta atrás con anuncio', (
      tester,
    ) async {
      final semantics = tester.ensureSemantics();
      await pumpSos(tester);
      await holdSos(tester, clock);

      expect(find.text('La alerta se enviará en'), findsOneWidget);
      expect(find.text('5'), findsOneWidget);
      expect(find.text('Cancelar'), findsOneWidget);
      expect(
        find.bySemanticsLabel('La alerta se enviará en 5 segundos'),
        findsOneWidget,
      );
      // "Llamar al 123" sigue visible durante la cuenta atrás.
      expect(find.text('Llamar al 123'), findsOneWidget);

      await elapse(tester, clock, const Duration(seconds: 1));
      expect(find.text('4'), findsOneWidget);
      expect(
        find.bySemanticsLabel('La alerta se enviará en 4 segundos'),
        findsOneWidget,
      );
      expect(repository.raised, isEmpty);
      semantics.dispose();
    });

    testWidgets('cancelar durante la cuenta atrás no crea ninguna alerta', (
      tester,
    ) async {
      await pumpSos(tester);
      await holdSos(tester, clock);
      await elapse(tester, clock, const Duration(seconds: 3));
      await tester.tap(find.text('Cancelar'));
      await elapse(tester, clock, const Duration(seconds: 10));

      expect(repository.raised, isEmpty);
      expect(find.text('Cancelaste la alerta. No se envió nada.'), findsOne);
      expect(find.byType(NxHoldButton), findsOneWidget);
    });

    testWidgets(
      'cerrar la pantalla durante la cuenta atrás equivale a cancelar',
      (tester) async {
        final navigator = GlobalKey<NavigatorState>();
        await tester.pumpWidget(
          sosTestApp(
            overrides: sosOverrides(repository: repository, clock: clock),
            home: Navigator(
              key: navigator,
              onGenerateRoute: (_) => MaterialPageRoute<void>(
                builder: (_) => const Scaffold(body: Text('inicio')),
              ),
            ),
          ),
        );
        navigator.currentState!.push(
          MaterialPageRoute<void>(builder: (_) => const SosScreen()),
        );
        await settle(tester, frames: 10);
        await holdSos(tester, clock);
        expect(find.text('La alerta se enviará en'), findsOneWidget);

        navigator.currentState!.pop();
        await elapse(tester, clock, const Duration(seconds: 10));
        expect(find.text('inicio'), findsOneWidget);
        expect(repository.raised, isEmpty);
      },
    );

    testWidgets('tras la cuenta atrás se crea UNA alerta con la ubicación', (
      tester,
    ) async {
      await pumpSos(tester);
      await holdSos(tester, clock);
      final start = clock.now();
      await elapse(tester, clock, const Duration(seconds: 6));
      await settle(tester);

      expect(repository.raised, hasLength(1));
      final alert = repository.raised.single;
      expect(alert.uid, myUid);
      expect(alert.familyId, familyId);
      expect(alert.delivery, SosDelivery.queued);
      expect(alert.location?.latitude, 4.6097);
      expect(alert.locationAccuracyMeters, 15);
      expect(alert.createdAt.isAfter(start), isTrue);
      expect(
        find.text(
          'Guardada en tu teléfono. Se enviará en cuanto haya conexión.',
        ),
        findsOneWidget,
      );

      await elapse(tester, clock, const Duration(seconds: 10));
      expect(repository.raised, hasLength(1));
    });

    testWidgets('sin consentimiento la alerta va sin ubicación', (
      tester,
    ) async {
      await pumpSos(tester, sharing: SharingState.notConfigured);
      await holdSos(tester, clock);
      await elapse(tester, clock, const Duration(seconds: 6));
      await settle(tester);
      expect(repository.raised.single.location, isNull);
      expect(repository.raised.single.locationAccuracyMeters, isNull);
    });

    testWidgets('con precisión aproximada se redondea la ubicación', (
      tester,
    ) async {
      await pumpSos(tester, precision: LocationPrecision.approximate);
      await holdSos(tester, clock);
      await elapse(tester, clock, const Duration(seconds: 6));
      await settle(tester);
      final alert = repository.raised.single;
      expect(alert.location?.latitude, 4.61);
      expect(alert.location?.longitude, -74.08);
      expect(alert.locationAccuracyMeters, 1000);
    });

    testWidgets('si no se pudo guardar, se reintenta con el mismo id', (
      tester,
    ) async {
      repository.raiseResult = const Err(Failure.unexpected(SosCodes.notSaved));
      await pumpSos(tester);
      await holdSos(tester, clock);
      await elapse(tester, clock, const Duration(seconds: 6));
      await settle(tester);
      expect(find.text('No pudimos guardar la alerta'), findsOneWidget);

      repository.raiseResult = null;
      await tester.tap(find.text('Reintentar'));
      await settle(tester);
      expect(repository.raised, hasLength(2));
      expect(repository.raised.first.id, repository.raised.last.id);
      expect(find.text('Alerta pendiente de envío'), findsOneWidget);
    });
  });

  group('alerta en curso: textos honestos', () {
    final variants = <String, (EmergencyAlert, List<String>)>{
      'en cola': (
        alertOf(delivery: SosDelivery.queued),
        [
          'Alerta pendiente de envío',
          'Guardada en tu teléfono. Se enviará en cuanto haya conexión.',
          'Reintentar',
          'Cancelar envío',
        ],
      ),
      'enviando': (
        alertOf(delivery: SosDelivery.sending),
        ['Enviando tu alerta', 'Guardada en tu teléfono', 'Enviando…'],
      ),
      'registrada sin recuento': (
        alertOf(),
        [
          'Alerta activa',
          'Alerta registrada',
          'Aviso a los teléfonos de tu familia: aún sin confirmar.',
          'Terminar alerta',
        ],
      ),
      'notificada': (
        alertOf(notifiedCount: 3),
        [
          'Aviso enviado a 3 dispositivos',
          'Enviado no significa que lo hayan visto.',
          'Nadie ha confirmado todavía que la vio.',
        ],
      ),
      'notificada a nadie': (
        alertOf(notifiedCount: 0),
        [
          'Nadie pudo ser notificado. Llama al 123 si lo necesitas.',
          'Nadie ha confirmado todavía que la vio.',
        ],
      ),
      'confirmada por otro integrante': (
        alertOf(
          notifiedCount: 2,
          acks: [
            EmergencyAck(uid: 'luis', at: DateTime.utc(2026, 3, 10, 14, 32)),
          ],
        ),
        ['Alerta activa', 'Luis confirmó que la vio a las 14:32'],
      ),
      'fallida': (
        alertOf(delivery: SosDelivery.failed, failureCode: SosCodes.notMember),
        [
          'No se pudo enviar la alerta',
          'Ya no perteneces a esta familia.',
          'Reintentar',
        ],
      ),
    };

    for (final MapEntry(key: name, value: (alert, texts)) in variants.entries) {
      testWidgets(name, (tester) async {
        repository = FakeEmergencyRepository([alert]);
        await pumpSos(tester);
        for (final text in texts) {
          expect(find.text(text), findsOneWidget, reason: text);
        }
        expect(find.textContaining('Llamar al 123'), findsWidgets);
        expect(visibleText(tester), isNot(matches(forbiddenClaims)));
      });
    }

    testWidgets('la confirmación de la propia autora no cuenta', (
      tester,
    ) async {
      repository = FakeEmergencyRepository([
        alertOf(
          notifiedCount: 0,
          acks: [EmergencyAck(uid: myUid, at: testNow)],
        ),
      ]);
      await pumpSos(tester);
      expect(find.textContaining('confirmó'), findsNothing);
      expect(find.text('Nadie ha confirmado todavía que la vio.'), findsOne);
    });

    testWidgets('los estados avanzan al llegar datos verificados', (
      tester,
    ) async {
      repository = FakeEmergencyRepository([
        alertOf(delivery: SosDelivery.queued),
      ]);
      await pumpSos(tester);
      expect(find.text('Alerta pendiente de envío'), findsOneWidget);

      repository.put(alertOf(notifiedCount: 0));
      await settle(tester);
      expect(find.text('Alerta registrada'), findsOneWidget);

      repository.put(
        alertOf(
          notifiedCount: 0,
          acks: [
            EmergencyAck(uid: 'marta', at: DateTime.utc(2026, 3, 10, 14, 31)),
          ],
        ),
      );
      await settle(tester);
      expect(find.text('Marta confirmó que la vio a las 14:31'), findsOne);
      expect(visibleText(tester), isNot(matches(forbiddenClaims)));
    });

    testWidgets('si desaparece un momento conserva lo último conocido', (
      tester,
    ) async {
      repository = FakeEmergencyRepository([
        alertOf(delivery: SosDelivery.sending),
      ]);
      await pumpSos(tester);
      repository.alerts.value = const [];
      await settle(tester);
      // Nunca se da por enviada sin confirmación.
      expect(find.text('Enviando…'), findsOneWidget);
    });
  });

  group('acciones', () {
    testWidgets('el botón de llamada usa el número configurado', (
      tester,
    ) async {
      await pumpSos(tester, emergencyNumber: '112');
      expect(find.text('Llamar al 112'), findsOneWidget);
      await tester.tap(find.text('Llamar al 112'));
      await settle(tester);
      expect(dialer.numbers, ['112']);
      expect(find.textContaining('No pudimos abrir el marcador'), findsNothing);
    });

    testWidgets('si no se puede abrir el marcador muestra el número', (
      tester,
    ) async {
      dialer.opens = false;
      await pumpSos(tester, emergencyNumber: '112');
      await tester.tap(find.text('Llamar al 112'));
      await settle(tester);
      expect(
        find.text(
          'No pudimos abrir el marcador. Marca este número desde tu teléfono:',
        ),
        findsOneWidget,
      );
      expect(find.text('112'), findsOneWidget);
    });

    testWidgets('Reintentar pide un nuevo envío', (tester) async {
      repository = FakeEmergencyRepository([
        alertOf(delivery: SosDelivery.failed, failureCode: 'network'),
      ]);
      await pumpSos(tester);
      await tester.tap(find.text('Reintentar'));
      await settle(tester);
      expect(repository.retried, ['sos-1']);
    });

    testWidgets('terminar pide confirmación y muestra la alerta terminada', (
      tester,
    ) async {
      repository = FakeEmergencyRepository([alertOf(notifiedCount: 0)]);
      await pumpSos(tester);

      await tester.tap(find.text('Terminar alerta'));
      await settle(tester);
      expect(find.text('¿Terminar la alerta?'), findsOneWidget);
      await tester.tap(find.text('Mantenerla activa'));
      await settle(tester);
      expect(repository.resolved, isEmpty);

      await tester.tap(find.text('Terminar alerta'));
      await settle(tester);
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Terminar alerta'),
        ),
      );
      await settle(tester);
      expect(repository.resolved, ['sos-1']);
      expect(find.text('Alerta terminada'), findsOneWidget);
      expect(find.text('Terminaste la alerta a las 14:30.'), findsOneWidget);
      expect(find.text('Cerrar'), findsOneWidget);
    });

    testWidgets('si terminar falla no se da por terminada', (tester) async {
      repository = FakeEmergencyRepository([alertOf(notifiedCount: 0)])
        ..resolveResult = const Err(Failure.network());
      await pumpSos(tester);
      await tester.tap(find.text('Terminar alerta'));
      await settle(tester);
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Terminar alerta'),
        ),
      );
      await settle(tester);
      expect(find.text('Alerta activa'), findsOneWidget);
      expect(
        find.text('No hay conexión. Revisa tu red e inténtalo de nuevo.'),
        findsOneWidget,
      );
    });

    testWidgets('cancelar el envío de una alerta en cola vuelve al inicio', (
      tester,
    ) async {
      repository = FakeEmergencyRepository([
        alertOf(delivery: SosDelivery.queued),
      ]);
      await pumpSos(tester);
      await tester.tap(find.text('Cancelar envío'));
      await settle(tester);
      expect(find.text('¿Cancelar el envío?'), findsOneWidget);
      await tester.tap(
        find.descendant(
          of: find.byType(AlertDialog),
          matching: find.text('Cancelar envío'),
        ),
      );
      await settle(tester);
      expect(repository.resolved, ['sos-1']);
      expect(
        find.text('Cancelaste el envío. Dejamos de intentarlo.'),
        findsOneWidget,
      );
      expect(find.byType(NxHoldButton), findsOneWidget);
    });
  });
}
