import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexo_familia/core/failure.dart';
import 'package:nexo_familia/core/logging/safe_logger.dart';
import 'package:nexo_familia/core/result.dart';
import 'package:nexo_familia/infrastructure/sync/backoff.dart';
import 'package:nexo_familia/infrastructure/sync/outbox.dart';

import '../../helpers/fakes.dart';
import 'memory_outbox_store.dart';
import 'outbox_support.dart';

/// Decorador que puede detener `nextAttemptAt` para reproducir la carrera
/// entre un `drain()` nuevo y la programación del temporizador, o hacer
/// fallar una vez `scheduleRetry`.
final class _GatedStore implements OutboxStore {
  new(this._inner);

  final OutboxStore _inner;
  Completer<void>? nextAttemptGate;
  int nextAttemptCalls = 0;

  /// Si no es null, el próximo `scheduleRetry` lanza este error.
  Error? scheduleRetryError;

  @override
  Future<void> enqueue(OutboxEntry entry) => _inner.enqueue(entry);

  @override
  Future<List<OutboxEntry>> due(DateTime now) => _inner.due(now);

  @override
  Future<DateTime?> nextAttemptAt() async {
    nextAttemptCalls++;
    final gate = nextAttemptGate;
    if (gate != null) await gate.future;
    return await _inner.nextAttemptAt();
  }

  @override
  Future<void> markSending(String id, DateTime now) =>
      _inner.markSending(id, now);

  @override
  Future<void> remove(String id) => _inner.remove(id);

  @override
  Future<void> scheduleRetry(
    String id, {
    required int attempts,
    required DateTime nextAttemptAt,
    required String errorCode,
    required DateTime now,
  }) async {
    final error = scheduleRetryError;
    scheduleRetryError = null;
    if (error != null) throw error;
    await _inner.scheduleRetry(
      id,
      attempts: attempts,
      nextAttemptAt: nextAttemptAt,
      errorCode: errorCode,
      now: now,
    );
  }

  @override
  Future<void> markFailed(
    String id, {
    required String errorCode,
    required DateTime now,
  }) => _inner.markFailed(id, errorCode: errorCode, now: now);

  @override
  Future<void> requeue(String id, DateTime now) => _inner.requeue(id, now);

  @override
  Future<void> recoverInterrupted(DateTime now) =>
      _inner.recoverInterrupted(now);

  @override
  Stream<List<OutboxEntry>> watch({String? kind, String? familyId}) =>
      _inner.watch(kind: kind, familyId: familyId);

  @override
  Future<OutboxEntry?> find(String id) => _inner.find(id);
}

