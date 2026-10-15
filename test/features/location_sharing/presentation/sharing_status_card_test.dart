import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexo_familia/core/failure.dart';
import 'package:nexo_familia/features/family/domain/family.dart';
import 'package:nexo_familia/features/location_sharing/domain/location.dart';
import 'package:nexo_familia/features/location_sharing/presentation/location_providers.dart';
import 'package:nexo_familia/features/location_sharing/presentation/sharing_status_card.dart';

import 'location_test_support.dart';

void main() {
  Future<void> pumpCard(
    WidgetTester tester, {
    SharingState state = SharingState.sharing,
    LocationPrecision precision = LocationPrecision.exact,
    List<FamilyMember>? members,
    String? activeFamilyId = familyId,
    bool consentFails = false,
    double textScale = 1,
  }) async {
    final repository = FakeLocationRepository(
      state: state,
      precision: precision,
    );
    await tester.pumpWidget(
      locationTestApp(
        overrides: [
          ...locationOverrides(
            repository: repository,
            device: FakeDeviceLocation(),
            members: members,
            activeFamilyId: activeFamilyId,
          ),
          if (consentFails)
            myConsentProvider.overrideWith(
              (ref, id) => Stream.error(const Failure.network()),
            ),
        ],
        // Como en Inicio: dentro de una página desplazable.
        home: Scaffold(
          body: ListView(
            padding: const EdgeInsets.all(20),
            children: const [SharingStatusCard()],
          ),
        ),
        textScale: textScale,
      ),
    );
    await settle(tester);
  }

  testWidgets('compartiendo: dice con cuántas personas y permite pausar', (
    tester,
  ) async {
    await pumpCard(tester);
    expect(find.text('Compartes tu ubicación exacta'), findsOneWidget);
    expect(
      find.text('La pueden ver 3 integrantes de esta familia.'),
      findsOneWidget,
    );
    await tester.tap(find.text('Pausar o cambiar'));
    await settle(tester);
    expect(find.text('ruta: privacidad'), findsOneWidget);
  });

  testWidgets('con una sola persona más usa el singular', (tester) async {
    await pumpCard(
      tester,
      members: [member(myUid, 'Ana', MemberRole.owner), member('luis', 'Luis')],
    );
    expect(
      find.text('La puede ver 1 integrante de esta familia.'),
      findsOneWidget,
    );
  });

  testWidgets('sin más integrantes lo dice', (tester) async {
    await pumpCard(tester, members: [member(myUid, 'Ana', MemberRole.owner)]);
    expect(
      find.text('Por ahora no hay más integrantes en esta familia.'),
      findsOneWidget,
    );
  });

  testWidgets('precisión aproximada', (tester) async {
    await pumpCard(tester, precision: LocationPrecision.approximate);
    expect(
      find.text('Compartes tu ubicación aproximada (±1\u00A0km)'),
      findsOneWidget,
    );
  });

  testWidgets('en pausa', (tester) async {
    await pumpCard(tester, state: SharingState.paused);
    expect(find.text('Tu ubicación está en pausa'), findsOneWidget);
    expect(
      find.text(
        'Tu familia no ve tu ubicación. Puedes reanudarla cuando quieras.',
      ),
      findsOneWidget,
    );
    expect(find.text('Configurar'), findsOneWidget);
  });

  testWidgets('sin configurar', (tester) async {
    await pumpCard(tester, state: SharingState.notConfigured);
    expect(find.text('Aún no compartes tu ubicación'), findsOneWidget);
    await tester.tap(find.text('Configurar'));
    await settle(tester);
    expect(find.text('ruta: privacidad'), findsOneWidget);
  });

  testWidgets('si no se puede leer el estado, no inventa uno', (tester) async {
    await pumpCard(tester, consentFails: true);
    expect(
      find.text('No pudimos leer si compartes tu ubicación.'),
      findsOneWidget,
    );
    expect(find.textContaining('Compartes'), findsNothing);
  });

  testWidgets('sin familia activa no muestra nada', (tester) async {
    await pumpCard(tester, activeFamilyId: null);
    expect(find.byType(SharingStatusCard, skipOffstage: false), findsOneWidget);
    expect(find.byType(Text), findsNothing);
  });

  testWidgets('al 200 % no se desborda', (tester) async {
    tester.view
      ..physicalSize = const Size(320, 640) * 3
      ..devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await pumpCard(tester, textScale: 2);
    expect(tester.takeException(), isNull);
    expect(find.text('Pausar o cambiar'), findsOneWidget);
  });
}
