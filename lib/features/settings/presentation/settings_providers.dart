import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexo_familia/features/settings/domain/preferences.dart';

final preferencesRepositoryProvider = Provider<PreferencesRepository>(
  (ref) =>
      throw UnimplementedError('preferencesRepositoryProvider: ver bootstrap'),
);

final preferencesProvider = StreamProvider<AppPreferences>(
  (ref) => ref.watch(preferencesRepositoryProvider).watch(),
);
