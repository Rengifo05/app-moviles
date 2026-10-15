import 'package:flutter_test/flutter_test.dart';
import 'package:nexo_familia/core/geo/geo_point.dart';
import 'package:nexo_familia/features/emergency/domain/emergency.dart';

const _author = 'u-autora';
const _other = 'u-otro';
final _createdAt = DateTime.utc(2026, 3, 10, 9);
final _resolvedAt = DateTime.utc(2026, 3, 10, 9, 30);

EmergencyAlert _alert({
  SosDelivery delivery = SosDelivery.sent,
  int? notifiedCount,
  List<EmergencyAck> acks = const [],
  DateTime? resolvedAt,
  String? failureCode,
  GeoPoint? location,
}) => EmergencyAlert(
  id: 'sos-1',
  familyId: 'f1',
  uid: _author,
  createdAt: _createdAt,
  delivery: delivery,
  location: location,
  notifiedCount: notifiedCount,
  acks: acks,
  resolvedAt: resolvedAt,
  failureCode: failureCode,
);

EmergencyAck _ack(String uid, [int minute = 5]) =>
    EmergencyAck(uid: uid, at: DateTime.utc(2026, 3, 10, 9, minute));

/// Conjuntos de confirmaciones a combinar.
final _ackSets = <String, List<EmergencyAck>>{
  'sin acks': const [],
  'solo de la autora': [_ack(_author)],
  'de otro integrante': [_ack(_other)],
  'de la autora y de otro': [_ack(_author), _ack(_other, 7)],
};

/// Recuentos posibles: desconocido, inválido, nadie notificado y algunos.
const _counts = <int?>[null, -1, 0, 3];

/// Tabla de decisión escrita a partir de la máquina de estados de
/// `docs/architecture/02-modelo-de-datos.md`, sin mirar la implementación.
SosStatus _expected(
  SosDelivery delivery,
  int? count,
  List<EmergencyAck> acks, {
  required bool resolved,
}) {
  if (resolved) return SosStatus.resolved;
  switch (delivery) {
    case SosDelivery.failed:
      return SosStatus.failed;
    case SosDelivery.queued:
      return SosStatus.queued;
    case SosDelivery.sending:
      return SosStatus.sending;
    case SosDelivery.sent:
      final seenByOther = acks.map((a) => a.uid).any((uid) => uid != _author);
      if (seenByOther) return SosStatus.acknowledged;
      if (count != null && count >= 0) return SosStatus.notified;
      return SosStatus.sent;
  }
}

