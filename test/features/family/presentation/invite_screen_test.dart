import 'package:flutter_test/flutter_test.dart';
import 'package:nexo_familia/core/failure.dart';
import 'package:nexo_familia/core/result.dart';
import 'package:nexo_familia/design_system/components/nx_button.dart';
import 'package:nexo_familia/features/common/presentation/routes.dart';
import 'package:nexo_familia/features/family/domain/family.dart';

import 'family_test_harness.dart';

void main() {
  Future<FamilyTestEnv> open(WidgetTester tester, [FamilyTestEnv? env]) async {
    final e = env ?? FamilyTestEnv();
    await pumpFamilyApp(tester, e, initialLocation: AppRoutes.invite);
    return e;
  }

  Future<void> generate(WidgetTester tester) async {
    await tester.tap(find.text('Generar código'));
    await pumpFrames(tester);
  }

  NxButton buttonLabeled(WidgetTester tester, String label) =>
      tester.widget<NxButton>(
        find.ancestor(of: find.text(label), matching: find.byType(NxButton)),
      );

  testWidgets('antes de generar explica los avisos honestos', (tester) async {
    await open(tester);
    expect(
      find.text('Genera un código para que alguien se una a Familia Gómez.'),
      findsOneWidget,
    );
    expect(
      find.text('Compártelo solo con la persona que quieres invitar.'),
      findsOneWidget,
    );
    expect(
      find.text(
        'Quien se una podrá ver la ubicación de quienes la comparten en esta '
        'familia.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('genera y muestra el código con su vigencia real', (
    tester,
  ) async {
    final env = await open(tester);
    await generate(tester);
    expect(env.families.inviteCalls, [familyId]);
    expect(find.text('ABCDE-FGHJK'), findsOneWidget);
    expect(find.text('Vence en 48 h · un solo uso'), findsOneWidget);
    expect(
      find.bySemanticsLabel('Código de invitación: A B C D E, F G H J K'),
      findsOneWidget,
    );
    expect(find.text('Generar otro código'), findsOneWidget);
  });

  testWidgets('la vigencia sale de expiresAt, no de un valor fijo', (
    tester,
  ) async {
    final env = FamilyTestEnv();
    env.families.invite.result = Ok(
      CreatedInvitation(
        invitationId: 'inv',
        code: 'ABCDEFGHJK',
        expiresAt: testNow.add(const Duration(hours: 5, minutes: 10)),
        maxUses: 3,
      ),
    );
    await open(tester, env);
    await generate(tester);
    expect(find.text('Vence en 5 h · 3 usos'), findsOneWidget);
  });

  testWidgets('copiar pone el código en el portapapeles y lo confirma', (
    tester,
  ) async {
    final copied = captureClipboard(tester);
    await open(tester);
    await generate(tester);
    await tester.tap(find.text('Copiar código'));
    await pumpFrames(tester);
    expect(copied, ['ABCDE-FGHJK']);
    // Confirmación visible y anunciada (SnackBar en región en vivo) y en el
    // propio botón.
    expect(find.text('Código copiado'), findsNWidgets(2));
  });

  testWidgets('al vencer, lo indica y ya no deja copiarlo', (tester) async {
    final env = await open(tester);
    await generate(tester);
    env.clock.advance(const Duration(hours: 48, minutes: 1));
    await tester.pump(const Duration(seconds: 31));
    expect(
      find.text('Este código ya venció. Genera uno nuevo.'),
      findsOneWidget,
    );
    expect(buttonLabeled(tester, 'Copiar código').onPressed, isNull);
  });

  final cases = <String, (Failure, String)>{
    'not-allowed': (
      const Failure.permissionDenied('not-allowed'),
      'Solo quienes administran el grupo pueden invitar.',
    ),
    'too-many-invitations': (
      const Failure(FailureKind.rateLimited, 'too-many-invitations'),
      'Este grupo ya tiene demasiadas invitaciones activas. Espera a que se '
          'usen o venzan.',
    ),
    'sin conexión': (
      const Failure.network(),
      'No hay conexión. Revisa tu red e inténtalo de nuevo.',
    ),
  };
  for (final MapEntry(key: name, value: (failure, message)) in cases.entries) {
    testWidgets('error: $name', (tester) async {
      final env = FamilyTestEnv();
      env.families.invite.result = Err(failure);
      await open(tester, env);
      await generate(tester);
      expect(find.text(message), findsOneWidget);
      expect(find.text('Copiar código'), findsNothing);
    });
  }

  testWidgets('quien no administra no puede generar códigos', (tester) async {
    final env = FamilyTestEnv(
      families: FakeFamilyRepository(
        families: [familyGroup(role: MemberRole.member)],
        members: {familyId: sampleMembers()},
      ),
    );
    await open(tester, env);
    expect(
      find.text('Solo quienes administran el grupo pueden invitar.'),
      findsOneWidget,
    );
    expect(find.text('Generar código'), findsNothing);
  });

  testWidgets('con el grupo lleno avisa y desactiva el botón', (tester) async {
    final env = FamilyTestEnv(
      families: FakeFamilyRepository(
        families: [familyGroup()],
        members: {
          familyId: [
            for (var i = 0; i < FamilyRules.maxMembers; i++)
              familyMember('u$i', 'Persona $i', MemberRole.member),
          ],
        },
      ),
    );
    await open(tester, env);
    expect(
      find.text(
        'El grupo ya tiene 12 integrantes, el máximo permitido. Nadie más '
        'podrá unirse.',
      ),
      findsOneWidget,
    );
    expect(buttonLabeled(tester, 'Generar código').onPressed, isNull);
  });

  testWidgets('al 200 % de texto el código no se desborda', (tester) async {
    await pumpFamilyApp(
      tester,
      FamilyTestEnv(),
      initialLocation: AppRoutes.invite,
      textScale: 2,
    );
    await scrollAndTap(tester, find.text('Generar código'));
    await pumpFrames(tester);
    expect(tester.takeException(), isNull);
    // El código aparece por encima del botón: la página lo trae a la vista.
    expect(find.text('ABCDE-FGHJK').hitTestable(), findsOneWidget);
  });
}
