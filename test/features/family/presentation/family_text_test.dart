import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexo_familia/core/failure.dart';
import 'package:nexo_familia/core/geo/geo_point.dart';
import 'package:nexo_familia/features/family/domain/family.dart';
import 'package:nexo_familia/features/family/presentation/family_text.dart';
import 'package:nexo_familia/features/family/presentation/family_view_logic.dart';
import 'package:nexo_familia/features/location_sharing/domain/location.dart';
import 'package:nexo_familia/l10n/gen/app_localizations.dart';

import 'family_test_harness.dart';

void main() {
  final l10n = lookupAppLocalizations(const Locale('es'));

  group('familyRoleLabel', () {
    test('cada rol tiene un texto (no solo un color)', () {
      expect(familyRoleLabel(l10n, MemberRole.owner), 'Administra el grupo');
      expect(familyRoleLabel(l10n, MemberRole.admin), 'Ayuda a administrar');
      expect(familyRoleLabel(l10n, MemberRole.member), 'Integrante');
    });
  });

  group('familyFailureMessage', () {
    String message(Failure f, [FamilyOperation op = FamilyOperation.join]) =>
        familyFailureMessage(l10n, f, op);

    test('traduce los códigos del contrato del backend', () {
      expect(
        message(const Failure.notFound('invitation-invalid')),
        'El código no es válido o ya venció. Pide uno nuevo a quien te '
        'invitó.',
      );
      expect(
        message(const Failure.validation('invitation-format')),
        l10n.familyErrorInvitationFormat,
      );
      expect(
        message(const Failure.conflict('already-member')),
        l10n.familyErrorAlreadyMember,
      );
      expect(
        message(const Failure(FailureKind.rateLimited, 'family-full')),
        'Esta familia ya tiene 12 integrantes, el máximo permitido.',
      );
      expect(
        message(const Failure(FailureKind.rateLimited, 'rate-limited')),
        l10n.familyErrorRateLimited,
      );
      expect(
        message(
          const Failure(FailureKind.rateLimited, 'too-many-families'),
          FamilyOperation.create,
        ),
        l10n.familyErrorTooManyFamilies,
      );
      expect(
        message(
          const Failure.validation('family-name-invalid'),
          FamilyOperation.create,
        ),
        l10n.familyErrorNameInvalid(40),
      );
      expect(
        message(
          const Failure(FailureKind.rateLimited, 'too-many-invitations'),
          FamilyOperation.invite,
        ),
        l10n.familyErrorTooManyInvitations,
      );
    });

    test('not-allowed depende de la operación', () {
      const failure = Failure.permissionDenied('not-allowed');
      expect(
        message(failure, FamilyOperation.invite),
        l10n.familyErrorNotAllowedInvite,
      );
      expect(
        message(failure, FamilyOperation.remove),
        l10n.familyErrorNotAllowedRemove,
      );
      expect(
        message(failure, FamilyOperation.leave),
        l10n.errorPermissionDenied,
      );
    });

    test('los códigos desconocidos usan el mensaje por categoría', () {
      expect(message(const Failure.network()), l10n.errorNetwork);
      expect(
        message(const Failure.unexpected('bad-response')),
        l10n.errorUnexpected,
      );
    });
  });

  group('familyNameValidationMessage', () {
    test('mensajes de FamilyRules.familyName', () {
      expect(familyNameValidationMessage(l10n, null), isNull);
      expect(
        familyNameValidationMessage(l10n, FamilyRules.familyName('  ')),
        'Escribe un nombre para la familia.',
      );
      expect(
        familyNameValidationMessage(l10n, FamilyRules.familyName('x' * 41)),
        'Usa como máximo 40 caracteres.',
      );
    });
  });

  group('inviteExpiresText', () {
    test('un código recién creado vence "en 48 h"', () {
      expect(
        inviteExpiresText(l10n, const Duration(hours: 48)),
        'Vence en 48 h',
      );
      expect(
        inviteExpiresText(l10n, const Duration(hours: 47, minutes: 59)),
        'Vence en 48 h',
      );
    });

    test('con menos de una hora muestra minutos', () {
      expect(
        inviteExpiresText(l10n, const Duration(minutes: 35)),
        'Vence en 35 min',
      );
      expect(
        inviteExpiresText(l10n, const Duration(seconds: 20)),
        'Vence en 1 min',
      );
    });

    test('vencido devuelve null', () {
      expect(inviteExpiresText(l10n, Duration.zero), isNull);
      expect(inviteExpiresText(l10n, const Duration(minutes: -5)), isNull);
    });
  });

  test('spellInvitationCode deletrea el código para lectores de pantalla', () {
    expect(spellInvitationCode('ABCDEFGHJK'), 'A B C D E, F G H J K');
  });

  group('canRemoveMember (regla de removeMember)', () {
    final owner = familyMember('ana', 'Ana', MemberRole.owner);
    final admin = familyMember('marta', 'Marta', MemberRole.admin);
    final admin2 = familyMember('pedro', 'Pedro', MemberRole.admin);
    final member = familyMember('luis', 'Luis', MemberRole.member);

    bool can(FamilyMember actor, FamilyMember target) =>
        canRemoveMember(myUid: actor.uid, myRole: actor.role, target: target);

    test('el owner quita a cualquiera menos a sí mismo', () {
      expect(can(owner, admin), isTrue);
      expect(can(owner, member), isTrue);
      expect(can(owner, owner), isFalse);
    });

    test('un admin solo quita a integrantes con rol member', () {
      expect(can(admin, member), isTrue);
      expect(can(admin, admin2), isFalse);
      expect(can(admin, owner), isFalse);
      expect(can(admin, admin), isFalse);
    });

    test('un member no quita a nadie', () {
      expect(can(member, owner), isFalse);
      expect(can(member, familyMember('x', 'X', MemberRole.member)), isFalse);
    });
  });

  group('summarizeMemberLocation', () {
    const staleAfter = Duration(minutes: 30);

    test('sin ubicación: no comparte', () {
      final s = summarizeMemberLocation(
        null,
        now: testNow,
        staleAfter: staleAfter,
      );
      expect(s.state, MemberLocationState.notSharing);
      expect(s.reportedAt, isNull);
    });

    test('reciente dentro del umbral (límite incluido)', () {
      final s = summarizeMemberLocation(
        sampleLocation('luis', age: staleAfter),
        now: testNow,
        staleAfter: staleAfter,
      );
      expect(s.state, MemberLocationState.recent);
      expect(s.reportedAt, testNow.subtract(staleAfter));
    });

    test('antigua: sin actualización reciente', () {
      final s = summarizeMemberLocation(
        sampleLocation(
          'luis',
          age: const Duration(hours: 2),
          approximate: true,
        ),
        now: testNow,
        staleAfter: staleAfter,
      );
      expect(s.state, MemberLocationState.stale);
      expect(s.isApproximate, isTrue);
    });

    test('con el reloj del emisor adelantado usa la hora de recepción', () {
      final received = testNow.subtract(const Duration(hours: 3));
      final s = summarizeMemberLocation(
        MemberLocation(
          uid: 'luis',
          point: GeoPoint(4.6, -74.08),
          accuracyMeters: 25,
          capturedAt: testNow,
          receivedAt: received,
          isApproximate: false,
        ),
        now: testNow,
        staleAfter: staleAfter,
      );
      expect(s.state, MemberLocationState.stale);
      expect(s.reportedAt, received);
    });
  });
}