void main() {
  final t0 = DateTime.utc(2026, 1, 1, 12);

  for (final variant in outboxStoreVariants()) {
    group('OutboxProcessor con almacén ${variant.name}', () {
      late OutboxStore store;
      late FakeClock clock;
      late MemoryLogSink sink;
      late FakeHandler checkIns;
      late FakeHandler sos;

      setUp(() {
        store = variant.open();
        clock = FakeClock(t0);
        sink = MemoryLogSink();
        checkIns = FakeHandler();
        sos = FakeHandler();
      });

      tearDown(variant.close);

      OutboxProcessor processor({
        OutboxStore? using,
        Map<String, OutboxHandler>? handlers,
        Map<String, BackoffPolicy> policies = const {},
        double random = 0.5,
      }) => OutboxProcessor(
        store: using ?? store,
        handlers: handlers ?? {'checkIn': checkIns, 'sos': sos},
        clock: clock,
        logger: SafeLogger(sink: sink, clock: clock),
        policies: policies,
        random: () => random,
      );

      /// Avanza a la vez el reloj inyectado y el tiempo de los temporizadores.
      void elapse(FakeAsync async, Duration duration) {
        clock.advance(duration);
        async.elapse(duration);
      }

      Iterable<LogEntry> logs(String event) =>
          sink.entries.where((e) => e.event == event);

      test('envía por prioridad y antigüedad: el SOS primero', () async {
        final both = FakeHandler();
        await store.enqueue(entry(opA, createdAt: t0));
        await store.enqueue(
          entry(opB, createdAt: t0.add(const Duration(seconds: 1))),
        );
        await store.enqueue(
          entry(
            opC,
            createdAt: t0.add(const Duration(seconds: 2)),
            kind: 'sos',
            priority: 10,
          ),
        );

        await processor(handlers: {'checkIn': both, 'sos': both}).drain();

        expect(both.sentIds, [opC, opA, opB]);
        expect(await store.watch().first, isEmpty);
      });

      test('un envío correcto elimina la entrada y lo registra', () async {
        await store.enqueue(entry(opA, createdAt: t0));

        await processor().drain();

        expect(checkIns.sentIds, [opA]);
        expect(await store.find(opA), isNull);
        final sent = logs('outbox.sent').single;
        expect(sent.level, LogLevel.info);
        expect(sent.fields, {
          'opId': opA,
          'operation': 'checkIn',
          'attempt': 1,
        });
      });

      test(
        'un error transitorio reprograma con espera de 2, 4 y 8 s',
        () async {
          checkIns.respond = (_) => const Err(Failure.network());
          await store.enqueue(entry(opA, createdAt: t0));
          final p = processor();

          for (final (attempt, seconds) in [(1, 2), (2, 4), (3, 8)]) {
            await p.drain();
            final found = (await store.find(opA))!;
            expect(found.status, OutboxStatus.pending);
            expect(found.attempts, attempt);
            expect(found.lastErrorCode, 'network');
            expect(
              found.nextAttemptAt,
              clock.now().add(Duration(seconds: seconds)),
            );

            // Antes de vencer no se reintenta.
            clock.advance(Duration(seconds: seconds) - _ms);
            await p.drain();
            expect(checkIns.sent, hasLength(attempt));
            clock.advance(_ms);
          }

          expect(
            [for (final e in logs('outbox.retry_scheduled')) e.fields],
            [
              {
                'opId': opA,
                'operation': 'checkIn',
                'attempt': 1,
                'durationMs': 2000,
              },
              {
                'opId': opA,
                'operation': 'checkIn',
                'attempt': 2,
                'durationMs': 4000,
              },
              {
                'opId': opA,
                'operation': 'checkIn',
                'attempt': 3,
                'durationMs': 8000,
              },
            ],
          );
        },
      );

      test(
        'aplica la política de cada tipo: el SOS espera como mucho 30 s',
        () async {
          checkIns.respond = (_) => const Err(Failure.unavailable());
          sos.respond = (_) => const Err(Failure.unavailable());
          await store.enqueue(entry(opA, createdAt: t0, attempts: 9));
          await store.enqueue(
            entry(opB, createdAt: t0, kind: 'sos', priority: 10, attempts: 9),
          );

          // Con el máximo jitter posible el tope se respeta.
          await processor(
            policies: {'sos': BackoffPolicy.sos},
            random: 0.999,
          ).drain();

          final sosEntry = (await store.find(opB))!;
          expect(sosEntry.attempts, 10);
          expect(sosEntry.nextAttemptAt, t0.add(const Duration(seconds: 30)));
          final checkIn = (await store.find(opA))!;
          expect(checkIn.nextAttemptAt, t0.add(const Duration(minutes: 5)));
        },
      );

      test(
        'un error permanente marca la entrada como fallida sin reintentos',
        () async {
          const permanent = [
            Failure.validation('invalid-payload'),
            Failure.permissionDenied(),
            Failure.notFound(),
            Failure.conflict(),
            Failure.unauthenticated(),
          ];
          final ids = [opA, opB, opC, opD, opE];
          final byId = {
            for (var i = 0; i < ids.length; i++) ids[i]: permanent[i],
          };
          checkIns.respond = (e) => Err(byId[e.id]!);
          for (final id in ids) {
            await store.enqueue(entry(id, createdAt: t0));
          }
          final p = processor();

          await p.drain();

          for (final id in ids) {
            final found = (await store.find(id))!;
            expect(found.status, OutboxStatus.failed);
            expect(found.attempts, 0);
            expect(found.lastErrorCode, byId[id]!.code);
          }
          expect(await store.nextAttemptAt(), isNull);
          clock.advance(const Duration(hours: 1));
          await p.drain();
          expect(checkIns.sent, hasLength(ids.length));
          final warning = logs('outbox.failed').first;
          expect(warning.level, LogLevel.warning);
          expect(warning.fields, {
            'opId': opA,
            'operation': 'checkIn',
            'kind': 'validation',
            'code': 'invalid-payload',
          });
        },
      );

      test(
        'un manejador que lanza se reintenta y no detiene la bandeja',
        () async {
          checkIns.respond = (_) => throw StateError('fallo inesperado');
          await store.enqueue(entry(opA, createdAt: t0));
          await store.enqueue(
            entry(opB, createdAt: t0.add(const Duration(seconds: 1))),
          );
          await store.enqueue(
            entry(opC, createdAt: t0, kind: 'sos', priority: 10),
          );

          await processor().drain();

          expect(sos.sentIds, [opC]);
          expect(checkIns.sentIds, [opA, opB]);
          for (final id in [opA, opB]) {
            final found = (await store.find(id))!;
            expect(found.status, OutboxStatus.pending);
            expect(found.attempts, 1);
            expect(found.lastErrorCode, 'handler-threw');
            expect(found.nextAttemptAt, t0.add(const Duration(seconds: 2)));
          }
          expect(await store.find(opC), isNull);
        },
      );

      test(
        'un tipo desconocido se marca como fallido sin llamar a nadie',
        () async {
          await store.enqueue(entry(opA, createdAt: t0, kind: 'desconocido'));

          await processor().drain();

          expect(checkIns.sent, isEmpty);
          expect(sos.sent, isEmpty);
          final found = (await store.find(opA))!;
          expect(found.status, OutboxStatus.failed);
          expect(found.lastErrorCode, 'unknown-kind');
          final error = logs('outbox.unknown_kind').single;
          expect(error.level, LogLevel.error);
          expect(error.fields, {'opId': opA});
        },
      );

      test('el mismo id encolado dos veces se envía una sola vez', () async {
        await store.enqueue(entry(opA, createdAt: t0, payload: {'v': 1}));
        await store.enqueue(entry(opA, createdAt: t0, payload: {'v': 2}));

        await processor().drain();

        expect(checkIns.sentIds, [opA]);
        expect(checkIns.sent.single.payload, {'v': 1});
      });

      test('start recupera las entradas interrumpidas y las envía', () async {
        await store.enqueue(entry(opA, createdAt: t0));
        // La app se cerró a mitad de envío.
        await store.markSending(opA, t0);
        final p = processor();
        await p.drain();
        expect(checkIns.sent, isEmpty);

        await p.start();
        p.stop();

        expect(checkIns.sentIds, [opA]);
        expect(await store.find(opA), isNull);
      });

      test(
        'start durante un envío no devuelve a pending la entrada en curso',
        () async {
          final gate = Completer<VoidResult>();
          checkIns.respond = (_) => gate.future;
          await store.enqueue(entry(opA, createdAt: t0));
          final p = processor();

          final first = p.start();
          await pumpEventQueue();
          expect((await store.find(opA))!.status, OutboxStatus.sending);

          final second = p.start();
          await pumpEventQueue();
          expect((await store.find(opA))!.status, OutboxStatus.sending);

          gate.complete(const Ok(null));
          await Future.wait([first, second]);
          p.stop();
          expect(checkIns.sentIds, [opA]);
          expect(await store.find(opA), isNull);
        },
      );

      test('drain concurrente no envía dos veces la misma entrada', () async {
        final gate = Completer<VoidResult>();
        checkIns.respond = (_) => gate.future;
        await store.enqueue(entry(opA, createdAt: t0));
        await store.enqueue(
          entry(opB, createdAt: t0.add(const Duration(seconds: 1))),
        );
        final p = processor();

        final runs = [p.drain(), p.drain(), p.drain()];
        await pumpEventQueue();
        expect(checkIns.sentIds, [opA]);

        gate.complete(const Ok(null));
        await Future.wait(runs);
        expect(checkIns.sentIds, [opA, opB]);
        expect(await store.watch().first, isEmpty);
      });

      test(
        'un drain durante el envío repite la vuelta para lo nuevo',
        () async {
          final gate = Completer<VoidResult>();
          checkIns.respond = (e) => e.id == opA ? gate.future : const Ok(null);
          await store.enqueue(entry(opA, createdAt: t0));
          final p = processor();

          final first = p.drain();
          await pumpEventQueue();
          await store.enqueue(entry(opB, createdAt: t0));
          final second = p.drain();
          gate.complete(const Ok(null));
          await second;

          expect(checkIns.sentIds, [opA, opB]);
          await first;
        },
      );

      test(
        'un SOS que llega durante el envío de otras pasa delante del resto',
        () async {
          final gate = Completer<VoidResult>();
          final both = FakeHandler(
            (e) => e.id == opA ? gate.future : const Ok(null),
          );
          await store.enqueue(entry(opA, createdAt: t0));
          await store.enqueue(
            entry(opB, createdAt: t0.add(const Duration(seconds: 1))),
          );
          final p = processor(handlers: {'checkIn': both, 'sos': both});

          final run = p.drain();
          await pumpEventQueue();
          expect(both.sentIds, [opA]);
          // B ya estaba en la lista de esta vuelta; el SOS llega después.
          await store.enqueue(
            entry(
              opC,
              createdAt: t0.add(const Duration(seconds: 2)),
              kind: 'sos',
              priority: 10,
            ),
          );
          unawaited(p.drain());
          gate.complete(const Ok(null));
          await run;

          expect(both.sentIds, [opA, opC, opB]);
        },
      );

      test(
        'un drain mientras se programa el temporizador no pierde la entrada',
        () async {
          final gated = _GatedStore(store);
          await gated.enqueue(entry(opA, createdAt: t0));
          final p = processor(using: gated);
          gated.nextAttemptGate = Completer<void>();

          // Con start() el procesador programa el temporizador al terminar.
          final first = p.start();
          await pumpEventQueue();
          // A ya se envió y el procesador está consultando el próximo
          // vencimiento.
          expect(checkIns.sentIds, [opA]);
          expect(gated.nextAttemptCalls, 1);

          await gated.enqueue(entry(opB, createdAt: t0));
          final second = p.drain();
          gated.nextAttemptGate!.complete();
          await second;

          expect(checkIns.sentIds, [opA, opB]);
          await first;
          p.stop();
        },
      );

      test(
        'una entrada eliminada mientras se enviaban otras no se envía',
        () async {
          final gate = Completer<VoidResult>();
          checkIns.respond = (e) => e.id == opA ? gate.future : const Ok(null);
          await store.enqueue(entry(opA, createdAt: t0));
          await store.enqueue(
            entry(opB, createdAt: t0.add(const Duration(seconds: 1))),
          );
          await store.enqueue(
            entry(opC, createdAt: t0.add(const Duration(seconds: 2))),
          );
          final p = processor();

          final run = p.drain();
          await pumpEventQueue();
          // B se cancela y C falla en otro lugar mientras A se envía.
          await store.remove(opB);
          await store.markFailed(opC, errorCode: 'validation', now: t0);
          gate.complete(const Ok(null));
          await run;

          expect(checkIns.sentIds, [opA]);
          expect((await store.find(opC))!.status, OutboxStatus.failed);
        },
      );

      test('requeue permite reenviar una entrada fallida', () async {
        var calls = 0;
        checkIns.respond = (_) => calls++ == 0
            ? const Err(Failure.validation('invalid-payload'))
            : const Ok(null);
        await store.enqueue(entry(opA, createdAt: t0));
        final p = processor();

        await p.drain();
        expect((await store.find(opA))!.status, OutboxStatus.failed);

        await store.requeue(opA, clock.now());
        await p.drain();

        expect(checkIns.sentIds, [opA, opA]);
        expect(await store.find(opA), isNull);
      });

      test('los registros no contienen el payload ni datos privados', () async {
        const secrets = [
          'Persona Ficticia',
          '12.3456789',
          '-98.7654321',
          'tok-secreto-xyz',
          'desconocido',
          'familia-secreta',
        ];
        const payload = {
          'note': 'Persona Ficticia',
          'lat': 12.3456789,
          'lng': -98.7654321,
          'token': 'tok-secreto-xyz',
        };
        final responses = <String, FutureOr<VoidResult> Function()>{
          opA: () => const Ok(null),
          opB: () => const Err(Failure.network('network', 'tok-secreto-xyz')),
          opC: () => const Err(Failure.validation('invalid-payload')),
          opE: () => throw StateError('Persona Ficticia 12.3456789'),
        };
        checkIns.respond = (e) => responses[e.id]!();
        for (final id in [opA, opB, opC, opE]) {
          await store.enqueue(
            entry(
              id,
              createdAt: t0,
              payload: payload,
              family: 'familia-secreta',
            ),
          );
        }
        await store.enqueue(
          entry(
            opD,
            createdAt: t0,
            kind: 'desconocido',
            payload: payload,
            family: 'familia-secreta',
          ),
        );

        await processor().drain();

        expect(
          {for (final e in sink.entries) e.event},
          {
            'outbox.sent',
            'outbox.retry_scheduled',
            'outbox.failed',
            'outbox.unknown_kind',
          },
        );
        for (final log in sink.entries) {
          final text = log.toString();
          for (final secret in secrets) {
            expect(text, isNot(contains(secret)), reason: log.event);
          }
          // El procesador solo usa campos permitidos: nada se redacta.
          expect(log.fields.keys, everyElement(isIn(SafeLogger.allowedFields)));
          expect(log.fields.values, isNot(contains(SafeLogger.redactedValue)));
        }
      });

      group('temporizador', () {
        test('programa el siguiente intento y reintenta al vencer', () {
          fakeAsync((async) {
            var calls = 0;
            sos.respond = (_) =>
                ++calls < 3 ? const Err(Failure.network()) : const Ok(null);
            final p = processor(policies: {'sos': BackoffPolicy.sos});
            unawaited(
              store.enqueue(
                entry(opA, createdAt: t0, kind: 'sos', priority: 10),
              ),
            );
            unawaited(p.start());
            async.flushMicrotasks();
            expect(sos.sent, hasLength(1));
            expect(async.pendingTimers, hasLength(1));

            elapse(async, const Duration(milliseconds: 1999));
            expect(sos.sent, hasLength(1));
            elapse(async, _ms);
            expect(sos.sent, hasLength(2));

            elapse(async, const Duration(seconds: 4));
            expect(sos.sent, hasLength(3));
            // Enviado: ya no hay nada que esperar.
            expect(async.pendingTimers, isEmpty);
            p.stop();
          });
        });

        test('stop() cancela el temporizador pendiente', () {
          fakeAsync((async) {
            checkIns.respond = (_) => const Err(Failure.network());
            final p = processor();
            unawaited(store.enqueue(entry(opA, createdAt: t0)));
            unawaited(p.start());
            async.flushMicrotasks();
            expect(async.pendingTimers, hasLength(1));

            p.stop();
            expect(async.pendingTimers, isEmpty);
            elapse(async, const Duration(minutes: 10));
            expect(checkIns.sent, hasLength(1));
          });
        });

        test('stop() durante un envío no deja un temporizador al terminar', () {
          fakeAsync((async) {
            final gate = Completer<VoidResult>();
            checkIns.respond = (_) => gate.future;
            final p = processor();
            unawaited(store.enqueue(entry(opA, createdAt: t0)));
            unawaited(p.start());
            async.flushMicrotasks();

            p.stop();
            gate.complete(const Err(Failure.network()));
            async.flushMicrotasks();

            expect(_resolve(store.find(opA), async)!.attempts, 1);
            expect(async.pendingTimers, isEmpty);
          });
        });

        test(
          'un fallo del almacén tras enviar no deja la entrada en sending',
          () {
            fakeAsync((async) {
              final gated = _GatedStore(store)
                ..scheduleRetryError = StateError('base ocupada');
              var calls = 0;
              sos.respond = (_) =>
                  ++calls == 1 ? const Err(Failure.network()) : const Ok(null);
              final p = processor(
                using: gated,
                policies: {'sos': BackoffPolicy.sos},
              );
              unawaited(
                gated.enqueue(
                  entry(opA, createdAt: t0, kind: 'sos', priority: 10),
                ),
              );
              // El envío falla y guardar el reintento también: start() lo
              // propaga y la entrada queda en `sending`.
              unawaited(p.start().catchError((Object _) {}));
              async.flushMicrotasks();
              expect(sos.sent, hasLength(1));
              expect(
                _resolve(gated.find(opA), async)!.status,
                OutboxStatus.sending,
              );

              // Sin start() ni drain() externos se recupera y se reenvía.
              elapse(async, const Duration(seconds: 2));
              expect(sos.sent, hasLength(2));
              expect(_resolve(gated.find(opA), async), isNull);
              p.stop();
            });
          },
        );

        test('drain sin start no programa temporizadores', () {
          fakeAsync((async) {
            checkIns.respond = (_) => const Err(Failure.network());
            unawaited(store.enqueue(entry(opA, createdAt: t0)));
            unawaited(processor().drain());
            async.flushMicrotasks();

            expect(checkIns.sent, hasLength(1));
            expect(async.pendingTimers, isEmpty);
          });
        });

        test(
          'una entrada pendiente sin fecha programa un intento inmediato',
          () {
            fakeAsync((async) {
              final gate = Completer<VoidResult>();
              checkIns.respond = (e) =>
                  e.id == opA ? gate.future : const Ok(null);
              final p = processor();
              unawaited(store.enqueue(entry(opA, createdAt: t0)));
              unawaited(p.start());
              async.flushMicrotasks();
              // Llega B (creada con un reloj adelantado) sin que nadie llame
              // a drain(); al terminar con A se programa de inmediato.
              unawaited(
                store.enqueue(
                  entry(opB, createdAt: t0.add(const Duration(hours: 1))),
                ),
              );
              gate.complete(const Ok(null));
              async.flushMicrotasks();
              expect(checkIns.sentIds, [opA]);

              async.elapse(Duration.zero);
              expect(checkIns.sentIds, [opA, opB]);
              p.stop();
            });
          },
        );

        if (variant is MemoryStoreVariant) {
          test('un fallo del almacén al vencer se registra sin propagarse', () {
            fakeAsync((async) {
              final memory = store as MemoryOutboxStore;
              checkIns.respond = (_) => const Err(Failure.network());
              final p = processor();
              unawaited(memory.enqueue(entry(opA, createdAt: t0)));
              unawaited(p.start());
              async.flushMicrotasks();

              memory.dueError = StateError('detalle privado');
              elapse(async, const Duration(seconds: 2));

              final failure = logs('outbox.drain_failed').single;
              expect(failure.level, LogLevel.error);
              expect(failure.fields, {
                'feature': 'sync',
                'kind': 'unexpected',
                'code': 'drain-failed',
              });
              expect(failure.toString(), isNot(contains('privado')));

              // Un drain posterior funciona con normalidad.
              memory.dueError = null;
              checkIns.respond = null;
              unawaited(p.drain());
              async.flushMicrotasks();
              expect(checkIns.sent, hasLength(2));
              p.stop();
            });
          });

          test(
            'tras un fallo del almacén al vencer, reintenta solo con espera',
            () {
              fakeAsync((async) {
                final memory = store as MemoryOutboxStore;
                var calls = 0;
                sos.respond = (_) => ++calls == 1
                    ? const Err(Failure.network())
                    : const Ok(null);
                final p = processor(policies: {'sos': BackoffPolicy.sos});
                unawaited(
                  memory.enqueue(
                    entry(opA, createdAt: t0, kind: 'sos', priority: 10),
                  ),
                );
                unawaited(p.start());
                async.flushMicrotasks();
                expect(sos.sent, hasLength(1));

                memory.dueError = StateError('base ocupada');
                elapse(async, const Duration(seconds: 2));
                expect(logs('outbox.drain_failed'), hasLength(1));
                // Ni bucle inmediato ni abandono: un único reintento en espera.
                expect(async.pendingTimers, hasLength(1));
                expect(sos.sent, hasLength(1));

                // El almacén se recupera sin que nadie llame a start() ni a
                // drain(): el SOS se envía igualmente.
                memory.dueError = null;
                elapse(async, const Duration(seconds: 2));
                expect(sos.sent, hasLength(2));
                expect(_resolve(memory.find(opA), async), isNull);
                p.stop();
              });
            },
          );
        }
      });
    });
  }
}

const _ms = Duration(milliseconds: 1);

/// Resuelve [future] dentro de `fakeAsync` (sin `await`).
T _resolve<T>(Future<T> future, FakeAsync async) {
  late T value;
  var done = false;
  unawaited(
    future.then((v) {
      value = v;
      done = true;
    }),
  );
  async.flushMicrotasks();
  expect(done, isTrue, reason: 'el Future no terminó');
  return value;
}
