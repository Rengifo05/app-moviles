import 'package:flutter_test/flutter_test.dart';
import 'package:nexo_familia/infrastructure/sync/outbox.dart';

import 'outbox_support.dart';

/// Contrato de [OutboxStore]: se verifica igual en memoria y en Drift para
/// que las pruebas del procesador con la versión en memoria sean fieles.
void main() {
  final t0 = DateTime.utc(2026, 1, 1, 12);

  for (final variant in outboxStoreVariants()) {
    group('OutboxStore ${variant.name}', () {
      late OutboxStore store;

      setUp(() => store = variant.open());
      tearDown(variant.close);

      Future<List<String>> dueIds(DateTime now) async => [
        for (final e in await store.due(now)) e.id,
      ];

      test(
        'conserva todos los campos (fechas en UTC con milisegundos)',
        () async {
          final created = t0.add(const Duration(milliseconds: 123));
          final next = t0.add(const Duration(seconds: 5, milliseconds: 7));
          await store.enqueue(
            entry(
              opA,
              createdAt: created,
              kind: 'sos',
              payload: {
                'alertId': opA,
                'at': created,
                'tags': ['a', 1, true, null],
              },
              priority: 10,
              attempts: 2,
              nextAttemptAt: next,
              lastErrorCode: 'network',
            ),
          );

          final found = await store.find(opA);
          expect(found, isNotNull);
          found!;
          expect(found.kind, 'sos');
          expect(found.familyId, familyId);
          expect(found.payload, {
            'alertId': opA,
            'at': created,
            'tags': ['a', 1, true, null],
          });
          expect(found.priority, 10);
          expect(found.status, OutboxStatus.pending);
          expect(found.attempts, 2);
          expect(found.nextAttemptAt, next);
          expect(found.nextAttemptAt!.isUtc, isTrue);
          expect(found.createdAt, created);
          expect(found.createdAt.isUtc, isTrue);
          expect(found.lastErrorCode, 'network');
        },
      );

      test(
        'un payload que no es JSON falla de forma asíncrona y no se guarda',
        () async {
          final enqueued = store.enqueue(
            entry(opA, createdAt: t0, payload: {'valor': Object()}),
          );
          await expectLater(enqueued, throwsUnsupportedError);
          expect(await store.find(opA), isNull);
        },
      );

      test('find de un id inexistente devuelve null', () async {
        expect(await store.find('no-existe'), isNull);
      });

      test(
        'enqueue es idempotente: el mismo id no duplica ni sobrescribe',
        () async {
          await store.enqueue(entry(opA, createdAt: t0, payload: {'v': 1}));
          await store.enqueue(
            entry(
              opA,
              createdAt: t0.add(const Duration(minutes: 1)),
              payload: {'v': 2},
              priority: 9,
            ),
          );

          final all = await store.watch().first;
          expect(all, hasLength(1));
          expect(all.single.payload, {'v': 1});
          expect(all.single.priority, 0);
          expect(all.single.createdAt, t0);
        },
      );

      group('due', () {
        test(
          'ordena por prioridad descendente y luego por antigüedad',
          () async {
            await store.enqueue(entry(opA, createdAt: t0));
            await store.enqueue(
              entry(
                opB,
                createdAt: t0.add(const Duration(seconds: 2)),
                kind: 'sos',
                priority: 10,
              ),
            );
            await store.enqueue(
              entry(opC, createdAt: t0.subtract(const Duration(seconds: 1))),
            );

            expect(await dueIds(t0.add(const Duration(minutes: 1))), [
              opB,
              opC,
              opA,
            ]);
          },
        );

        test(
          'a igual prioridad y fecha, respeta el orden de inserción',
          () async {
            for (final id in [opC, opA, opB]) {
              await store.enqueue(entry(id, createdAt: t0));
            }
            expect(await dueIds(t0), [opC, opA, opB]);
          },
        );

        test('distingue fechas creadas en el mismo segundo', () async {
          await store.enqueue(
            entry(opA, createdAt: t0.add(const Duration(milliseconds: 900))),
          );
          await store.enqueue(
            entry(opB, createdAt: t0.add(const Duration(milliseconds: 100))),
          );
          expect(await dueIds(t0.add(const Duration(seconds: 1))), [opB, opA]);
        });

        test(
          'sin nextAttemptAt está vencida; con fecha, solo al llegar',
          () async {
            final next = t0.add(const Duration(seconds: 4));
            await store.enqueue(entry(opA, createdAt: t0));
            await store.enqueue(entry(opB, createdAt: t0, nextAttemptAt: next));

            expect(await dueIds(t0), [opA]);
            expect(
              await dueIds(next.subtract(const Duration(milliseconds: 1))),
              [opA],
            );
            expect(await dueIds(next), [opA, opB]);
          },
        );

        test('excluye las entradas sending y failed', () async {
          await store.enqueue(entry(opA, createdAt: t0));
          await store.enqueue(entry(opB, createdAt: t0));
          await store.enqueue(entry(opC, createdAt: t0));
          await store.markSending(opA, t0);
          await store.markFailed(opB, errorCode: 'validation', now: t0);

          expect(await dueIds(t0), [opC]);
        });
      });

      group('nextAttemptAt', () {
        test('sin entradas pendientes es null', () async {
          expect(await store.nextAttemptAt(), isNull);
          await store.enqueue(entry(opA, createdAt: t0));
          await store.enqueue(entry(opB, createdAt: t0));
          await store.markSending(opA, t0);
          await store.markFailed(opB, errorCode: 'validation', now: t0);
          expect(await store.nextAttemptAt(), isNull);
        });

        test('devuelve el próximo vencimiento entre las pendientes', () async {
          final soon = t0.add(const Duration(seconds: 3, milliseconds: 250));
          await store.enqueue(
            entry(
              opA,
              createdAt: t0,
              nextAttemptAt: t0.add(const Duration(minutes: 1)),
            ),
          );
          await store.enqueue(entry(opB, createdAt: t0, nextAttemptAt: soon));
          // Una fallida con fecha anterior no cuenta.
          await store.enqueue(
            entry(
              opC,
              createdAt: t0,
              nextAttemptAt: t0.add(const Duration(seconds: 1)),
            ),
          );
          await store.markFailed(opC, errorCode: 'validation', now: t0);

          final next = await store.nextAttemptAt();
          expect(next, soon);
          expect(next!.isUtc, isTrue);
        });

        test('una entrada sin nextAttemptAt cuenta como vencida', () async {
          // Creada con un reloj adelantado: aun así ya está vencida.
          final future = t0.add(const Duration(hours: 1));
          await store.enqueue(
            entry(
              opA,
              createdAt: t0,
              nextAttemptAt: t0.add(const Duration(minutes: 10)),
            ),
          );
          await store.enqueue(entry(opB, createdAt: future));

          final next = await store.nextAttemptAt();
          expect(next, isNotNull);
          expect(next!.isAfter(t0), isFalse);
          expect(await dueIds(t0), contains(opB));
        });
      });

      test(
        'markSending, scheduleRetry y markFailed actualizan el estado',
        () async {
          await store.enqueue(entry(opA, createdAt: t0));

          await store.markSending(opA, t0);
          expect((await store.find(opA))!.status, OutboxStatus.sending);

          final retryAt = t0.add(const Duration(seconds: 2));
          await store.scheduleRetry(
            opA,
            attempts: 1,
            nextAttemptAt: retryAt,
            errorCode: 'network',
            now: t0,
          );
          var found = (await store.find(opA))!;
          expect(found.status, OutboxStatus.pending);
          expect(found.attempts, 1);
          expect(found.nextAttemptAt, retryAt);
          expect(found.lastErrorCode, 'network');

          await store.markFailed(opA, errorCode: 'validation', now: t0);
          found = (await store.find(opA))!;
          expect(found.status, OutboxStatus.failed);
          expect(found.attempts, 1);
          expect(found.lastErrorCode, 'validation');
        },
      );

      test(
        'requeue vuelve a pending y la entrada vence de inmediato',
        () async {
          await store.enqueue(
            entry(
              opA,
              createdAt: t0,
              nextAttemptAt: t0.add(const Duration(minutes: 5)),
            ),
          );
          await store.markFailed(opA, errorCode: 'validation', now: t0);

          await store.requeue(opA, t0);
          final found = (await store.find(opA))!;
          expect(found.status, OutboxStatus.pending);
          expect(found.nextAttemptAt, isNull);
          expect(await dueIds(t0), [opA]);
        },
      );

      test(
        'recoverInterrupted devuelve sending a pending sin tocar failed',
        () async {
          await store.enqueue(entry(opA, createdAt: t0));
          await store.enqueue(entry(opB, createdAt: t0));
          await store.enqueue(entry(opC, createdAt: t0));
          await store.markSending(opA, t0);
          await store.markSending(opB, t0);
          await store.markFailed(opC, errorCode: 'validation', now: t0);

          await store.recoverInterrupted(t0);

          expect((await store.find(opA))!.status, OutboxStatus.pending);
          expect((await store.find(opB))!.status, OutboxStatus.pending);
          expect((await store.find(opC))!.status, OutboxStatus.failed);
        },
      );

      test('remove elimina la entrada', () async {
        await store.enqueue(entry(opA, createdAt: t0));
        await store.remove(opA);
        expect(await store.find(opA), isNull);
        expect(await store.due(t0), isEmpty);
      });

      test('watch filtra por tipo y familia y emite los cambios', () async {
        await store.enqueue(entry(opA, createdAt: t0, kind: 'sos'));
        await store.enqueue(
          entry(opB, createdAt: t0.add(const Duration(seconds: 1))),
        );
        await store.enqueue(
          entry(
            opC,
            createdAt: t0.add(const Duration(seconds: 2)),
            kind: 'sos',
            family: 'otra-familia',
          ),
        );

        List<String> ids(List<OutboxEntry> list) => [
          for (final e in list) e.id,
        ];
        expect(ids(await store.watch().first), [opA, opB, opC]);
        expect(ids(await store.watch(kind: 'sos').first), [opA, opC]);
        expect(ids(await store.watch(familyId: familyId).first), [opA, opB]);
        expect(ids(await store.watch(kind: 'sos', familyId: familyId).first), [
          opA,
        ]);

        final emitted = <List<String>>[];
        final sub = store
            .watch(kind: 'sos')
            .listen((list) => emitted.add(ids(list)));
        await pumpEventQueue();
        await store.remove(opA);
        await pumpEventQueue();
        await sub.cancel();
        expect(emitted.first, [opA, opC]);
        expect(emitted.last, [opC]);
      });
    });
  }
}
