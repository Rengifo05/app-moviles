import 'package:nexo_familia/core/failure.dart';
import 'package:nexo_familia/core/result.dart';
import 'package:nexo_familia/features/family/domain/family.dart';
import 'package:nexo_familia/infrastructure/backend_paths.dart';
import 'package:nexo_familia/infrastructure/remote/remote_store.dart';
import 'package:nexo_familia/infrastructure/remote_json.dart';
import 'package:nexo_familia/infrastructure/sync/document_cache.dart';

/// Familias e integrantes. Lee de la caché local (reflejada por
/// `RemoteMirror`); las operaciones privilegiadas pasan por las Functions,
/// que validan permisos en el servidor.
final class FamilyRepositoryImpl implements FamilyRepository {
  new({
    required this._functions,
    required this._cache,
    required this._currentUid,
  });

  final FunctionsClient _functions;
  final DocumentCache _cache;
  final String? Function() _currentUid;

  @override
  Stream<List<FamilyGroup>> watchMyFamilies() {
    final uid = _currentUid();
    if (uid == null) return Stream.value(const []);
    return _cache
        .watchCollection(BackendPaths.memberships(uid))
        .map(
          (docs) =>
              docs
                  .map((d) => _familyFromMembership(d.id, d.data, uid))
                  .nonNulls
                  .toList()
                ..sort((a, b) => a.joinedAt.compareTo(b.joinedAt)),
        );
  }

  @override
  Stream<List<FamilyMember>> watchMembers(String familyId) => _cache
      .watchCollection(BackendPaths.members(familyId))
      .map(
        (docs) =>
            docs.map((d) => _member(familyId, d.id, d.data)).nonNulls.toList()
              ..sort(_byRoleThenName),
      );

  @override
  Future<Result<FamilyGroup>> createFamily(String name) async {
    if (FamilyRules.familyName(name) case final code?) {
      return Err(Failure.validation(code));
    }
    final uid = _currentUid();
    if (uid == null) return const Err(Failure.unauthenticated());
    final result = await _functions.call(BackendFunctions.createFamily, {
      'name': name.trim(),
    });
    return switch (result) {
      Err(:final failure) => Err(failure),
      Ok(value: final json) => switch (RemoteJson.string(json['familyId'])) {
        null => const Err(Failure.unexpected('bad-response')),
        final id => Ok(
          FamilyGroup(
            id: id,
            name: name.trim(),
            myRole: MemberRole.owner,
            joinedAt: DateTime.now().toUtc(),
          ),
        ),
      },
    };
  }

  @override
  Future<Result<CreatedInvitation>> createInvitation(String familyId) async {
    final result = await _functions.call(BackendFunctions.createInvitation, {
      'familyId': familyId,
    });
    if (result case Err(:final failure)) return Err(failure);
    final json = result.valueOrNull!;
    final code = RemoteJson.string(json['code']);
    final expiresAt = RemoteJson.date(json['expiresAt']);
    if (code == null || expiresAt == null) {
      return const Err(Failure.unexpected('bad-response'));
    }
    return Ok(
      CreatedInvitation(
        invitationId: RemoteJson.string(json['invitationId']) ?? '',
        code: code,
        expiresAt: expiresAt,
        maxUses: RemoteJson.integer(json['maxUses']) ?? 1,
      ),
    );
  }

  @override
  Future<Result<String>> acceptInvitation(String code) async {
    final normalized = FamilyRules.normalizeCode(code);
    if (normalized == null) {
      return const Err(Failure.validation('invitation-format'));
    }
    final result = await _functions.call(BackendFunctions.acceptInvitation, {
      'code': normalized,
    });
    return switch (result) {
      Err(:final failure) => Err(failure),
      Ok(value: final json) => switch (RemoteJson.string(json['familyId'])) {
        null => const Err(Failure.unexpected('bad-response')),
        final id => Ok(id),
      },
    };
  }

  @override
  Future<VoidResult> leaveFamily(String familyId) async {
    final result = await _functions.call(BackendFunctions.leaveFamily, {
      'familyId': familyId,
    });
    if (result case Err(:final failure)) return Err(failure);
    // Se purga la copia local de inmediato (amenaza 10).
    await _cache.clearScope(familyId);
    return const Ok(null);
  }

  @override
  Future<VoidResult> removeMember(String familyId, String uid) async {
    final result = await _functions.call(BackendFunctions.removeMember, {
      'familyId': familyId,
      'uid': uid,
    });
    return result.map((_) {});
  }

  static FamilyGroup? _familyFromMembership(
    String familyId,
    Json data,
    String uid,
  ) {
    final name = RemoteJson.string(data['familyName']);
    final role = _role(data['role']);
    if (name == null || role == null) return null;
    return FamilyGroup(
      id: familyId,
      name: name,
      myRole: role,
      joinedAt:
          RemoteJson.date(data['joinedAt']) ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );
  }

  static MemberRole? _role(Object? value) => switch (value) {
    'owner' => MemberRole.owner,
    'admin' => MemberRole.admin,
    'member' => MemberRole.member,
    _ => null,
  };

  static FamilyMember? _member(String familyId, String uid, Json data) {
    final role = _role(data['role']);
    if (role == null) return null;
    return FamilyMember(
      uid: uid,
      familyId: familyId,
      displayName: RemoteJson.string(data['displayName']) ?? '',
      role: role,
      joinedAt:
          RemoteJson.date(data['joinedAt']) ??
          DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
    );
  }

  static int _byRoleThenName(FamilyMember a, FamilyMember b) {
    final byRole = a.role.index.compareTo(b.role.index);
    return byRole != 0
        ? byRole
        : a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase());
  }
}
