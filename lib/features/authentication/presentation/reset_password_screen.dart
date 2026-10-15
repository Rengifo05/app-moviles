import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexo_familia/core/result.dart';
import 'package:nexo_familia/design_system/components/nx_banner.dart';
import 'package:nexo_familia/design_system/components/nx_button.dart';
import 'package:nexo_familia/design_system/components/nx_status_pill.dart';
import 'package:nexo_familia/design_system/tokens/nx_dimens.dart';
import 'package:nexo_familia/features/authentication/domain/auth.dart';
import 'package:nexo_familia/features/authentication/presentation/auth_messages.dart';
import 'package:nexo_familia/features/authentication/presentation/auth_providers.dart';
import 'package:nexo_familia/features/authentication/presentation/auth_widgets.dart';
import 'package:nexo_familia/l10n/gen/app_localizations.dart';

class ResetPasswordScreen extends ConsumerStatefulWidget {
  const new({super.key});

  @override
  ConsumerState<ResetPasswordScreen> createState() =>
      _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends ConsumerState<ResetPasswordScreen> {
  final _email = TextEditingController();
  String? _error;
  bool _busy = false;
  bool _sent = false;

  @override
  void dispose() {
    _email.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final l10n = AppLocalizations.of(context);
    final validation = authValidationMessage(
      l10n,
      AuthValidators.email(_email.text),
    );
    setState(() => _error = validation);
    if (validation != null) return;
    setState(() => _busy = true);
    final result = await ref
        .read(authRepositoryProvider)
        .sendPasswordReset(_email.text.trim());
    if (!mounted) return;
    setState(() {
      _busy = false;
      switch (result) {
        case Ok():
          _sent = true;
        case Err(:final failure):
          _error = authFailureMessage(l10n, failure);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AuthScaffold(
      title: l10n.resetTitle,
      subtitle: l10n.resetBody,
      showBack: true,
      children: [
        TextField(
          controller: _email,
          keyboardType: TextInputType.emailAddress,
          autocorrect: false,
          autofillHints: const [AutofillHints.email],
          onSubmitted: (_) => _submit(),
          decoration: InputDecoration(
            labelText: l10n.authEmailLabel,
            errorText: _error,
          ),
        ),
        const SizedBox(height: NxSpace.lg),
        if (_sent)
          // Mismo mensaje exista o no la cuenta: no revela correos.
          NxBanner(
            icon: Icons.mark_email_read_outlined,
            message: l10n.resetSent,
            tone: NxTone.info,
          )
        else
          NxButton(label: l10n.resetAction, loading: _busy, onPressed: _submit),
      ],
    );
  }
}
