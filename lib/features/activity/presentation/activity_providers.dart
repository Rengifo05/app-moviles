import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexo_familia/features/activity/domain/activity.dart';
import 'package:riverpod/misc.dart';

final activityRepositoryProvider = Provider<ActivityRepository>(
  (ref) =>
      throw UnimplementedError('activityRepositoryProvider: ver bootstrap'),
);

final StreamProviderFamily<List<ActivityItem>, String> activityProvider =
    StreamProvider.family<List<ActivityItem>, String>(
      (ref, familyId) =>
          ref.watch(activityRepositoryProvider).watchActivity(familyId),
    );
