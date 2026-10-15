import 'package:flutter_test/flutter_test.dart';
import 'package:nexo_familia/core/failure.dart';
import 'package:nexo_familia/core/geo/geo_point.dart';
import 'package:nexo_familia/core/result.dart';
import 'package:nexo_familia/features/check_ins/domain/check_in.dart';
import 'package:nexo_familia/features/check_ins/domain/submit_check_in.dart';
import 'package:nexo_familia/features/location_sharing/domain/location.dart';

import '../../helpers/fakes.dart';

final class _RecordingRepository implements CheckInRepository {
  final List<CheckIn> submitted = [];
  Failure? fail;

  @override
  Future<Result<CheckIn>> submit(CheckIn checkIn) async {
    submitted.add(checkIn);
    return switch (fail) {
      final failure? => Err(failure),
      null => Ok(checkIn),
    };
  }

  @override
  Stream<List<CheckIn>> watchPending(String familyId) => const Stream.empty();
}

void main() {
  late _RecordingRepository repo;
  late FakeClock clock;
  late SubmitCheckIn submit;

  setUp(() {
    repo = _RecordingRepository();
    clock = FakeClock(DateTime.utc(2026, 10, 15, 15, 30));
    submit = SubmitCheckIn(repo, SequentialIdGenerator(), clock);
  });

  test('construye el check-in con id, hora y estado pendiente', () async {
    final result = await submit(
      familyId: 'fam',
      uid: 'ana',
      kind: CheckInKind.ok,
      message: '  Llegué  ',
    );
    final checkIn = repo.submitted.single;
    expect(result.valueOrNull, same(checkIn));
    expect(checkIn.id, 'id-1');
    expect(checkIn.familyId, 'fam');
    expect(checkIn.uid, 'ana');
    expect(checkIn.kind, CheckInKind.ok);
    expect(checkIn.createdAt, clock.now());
    expect(checkIn.delivery, DeliveryState.pending);
    expect(checkIn.message, 'Llegué');
    expect(checkIn.location, isNull);
  });

  test('cada envío es una operación nueva (id distinto)', () async {
    await submit(familyId: 'fam', uid: 'ana', kind: CheckInKind.ok);
    await submit(familyId: 'fam', uid: 'ana', kind: CheckInKind.ok);
    expect(repo.submitted.map((c) => c.id), ['id-1', 'id-2']);
  });

  test('un mensaje vacío o solo con espacios no se envía', () async {
    await submit(
      familyId: 'fam',
      uid: 'ana',
      kind: CheckInKind.needHelp,
      message: ' \n ',
    );
    expect(repo.submitted.single.message, isNull);
  });

  test('adjunta la ubicación solo si se le pasa', () async {
    final point = GeoPoint(4.5, -74.25);
    await submit(
      familyId: 'fam',
      uid: 'ana',
      kind: CheckInKind.needHelp,
      location: DeviceFix(
        point: point,
        accuracyMeters: 1000,
        capturedAt: clock.now(),
      ),
    );
    expect(repo.submitted.single.location, point);
  });

  test('valida el mensaje antes de llegar al repositorio', () async {
    final result = await submit(
      familyId: 'fam',
      uid: 'ana',
      kind: CheckInKind.ok,
      message: 'a' * 141,
    );
    expect(
      result.failureOrNull,
      const Failure.validation('check-in-message-too-long'),
    );
    expect(repo.submitted, isEmpty);
  });

  test('sin sesión o sin familia no se crea nada', () async {
    expect(
      (await submit(
        familyId: 'fam',
        uid: '',
        kind: CheckInKind.ok,
      )).failureOrNull,
      const Failure.unauthenticated(),
    );
    expect(
      (await submit(
        familyId: '',
        uid: 'ana',
        kind: CheckInKind.ok,
      )).failureOrNull,
      const Failure.validation(CheckInFailureCodes.noFamily),
    );
    expect(repo.submitted, isEmpty);
  });

  test('devuelve el fallo del repositorio', () async {
    repo.fail = const Failure.unexpected('check-in-not-saved');
    final result = await submit(
      familyId: 'fam',
      uid: 'ana',
      kind: CheckInKind.ok,
    );
    expect(
      result.failureOrNull,
      const Failure.unexpected('check-in-not-saved'),
    );
  });
}
