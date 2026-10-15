@Tags(['golden'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexo_familia/core/failure.dart';
import 'package:nexo_familia/core/result.dart';
import 'package:nexo_familia/design_system/theme/nx_theme.dart';
import 'package:nexo_familia/features/common/presentation/routes.dart';
import 'package:nexo_familia/features/common/presentation/sync_status.dart';
import 'package:nexo_familia/features/family/domain/family.dart';

import '../../../helpers/fonts.dart';
import 'family_test_harness.dart';

/// Capturas de las pantallas de familia para revisión visual, en claro al
/// 100 % y en oscuro al 200 %. Para regenerarlas:
/// `flutter test --update-goldens test/features/family/presentation/family_golden_test.dart`.
typedef _Case = ({
  String name,
  String location,
  FamilyTestEnv Function() env,
  Future<void> Function(WidgetTester tester)? act,
});

FamilyTestEnv _ownerWithTwoFamilies() => FamilyTestEnv(
  families: FakeFamilyRepository(
    families: [
      familyGroup(),
      familyGroup(id: 'fam-2', name: 'Casa de la abuela'),
    ],
    members: {familyId: sampleMembers()},
  ),
);

Future<void> _generateCode(WidgetTester tester) async {
  await scrollAndTap(tester, find.text('Generar código'));
  await pumpFrames(tester);
}

Future<void> _scrollToEnd(WidgetTester tester) async {
  await tester.drag(find.byType(Scrollable).first, const Offset(0, -4000));
  await pumpFrames(tester);
}

final List<_Case> _cases = [
  (
    name: 'familia',
    location: AppRoutes.family,
    env: _ownerWithTwoFamilies,
    act: null,
  ),
  (
    name: 'familia_fin',
    location: AppRoutes.family,
    env: _ownerWithTwoFamilies,
    act: _scrollToEnd,
  ),
  (
    name: 'familia_sin_conexion_member',
    location: AppRoutes.family,
    env: () => FamilyTestEnv(
      syncStatus: SyncStatus.offline,
      families: FakeFamilyRepository(
        families: [familyGroup(role: MemberRole.member)],
        members: {
          familyId: [
            familyMember('marta', 'Marta Ruiz', MemberRole.owner),
            familyMember('ana', 'Ana', MemberRole.member),
            familyMember('luis', 'Luis', MemberRole.member),
          ],
        },
      ),
    ),
    act: null,
  ),
  (
    name: 'invitar',
    location: AppRoutes.invite,
    env: FamilyTestEnv.new,
    act: _generateCode,
  ),
  (
    name: 'invitar_fin',
    location: AppRoutes.invite,
    env: FamilyTestEnv.new,
    act: (tester) async {
      await _generateCode(tester);
      await _scrollToEnd(tester);
    },
  ),
  (
    name: 'invitar_inicial',
    location: AppRoutes.invite,
    env: FamilyTestEnv.new,
    act: null,
  ),
  (
    name: 'bienvenida',
    location: AppRoutes.familySetup,
    env: () => FamilyTestEnv(activeFamilyId: null),
    act: null,
  ),
  (
    name: 'crear',
    location: AppRoutes.createFamily,
    env: () => FamilyTestEnv(activeFamilyId: null),
    act: null,
  ),
  (
    name: 'unirse_error',
    location: AppRoutes.joinFamily,
    env: () {
      final env = FamilyTestEnv(activeFamilyId: null);
      env.families.accept.result = const Err(
        Failure.notFound('invitation-invalid'),
      );
      return env;
    },
    act: (tester) async {
      await tester.enterText(find.byType(TextField), 'abcde-fghjk');
      await scrollAndTap(tester, find.text('Unirme'));
      await pumpFrames(tester);
    },
  ),
  (
    name: 'integrante',
    location: AppRoutes.member('luis'),
    env: () => FamilyTestEnv(
      locations: FakeLocationRepository([
        sampleLocation('luis', age: const Duration(minutes: 5)),
      ]),
    ),
    act: null,
  ),
  (
    name: 'integrante_sin_actualizacion',
    location: AppRoutes.member('sofia'),
    env: () => FamilyTestEnv(
      locations: FakeLocationRepository([
        sampleLocation(
          'sofia',
          age: const Duration(hours: 3),
          approximate: true,
        ),
      ]),
    ),
    act: null,
  ),
  (
    name: 'integrante_yo',
    location: AppRoutes.member('ana'),
    env: FamilyTestEnv.new,
    act: null,
  ),
];

void main() {
  setUpAll(loadAppFonts);

  for (final c in _cases) {
    for (final (theme, scale) in [('claro', 1.0), ('oscuro', 2.0)]) {
      testWidgets('${c.name} $theme al ${(scale * 100).round()} %', (
        tester,
      ) async {
        await pumpFamilyApp(
          tester,
          c.env(),
          initialLocation: c.location,
          theme: theme == 'claro' ? NxTheme.light() : NxTheme.dark(),
          textScale: scale,
        );
        if (c.act case final act?) await act(tester);
        expect(tester.takeException(), isNull);
        await expectLater(
          find.byType(MaterialApp),
          matchesGoldenFile('goldens/${c.name}_${theme}_x${scale.round()}.png'),
        );
      });
    }
  }
}
