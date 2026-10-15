import 'package:flutter/material.dart';
import 'package:nexo_familia/design_system/components/nx_state_views.dart';
import 'package:nexo_familia/l10n/gen/app_localizations.dart';

// PROVISIONAL: se reemplaza por la pantalla completa en el incremento 3.
class InviteScreen extends StatelessWidget {
  const new({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.navFamily)),
      body: NxMessageView(
        icon: Icons.construction_outlined,
        title: l10n.navFamily,
      ),
    );
  }
}
