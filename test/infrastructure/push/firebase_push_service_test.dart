import 'package:flutter_test/flutter_test.dart';
import 'package:nexo_familia/features/notifications/domain/push.dart';
import 'package:nexo_familia/infrastructure/push/firebase_push_service.dart';

void main() {
  test('un aviso SOS válido abre esa alerta', () {
    expect(
      sosOpenOf({'type': 'sos', 'familyId': 'f1', 'alertId': 'a1'}),
      const PushOpen(familyId: 'f1', alertId: 'a1'),
    );
  });

  test('datos incompletos o de otro tipo no abren nada', () {
    for (final data in <Map<String, dynamic>>[
      {},
      {'type': 'otro', 'familyId': 'f1', 'alertId': 'a1'},
      {'type': 'sos', 'familyId': 'f1'},
      {'type': 'sos', 'alertId': 'a1'},
      {'type': 'sos', 'familyId': '', 'alertId': 'a1'},
      {'type': 'sos', 'familyId': 'f1', 'alertId': ''},
      {'type': 'sos', 'familyId': 1, 'alertId': 'a1'},
    ]) {
      expect(sosOpenOf(data), isNull, reason: '$data');
    }
  });
}
