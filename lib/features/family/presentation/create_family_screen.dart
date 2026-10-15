import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nexo_familia/core/failure.dart';
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

/// Crea una familia. Al tener éxito queda como familia activa y el
/// enrutador lleva a Inicio cuando la sesión lo refleja.
class CreateFamilyScreen extends ConsumerStatefulWidget {
  const new({super.key});

  @override
  ConsumerState<CreateFamilyScreen> createState() => _CreateFamilyScreenState();
}

class _CreateFamilyScreenState extends ConsumerState<CreateFamilyScreen> {
  final _name = TextEditingController();
  final GlobalKey _fieldKey = GlobalKey();
  final GlobalKey _errorKey = GlobalKey();
  String? _nameError;
  String? _formError;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_busy) return;
    final l10n = AppLocalizations.of(context);
    final code = FamilyRules.familyName(_name.text);
    setState(() {
      _nameError = familyNameValidationMessage(l10n, code);
      _formError = null;
    });
    if (code != null) {
      revealAfterFrame(_fieldKey);
      return;
    }
    setState(() => _busy = true);
    final hadFamily = ref.read(hasAnyFamilyProvider);
    final result = await ref
        .read(familyActionsProvider)
        .createFamily(_name.text);
    if (!mounted) return;
    if (result is Ok && hadFamily) return context.go(AppRoutes.family);
    if (result case Err(:final failure)) {
      final message = familyFailureMessage(
        l10n,
        failure,
        FamilyOperation.create,
      );
      setState(() {
        _busy = false;
        final isNameProblem =
            failure.kind == FailureKind.validation &&
            failure.code.startsWith('family-name-');
        if (isNameProblem) {
          _nameError = message;
        } else {
          _formError = message;
        }
      });
      revealAfterFrame(
        _formError == null ? _fieldKey : _errorKey,
        alignEnd: _formError != null,
      );
    }
    // Con éxito y sin familia previa, el botón sigue ocupado: la sesión
    // cambia en cuanto llega la membresía y el enrutador lleva a Inicio.
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    // Se observa para que esté cargado al enviar (ver _submit).
    ref.watch(hasAnyFamilyProvider);
    return FamilyFormScaffold(
      title: l10n.familyCreateTitle,
      subtitle: l10n.familyCreateBody,
      children: [
        TextField(
          key: _fieldKey,
          controller: _name,
          enabled: !_busy,
          maxLength: FamilyRules.maxNameLength,
          textCapitalization: TextCapitalization.words,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _submit(),
          decoration: InputDecoration(
            labelText: l10n.familyCreateNameLabel,
            hintText: l10n.familyCreateNameHint,
            errorText: _nameError,
          ),
        ),
        FamilyNote(
          icon: Icons.manage_accounts_outlined,
          text: l10n.familyCreateOwnerNote,
        ),
        if (_formError case final error?) ...[
          const SizedBox(height: NxSpace.sm),
          NxBanner(key: _errorKey, icon: Icons.error_outline, message: error),
        ],
        const SizedBox(height: NxSpace.lg),
        NxButton(
          label: l10n.familyCreateAction,
          loading: _busy,
          onPressed: _submit,
        ),
      ],
    );
  }
}
