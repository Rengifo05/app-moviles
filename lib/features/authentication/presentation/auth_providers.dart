import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexo_familia/features/authentication/domain/auth.dart';

/// Implementación concreta inyectada por `app/bootstrap.dart`.
final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => throw UnimplementedError('authRepositoryProvider: ver bootstrap'),
);

/// Usuario de la sesión actual (null si no hay sesión).
final currentUserProvider = StreamProvider<AuthUser?>(
  (ref) => ref.watch(authRepositoryProvider).watchUser(),
);
