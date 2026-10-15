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
