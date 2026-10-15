import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nexo_familia/core/result.dart';
import 'package:nexo_familia/design_system/components/nx_button.dart';
import 'package:nexo_familia/design_system/tokens/nx_dimens.dart';
import 'package:nexo_familia/features/authentication/domain/auth.dart';
import 'package:nexo_familia/features/authentication/presentation/auth_messages.dart';
import 'package:nexo_familia/features/authentication/presentation/auth_providers.dart';
import 'package:nexo_familia/features/authentication/presentation/auth_widgets.dart';
import 'package:nexo_familia/features/common/presentation/routes.dart';
import 'package:nexo_familia/l10n/gen/app_localizations.dart';

class SignInScreen extends ConsumerStatefulWidget {
  const new({super.key});

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen> {
  final _email = TextEditingController();
  final _password = TextEditingController();
  String? _emailError;
  String? _passwordError;
  String? _formError;
  bool _busy = false;

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final l10n = AppLocalizations.of(context);
    setState(() {
      _emailError = authValidationMessage(
        l10n,
        AuthValidators.email(_email.text),
      );
      _passwordError = _password.text.isEmpty
          ? l10n.validationPasswordRequired
          : null;
      _formError = null;
    });
    if (_emailError != null || _passwordError != null) return;
    setState(() => _busy = true);
    final result = await ref
        .read(authRepositoryProvider)
        .signIn(email: _email.text, password: _password.text);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (result case Err(:final failure)) {
        _formError = authFailureMessage(l10n, failure);
      }
    });
    // En caso de éxito, la sesión cambia y el enrutador redirige.
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AuthScaffold(
      title: l10n.signInTitle,
      subtitle: l10n.signInSubtitle,
      children: [
        AutofillGroup(
          child: Column(
            children: [
              TextField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                autofillHints: const [AutofillHints.email],
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: l10n.authEmailLabel,
                  errorText: _emailError,
                ),
              ),
              const SizedBox(height: NxSpace.md),
              PasswordField(
                controller: _password,
                errorText: _passwordError,
                onSubmitted: (_) => _submit(),
              ),
            ],
          ),
        ),
        if (_formError != null) ...[
          const SizedBox(height: NxSpace.md),
          Semantics(
            liveRegion: true,
            child: Text(
              _formError!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        ],
        const SizedBox(height: NxSpace.lg),
        NxButton(label: l10n.signInAction, loading: _busy, onPressed: _submit),
        const SizedBox(height: NxSpace.xs),
        NxButton(
          label: l10n.signInForgot,
          variant: NxButtonVariant.tertiary,
          onPressed: () => context.push(AppRoutes.resetPassword),
        ),
        NxButton(
          label: l10n.signInNoAccount,
          variant: NxButtonVariant.tertiary,
          onPressed: () => context.go(AppRoutes.signUp),
        ),
      ],
    );
  }
}