void main() {
  group('EmergencyAlert.status: todas las combinaciones', () {
    test('coincide con la tabla de decisión documentada', () {
      final reached = <SosStatus>{};
      var combinations = 0;
      for (final delivery in SosDelivery.values) {
        for (final count in _counts) {
          for (final MapEntry(key: ackLabel, value: acks) in _ackSets.entries) {
            for (final resolved in [false, true]) {
              final alert = _alert(
                delivery: delivery,
                notifiedCount: count,
                acks: acks,
                resolvedAt: resolved ? _resolvedAt : null,
              );
              final expected = _expected(
                delivery,
                count,
                acks,
                resolved: resolved,
              );
              expect(
                alert.status,
                expected,
                reason:
                    'delivery=$delivery, count=$count, $ackLabel, '
                    'resolved=$resolved',
              );
              reached.add(alert.status);
              combinations++;
            }
          }
        }
      }
      expect(combinations, 4 * 4 * 4 * 2);
      expect(reached, SosStatus.values.toSet());
    });

    test('invariantes honestos en todas las combinaciones', () {
      for (final delivery in SosDelivery.values) {
        for (final count in _counts) {
          for (final acks in _ackSets.values) {
            for (final resolvedAt in [null, _resolvedAt]) {
              final alert = _alert(
                delivery: delivery,
                notifiedCount: count,
                acks: acks,
                resolvedAt: resolvedAt,
              );
              final status = alert.status;
              final why = '$delivery/$count/${acks.length}/$resolvedAt';

              // Nunca "confirmada" sin la confirmación de otro integrante.
              if (status == SosStatus.acknowledged) {
                expect(acks.any((a) => a.uid != _author), isTrue, reason: why);
              }
              // Nunca "notificada" sin un recuento válido.
              if (status == SosStatus.notified) {
                expect(count, isNotNull, reason: why);
                expect(count, greaterThanOrEqualTo(0), reason: why);
              }
              // Registrada, notificada o confirmada exige confirmación del
              // servidor.
              if (const {
                SosStatus.sent,
                SosStatus.notified,
                SosStatus.acknowledged,
              }.contains(status)) {
                expect(delivery, SosDelivery.sent, reason: why);
              }
              expect(status == SosStatus.resolved, resolvedAt != null);
              if (status == SosStatus.failed) {
                expect(delivery, SosDelivery.failed, reason: why);
              }
            }
          }
        }
      }
    });
  });

  group('EmergencyAlert.status: casos concretos', () {
    test('cada fase de envío sin datos del servidor', () {
      expect(_alert(delivery: SosDelivery.queued).status, SosStatus.queued);
      expect(_alert(delivery: SosDelivery.sending).status, SosStatus.sending);
      expect(_alert().status, SosStatus.sent);
      expect(
        _alert(delivery: SosDelivery.failed, failureCode: 'not-member').status,
        SosStatus.failed,
      );
    });

    test('enviada con recuento conocido está notificada, también con 0', () {
      // 0 es un dato real: "Nadie pudo ser notificado".
      expect(_alert(notifiedCount: 0).status, SosStatus.notified);
      expect(_alert(notifiedCount: 3).status, SosStatus.notified);
    });

    test('un recuento negativo no es un recuento: queda registrada', () {
      expect(_alert(notifiedCount: -1).status, SosStatus.sent);
    });

    test('confirmada solo con el ack de otro integrante', () {
      expect(_alert(acks: [_ack(_other)]).status, SosStatus.acknowledged);
      expect(
        _alert(notifiedCount: 2, acks: [_ack(_other)]).status,
        SosStatus.acknowledged,
      );
      // Un ack sin recuento de push también vale: alguien la vio en la app.
      expect(
        _alert(notifiedCount: 0, acks: [_ack(_other)]).status,
        SosStatus.acknowledged,
      );
    });

    test('el ack de quien pidió ayuda no la marca como vista por otros', () {
      expect(_alert(acks: [_ack(_author)]).status, SosStatus.sent);
      expect(
        _alert(notifiedCount: 2, acks: [_ack(_author)]).status,
        SosStatus.notified,
      );
    });

    test('mientras no se confirma el envío, la fase local manda', () {
      // Datos incoherentes (acks o recuento sin confirmación propia): se
      // muestra la fase que ofrece reintentar y llamar al 123.
      for (final delivery in [SosDelivery.queued, SosDelivery.sending]) {
        final alert = _alert(
          delivery: delivery,
          notifiedCount: 4,
          acks: [_ack(_other)],
        );
        expect(
          alert.status,
          delivery == SosDelivery.queued ? SosStatus.queued : SosStatus.sending,
        );
      }
      expect(
        _alert(
          delivery: SosDelivery.failed,
          notifiedCount: 4,
          acks: [_ack(_other)],
        ).status,
        SosStatus.failed,
      );
    });

    test('terminada tiene prioridad sobre cualquier otro dato', () {
      for (final delivery in SosDelivery.values) {
        expect(
          _alert(
            delivery: delivery,
            notifiedCount: 1,
            acks: [_ack(_other)],
            resolvedAt: _resolvedAt,
          ).status,
          SosStatus.resolved,
          reason: '$delivery',
        );
      }
    });

    test('recorrido feliz de la máquina de estados', () {
      var alert = _alert(delivery: SosDelivery.queued);
      expect(alert.status, SosStatus.queued);
      alert = alert.copyWith(delivery: SosDelivery.sending);
      expect(alert.status, SosStatus.sending);
      alert = alert.copyWith(delivery: SosDelivery.sent);
      expect(alert.status, SosStatus.sent);
      alert = alert.copyWith(notifiedCount: 2);
      expect(alert.status, SosStatus.notified);
      alert = alert.copyWith(acks: [_ack(_other)]);
      expect(alert.status, SosStatus.acknowledged);
      alert = alert.copyWith(resolvedAt: _resolvedAt);
      expect(alert.status, SosStatus.resolved);
    });
  });

  group('EmergencyAlert.isActive', () {
    test('activa salvo terminada o fallida, en todas las combinaciones', () {
      for (final delivery in SosDelivery.values) {
        for (final resolvedAt in [null, _resolvedAt]) {
          for (final acks in _ackSets.values) {
            final alert = _alert(
              delivery: delivery,
              acks: acks,
              resolvedAt: resolvedAt,
              notifiedCount: 1,
            );
            expect(
              alert.isActive,
              resolvedAt == null && delivery != SosDelivery.failed,
              reason: '$delivery/$resolvedAt',
            );
          }
        }
      }
    });

    test('en cola o enviándose sigue activa: aún se intenta avisar', () {
      expect(_alert(delivery: SosDelivery.queued).isActive, isTrue);
      expect(_alert(delivery: SosDelivery.sending).isActive, isTrue);
    });
  });

  group('EmergencyAlert.acknowledgedBy', () {
    test('indica si un integrante concreto confirmó', () {
      final alert = _alert(acks: [_ack(_other), _ack('u-tercero')]);
      expect(alert.acknowledgedBy(_other), isTrue);
      expect(alert.acknowledgedBy('u-tercero'), isTrue);
      expect(alert.acknowledgedBy(_author), isFalse);
      expect(alert.acknowledgedBy('u-desconocido'), isFalse);
      expect(_alert().acknowledgedBy(_other), isFalse);
    });
  });

  group('EmergencyAlert.copyWith', () {
    final location = GeoPoint(-40, -30);

    test('conserva identidad, autora, fecha y ubicación', () {
      final original = _alert(location: location, delivery: SosDelivery.queued);
      final copy = original.copyWith(
        delivery: SosDelivery.sent,
        notifiedCount: 1,
        acks: [_ack(_other)],
        resolvedAt: _resolvedAt,
      );
      expect(copy.id, original.id);
      expect(copy.familyId, original.familyId);
      expect(copy.uid, original.uid);
      expect(copy.createdAt, original.createdAt);
      expect(copy.location, location);
    });

    test('sin argumentos conserva todos los campos', () {
      final acks = [_ack(_other)];
      final original = _alert(
        location: location,
        notifiedCount: 2,
        acks: acks,
        resolvedAt: _resolvedAt,
      );
      final copy = original.copyWith();
      expect(copy.delivery, original.delivery);
      expect(copy.notifiedCount, 2);
      expect(copy.acks, same(acks));
      expect(copy.resolvedAt, _resolvedAt);
      expect(copy.failureCode, isNull);
      expect(copy.location, location);
    });

    test('cambia cada campo indicado sin tocar los demás', () {
      final original = _alert(delivery: SosDelivery.sending);
      expect(
        original.copyWith(delivery: SosDelivery.sent).delivery,
        SosDelivery.sent,
      );
      final counted = original.copyWith(notifiedCount: 5);
      expect(counted.notifiedCount, 5);
      expect(counted.delivery, SosDelivery.sending);
      final acked = original.copyWith(acks: [_ack(_other)]);
      expect(acked.acks.single.uid, _other);
      expect(acked.notifiedCount, isNull);
      final resolved = original.copyWith(resolvedAt: _resolvedAt);
      expect(resolved.resolvedAt, _resolvedAt);
      expect(resolved.acks, isEmpty);
    });

    test('no modifica la alerta original', () {
      final original = _alert();
      final copy = original.copyWith(
        delivery: SosDelivery.failed,
        notifiedCount: 3,
        acks: [_ack(_other)],
        resolvedAt: _resolvedAt,
        failureCode: 'rate-limited',
      );
      expect(copy.failureCode, 'rate-limited');
      expect(original.delivery, SosDelivery.sent);
      expect(original.notifiedCount, isNull);
      expect(original.acks, isEmpty);
      expect(original.resolvedAt, isNull);
      expect(original.failureCode, isNull);
    });

    test('no borra el recuento ni la resolución (son definitivos)', () {
      final original = _alert(notifiedCount: 2, resolvedAt: _resolvedAt);
      final copy = original.copyWith();
      expect(copy.notifiedCount, 2);
      expect(copy.resolvedAt, _resolvedAt);
    });

    test('al fallar guarda el código del fallo', () {
      final failed = _alert(delivery: SosDelivery.sending)
          .copyWith(delivery: SosDelivery.failed, failureCode: 'not-member');
      expect(failed.status, SosStatus.failed);
      expect(failed.failureCode, 'not-member');
      expect(failed.isActive, isFalse);
    });

    test('al reintentar una alerta fallida descarta el código antiguo', () {
      final failed = _alert(
        delivery: SosDelivery.failed,
        failureCode: 'not-member',
      );
      final retried = failed.copyWith(delivery: SosDelivery.queued);
      expect(retried.status, SosStatus.queued);
      expect(retried.failureCode, isNull);
      expect(retried.isActive, isTrue);

      final sent = retried.copyWith(delivery: SosDelivery.sent);
      expect(sent.failureCode, isNull);
    });

    test('mientras sigue fallida conserva o reemplaza el código', () {
      final failed = _alert(
        delivery: SosDelivery.failed,
        failureCode: 'not-member',
      );
      expect(
        failed.copyWith(resolvedAt: _resolvedAt).failureCode,
        'not-member',
      );
      expect(
        failed.copyWith(delivery: SosDelivery.failed).failureCode,
        'not-member',
      );
      expect(
        failed.copyWith(failureCode: 'rate-limited').failureCode,
        'rate-limited',
      );
    });

    test('un código indicado explícitamente siempre se respeta', () {
      final copy = _alert(
        delivery: SosDelivery.failed,
        failureCode: 'x-y',
      ).copyWith(delivery: SosDelivery.queued, failureCode: 'network');
      expect(copy.failureCode, 'network');
    });
  });

  group('SosRules', () {
    test('confirmación deliberada y límite de frecuencia documentados', () {
      expect(SosRules.holdToActivate, const Duration(seconds: 2));
      expect(SosRules.cancelWindow, const Duration(seconds: 5));
      expect(SosRules.maxPerHour, 5);
    });
  });
}
