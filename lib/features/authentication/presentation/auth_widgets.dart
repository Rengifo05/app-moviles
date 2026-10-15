import 'package:flutter/material.dart';
import 'package:nexo_familia/design_system/theme/nx_theme.dart';
import 'package:nexo_familia/design_system/tokens/nx_dimens.dart';
import 'package:nexo_familia/l10n/gen/app_localizations.dart';

/// Estructura común de las pantallas de autenticación.
class AuthScaffold extends StatelessWidget {
  const new({
    required this.title,
    required this.subtitle,
    required this.children,
    super.key,
    this.showBack = false,
  });

  final String title;
  final String subtitle;
  final List<Widget> children;
  final bool showBack;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: showBack ? AppBar() : null,
    body: SafeArea(
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: ListView(
            padding: const EdgeInsets.fromLTRB(
              NxSpace.gutter,
              NxSpace.xl,
              NxSpace.gutter,
              NxSpace.xxl,
            ),
            children: [
              Semantics(
                header: true,
                child: Text(title, style: context.text.headlineMedium),
              ),
              const SizedBox(height: NxSpace.xs),
              Text(
                subtitle,
                style: context.text.bodyLarge?.copyWith(
                  color: context.nx.inkMuted,
                ),
              ),
              const SizedBox(height: NxSpace.xl),
              ...children,
            ],
          ),
        ),
      ),
    ),
  );
}

/// Campo de contraseña con botón para mostrarla u ocultarla.
class PasswordField extends StatefulWidget {
  const new({
    required this.controller,
    super.key,
    this.errorText,
    this.helperText,
    this.onSubmitted,
    this.isNewPassword = false,
  });

  final TextEditingController controller;
  final String? errorText;
  final String? helperText;
  final ValueChanged<String>? onSubmitted;
  final bool isNewPassword;

  @override
  State<PasswordField> createState() => _PasswordFieldState();
}

class _PasswordFieldState extends State<PasswordField> {
  bool _visible = false;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return TextField(
      controller: widget.controller,
      obscureText: !_visible,
      autocorrect: false,
      enableSuggestions: false,
      autofillHints: [
        if (widget.isNewPassword)
          AutofillHints.newPassword
        else
          AutofillHints.password,
      ],
      textInputAction: TextInputAction.done,
      onSubmitted: widget.onSubmitted,
      decoration: InputDecoration(
        labelText: l10n.authPasswordLabel,
        helperText: widget.helperText,
        errorText: widget.errorText,
        suffixIcon: IconButton(
          tooltip: _visible ? l10n.authHidePassword : l10n.authShowPassword,
          icon: Icon(_visible ? Icons.visibility_off : Icons.visibility),
          onPressed: () => setState(() => _visible = !_visible),
        ),
      ),
    );
  }
}
