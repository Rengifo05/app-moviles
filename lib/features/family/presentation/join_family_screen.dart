import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nexo_familia/core/result.dart';
import 'package:nexo_familia/design_system/components/nx_banner.dart';
import 'package:nexo_familia/design_system/components/nx_button.dart';
import 'package:nexo_familia/design_system/tokens/nx_dimens.dart';
import 'package:nexo_familia/features/common/presentation/routes.dart';
import 'package:nexo_familia/features/family/domain/family.dart';
import 'package:nexo_familia/features/family/presentation/family_actions.dart';
import 'package:nexo_familia/features/family/presentation/family_providers.dart';
import 'package:nexo_familia/features/family/presentation/family_text.dart';
import 'package:nexo_familia/features/family/presentation/family_widgets.dart';
import 'package:nexo_familia/l10n/gen/app_localizations.dart';

/// Unirse a una familia con un código de invitación.
class JoinFamilyScreen extends ConsumerStatefulWidget {
  const new({super.key});

  @override
  ConsumerState<JoinFamilyScreen> createState() => _JoinFamilyScreenState();
}

class _JoinFamilyScreenState extends ConsumerState<JoinFamilyScreen> {
  /// Holgura para espacios y guiones al pegar un código (10 caracteres).
  static const int _maxInputLength = 20;

  final _code = TextEditingController();
  final GlobalKey _fieldKey = GlobalKey();
  final GlobalKey _errorKey = GlobalKey();
  String? _codeError;
  String? _formError;
  bool _busy = false;

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    final l10n = AppLocalizations.of(context);
    final wellFormed = FamilyRules.normalizeCode(_code.text) != null;
    setState(() {
      _codeError = wellFormed ? null : l10n.familyErrorInvitationFormat;
      _formError = null;
    });
    if (!wellFormed) {
      revealAfterFrame(_fieldKey);
      return;
    }
    setState(() => _busy = true);
    final hadFamily = ref.read(hasAnyFamilyProvider);
    final result = await ref
        .read(familyActionsProvider)
        .joinWithCode(_code.text);
    if (!mounted) return;
    if (result is Ok && hadFamily) return context.go(AppRoutes.family);
    if (result case Err(:final failure)) {
      final message = familyFailureMessage(l10n, failure, FamilyOperation.join);
      setState(() {
        _busy = false;
        if (failure.code == 'invitation-format') {
          _codeError = message;
        } else {
          _formError = message;
        }
      });
      revealAfterFrame(
        _formError == null ? _fieldKey : _errorKey,
        alignEnd: _formError != null,
      );
    }
    // Con éxito y sin familia previa, la sesión cambia en cuanto llega la
    // membresía y el enrutador lleva a Inicio.
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // Se observa para que esté cargado al enviar (ver _submit).
    ref.watch(hasAnyFamilyProvider);
    return FamilyFormScaffold(
      title: l10n.familyJoinTitle,
      subtitle: l10n.familyJoinBody,
      children: [
        TextField(
          key: _fieldKey,
          controller: _code,
          enabled: !_busy,
          autocorrect: false,
          enableSuggestions: false,
          textCapitalization: TextCapitalization.characters,
          textInputAction: TextInputAction.done,
          inputFormatters: [
            LengthLimitingTextInputFormatter(_maxInputLength),
            InvitationCodeInputFormatter(),
          ],
          onSubmitted: (_) => _submit(),
          decoration: InputDecoration(
            labelText: l10n.familyJoinCodeLabel,
            helperText: l10n.familyJoinCodeHelper,
            errorText: _codeError,
            errorMaxLines: 3,
          ),
        ),
        const SizedBox(height: NxSpace.xs),
        FamilyNote(
          icon: Icons.visibility_outlined,
          text: l10n.familyJoinPrivacyNote,
        ),
        if (_formError case final error?) ...[
          const SizedBox(height: NxSpace.sm),
          NxBanner(key: _errorKey, icon: Icons.error_outline, message: error),
        ],
        const SizedBox(height: NxSpace.lg),
        NxButton(
          label: l10n.familyJoinAction,
          loading: _busy,
          onPressed: _submit,
        ),
      ],
    );
  }
}
