import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nexo_familia/core/result.dart';
import 'package:nexo_familia/design_system/components/nx_button.dart';
import 'package:nexo_familia/design_system/theme/nx_theme.dart';
import 'package:nexo_familia/design_system/tokens/nx_dimens.dart';
import 'package:nexo_familia/features/authentication/domain/auth.dart';
import 'package:nexo_familia/features/authentication/presentation/auth_messages.dart';
import 'package:nexo_familia/features/authentication/presentation/auth_providers.dart';
import 'package:nexo_familia/features/authentication/presentation/auth_widgets.dart';
import 'package:nexo_familia/features/common/presentation/routes.dart';
import 'package:nexo_familia/l10n/gen/app_localizations.dart';

class SignUpScreen extends ConsumerStatefulWidget {
  const new({super.key});

  @override
  ConsumerState<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends ConsumerState<SignUpScreen> {
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  bool _adult = false;
  bool _privacy = false;
  Map<String, String> _errors = const {};
  String? _formError;
  bool _busy = false;

  @override
  void dispose() {
    _name.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final l10n = AppLocalizations.of(context);
    final request = SignUpRequest(
      email: _email.text,
      password: _password.text,
      displayName: _name.text,
      confirmedAdult: _adult,
      acceptedPrivacyPolicy: _privacy,
    );
    final errors = <String, String>{};
    for (final code in AuthValidators.signUp(request)) {
      final field = switch (code) {
        final c when c.startsWith('email') => 'email',
        final c when c.startsWith('password') => 'password',
        final c when c.startsWith('display-name') => 'name',
        'adult-confirmation-required' => 'adult',
        _ => 'privacy',
      };
      errors.putIfAbsent(field, () => authValidationMessage(l10n, code)!);
    }
    setState(() {
      _errors = errors;
      _formError = null;
    });
    if (errors.isNotEmpty) return;
    setState(() => _busy = true);
    final result = await ref.read(authRepositoryProvider).signUp(request);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (result case Err(:final failure)) {
        _formError = authFailureMessage(l10n, failure);
      }
    });
  }

  Future<void> _showPrivacy() {
    final l10n = AppLocalizations.of(context);
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            NxSpace.gutter,
            0,
            NxSpace.gutter,
            NxSpace.xl,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(
                header: true,
                child: Text(
                  l10n.privacySummaryTitle,
                  style: context.text.titleLarge,
                ),
              ),
              const SizedBox(height: NxSpace.md),
              Text(
                l10n.privacySummaryBody,
                style: context.text.bodyLarge?.copyWith(height: 1.5),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _check({
    required bool value,
    required ValueChanged<bool> onChanged,
    required String label,
    String? error,
    String? note,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      CheckboxListTile(
        value: value,
        onChanged: (v) => onChanged(v ?? false),
        title: Text(label),
        subtitle: note == null ? null : Text(note),
        controlAffinity: ListTileControlAffinity.leading,
        contentPadding: EdgeInsets.zero,
      ),
      if (error != null)
        Padding(
          padding: const EdgeInsets.only(left: NxSpace.xxl),
          child: Text(
            error,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        ),
    ],
  );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return AuthScaffold(
      title: l10n.signUpTitle,
      subtitle: l10n.signUpSubtitle,
      children: [
        AutofillGroup(
          child: Column(
            children: [
              TextField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                autofillHints: const [AutofillHints.nickname],
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: l10n.authNameLabel,
                  helperText: l10n.authNameHint,
                  errorText: _errors['name'],
                ),
              ),
              const SizedBox(height: NxSpace.md),
              TextField(
                controller: _email,
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
                autofillHints: const [AutofillHints.email],
                textInputAction: TextInputAction.next,
                decoration: InputDecoration(
                  labelText: l10n.authEmailLabel,
                  errorText: _errors['email'],
                ),
              ),
              const SizedBox(height: NxSpace.md),
              PasswordField(
                controller: _password,
                isNewPassword: true,
                helperText: l10n.authPasswordHint,
                errorText: _errors['password'],
              ),
            ],
          ),
        ),
        const SizedBox(height: NxSpace.md),
        _check(
          value: _adult,
          onChanged: (v) => setState(() => _adult = v),
          label: l10n.signUpAdult,
          note: l10n.signUpAdultNote,
          error: _errors['adult'],
        ),
        _check(
          value: _privacy,
          onChanged: (v) => setState(() => _privacy = v),
          label: l10n.signUpPrivacy,
          error: _errors['privacy'],
        ),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton(
            onPressed: _showPrivacy,
            child: Text(l10n.signUpReadPrivacy),
          ),
        ),
        if (_formError != null) ...[
          const SizedBox(height: NxSpace.xs),
          Semantics(
            liveRegion: true,
            child: Text(
              _formError!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        ],
        const SizedBox(height: NxSpace.lg),
        NxButton(label: l10n.signUpAction, loading: _busy, onPressed: _submit),
        const SizedBox(height: NxSpace.xs),
        NxButton(
          label: l10n.signUpHaveAccount,
          variant: NxButtonVariant.tertiary,
          onPressed: () => context.go(AppRoutes.signIn),
        ),
      ],
    );
  }
}
