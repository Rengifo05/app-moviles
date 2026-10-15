import 'package:flutter_test/flutter_test.dart';
import 'package:nexo_familia/core/failure.dart';
import 'package:nexo_familia/core/result.dart';

void main() {
  const failure = Failure.network();

  group('Result', () {
    test('Ok expone su valor y no tiene fallo', () {
      const Result<int> result = Ok(3);
      expect(result.isOk, isTrue);
      expect(result.valueOrNull, 3);
      expect(result.failureOrNull, isNull);
    });

    test('Err expone su fallo y no tiene valor', () {
      const Result<int> result = Err(failure);
      expect(result.isOk, isFalse);
      expect(result.valueOrNull, isNull);
      expect(result.failureOrNull, failure);
    });

    test('fold elige la rama correcta', () {
      String describe(Result<int> r) =>
          r.fold(ok: (v) => 'ok $v', err: (f) => 'err ${f.code}');
      expect(describe(const Ok(1)), 'ok 1');
      expect(describe(const Err(failure)), 'err network');
    });

    test('map transforma el valor y conserva el fallo', () {
      expect(const Ok(2).map((v) => v * 10), const Ok(20));
      expect(
        const Err<int>(failure).map((v) => v * 10),
        const Err<int>(failure),
      );
    });

    test('la igualdad es simétrica respecto al argumento de tipo', () {
      const Result<int> a = Ok(1);
      const Result<num> b = Ok<num>(1);
      expect(a == b, b == a);
      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('then encadena y corta en el primer fallo', () async {
      var called = false;
      final ok = await const Ok(2).then((v) async => Ok('v$v'));
      expect(ok, const Ok('v2'));

      final err = await const Err<int>(failure).then((v) async {
        called = true;
        return Ok('v$v');
      });
      expect(err, const Err<String>(failure));
      expect(called, isFalse);
    });
  });

  group('Failure', () {
    test('la igualdad ignora la causa', () {
      expect(
        Failure.network('timeout', Exception('a')),
        Failure.network('timeout', Exception('b')),
      );
    });

    test('toString no incluye la causa', () {
      final f = Failure.unexpected('boom', Exception('lat=4.711,-74.07'));
      expect(f.toString(), 'Failure(unexpected, boom)');
    });

    test(
      'solo red, indisponibilidad y límite de frecuencia son transitorios',
      () {
        final transient = FailureKind.values
            .where((k) => k.isTransient)
            .toSet();
        expect(transient, {
          FailureKind.network,
          FailureKind.unavailable,
          FailureKind.rateLimited,
        });
      },
    );
  });
}
