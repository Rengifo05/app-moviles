import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexo_familia/features/authentication/presentation/auth_providers.dart';
import 'package:nexo_familia/features/family/domain/family.dart';
import 'package:riverpod/misc.dart';

final familyRepositoryProvider = Provider<FamilyRepository>(
  (ref) => throw UnimplementedError('familyRepositoryProvider: ver bootstrap'),
);

/// Familias del usuario actual. Vacío sin sesión.
final myFamiliesProvider = StreamProvider<List<FamilyGroup>>((ref) {
  final user = ref.watch(currentUserProvider).value;
  if (user == null) return Stream.value(const []);
  return ref.watch(familyRepositoryProvider).watchMyFamilies();
});

/// Integrantes de una familia.
final StreamProviderFamily<List<FamilyMember>, String> familyMembersProvider =
    StreamProvider.family<List<FamilyMember>, String>(
      (ref, familyId) =>
          ref.watch(familyRepositoryProvider).watchMembers(familyId),
    );

/// Familia activa de la sesión (null si no hay ninguna). La calcula la raíz
/// de composición a partir de la sesión; las pantallas solo la leen.
final activeFamilyIdProvider = Provider<String?>(
  (ref) => throw UnimplementedError('activeFamilyIdProvider: ver app/'),
);

/// Familia activa con el rol del usuario actual en ella.
///
/// Carga mientras llegan las familias; `null` si no hay familia activa o si
/// la familia activa ya no figura entre las del usuario (p. ej. justo
/// después de salir de ella).
final activeFamilyProvider = Provider<AsyncValue<FamilyGroup?>>((ref) {
  final familyId = ref.watch(activeFamilyIdProvider);
  if (familyId == null) return const AsyncData(null);
  return ref
      .watch(myFamiliesProvider)
      .whenData(
        (families) => families.where((f) => f.id == familyId).firstOrNull,
      );
});

/// Si la persona ya pertenece a alguna familia: crear o unirse a otra la
/// devuelve a la pestaña Familia en lugar de esperar al cambio de sesión.
/// Las pantallas lo observan en `build` para tenerlo cargado al enviar.
final hasAnyFamilyProvider = Provider<bool>(
  (ref) => ref.watch(myFamiliesProvider).value?.isNotEmpty ?? false,
);
